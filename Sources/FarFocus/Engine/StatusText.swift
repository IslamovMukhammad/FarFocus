import Foundation

/// The menu-bar text and the menu's status line, derived from the engine.
enum StatusText {

    /// "18m", "45s", "24s"; "due" while a break is held; empty while off or while the break is up.
    static func label(for engine: FarFocusEngine) -> String {
        guard engine.isEnabled else { return "" }
        if engine.hold != nil { return "due" }
        switch engine.phase {
        case .breaking:
            return ""
        case .warning, .starting:
            return "\(engine.secondsLeft)s"
        case .working:
            let seconds = engine.secondsLeft
            if seconds > 60 { return "\(Int((Double(seconds) / 60).rounded(.up)))m" }
            return "\(seconds)s"
        }
    }

    /// The first, greyed line of the menu.
    static func statusLine(for engine: FarFocusEngine) -> String {
        guard engine.isEnabled else { return "Eye breaks are off" }
        if let hold = engine.hold { return "Holding: \(hold.explanation)" }
        switch engine.phase {
        case .breaking: return "Break in progress"
        case .warning, .starting: return "Break in \(duration(engine.secondsLeft))"
        case .working:
            if engine.isIdle { return "Paused while you're away" }
            return "Next break in \(duration(engine.secondsLeft))"
        }
    }

    /// For VoiceOver on the menu-bar item.
    static func accessibilityLabel(for engine: FarFocusEngine) -> String {
        "FarFocus, " + statusLine(for: engine).lowercasedFirst
    }

    /// "18 min", "45 s", "1 min".
    static func duration(_ seconds: Int) -> String {
        if seconds > 60 { return "\(Int((Double(seconds) / 60).rounded(.up))) min" }
        return "\(seconds) s"
    }

    /// "0:24", "1:05", "12:00": the clock style used on the card and the break screen.
    /// `padded`: "00:24" (the card and the break, as the original showed them).
    static func clock(_ seconds: Int, padded: Bool = false) -> String {
        let s = max(0, seconds)
        return (padded ? String(format: "%02d", s / 60) : "\(s / 60)") + ":" + String(format: "%02d", s % 60)
    }
}

private extension String {
    var lowercasedFirst: String { prefix(1).lowercased() + dropFirst() }
}
