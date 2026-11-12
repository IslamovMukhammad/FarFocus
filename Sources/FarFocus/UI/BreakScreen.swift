import AppKit
import SwiftUI

/// The break itself, the same on every display. Laid out like the original app's break: the time of day at the top;
/// the big line, the sub-line, a short line under them and the time left in the middle; the two buttons, the
/// postpones line and the Esc hint at the bottom. Here the short line fills with amber as the break runs.
struct BreakScreen: View {
    let model: BreakModel
    let screenWidth: CGFloat
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    private var reduceMotion: Bool { systemReduceMotion || Demo.forceReduceMotion }

    var body: some View {
        ZStack {
            BlurBackdrop(material: .hudWindow)
            // The defocused screen, dimmed: a touch darker at the top, a touch warmer toward the bottom.
            LinearGradient(colors: [Theme.graphite.opacity(0.42), Theme.graphite.opacity(0.26),
                                    Color(red: 0.18, green: 0.13, blue: 0.08).opacity(0.34)],
                           startPoint: .top, endPoint: .bottom)

            VStack(spacing: 0) {
                TimelineView(.everyMinute) { context in
                    Text(context.date, format: .dateTime.hour().minute())
                        .font(.system(size: 17, weight: .semibold).monospacedDigit())
                        .foregroundStyle(Theme.ivory.opacity(0.85))
                }
                .padding(.top, 42)
                .stagger(0, model.isPresented, reduceMotion)

                Spacer()

                Text("Let your eyes go far")
                    .font(.system(size: 62, weight: .bold))
                    .tracking(-1)
                    .foregroundStyle(Theme.ivory)
                    .multilineTextAlignment(.center)
                    .stagger(1, model.isPresented, reduceMotion)
                Text("Look at something at least six metres away until the time is up")
                    .font(.system(size: 20))
                    .foregroundStyle(Theme.ivory.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .padding(.top, 14)
                    .stagger(2, model.isPresented, reduceMotion)

                ProgressLine(progress: model.progress, reduceMotion: reduceMotion)
                    .padding(.top, 40)
                    .stagger(3, model.isPresented, reduceMotion)

                Text(StatusText.clock(model.secondsLeft, padded: true))
                    .font(.system(size: 44, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(Theme.warmLight)
                    .contentTransition(reduceMotion ? .identity : .numericText(countsDown: true))
                    .animation(reduceMotion ? nil : Theme.easeOut(0.3), value: model.secondsLeft)
                    .padding(.top, 34)
                    .accessibilityLabel("\(model.secondsLeft) seconds left")
                    .stagger(4, model.isPresented, reduceMotion)

                Spacer()

                controls
                    .stagger(5, model.isPresented, reduceMotion)
            }
            .padding(.horizontal, 40)
        }
        .ignoresSafeArea()
        .environment(\.colorScheme, .dark)
    }

    private var controls: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Button(action: model.endBreak) {
                    Label("End break", systemImage: "forward.end")
                }
                Button(action: model.turnOffDisplay) {
                    Label("Turn off display", systemImage: "moon")
                }
                .help("Puts the displays to sleep. If they stay off for the length of a break, it counts as taken.")
            }
            // Drawn by hand: only one display's window holds the keyboard, and system buttons in the others
            // would render as inactive.
            .buttonStyle(PillButtonStyle(large: true))

            Text(postponesLine)
                .font(.system(size: 13))
                .foregroundStyle(Theme.ivorySecondary)
                .padding(.top, 16)
            HStack(spacing: 6) {
                Text("Press")
                KeyCap(label: "esc")
                Text(model.escapeHint ? "again to end the break" : "twice to end the break")
            }
            .font(.system(size: 13))
            .foregroundStyle(model.escapeHint ? Theme.index : Theme.ivorySecondary)
            .animation(.easeOut(duration: 0.15), value: model.escapeHint)
            .padding(.top, 8)
        }
        .padding(.bottom, 46)
    }

    private var postponesLine: String {
        switch model.postponesLeft {
        case 0: "No postpones left"
        case 1: "1 postpone left"
        default: "\(model.postponesLeft) postpones left"
        }
    }
}

/// The short line under the words: a hairline track that fills with amber over the break (constant: linear).
/// Reduce Motion: it steps once a second without sliding.
private struct ProgressLine: View {
    let progress: Double
    let reduceMotion: Bool
    static let width: CGFloat = 96

    var body: some View {
        ZStack(alignment: .leading) {
            Capsule().fill(Theme.ivory.opacity(0.28))
            Capsule()
                .fill(Theme.index)
                .frame(width: max(2, Self.width * min(1, max(0, progress))))
                .animation(reduceMotion ? nil : .linear(duration: 1), value: progress)
        }
        .frame(width: Self.width, height: 2)
        .accessibilityElement()
        .accessibilityLabel("Break progress")
        .accessibilityValue("\(Int(progress * 100)) percent")
    }
}

private extension View {
    /// The break arrives in order, top to bottom, 50 ms apart (a rare moment: the slower, calmer entrance is
    /// earned). Reduce Motion: a plain fade.
    func stagger(_ step: Int, _ shown: Bool, _ reduceMotion: Bool) -> some View {
        opacity(shown ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : 10)
            .animation(shown ? Theme.easeOut(reduceMotion ? 0.2 : 0.5).delay(reduceMotion ? 0 : 0.12 + Double(step) * 0.05)
                             : Theme.easeOut(0.2),
                       value: shown)
    }
}

/// Whatever is behind the window, out of focus. Needs no screen-recording permission.
/// With Reduce Transparency macOS makes it solid by itself.
struct BlurBackdrop: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .fullScreenUI

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .active
        view.appearance = NSAppearance(named: .darkAqua)
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
