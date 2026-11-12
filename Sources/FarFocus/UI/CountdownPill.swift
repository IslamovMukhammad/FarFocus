import SwiftUI

/// The last seconds before the break, beside the pointer (where the eyes already are). Laid out like the original:
/// a small badge, "Break in", the digit. The badge's ring empties over the countdown.
struct CountdownPill: View {
    let model: CountdownModel
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    private var reduceMotion: Bool { systemReduceMotion || Demo.forceReduceMotion }

    static let size = CGSize(width: 200, height: 76)
    /// Room around the pill for its shadow.
    static let inset = EdgeInsets(top: 6, leading: 10, bottom: 20, trailing: 10)

    var body: some View {
        HStack(spacing: 9) {
            Badge(remaining: model.ring, size: 22)
            Text("Break in")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Theme.ivory.opacity(0.85))
            Text("\(model.secondsLeft)")
                .font(.system(size: 17, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(Theme.ivory)
                .contentTransition(reduceMotion ? .identity : .numericText(countsDown: true))
                .animation(reduceMotion ? nil : Theme.easeOut(0.28), value: model.secondsLeft)
                .frame(minWidth: 11)
        }
        .padding(.leading, 8)
        .padding(.trailing, 14)
        .padding(.vertical, 6)
        .darkGlassCapsule()
        .shadow(color: .black.opacity(0.25), radius: 8, y: 5)
        .padding(Self.inset)
        .opacity(model.isPresented ? 1 : 0)
        .scaleEffect(model.isPresented || reduceMotion ? 1 : 0.94, anchor: .topLeading)
        .animation(model.isPresented ? Theme.easeOut(0.2) : Theme.easeOut(0.14), value: model.isPresented)
        .frame(width: Self.size.width, height: Self.size.height, alignment: .topLeading)
        .environment(\.colorScheme, .dark)
        .accessibilityElement()
        .accessibilityLabel("Break in \(model.secondsLeft) seconds")
    }
}
