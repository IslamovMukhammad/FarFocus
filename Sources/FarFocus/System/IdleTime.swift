import CoreGraphics

/// Seconds since the last keyboard or mouse input, system-wide. Needs no permission.
enum IdleTime {
    private static let inputs: [CGEventType] = [
        .keyDown, .flagsChanged, .mouseMoved, .leftMouseDown, .rightMouseDown, .otherMouseDown,
        .leftMouseDragged, .scrollWheel,
    ]

    static func seconds() -> Double {
        inputs.map { CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: $0) }.min() ?? 0
    }
}
