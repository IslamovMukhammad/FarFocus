import AppKit
import SwiftUI

/// The display the pointer is on (where the user is looking).
@MainActor
func screenWithPointer() -> NSScreen? {
    if let screen = Demo.screen { return screen }
    let mouse = NSEvent.mouseLocation
    return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main ?? NSScreen.screens.first
}

extension NSScreen {
    /// Stable identity of a display (NSScreen objects can be recreated).
    var displayID: CGDirectDisplayID {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }
}

/// A transparent floating panel that never activates the app or takes keyboard focus.
@MainActor
private func makeFloatingPanel(size: NSSize) -> NSPanel {
    let panel = NSPanel(contentRect: NSRect(origin: .zero, size: size),
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: true)
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = false          // the SwiftUI view draws its own soft shadow
    panel.level = .statusBar
    panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
    panel.isReleasedWhenClosed = false
    panel.hidesOnDeactivate = false
    panel.becomesKeyOnlyIfNeeded = true
    return panel
}

// MARK: - Warning card

@MainActor
final class CardPanel {
    let model = CardModel()
    private var panel: NSPanel?
    private var generation = 0

    var isVisible: Bool { panel?.isVisible == true && model.isPresented }
    /// Shown, or on its way in.
    var isShowing: Bool { panel?.isVisible == true && generation > 0 && wantsShown }
    private var wantsShown = false

    func present() {
        generation += 1
        wantsShown = true
        if panel == nil {
            let host = NSHostingView(rootView: WarningCard(model: model))
            let panel = makeFloatingPanel(size: host.fittingSize)
            panel.contentView = host
            self.panel = panel
        }
        guard let panel, !model.isPresented else { return }
        let size = panel.contentView?.fittingSize ?? panel.frame.size
        if let screen = screenWithPointer() {
            let area = screen.visibleFrame
            // The card's top edge sits 24 pt under the menu bar (as the original); the panel has a margin for the shadow.
            panel.setFrame(NSRect(x: (area.midX - size.width / 2).rounded(),
                                  y: (area.maxY - 24 + WarningCard.margin.top - size.height).rounded(),
                                  width: size.width, height: size.height), display: false)
        }
        panel.orderFrontRegardless()
        Demo.log("card frame \(panel.frame)")
        DispatchQueue.main.async { self.model.isPresented = true }
    }

    func dismiss() {
        wantsShown = false
        guard model.isPresented || panel?.isVisible == true else { return }
        model.isPresented = false
        generation += 1
        let mine = generation
        DispatchQueue.main.asyncAfter(deadline: .now() + WarningCard.exitDuration + 0.05) {
            if self.generation == mine { self.panel?.orderOut(nil) }
        }
    }
}

// MARK: - Countdown next to the pointer

@MainActor
final class CountdownPanel {
    let model = CountdownModel()
    private var panel: NSPanel?
    private var follow: Timer?
    private var generation = 0
    /// Demo override: a fixed pointer position.
    var pointerOverride: NSPoint?
    /// Shown, or on its way in.
    private(set) var isShowing = false

    func present() {
        isShowing = true
        generation += 1
        if panel == nil {
            let panel = makeFloatingPanel(size: CountdownPill.size)
            panel.ignoresMouseEvents = true
            panel.contentView = NSHostingView(rootView: CountdownPill(model: model))
            self.panel = panel
        }
        guard let panel, !model.isPresented else { return }
        position()
        panel.orderFrontRegardless()
        DispatchQueue.main.async { self.model.isPresented = true }
        if follow == nil {
            // Follow the pointer 1:1 at display rate, only during these few seconds.
            let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.position() }
            }
            RunLoop.main.add(timer, forMode: .common)
            follow = timer
        }
    }

    func dismiss() {
        isShowing = false
        follow?.invalidate()
        follow = nil
        guard model.isPresented || panel?.isVisible == true else { return }
        model.isPresented = false
        generation += 1
        let mine = generation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            if self.generation == mine { self.panel?.orderOut(nil) }
        }
    }

    /// Right-below the pointer, never covering it, kept inside the pointer's display.
    private func position() {
        guard let panel else { return }
        let mouse = pointerOverride ?? NSEvent.mouseLocation
        let size = panel.frame.size
        var origin = NSPoint(x: mouse.x + 20 - CountdownPill.inset.leading,
                             y: mouse.y - 12 - size.height + CountdownPill.inset.top)
        if let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) ?? NSScreen.main {
            let b = screen.frame
            origin.x = min(max(origin.x, b.minX + 8), b.maxX - size.width - 8)
            origin.y = min(max(origin.y, b.minY + 8), b.maxY - size.height - 8)
        }
        if panel.frame.origin != origin { panel.setFrameOrigin(origin) }
    }
}

