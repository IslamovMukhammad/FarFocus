import AppKit
import SwiftUI

/// Native settings: grouped form, system appearance, nothing custom where macOS has a control.
struct SettingsView: View {
    @Bindable var settings: AppSettings
    @State private var openAtLogin = LoginItem.isOn
    @State private var loginNeedsApproval = LoginItem.needsApproval

    var body: some View {
        Form {
            Section {
                Toggle("Remind me to rest my eyes", isOn: $settings.enabled)
                StepperRow(title: "Work for", value: $settings.workMinutes,
                           range: BreakSettings.workMinutesRange, step: 5) { "\($0) min" }
                StepperRow(title: "Rest for", value: $settings.breakSeconds,
                           range: BreakSettings.breakSecondsRange, step: 5) { "\($0) s" }
            } header: {
                Text("Breaks")
            } footer: {
                Text("The 20-20-20 rule: every 20 minutes, look about 20 feet (6 m) away for 20 seconds.")
                    .foregroundStyle(.secondary)
            }

            Section {
                Picker("Warn me", selection: $settings.warningLeadSeconds) {
                    ForEach(BreakSettings.warningLeadChoices, id: \.self) { Text("\($0) s before").tag($0) }
                }
                StepperRow(title: "Postpones per break", value: $settings.postponeLimit,
                           range: BreakSettings.postponeLimitRange, step: 1) { $0 == 0 ? "None" : "\($0)" }
            } header: {
                Text("Before a break")
            } footer: {
                Text("Breaks wait while your screen is shared or recorded, while a display is mirrored, and while a full-screen app plays a video or a presentation. The break comes, with its warning, as soon as that ends.")
                    .foregroundStyle(.secondary)
            }

            Section {
                Picker("Pause the timer after", selection: $settings.idleThresholdSeconds) {
                    ForEach(BreakSettings.idleThresholdChoices, id: \.self) { Text(Self.idleTitle($0)).tag($0) }
                }
            } header: {
                Text("While you're away")
            } footer: {
                Text("Time without keyboard or mouse input doesn't count as work.")
                    .foregroundStyle(.secondary)
            }

            Section("General") {
                Toggle("Open at login", isOn: $openAtLogin)
                    .onChange(of: openAtLogin) { _, on in
                        if !LoginItem.set(on) { openAtLogin = LoginItem.isOn }
                        loginNeedsApproval = LoginItem.needsApproval
                    }
                if loginNeedsApproval {
                    Text("Allow FarFocus in System Settings › General › Login Items.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
    }

    static func idleTitle(_ seconds: Int) -> String {
        seconds < 60 ? "\(seconds) s" : "\(seconds / 60) min"
    }
}

/// "Work for            20 min [-+]": the value sits next to its stepper, like System Settings.
private struct StepperRow: View {
    let title: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    let step: Int
    let format: (Int) -> String

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 6) {
                Text(format(value))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                Stepper(title, value: $value, in: range, step: step)
                    .labelsHidden()
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(format(value))
    }
}

/// The settings window, managed by hand so it can be opened from the menu, from Finder and in demo mode.
@MainActor
final class SettingsWindow {
    static let shared = SettingsWindow()
    private(set) var window: NSWindow?

    var isVisible: Bool { window?.isVisible == true }

    func show() {
        if window == nil {
            let host = NSHostingView(rootView: SettingsView(settings: AppSettings.shared))
            let window = NSWindow(contentRect: NSRect(origin: .zero, size: host.fittingSize),
                                  styleMask: [.titled, .closable, .miniaturizable],
                                  backing: .buffered, defer: false)
            window.title = "FarFocus Settings"
            window.contentView = host
            window.isReleasedWhenClosed = false
            window.center()
            if let screen = Demo.screen {
                // Screenshots: the sharpest display, near the top.
                let area = screen.visibleFrame
                window.setFrameOrigin(NSPoint(x: area.midX - window.frame.width / 2,
                                              y: area.maxY - window.frame.height - 40))
            }
            self.window = window
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}
