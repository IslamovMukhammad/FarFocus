import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: FarFocusController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !Self.isRunningTests else { return }
        NSApp.setActivationPolicy(.accessory)
        let controller = FarFocusController(settings: AppSettings.shared)
        self.controller = controller
        controller.start()
        if Demo.isOn {
            Demo.run(controller)
        } else if !launchedAsLoginItem && !UserDefaults.standard.bool(forKey: "launchedBefore") {
            // First launch: show Settings once so the app is discoverable.
            UserDefaults.standard.set(true, forKey: "launchedBefore")
            SettingsWindow.shared.show()
        }
    }

    /// Opening the app again (Finder, Spotlight) shows Settings: the way back if the menu-bar item is hidden.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        SettingsWindow.shared.show()
        return false
    }

    static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || ProcessInfo.processInfo.arguments.contains { $0.contains("swiftpm-testing-helper") || $0.hasSuffix(".xctest") }
    }

    private var launchedAsLoginItem: Bool {
        guard let event = NSAppleEventManager.shared().currentAppleEvent else { return false }
        return event.eventID == kAEOpenApplication
            && event.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
    }
}