// MARK: - Break screen on every display

/// A borderless, non-activating panel that can still become key. Since macOS 14 a background app may not
/// activate itself, so a plain window would get neither Esc nor the first click; a non-activating panel takes
/// the keyboard without activating the app (and the user's app stays active underneath).
private final class BreakWindow: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class BreakWindows {
    let model = BreakModel()
    private var windows: [NSWindow] = []
    private var generation = 0

    var isVisible: Bool { !windows.isEmpty }
    var windowCount: Int { windows.count }

    /// Covers every display with the same break. The one with the pointer gets the keyboard.
    func present() {
        generation += 1
        guard windows.isEmpty else { return }
        let primaryID = screenWithPointer()?.displayID
        let reduceMotion = Theme.reduceMotion
        Demo.log("break: pointer \(NSEvent.mouseLocation) → display \(primaryID ?? 0); screens \(NSScreen.screens.map { "\($0.displayID): \($0.frame)" })")
        for screen in NSScreen.screens {
            let isPrimary = screen.displayID == primaryID
            let window = BreakWindow(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel],
                                     backing: .buffered, defer: false)
            window.hidesOnDeactivate = false
            window.becomesKeyOnlyIfNeeded = false
            window.isOpaque = false
            window.backgroundColor = .clear
            window.level = .screenSaver
            window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
            window.isReleasedWhenClosed = false
            window.hasShadow = false
            window.animationBehavior = .none
            window.contentView = NSHostingView(rootView: BreakScreen(model: model,
                                                                     screenWidth: screen.frame.width))
            window.setFrame(screen.frame, display: false)
            window.alphaValue = 0
            window.orderFrontRegardless()
            if isPrimary { windows.insert(window, at: 0) } else { windows.append(window) }
        }
        // Keyboard to the display with the pointer, without activating the app.
        windows.first?.makeKeyAndOrderFront(nil)

        // The world goes out of focus: the blur arrives over 600 ms (a plain 200 ms fade with Reduce Motion).
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = reduceMotion ? 0.2 : 0.6
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.23, 1, 0.32, 1)
            for window in windows { window.animator().alphaValue = 1 }
        }
        DispatchQueue.main.async { self.model.isPresented = true }
    }

    func dismiss(hideApp: Bool) {
        guard !windows.isEmpty else { return }
        generation += 1
        let mine = generation
        let closing = windows
        windows.removeAll()
        model.isPresented = false
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = Theme.reduceMotion ? 0.2 : 0.26
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.23, 1, 0.32, 1)
            for window in closing { window.animator().alphaValue = 0 }
        }, completionHandler: {
            MainActor.assumeIsolated {
                for window in closing { window.orderOut(nil) }
                // If the app did end up active (a click on it), hand the keyboard back to the user's app.
                if hideApp && NSApp.isActive && self.generation == mine && self.windows.isEmpty { NSApp.hide(nil) }
            }
        })
    }

    /// Displays came or went mid-break: cover the new arrangement.
    func rebuild() {
        guard !windows.isEmpty else { return }
        for window in windows { window.orderOut(nil) }
        windows.removeAll()
        model.isPresented = false
        present()
    }
}
