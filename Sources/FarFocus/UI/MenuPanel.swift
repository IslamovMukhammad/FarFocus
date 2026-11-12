import AppKit
import Observation
import SwiftUI

/// What the menu-bar item and its panel show. The controller writes it only when something changed,
/// so the menu bar is redrawn about once a minute far from a break.
@MainActor @Observable
final class PanelModel {
    static let shared = PanelModel()

    var label = ""
    var isEnabled = true
    var statusLine = ""
    var accessibilityLabel = "FarFocus"
    var canStartNow = true

    @ObservationIgnored var startNow: () -> Void = {}
}

/// The menu-bar item: the drawn ∞ and the time to the next break ("18m", "45s", "due").
struct MenuBarLabel: View {
    let model: PanelModel

    var body: some View {
        HStack(spacing: 4) {
            Image(nsImage: InfinityMark.menuBarImage())
            if !model.label.isEmpty {
                Text(model.label).monospacedDigit()
            }
        }
        .opacity(model.isEnabled ? 1 : 0.5)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(model.accessibilityLabel)
    }
}

/// The panel under the menu-bar item, as in the original app: the eye-break header with the time, Break now,
/// the on/off switch and quick choices for Every and Rest; then Settings and Quit.
struct MenuPanel: View {
    let model: PanelModel
    @Bindable var settings: AppSettings

    static let workChoices = [10, 15, 20, 30, 45, 60]
    static let restChoices = [20, 30, 45, 60]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Badge(remaining: nil, size: 32)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Eye break")
                        .font(.system(size: 13, weight: .semibold))
                    Text(model.statusLine)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Text(model.label)
                    .font(.system(size: 12, weight: .medium).monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                Button("Break now", action: model.startNow)
                    .buttonStyle(.glass)
                    .disabled(!model.isEnabled || !model.canStartNow)
                Spacer()
                Toggle("Eye breaks", isOn: $settings.enabled)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .labelsHidden()
            }

            HStack(spacing: 16) {
                QuickChoice(label: "Every", value: $settings.workMinutes,
                            options: Self.workChoices, suffix: "m")
                QuickChoice(label: "Rest", value: $settings.breakSeconds,
                            options: Self.restChoices, suffix: "s")
                Spacer()
            }
            .disabled(!model.isEnabled)

            Divider()

            HStack {
                Button("Settings…") { SettingsWindow.shared.show() }
                    .keyboardShortcut(",")
                Spacer()
                Button("Quit FarFocus") { NSApp.terminate(nil) }
                    .keyboardShortcut("q")
            }
            .buttonStyle(.borderless)
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(width: 300)
    }
}

/// "Every [20m ▾]": a small pop-up of common values. A value set in Settings that isn't in the list is added,
/// so the pop-up never shows a blank.
private struct QuickChoice: View {
    let label: String
    @Binding var value: Int
    let options: [Int]
    let suffix: String

    var body: some View {
        HStack(spacing: 5) {
            Text(label)
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
            Picker(label, selection: $value) {
                ForEach(Array(Set(options + [value])).sorted(), id: \.self) { option in
                    Text("\(option)\(suffix)").tag(option)
                }
            }
            .labelsHidden()
            .controlSize(.small)
            .fixedSize()
        }
    }
}
