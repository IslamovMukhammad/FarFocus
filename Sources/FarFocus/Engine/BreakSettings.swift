import Foundation

/// The numbers that shape a cycle. Plain values, so the engine can be tested without UserDefaults.
struct BreakSettings: Equatable, Sendable {
    /// Active work between two breaks.
    var workInterval: TimeInterval = 20 * 60
    /// How long a break lasts.
    var breakLength: TimeInterval = 20
    /// How long before the break the warning card appears.
    var warningLead: TimeInterval = 30
    /// Postpones allowed per cycle (refilled after every break or skip).
    var postponeLimit: Int = 4
    /// No keyboard or mouse for this long and the work timer stops.
    var idleThreshold: TimeInterval = 60

    /// The countdown next to the pointer, right before the break.
    static let countdownLength: TimeInterval = 5
    /// The postpone choices on the warning card, in minutes.
    static let postponeChoices = [1, 5, 15]
    /// Two Esc presses within this window end a break.
    static let escapeWindow: TimeInterval = 1.5
    /// The safety net releases the screen this long after a break should have ended.
    static let safetyGrace: TimeInterval = 10
    /// How long the warning card stays up before it leaves on its own (the user's choice, 2026-11-12: appear at
    /// 0:30, stay until 0:20, then animate away).
    static let cardMaxVisible: TimeInterval = 10

    /// The warning lead actually used: never shorter than the countdown, never longer than the work interval.
    var effectiveLead: TimeInterval {
        min(max(warningLead, Self.countdownLength), max(workInterval, Self.countdownLength))
    }

    /// How long the card is on screen: 10 s (with the default 30 s lead, from 0:30 down to 0:20).
    var cardVisibleFor: TimeInterval {
        max(0, min(Self.cardMaxVisible, effectiveLead - Self.countdownLength))
    }

    // Ranges offered in Settings.
    static let workMinutesRange = 5...120
    static let breakSecondsRange = 10...120
    static let warningLeadChoices = [10, 15, 20, 30, 45, 60, 90]
    static let postponeLimitRange = 0...10
    static let idleThresholdChoices = [30, 60, 120, 180, 300, 600]
}

/// Why a due break is waiting instead of covering the screen.
enum HoldReason: Equatable, Sendable {
    case screenShared
    case mirroredDisplay
    case fullScreenMedia

    /// For the menu: "Holding: …".
    var explanation: String {
        switch self {
        case .screenShared: "your screen is being shared or recorded"
        case .mirroredDisplay: "your display is mirrored"
        case .fullScreenMedia: "a full-screen video or presentation is playing"
        }
    }
}
