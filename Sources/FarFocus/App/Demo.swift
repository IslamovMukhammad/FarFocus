import AppKit

/// Demo mode, for screenshots and for watching a whole cycle quickly. Settings go to a throwaway store,
/// never yours.
///
///     FARFOCUS_DEMO=card        build/FarFocus.app/Contents/MacOS/FarFocus   # the warning card, 0:27, 2 of 4 postpones left
///     FARFOCUS_DEMO=countdown   …   # the countdown next to the pointer, 3 s
///     FARFOCUS_DEMO=break       …   # the break screen on every display, 0:11 left
///     FARFOCUS_DEMO=settings    …   # the Settings window
///     FARFOCUS_DEMO=live        …   # runs for real, with the short intervals below
///
/// `FARFOCUS_WORK_SECONDS`, `FARFOCUS_BREAK_SECONDS`, `FARFOCUS_LEAD_SECONDS` shrink the cycle (live mode).
/// `FARFOCUS_FAKE_HOLD=share|mirror|media|focus` pretends a hold is active.
/// Testing: `FARFOCUS_IDLE_SECONDS` (a short idle threshold), `FARFOCUS_TEST_STALL=1` (the timer stops when a
/// break starts, so only the safety net can end it), `FARFOCUS_LOG=1` (state changes to stderr),
/// `FARFOCUS_REDUCE_MOTION=1`, and the `FarFocus.test.lock` / `FarFocus.test.unlock` distributed notifications.
/// `FARFOCUS_BACKDROP=1` covers every display with a plain made-up desk first, so nothing personal shows.
@MainActor
enum Demo {
    static let env = ProcessInfo.processInfo.environment
    static let mode = env["FARFOCUS_DEMO"]
    static var isOn: Bool { mode != nil }

    static let defaults: UserDefaults = {
        let suite = "FarFocus.demo"
        UserDefaults().removePersistentDomain(forName: suite)
        return UserDefaults(suiteName: suite) ?? .standard
    }()

    static var workSeconds: TimeInterval? { isOn ? env["FARFOCUS_WORK_SECONDS"].flatMap(Double.init) : nil }
    static var breakSeconds: TimeInterval? { isOn ? env["FARFOCUS_BREAK_SECONDS"].flatMap(Double.init) : nil }
    static var leadSeconds: TimeInterval? { isOn ? env["FARFOCUS_LEAD_SECONDS"].flatMap(Double.init) : nil }

    static var idleSeconds: TimeInterval? { isOn ? env["FARFOCUS_IDLE_SECONDS"].flatMap(Double.init) : nil }
    static var logging: Bool { env["FARFOCUS_LOG"] == "1" }
    /// `FARFOCUS_REDUCE_MOTION=1`: render as if Reduce Motion were on (screenshots of the still variant).
    /// `FARFOCUS_NO_HOLDS=1`: never hold (to film the app: recording the screen is itself a reason to hold).
    static var ignoreHolds: Bool { isOn && env["FARFOCUS_NO_HOLDS"] == "1" }
    static var forceReduceMotion: Bool { isOn && env["FARFOCUS_REDUCE_MOTION"] == "1" }

    /// Debug line to stderr when `FARFOCUS_LOG=1`.
    static func log(_ line: @autoclosure () -> String) {
        guard logging else { return }
        FileHandle.standardError.write(Data((line() + "\n").utf8))
    }
    static var stallAtBreak: Bool { isOn && env["FARFOCUS_TEST_STALL"] == "1" }

    static var fakeHold: HoldReason? {
        guard isOn else { return nil }
        switch env["FARFOCUS_FAKE_HOLD"] {
        case "share": return .screenShared
        case "mirror": return .mirroredDisplay
        case "media": return .fullScreenMedia
        case "focus": return .focus
        default: return nil
        }
    }

    /// Screenshot modes use the sharpest display instead of the one with the pointer.
    static var screen: NSScreen? {
        guard isOn, mode != "live" else { return nil }
        return NSScreen.screens.max { $0.backingScaleFactor < $1.backingScaleFactor }
    }

    private static var backdrops: [NSWindow] = []

