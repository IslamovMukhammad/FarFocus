import Foundation

/// The whole break cycle as a value: no timers, no windows, no clock. Time is handed in from outside,
/// so every rule can be tested with made-up seconds.
///
///     working ──(lead left)──▶ warning ──(5 s left)──▶ starting ──(0)──▶ breaking ──(0)──▶ working
///
/// `remaining` is the time until the break starts (working, warning, starting) or until it ends (breaking).
struct FarFocusEngine: Equatable {

    enum Phase: Equatable, Sendable {
        case working, warning, starting, breaking
    }

    /// What should be on screen right now.
    enum Surface: Equatable, Sendable {
        case none, card, countdown, breakScreen
    }

    private(set) var settings: BreakSettings
    private(set) var phase: Phase = .working
    private(set) var remaining: TimeInterval
    private(set) var postponesLeft: Int
    private(set) var isEnabled: Bool
    /// Set while a due break waits for a shared screen, a presentation or a Focus to end.
    private(set) var hold: HoldReason?
    /// True when the last tick found nobody at the keyboard (the work timer is paused).
    private(set) var isIdle = false
    /// Screens or the whole Mac are asleep (or locked): nothing counts, nothing shows.
    private(set) var isAsleep = false
    /// The length of the break in progress (settings changed mid-break apply from the next one).
    private(set) var breakTotal: TimeInterval
    /// When the first Esc of a pair was pressed (uptime seconds).
    private(set) var firstEscapeAt: TimeInterval?
    /// "Take a break now" / "Start now": the user asked, so holds don't apply to this break.
    private(set) var startedByUser = false

    init(settings: BreakSettings = BreakSettings(), enabled: Bool = true) {
        self.settings = settings
        self.remaining = settings.workInterval
        self.postponesLeft = settings.postponeLimit
        self.isEnabled = enabled
        self.breakTotal = settings.breakLength
    }

    // MARK: - What the UI shows

    var surface: Surface {
        guard isEnabled, !isAsleep else { return .none }
        switch phase {
        case .working: return .none
        case .warning:
            // The card leaves on its own after a few seconds; the menu-bar seconds carry on.
            let lead = settings.effectiveLead
            return remaining > lead - settings.cardVisibleFor ? .card : .none
        case .starting: return .countdown
        case .breaking: return .breakScreen
        }
    }

    /// Whole seconds left, rounded up, for every on-screen number ("0:24", "3").
    var secondsLeft: Int { max(0, Int(remaining.rounded(.up))) }

    /// 0 at the start of a break, 1 at its end.
    var breakProgress: Double {
        guard phase == .breaking, breakTotal > 0 else { return 0 }
        return min(1, max(0, 1 - remaining / breakTotal))
    }

    /// Near the break the app ticks every second; far away every 5 s (the menu-bar text only changes once a minute).
    var tickInterval: TimeInterval {
        guard isEnabled, !isAsleep else { return 5 }
        if phase != .working { return 1 }
        if hold != nil { return 5 }
        return remaining - settings.effectiveLead > 70 ? 5 : 1
    }

    /// From shortly before the warning until the break ends, timers must not be delayed by App Nap.
    var needsPreciseTiming: Bool {
        isEnabled && !isAsleep && (phase != .working || (hold == nil && remaining - settings.effectiveLead <= 70))
    }

    /// Whether the next tick needs to know about holds (only when a break is due or close).
    var wantsHoldCheck: Bool {
        guard isEnabled, !isAsleep, !startedByUser else { return false }
        switch phase {
        case .working: return hold != nil || remaining <= settings.effectiveLead + 6
        case .warning, .starting: return true
        case .breaking: return false
        }
    }

    // MARK: - Time

