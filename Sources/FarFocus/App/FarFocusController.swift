import AppKit
import SwiftUI

/// Runs the engine against the real clock and the real Mac: one self-rescheduling timer, the system
/// signals (idle, holds, sleep, displays) and the three surfaces.
@MainActor
final class FarFocusController {

    private(set) var engine: FarFocusEngine
    private let settings: AppSettings
    private let holds = HoldDetector()
    private let sleep = SleepWatcher()
    private let panel = PanelModel.shared
    private let card = CardPanel()
    private let countdown = CountdownPanel()
    private let breakWindows = BreakWindows()

    private var timer: Timer?
    private var lastTick = ProcessInfo.processInfo.systemUptime
    private var activity: NSObjectProtocol?

    // Break bookkeeping
    private var breakShownAt: TimeInterval?
    private var safetyTimer: Timer?
    private var escapeMonitors: [Any] = []
    private var hintReset: DispatchWorkItem?
    private var announcedCountdown = false

    /// Demo: freeze the clock (for screenshots of one exact moment).
    var frozen = false

    init(settings: AppSettings) {
        self.settings = settings
        engine = FarFocusEngine(settings: settings.breakSettings, enabled: settings.enabled)
    }

    private var now: TimeInterval { ProcessInfo.processInfo.systemUptime }

