import Foundation

/// The badge ring: how much of a stretch of time is left (1 = full, 0 = empty).
/// A surface shows it full the moment it appears (set without animation), then the ring glides, linearly, to where
/// it will be one second later, and again on every tick, so it drains smoothly and never fills up on screen.
enum Ring {
    static func now(remaining: TimeInterval, total: TimeInterval) -> Double {
        guard total > 0 else { return 0 }
        return min(1, max(0, remaining / total))
    }

    /// Where the ring will be one tick (1 s) from now.
    static func inOneSecond(remaining: TimeInterval, total: TimeInterval) -> Double {
        now(remaining: remaining - 1, total: total)
    }
}
