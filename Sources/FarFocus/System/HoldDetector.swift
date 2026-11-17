import AppKit
import CoreGraphics
import IOKit.pwr_mgt

/// Answers "should a due break wait right now?". Every check is cheap and needs no permission.
/// Focus / Do Not Disturb is not one of them: macOS only reports Focus to messaging apps (see the README).
@MainActor
final class HoldDetector {

    /// Demo/testing override: `FARFOCUS_FAKE_HOLD=share|mirror|media`.
    var forced: HoldReason?

    func current() -> HoldReason? {
        if let forced { return forced }
        if Demo.ignoreHolds { return nil }
        if Self.screenIsCaptured() { return .screenShared }
        if Self.displayIsMirrored() { return .mirroredDisplay }
        if Self.fullScreenMediaIsPlaying() { return .fullScreenMedia }
        return nil
    }

    // MARK: Screen sharing / recording

    private typealias WatcherFunction = @convention(c) () -> Bool

    /// `SLSIsScreenWatcherPresent` (SkyLight, private): true while any app captures the screen, which
    /// covers screen sharing in calls and screen recording. If it ever disappears, this check is skipped.
    private static let screenWatcher: WatcherFunction? = {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY),
              let symbol = dlsym(handle, "SLSIsScreenWatcherPresent") else { return nil }
        return unsafeBitCast(symbol, to: WatcherFunction.self)
    }()

    static func screenIsCaptured() -> Bool {
        screenWatcher?() ?? false
    }

    // MARK: Mirroring (a projector showing the same picture)

    static func displayIsMirrored() -> Bool {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return false }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &ids, &count) == .success else { return false }
        return ids.prefix(Int(count)).contains { CGDisplayIsInMirrorSet($0) != 0 }
    }

    // MARK: Full-screen video or slideshow

    /// The frontmost app covers a whole display AND something is keeping the display awake for media
    /// (video players, browsers playing video and slideshows take a "prevent display sleep" assertion).
    /// A full-screen editor or terminal alone does not hold breaks.
    static func fullScreenMediaIsPlaying() -> Bool {
        guard let front = NSWorkspace.shared.frontmostApplication else { return false }
        let pid = front.processIdentifier
        guard frontmostCoversADisplay(pid: pid) else { return false }
        return displaySleepIsPrevented(byPID: pid)
    }

    private static func frontmostCoversADisplay(pid: pid_t) -> Bool {
        guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                       kCGNullWindowID) as? [[String: Any]] else { return false }
        var count: UInt32 = 0
        CGGetActiveDisplayList(0, nil, &count)
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        CGGetActiveDisplayList(count, &ids, &count)
        let displays = ids.prefix(Int(count)).map { CGDisplayBounds($0) }
        for window in windows {
            guard (window[kCGWindowOwnerPID as String] as? pid_t) == pid,
                  let dict = window[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: dict as CFDictionary) else { continue }
            if displays.contains(where: { covers(bounds, $0) }) { return true }
        }
        return false
    }

    static func covers(_ window: CGRect, _ display: CGRect) -> Bool {
        abs(window.minX - display.minX) <= 1 && abs(window.minY - display.minY) <= 1
            && window.width >= display.width - 1 && window.height >= display.height - 1
    }

    private static func displaySleepIsPrevented(byPID pid: pid_t) -> Bool {
        var unmanaged: Unmanaged<CFDictionary>?
        guard IOPMCopyAssertionsByProcess(&unmanaged) == kIOReturnSuccess,
              let byProcess = unmanaged?.takeRetainedValue() as? [NSNumber: [[String: Any]]] else { return false }
        return byProcess.contains { owner, assertions in
            assertions.contains { assertion in
                isMediaAssertion(assertion, ownedByFrontmost: owner.int32Value == pid)
            }
        }
    }

    /// A display-sleep assertion counts when the frontmost app owns it, or when its name says media
    /// (browsers play video in a helper process: "WebKit Media Playback", "Video Wake Lock", …).
    static func isMediaAssertion(_ assertion: [String: Any], ownedByFrontmost: Bool) -> Bool {
        let type = assertion[kIOPMAssertionTypeKey as String] as? String ?? ""
        guard type == kIOPMAssertionTypePreventUserIdleDisplaySleep as String
                || type == kIOPMAssertionTypeNoDisplaySleep as String else { return false }
        if ownedByFrontmost { return true }
        let name = (assertion[kIOPMAssertionNameKey as String] as? String ?? "").lowercased()
        return ["media", "video", "playback", "presentation", "slideshow"].contains { name.contains($0) }
    }
}
