import SwiftUI

/// The app's badge: a warm amber disc with the drawn ∞, and an optional thin ring around it that empties as the time
/// runs out (the warning on the card, the last seconds beside the pointer).
struct Badge: View {
    /// 1 = full ring, 0 = empty. `nil` hides the ring.
    var remaining: Double?
    var size: CGFloat = 46
    /// How long the ring takes to reach the next value (the engine ticks once a second).
    var tick: Double = 1
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    private var reduceMotion: Bool { systemReduceMotion || Demo.forceReduceMotion }

    var body: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [Theme.indexLight, Theme.index],
                                     center: UnitPoint(x: 0.35, y: 0.3), startRadius: 0, endRadius: size * 0.7))
            Circle()
                .strokeBorder(Color.white.opacity(0.25), lineWidth: 1)
            InfinityMark()
                .stroke(Theme.graphite.opacity(0.85),
                        style: StrokeStyle(lineWidth: max(1.5, size * 0.05), lineJoin: .round))
                .frame(width: size * 0.5, height: size * 0.23)
        }
        .frame(width: size, height: size)
        .padding(remaining == nil ? 0 : size * 0.1)
        .overlay {
            if let remaining {
                ZStack {
                    Circle().stroke(Theme.ivory.opacity(0.12), lineWidth: max(1.5, size * 0.045))
                    Circle()
                        .trim(from: 0, to: max(0.0001, min(1, remaining)))
                        .stroke(Theme.index, style: StrokeStyle(lineWidth: max(1.5, size * 0.045), lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        // Constant motion: linear, re-targeted every tick, so it never stalls between seconds.
                        .animation(reduceMotion ? nil : .linear(duration: tick), value: remaining)
                }
            }
        }
        .accessibilityHidden(true)
    }
}

/// A key cap for "esc".
struct KeyCap: View {
    let label: String

    var body: some View {
        Text(label)
            .font(.system(size: 11.5, weight: .semibold))
            .foregroundStyle(Theme.ivory.opacity(0.85))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Theme.ivory.opacity(0.14)))
            .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(Theme.ivory.opacity(0.2), lineWidth: 1))
    }
}

extension View {
    /// The floating surfaces' material: an always-dark frosted HUD (what is behind shows through, blurred),
    /// a graphite tint for depth and contrast, and a rim of light along the top edge.
    /// Not Liquid Glass: macOS 26 glass turns light over light content (a white document), and the light text
    /// on it became unreadable in testing. With Reduce Transparency macOS makes the frost solid by itself.
    func darkGlass(cornerRadius: CGFloat) -> some View {
        background(
            ZStack {
                BlurBackdrop(material: .hudWindow)
                Theme.graphite.opacity(0.55)
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        )
        .overlay(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).strokeBorder(Theme.rim, lineWidth: 1))
    }

    func darkGlassCapsule() -> some View {
        background(
            ZStack {
                BlurBackdrop(material: .hudWindow)
                Theme.graphite.opacity(0.6)
            }
            .clipShape(Capsule())
        )
        .overlay(Capsule().strokeBorder(Theme.rim, lineWidth: 1))
    }
}