    static func run(_ controller: FarFocusController) {
        if env["FARFOCUS_BACKDROP"] == "1" { showBackdrop() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            switch mode {
            case "card":
                controller.demoShow { e in
                    e = FarFocusEngine()
                    tick(&e, 1170)
                    e.postpone(minutes: 1)
                    tick(&e, 30)
                    e.postpone(minutes: 1)
                    tick(&e, 33)   // 0:27: inside the card's 10 s (0:30 → 0:20)
                }
            case "countdown":
                if let screen = Demo.screen {
                    controller.demoCountdown.pointerOverride = NSPoint(x: screen.frame.midX - 160,
                                                                       y: screen.frame.midY + 40)
                }
                controller.demoShow { e in
                    e = FarFocusEngine()
                    e.startNow()
                    tick(&e, 2)
                }
            case "break":
                controller.demoShow { e in
                    e = FarFocusEngine()
                    e.startNow()
                    tick(&e, 14)
                }
            case "settings":
                SettingsWindow.shared.show()
            default:
                break   // "live": the controller already runs with the short intervals
            }
        }
    }

    private static func tick(_ e: inout FarFocusEngine, _ seconds: Int) {
        for _ in 0..<seconds { e.advance(by: 1, idle: 0, hold: nil) }
    }

    /// A made-up desk on every display: a calm gradient and a blank document window, under everything
    /// the app draws (the break blurs it, the card floats over it).
    private static func showBackdrop() {
        for screen in NSScreen.screens {
            let window = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
            window.level = .statusBar   // over the Dock and the menu bar; the app's own panels order in front of it
            window.isOpaque = true
            window.hasShadow = false
            window.ignoresMouseEvents = true
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            window.contentView = DeskView(frame: NSRect(origin: .zero, size: screen.frame.size))
            window.setFrame(screen.frame, display: true)
            window.orderFrontRegardless()
            backdrops.append(window)
        }
    }

    private final class DeskView: NSView {
        override func draw(_ dirtyRect: NSRect) {
            NSGradient(colors: [NSColor(srgbRed: 0.27, green: 0.35, blue: 0.40, alpha: 1),
                                NSColor(srgbRed: 0.46, green: 0.52, blue: 0.50, alpha: 1),
                                NSColor(srgbRed: 0.72, green: 0.66, blue: 0.56, alpha: 1)])?
                .draw(in: bounds, angle: -55)
            // A blank "document": a window with grey lines standing in for text.
            let doc = NSRect(x: bounds.midX - 380, y: bounds.midY - 250, width: 760, height: 480)
            NSShadow().then {
                $0.shadowColor = NSColor.black.withAlphaComponent(0.25)
                $0.shadowBlurRadius = 30
                $0.shadowOffset = NSSize(width: 0, height: -10)
                $0.set()
            }
            NSColor(white: 0.98, alpha: 1).setFill()
            NSBezierPath(roundedRect: doc, xRadius: 12, yRadius: 12).fill()
            NSShadow().set()
            NSColor(white: 0.92, alpha: 1).setFill()
            NSBezierPath(rect: NSRect(x: doc.minX, y: doc.maxY - 36, width: doc.width, height: 24)).fill()
            NSBezierPath(roundedRect: NSRect(x: doc.minX, y: doc.maxY - 36, width: doc.width, height: 36),
                         xRadius: 12, yRadius: 12).fill()
            for (i, color) in [NSColor.systemRed, .systemYellow, .systemGreen].enumerated() {
                color.withAlphaComponent(0.8).setFill()
                NSBezierPath(ovalIn: NSRect(x: doc.minX + 16 + CGFloat(i) * 20, y: doc.maxY - 24, width: 12, height: 12)).fill()
            }
            let widths: [CGFloat] = [0.62, 0.88, 0.80, 0.92, 0.45, 0, 0.86, 0.90, 0.74, 0.83, 0.52, 0, 0.90, 0.68]
            for (i, w) in widths.enumerated() where w > 0 {
                NSColor(white: i == 0 ? 0.55 : 0.80, alpha: 1).setFill()
                let y = doc.maxY - 80 - CGFloat(i) * 26
                NSBezierPath(roundedRect: NSRect(x: doc.minX + 48, y: y, width: (doc.width - 96) * w, height: i == 0 ? 14 : 9),
                             xRadius: 4, yRadius: 4).fill()
            }
        }
    }
}

private extension NSShadow {
    func then(_ body: (NSShadow) -> Void) { body(self) }
}
