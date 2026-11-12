import Foundation
import Observation

/// What the warning card shows. The controller writes, the view reads.
@MainActor @Observable
final class CardModel {
    var secondsLeft = 30
    /// The badge ring: the time to the break as a share of the warning lead (see `Ring`).
    var ring = 1.0
    var postponesLeft = 4
    var postponeLimit = 4
    var isPresented = false

    var startNow: () -> Void = {}
    var postpone: (Int) -> Void = { _ in }
    var skip: () -> Void = {}
}

/// The countdown beside the pointer.
@MainActor @Observable
final class CountdownModel {
    var secondsLeft = 5
    /// The badge ring: the countdown's time left (see `Ring`).
    var ring = 1.0
    var isPresented = false
}

/// The break screen, shared by every display's window.
@MainActor @Observable
final class BreakModel {
    var secondsLeft = 20
    var progress = 0.0
    var postponesLeft = 4
    var escapeHint = false
    var isPresented = false

    var endBreak: () -> Void = {}
    var turnOffDisplay: () -> Void = {}
}
