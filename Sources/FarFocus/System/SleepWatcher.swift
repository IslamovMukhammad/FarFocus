import AppKit

/// Reports when nobody can see the screen (Mac asleep, displays asleep, screen locked) and for how long.
/// Sleep length is measured on `ContinuousClock`, which keeps counting through sleep and ignores clock changes.
@MainActor
final class SleepWatcher {

    var onSleep: (() -> Void)?
    var onWake: ((TimeInterval) -> Void)?

    private enum Reason: Hashable { case system, screens, locked }
    private var reasons: Set<Reason> = []
    private var since: ContinuousClock.Instant?
    private var tokens: [(NotificationCenter, NSObjectProtocol)] = []

    func start() {
        let workspace = NSWorkspace.shared.notificationCenter
        observe(workspace, NSWorkspace.willSleepNotification) { $0.begin(.system) }
        observe(workspace, NSWorkspace.didWakeNotification) { $0.end(.system) }
        observe(workspace, NSWorkspace.screensDidSleepNotification) { $0.begin(.screens) }
        observe(workspace, NSWorkspace.screensDidWakeNotification) { $0.end(.screens) }
        let distributed = DistributedNotificationCenter.default()
        observe(distributed, Notification.Name("com.apple.screenIsLocked")) { $0.begin(.locked) }
        observe(distributed, Notification.Name("com.apple.screenIsUnlocked")) { $0.end(.locked) }
        if Demo.isOn {
            // Testing only: the same path as a lock, without telling every other app the screen locked.
            observe(distributed, Notification.Name("FarFocus.test.lock")) { $0.begin(.locked) }
            observe(distributed, Notification.Name("FarFocus.test.unlock")) { $0.end(.locked) }
        }
    }

    private func observe(_ center: NotificationCenter, _ name: Notification.Name,
                         _ action: @escaping @MainActor (SleepWatcher) -> Void) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                action(self)
            }
        }
        tokens.append((center, token))
    }

    private func begin(_ reason: Reason) {
        let wasAwake = reasons.isEmpty
        reasons.insert(reason)
        guard wasAwake else { return }
        since = .now
        onSleep?()
    }

    private func end(_ reason: Reason) {
        guard reasons.remove(reason) != nil, reasons.isEmpty else { return }
        let slept = since.map { ContinuousClock.now - $0 } ?? .zero
        since = nil
        let seconds = Double(slept.components.seconds) + Double(slept.components.attoseconds) / 1e18
        onWake?(seconds)
    }
}
