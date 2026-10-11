import AppKit
import SwiftUI

/// A borderless, non-activating panel that hangs from the notch, above the menu bar.
final class NotchPanel: NSPanel {
    init() {
        super.init(contentRect: .zero,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered,
                   defer: true)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        isMovable = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .none // no system fade on top of the notch's own animation
    }

    // Borderless panels refuse key status by default; the text field needs it.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    // Keep AppKit from pushing the panel below the menu bar.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }

    func setRootView(_ view: some View) {
        let hosting = NSHostingView(rootView: view)
        hosting.sizingOptions = []
        contentView = hosting
    }
}
