import AppKit
import SwiftUI

/// The "focus to infinity" palette: a matte graphite lens barrel, warm ivory engraving and one amber
/// index mark. The floating surfaces (card, countdown, break) are always dark, like a HUD; Settings use the
/// system appearance.
enum Theme {
    static let graphite = Color(red: 0x11 / 255, green: 0x12 / 255, blue: 0x14 / 255)
    static let barrel = Color(red: 0x18 / 255, green: 0x19 / 255, blue: 0x1C / 255)
    static let ivory = Color(red: 0xEC / 255, green: 0xE7 / 255, blue: 0xDD / 255)
    static let ivorySecondary = ivory.opacity(0.66)
    static let ivoryFaint = ivory.opacity(0.40)
    static let hairline = ivory.opacity(0.14)
    static let index = Color(red: 0xF0 / 255, green: 0xA4 / 255, blue: 0x3A / 255)
    static let indexLight = Color(red: 0xFF / 255, green: 0xCD / 255, blue: 0x7E / 255)
    /// The break's big time: a pale warm tone (the original used a pale blue there).
    static let warmLight = Color(red: 0xFB / 255, green: 0xDF / 255, blue: 0xB4 / 255)
    /// Light catching the top edge of a surface, fading out toward the bottom.
    static let rim = LinearGradient(colors: [ivory.opacity(0.26), ivory.opacity(0.06)], startPoint: .top, endPoint: .bottom)

    // Motion (emil-design-eng / animate: strong ease-out for enter/exit, linear for constant travel).
    static func easeOut(_ duration: Double) -> Animation {
        .timingCurve(0.23, 1, 0.32, 1, duration: duration)
    }

    static var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion || Demo.forceReduceMotion }
}

/// The ∞ mark, drawn as a lemniscate (never a font glyph), used in the menu bar, on the card and on the scale.
nonisolated struct InfinityMark: Shape {
    func path(in rect: CGRect) -> Path {
        Path(Self.cgPath(in: rect))
    }

    static func cgPath(in rect: CGRect) -> CGPath {
        let path = CGMutablePath()
        let steps = 96
        let a = rect.width / 2
        let yScale = rect.height / (a * 0.7072)   // the lemniscate's height is ~0.7071 a
        for i in 0...steps {
            let t = Double(i) / Double(steps) * 2 * .pi
            let d = 1 + sin(t) * sin(t)
            let x = a * cos(t) / d
            let y = a * sin(t) * cos(t) / d
            let point = CGPoint(x: rect.midX + x, y: rect.midY + y * yScale / 2)
            if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return path
    }

    /// The menu-bar icon: a template image, so macOS colours it for light and dark menu bars.
    static func menuBarImage() -> NSImage {
        let size = NSSize(width: 18, height: 12)
        let image = NSImage(size: size, flipped: false) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            ctx.addPath(cgPath(in: rect.insetBy(dx: 1.2, dy: 2.4)))
            ctx.setLineWidth(1.7)
            ctx.setLineJoin(.round)
            ctx.setStrokeColor(NSColor.black.cgColor)
            ctx.strokePath()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "FarFocus"
        return image
    }
}

/// Buttons on the floating surfaces. Drawn by hand, because system controls render "inactive" in a panel that
/// never becomes the key window. Prominent: a filled pill; plain: an outlined pill (the original's hierarchy).
struct PillButtonStyle: ButtonStyle {
    var prominent = false
    var large = false

    func makeBody(configuration: Configuration) -> some View {
        Pill(configuration: configuration, prominent: prominent, large: large)
    }

    private struct Pill: View {
        let configuration: ButtonStyleConfiguration
        let prominent: Bool
        let large: Bool
        @Environment(\.isEnabled) private var isEnabled
        @State private var hovering = false

        var body: some View {
            configuration.label
                .font(.system(size: large ? 15 : 12.5, weight: prominent ? .semibold : .medium).monospacedDigit())
                .foregroundStyle(Theme.ivory)
                .padding(.horizontal, large ? 22 : 13)
                .padding(.vertical, large ? 12 : 6.5)
                .background(large ? AnyView(BlurBackdrop(material: .hudWindow).clipShape(Capsule())) : AnyView(Color.clear))
                .background(Capsule().fill(fill))
                .overlay(Capsule().strokeBorder(Theme.ivory.opacity(prominent ? 0.10 : 0.20), lineWidth: 1))
                .opacity(isEnabled ? 1 : 0.35)
                .scaleEffect(configuration.isPressed ? 0.97 : 1)
                .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
                .animation(.easeOut(duration: 0.12), value: hovering)
                .contentShape(Capsule())
                .onHover { hovering = $0 }
        }

        private var fill: Color {
            let base = prominent ? 0.18 : 0.04
            return Theme.ivory.opacity(base + (configuration.isPressed ? 0.12 : (hovering && isEnabled ? 0.07 : 0)))
        }
    }
}

/// Text-only buttons ("Skip").
struct QuietButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(Theme.ivorySecondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}
