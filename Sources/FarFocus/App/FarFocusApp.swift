import AppKit
import SwiftUI

/// A menu-bar app: no Dock icon, no main window. The item opens a panel (window style, like Control Center).
@main
struct FarFocusApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra {
            MenuPanel(model: PanelModel.shared, settings: AppSettings.shared)
        } label: {
            MenuBarLabel(model: PanelModel.shared)
        }
        .menuBarExtraStyle(.window)
    }
}