    func start() {
        holds.forced = Demo.fakeHold
        // Screenshot modes never ask for permissions.
        if settings.holdDuringFocus && (!Demo.isOn || Demo.mode == "live") { holds.prepareFocus() }
        SettingsWindow.shared.focusPermissionDenied = { [holds] in holds.focusPermissionDenied }

        settings.onChange = { [weak self] in self?.settingsChanged() }

        panel.startNow = { [weak self] in self?.perform { $0.startNow() } }

        card.model.startNow = { [weak self] in self?.perform { $0.startNow() } }
        card.model.postpone = { [weak self] minutes in self?.perform { $0.postpone(minutes: minutes) } }
        card.model.skip = { [weak self] in self?.perform { $0.skip() } }
        breakWindows.model.endBreak = { [weak self] in self?.perform { $0.skip() } }
        breakWindows.model.turnOffDisplay = { Self.turnOffDisplays() }

        sleep.onSleep = { [weak self] in self?.perform { $0.willSleep() } }
        sleep.onWake = { [weak self] slept in
            guard let self else { return }
            lastTick = now   // the awake clock already skipped the sleep; don't count the gap twice
            perform { $0.didWake(sleptFor: slept) }
        }
        sleep.start()

        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.breakWindows.rebuild() }
        }

        lastTick = now
        render()
        scheduleTick(after: engine.tickInterval)
    }

    // MARK: - Ticking

    private func scheduleTick(after interval: TimeInterval) {
        timer?.invalidate()
        let timer = Timer(timeInterval: interval, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        timer.tolerance = interval * 0.1
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func tick() {
        let t = now
        let dt = t - lastTick
        lastTick = t
        if !frozen {
            let hold = engine.wantsHoldCheck ? holds.current(respectFocus: settings.holdDuringFocus) : nil
            engine.advance(by: dt, idle: IdleTime.seconds(), hold: hold)
        }
        // The second half of the safety net: a break on screen far too long ends, whatever the engine says.
        if !frozen, let shown = breakShownAt, SafetyNet.isOverdue(shownAt: shown, now: t, breakLength: engine.breakTotal) {
            Demo.log("tick-side safety check fired")
            engine.forceEndBreak()
        }
        render()
        // Test hook (demo only): the timer "dies" when a break starts, to prove the safety net.
        if Demo.stallAtBreak && engine.phase == .breaking { timer?.invalidate(); return }
        scheduleTick(after: engine.tickInterval)
    }

    /// A user action: change the engine, show the result at once, restart the tick from now.
    private func perform(_ change: (inout FarFocusEngine) -> Void) {
        let t = now
        if !frozen {
            // Bank the time since the last tick first, so an action never loses or double-counts seconds.
            let hold = engine.wantsHoldCheck ? holds.current(respectFocus: settings.holdDuringFocus) : nil
            engine.advance(by: t - lastTick, idle: IdleTime.seconds(), hold: hold)
        }
        lastTick = t
        change(&engine)
        render()
        scheduleTick(after: engine.tickInterval)
    }

    private func settingsChanged() {
        if settings.enabled != engine.isEnabled { engine.setEnabled(settings.enabled) }
        engine.apply(settings.breakSettings)
        if settings.holdDuringFocus && (!Demo.isOn || Demo.mode == "live") { holds.prepareFocus() }
        render()
        scheduleTick(after: engine.tickInterval)
    }

    // MARK: - Showing the state

    private var lastLogged = ""

    /// `FARFOCUS_LOG=1`: one line per change of phase, surface or hold (stderr).
    private func log() {
        guard Demo.logging else { return }
        let line = "\(engine.phase) surface=\(engine.surface) hold=\(engine.hold.map { "\($0)" } ?? "-") idle=\(engine.isIdle) asleep=\(engine.isAsleep) postpones=\(engine.postponesLeft) windows=\(breakWindows.windowCount)"
        guard line != lastLogged else { return }
        lastLogged = line
        Demo.log(String(format: "%.1f ", now) + line + " left=\(engine.secondsLeft)")
    }

    private func render() {
        log()
        updatePanel()
        keepTimersPrecise(engine.needsPreciseTiming)

        let surface = engine.surface

        if surface == .card {
            let lead = engine.settings.effectiveLead
            if !card.isShowing {
                // A fresh showing: the right values at once, no animation from the last showing's numbers.
                quietly {
                    card.model.secondsLeft = engine.secondsLeft
                    card.model.ring = Ring.now(remaining: engine.remaining, total: lead)
                }
            }
            card.model.secondsLeft = engine.secondsLeft
            card.model.postponesLeft = engine.postponesLeft
            card.model.postponeLimit = engine.settings.postponeLimit
            card.present()
            glide { [card, engine] in card.model.ring = Self.ringTarget(engine.remaining, of: lead) }
        } else {
            card.dismiss()
        }

        if surface == .countdown {
            let total = BreakSettings.countdownLength
            if !countdown.isShowing {
                quietly {
                    countdown.model.secondsLeft = engine.secondsLeft
                    countdown.model.ring = Ring.now(remaining: engine.remaining, total: total)
                }
            }
            countdown.model.secondsLeft = engine.secondsLeft
            countdown.present()
            glide { [countdown, engine] in countdown.model.ring = Self.ringTarget(engine.remaining, of: total) }
            if !announcedCountdown {
                announcedCountdown = true
                announce("Eye break in \(engine.secondsLeft) seconds")
            }
        } else {
            countdown.dismiss()
            announcedCountdown = false
        }

        if surface == .breakScreen {
            if !breakWindows.isVisible {
                // A fresh break: the progress line starts empty, not sliding back from the last break's end.
                quietly {
                    breakWindows.model.secondsLeft = engine.secondsLeft
                    breakWindows.model.progress = engine.breakProgress
                }
            }
            breakWindows.model.secondsLeft = engine.secondsLeft
            breakWindows.model.progress = engine.breakProgress
            breakWindows.model.postponesLeft = engine.postponesLeft
            breakWindows.model.escapeHint = engine.escapeHintActive(at: now)
            if !breakWindows.isVisible { showBreak() }
        } else if breakWindows.isVisible {
            hideBreak()
        }
    }

    /// Changes that must not animate (a surface appearing with its starting values).
    private func quietly(_ change: () -> Void) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction, change)
    }

    /// The ring's next value, set on the next run-loop turn so it glides (linear, 1 s) from the value it shows now.
    private func glide(_ change: @escaping @MainActor () -> Void) {
        DispatchQueue.main.async { change() }
    }

    /// With Reduce Motion the ring doesn't glide, so it shows the time left now; otherwise it heads to where it
    /// will be in a second.
    private static func ringTarget(_ remaining: TimeInterval, of total: TimeInterval) -> Double {
        Theme.reduceMotion ? Ring.now(remaining: remaining, total: total)
                           : Ring.inOneSecond(remaining: remaining, total: total)
    }

    /// The menu-bar text and panel, written only when a value changes (the menu bar redraws on change).
    private func updatePanel() {
        let label = StatusText.label(for: engine)
        if panel.label != label { panel.label = label }
        if panel.isEnabled != engine.isEnabled { panel.isEnabled = engine.isEnabled }
        let line = StatusText.statusLine(for: engine)
        if panel.statusLine != line { panel.statusLine = line }
        let a11y = StatusText.accessibilityLabel(for: engine)
        if panel.accessibilityLabel != a11y { panel.accessibilityLabel = a11y }
        let canStart = engine.phase == .working || engine.phase == .warning
        if panel.canStartNow != canStart { panel.canStartNow = canStart }
    }

    private func showBreak() {
        breakWindows.present()
        breakShownAt = now
        if Demo.logging {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                Demo.log("break focus: key=\(NSApp.keyWindow.map { "\($0.frame)" } ?? "none")")
            }
        }
        installEscapeMonitors()
        // The safety net: an independent one-shot timer, armed for the whole break plus a grace period.
        safetyTimer?.invalidate()
        let armedFor = engine.remaining + BreakSettings.safetyGrace
        Demo.log(String(format: "%.1f safety net armed for %.1f s", now, armedFor))
        let timer = Timer(timeInterval: armedFor, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.breakWindows.isVisible else { return }
                Demo.log(String(format: "%.1f safety net fired", self.now))
                self.engine.forceEndBreak()
                self.render()
                self.scheduleTick(after: self.engine.tickInterval)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        safetyTimer = timer
        announce("Eye break, \(engine.secondsLeft) seconds. Press Escape twice to end it.")
    }

    private func hideBreak() {
        safetyTimer?.invalidate()
        safetyTimer = nil
        breakShownAt = nil
        removeEscapeMonitors()
        // Leave the app in front only if Settings is open; otherwise hand the keyboard back.
        breakWindows.dismiss(hideApp: !SettingsWindow.shared.isVisible)
    }

    // MARK: - Esc twice

    private func installEscapeMonitors() {
        guard escapeMonitors.isEmpty else { return }
        // Local: works without any permission while the break window is key. Swallows typing so it doesn't
        // beep; Tab, Return and Space still drive the buttons.
        if let local = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            let key = event.keyCode
            let pass: Bool = MainActor.assumeIsolated {
                guard let self, self.breakWindows.isVisible else { return true }
                if key == 53 { self.escapePressed(); return false }
                return [48, 36, 49, 76].contains(key)   // Tab, Return, Space, Enter
            }
            return pass ? event : nil
        }) {
            escapeMonitors.append(local)
        }
        // Global: only delivers if the user happens to have granted Accessibility (never requested).
        if let global = NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            guard event.keyCode == 53 else { return }
            MainActor.assumeIsolated { self?.escapePressed() }
        }) {
            escapeMonitors.append(global)
        }
    }

    private func removeEscapeMonitors() {
        for monitor in escapeMonitors { NSEvent.removeMonitor(monitor) }
        escapeMonitors.removeAll()
        hintReset?.cancel()
    }

    private func escapePressed() {
        let ended = engine.escape(at: now)
        Demo.log("esc → ended=\(ended)")
        render()
        if !ended {
            hintReset?.cancel()
            let work = DispatchWorkItem { [weak self] in self?.render() }
            hintReset = work
            DispatchQueue.main.asyncAfter(deadline: .now() + BreakSettings.escapeWindow + 0.05, execute: work)
        } else {
            scheduleTick(after: engine.tickInterval)
        }
    }

    // MARK: - Helpers

    /// Near a break, ask macOS not to delay our timers (App Nap); far away, let it save energy.
    private func keepTimersPrecise(_ precise: Bool) {
        if precise, activity == nil {
            activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiatedAllowingIdleSystemSleep],
                                                             reason: "An eye break is about to start")
        } else if !precise, let token = activity {
            ProcessInfo.processInfo.endActivity(token)
            activity = nil
        }
    }

    private func announce(_ text: String) {
        NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested,
                             userInfo: [.announcement: text, .priority: NSAccessibilityPriorityLevel.high.rawValue])
    }

    /// "Turn off display": puts the displays to sleep (which locks the Mac if a password is required).
    private static func turnOffDisplays() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        task.arguments = ["displaysleepnow"]
        try? task.run()
    }

    // MARK: - Demo hooks

    func demoShow(_ change: (inout FarFocusEngine) -> Void) {
        frozen = true
        change(&engine)
        render()
    }

    var demoCountdown: CountdownPanel { countdown }
}
