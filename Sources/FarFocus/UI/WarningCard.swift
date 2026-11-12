import SwiftUI

/// The card that says a break is coming, at the top centre. Laid out like the original app's card: the badge on the
/// left; the time, one line of text and the buttons on the right. It never takes keyboard focus.
struct WarningCard: View {
    let model: CardModel
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    private var reduceMotion: Bool { systemReduceMotion || Demo.forceReduceMotion }

    static let width: CGFloat = 560
    /// How long the card takes to leave (the panel is ordered out right after).
    static let exitDuration = 0.5
    /// Room around the card for its shadow (the panel is transparent there).
    static let margin = EdgeInsets(top: 8, leading: 26, bottom: 34, trailing: 26)

    var body: some View {
        HStack(spacing: 16) {
            Badge(remaining: model.ring, size: 44)
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(StatusText.clock(model.secondsLeft, padded: true))
                        .font(.system(size: 26, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(Theme.ivory)
                        .contentTransition(reduceMotion ? .identity : .numericText(countsDown: true))
                        .animation(reduceMotion ? nil : Theme.easeOut(0.25), value: model.secondsLeft)
                    Text("A short eye break is coming up. Wrap up your thought.")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.ivorySecondary)
                }
                actions
            }
            Spacer(minLength: 0)
        }
        .padding(18)
        .frame(width: Self.width)
        .darkGlass(cornerRadius: 22)
        .shadow(color: .black.opacity(0.3), radius: 16, y: 8)
        .padding(Self.margin)
        // Arrives from under the menu bar and comes into focus; after its 10 s it goes back up the same way,
        // softening out of focus (slow enough to be seen leaving, never a sudden vanish).
        .opacity(model.isPresented ? 1 : 0)
        .blur(radius: model.isPresented || reduceMotion ? 0 : 8)
        .scaleEffect(model.isPresented || reduceMotion ? 1 : 0.96, anchor: .top)
        .offset(y: model.isPresented || reduceMotion ? 0 : -18)
        .animation(model.isPresented ? Theme.easeOut(reduceMotion ? 0.2 : 0.35)
                                     : .timingCurve(0.4, 0, 0.2, 1, duration: WarningCard.exitDuration),
                   value: model.isPresented)
        .environment(\.colorScheme, .dark)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Eye break in \(model.secondsLeft) seconds")
    }

    private var actions: some View {
        HStack(spacing: 8) {
            // Starting early is always possible, even with no postpones left.
            Button("Start now", action: model.startNow)
                .buttonStyle(PillButtonStyle(prominent: true))
            ForEach(BreakSettings.postponeChoices, id: \.self) { minutes in
                Button("+\(minutes)m") { model.postpone(minutes) }
                    .buttonStyle(PillButtonStyle())
                    .disabled(model.postponesLeft == 0)
                    .help(model.postponesLeft == 0 ? "No postpones left for this break"
                                                   : "Postpone \(minutes) min (\(model.postponesLeft) of \(model.postponeLimit) left)")
                    .accessibilityLabel("Postpone \(minutes) minute\(minutes == 1 ? "" : "s")")
            }
            Spacer(minLength: 8)
            Button("Skip", action: model.skip)
                .buttonStyle(QuietButtonStyle())
                .accessibilityLabel("Skip this break")
        }
    }
}