    /// Moves the cycle on by `dt` seconds of awake time.
    /// - Parameters:
    ///   - idle: seconds since the last keyboard or mouse input.
    ///   - hold: why the break should wait right now, if it should.
    mutating func advance(by dt: TimeInterval, idle: TimeInterval, hold newHold: HoldReason?) {
        guard isEnabled, !isAsleep, dt > 0 else { return }
        let lead = settings.effectiveLead

        switch phase {
        case .working:
            // Of this tick, only the part up to `idleThreshold` after the last input counts as work.
            isIdle = idle >= settings.idleThreshold
            let worked = min(dt, max(0, dt - idle + settings.idleThreshold))
            remaining -= worked
            if remaining <= lead {
                if let newHold, !startedByUser {
                    hold = newHold
                    remaining = lead
                } else {
                    hold = nil
                    phase = .warning
                    remaining = lead
                }
            } else {
                hold = nil
            }

        case .warning:
            if let newHold, !startedByUser {
                holdBack(newHold)
                return
            }
            remaining -= dt
            if remaining <= BreakSettings.countdownLength {
                phase = .starting
                remaining = BreakSettings.countdownLength
            }

        case .starting:
            if let newHold, !startedByUser {
                holdBack(newHold)
                return
            }
            remaining -= dt
            if remaining <= 0 {
                phase = .breaking
                breakTotal = settings.breakLength
                remaining = breakTotal
                firstEscapeAt = nil
            }

        case .breaking:
            remaining -= dt
            if remaining <= 0 { resetCycle() }
        }
    }

    /// A shared screen / presentation / Focus appeared while the warning or countdown was up:
    /// put everything away and wait at the start of the warning.
    private mutating func holdBack(_ reason: HoldReason) {
        hold = reason
        phase = .working
        remaining = settings.effectiveLead
    }

    // MARK: - The user's choices

    /// "+1 / +5 / +15 min" on the warning card.
    mutating func postpone(minutes: Int) {
        guard isEnabled, postponesLeft > 0, phase == .warning || phase == .starting else { return }
        postponesLeft -= 1
        phase = .working
        remaining = TimeInterval(minutes * 60)
        hold = nil
        startedByUser = false
    }

    /// "Start now" on the card, "Take a Break Now" in the menu: straight to the countdown.
    mutating func startNow() {
        guard isEnabled, !isAsleep, phase == .working || phase == .warning else { return }
        phase = .starting
        remaining = BreakSettings.countdownLength
        hold = nil
        startedByUser = true
    }

    /// "Skip" on the card, "End break" on the break screen.
    mutating func skip() {
        guard phase != .working else { return }
        resetCycle()
    }

    /// Esc while the break is on screen. Two presses within `escapeWindow` end it.
    /// - Returns: true when this press ended the break.
    @discardableResult
    mutating func escape(at now: TimeInterval) -> Bool {
        guard phase == .breaking else { return false }
        if let first = firstEscapeAt, now - first <= BreakSettings.escapeWindow, now >= first {
            resetCycle()
            return true
        }
        firstEscapeAt = now
        return false
    }

    /// Whether the "press esc again" hint should show.
    func escapeHintActive(at now: TimeInterval) -> Bool {
        guard phase == .breaking, let first = firstEscapeAt else { return false }
        return now - first <= BreakSettings.escapeWindow && now >= first
    }

    /// The safety net fired: whatever state we are in, the break is over.
    mutating func forceEndBreak() {
        guard phase == .breaking else { return }
        resetCycle()
    }

    mutating func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }
        isEnabled = enabled
        resetCycle()
    }

    /// New settings. A new work interval while working restarts the cycle;
    /// everything else applies from the next cycle.
    mutating func apply(_ new: BreakSettings) {
        let workChanged = new.workInterval != settings.workInterval
        settings = new
        postponesLeft = min(postponesLeft, new.postponeLimit)
        if phase == .working && workChanged { resetCycle() }
    }

    // MARK: - Sleep

    mutating func willSleep() {
        isAsleep = true
    }

    /// A sleep at least as long as a break counts as one: a fresh cycle. A shorter one resumes where it was.
    mutating func didWake(sleptFor: TimeInterval) {
        guard isAsleep else { return }
        isAsleep = false
        if sleptFor >= settings.breakLength { resetCycle() }
    }

    private mutating func resetCycle() {
        phase = .working
        remaining = settings.workInterval
        postponesLeft = settings.postponeLimit
        hold = nil
        isIdle = false
        firstEscapeAt = nil
        startedByUser = false
        breakTotal = settings.breakLength
    }
}

/// The independent check behind the safety net: a break on screen longer than it should ever be.
enum SafetyNet {
    static func isOverdue(shownAt: TimeInterval, now: TimeInterval, breakLength: TimeInterval) -> Bool {
        now - shownAt >= breakLength + BreakSettings.safetyGrace
    }
}
