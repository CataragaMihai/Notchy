import AppKit
import NotchyCore
import Observation
import SwiftUI

/// A window over the physical notch that turns a click into the same toggle as the hotkey.
/// It draws the collapsed notch shape, so it matches the physical notch; its transparent parts let
/// clicks through. While the pointer is over it the shape grows past the notch, a hint that it is
/// clickable, since the cursor cannot show over the notch (no pixels there). Hover is visual only
/// and never captures.
/// In Claude Code mode it stays a little wider, with the mascot on the left, and takes file drops.
/// A right-click (or Control-click) shows a menu for switching modes; a switch is confirmed by the
/// notch widening for a moment with the mode's icon on the left and its name on the right.
/// Non-activating, so the app the owner was in stays frontmost and is what gets captured.
final class NotchHitWindow: NSPanel {
    /// Room around the notch for the badge and the hover growth.
    private static let margin = CGSize(width: 140, height: 90)
    /// How far the hovered shape reaches past the notch on each side (sideways only: growing down looked awkward).
    fileprivate static let growth: CGFloat = 14
    /// How far the notch drops while a file is dragged over it, to show the drop zone.
    fileprivate static let dropDepth: CGFloat = 72
    /// Extra width on each side in Claude Code mode: the mascot on the left, the status on the right.
    static let badgeWidth: CGFloat = 80
    /// Extra width on each side while a mode switch is announced.
    fileprivate static let announcementWidth: CGFloat = 116
    private let model = HoverModel()
    private let clickView: ClickView
    private var notch: CGRect?

    init(onClick: @escaping () -> Void, onHover: @escaping () -> Void, onDrop: @escaping ([URL]) -> Void,
         menu: @escaping @MainActor () -> NSMenu?) {
        clickView = ClickView(onClick: onClick, onDrop: onDrop, menu: menu)
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 2) // just below the dropdown
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        isMovable = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .none

        let shape = NSHostingView(rootView: HoverShape(model: model))
        shape.translatesAutoresizingMaskIntoConstraints = true
        shape.autoresizingMask = [.width, .height]
        clickView.addSubview(shape)
        clickView.onHover = { [model] hovered in
            withAnimation(hovered ? .spring(duration: 0.25, bounce: 0.3) : .spring(duration: 0.22, bounce: 0)) {
                model.hovered = hovered
            }
            if hovered { onHover() }
        }
        clickView.onDragOver = { [model] over in
            withAnimation(.spring(duration: 0.35, bounce: 0.25)) { model.dropping = over }
        }
        contentView = clickView
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }

    /// Covers `notch` (plus room to grow), or hides when the screen has no notch.
    func place(over notch: CGRect?) {
        self.notch = notch
        guard let notch else {
            orderOut(nil)
            return
        }
        let margin = Self.margin
        model.notchSize = notch.size
        // Raised by the bleed, like the dropdown, so the shape lines up with the collapsed dropdown.
        setFrame(CGRect(x: notch.minX - margin.width, y: notch.minY - margin.height,
                        width: notch.width + 2 * margin.width,
                        height: notch.height + margin.height + NotchShape.topBleed),
                 display: true)
        updateTracking()
        orderFrontRegardless()
        NotchSpace.shared.add(self)
    }

    /// Claude Code mode: the wider notch with the mascot, and file drops.
    func setBadge(_ on: Bool) {
        guard model.badge != on else { return }
        withAnimation(.spring(duration: 0.3, bounce: 0.15)) { model.badge = on }
        clickView.acceptsDrops = on
        updateTracking()
    }

    /// Confirms a mode switch: the notch widens, shows the mode, and settles back after a moment.
    func announce(_ mode: AnswerMode) {
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        model.announcementID += 1
        let id = model.announcementID
        withAnimation(reduceMotion ? .easeInOut(duration: 0.15) : .spring(duration: 0.4, bounce: 0.35)) {
            model.announced = mode
        }
        Task { @MainActor [model] in
            try? await Task.sleep(for: .seconds(1.6))
            guard model.announcementID == id else { return } // a newer switch is showing
            withAnimation(reduceMotion ? .easeInOut(duration: 0.15) : .spring(duration: 0.35, bounce: 0.1)) {
                model.announced = nil
            }
        }
    }

    /// Claude Code's activity, for the mascot and the status.
    func setActivity(_ activity: ClaudeTerminal.Activity) {
        model.activity = activity
    }

    private func updateTracking() {
        guard let notch else { return }
        let extra = model.badge ? Self.badgeWidth : 0
        let shown = CGRect(x: Self.margin.width - extra, y: Self.margin.height,
                           width: notch.width + 2 * extra, height: notch.height)
        clickView.setTracking(enter: shown, exit: shown.insetBy(dx: -Self.growth, dy: 0))
    }

    @MainActor
    @Observable
    fileprivate final class HoverModel {
        var hovered = false
        var dropping = false
        var badge = false
        var activity = ClaudeTerminal.Activity.off
        var notchSize = CGSize.zero
        var announced: AnswerMode?
        var announcementID = 0
    }

    fileprivate struct HoverShape: View {
        let model: HoverModel

        var body: some View {
            let side = model.announced != nil ? NotchHitWindow.announcementWidth
                : model.badge ? NotchHitWindow.badgeWidth : 0
            let extra = side + (model.hovered || model.dropping ? NotchHitWindow.growth : 0)
            let drop = model.dropping ? NotchHitWindow.dropDepth : 0
            NotchShape(bottomRadius: model.dropping ? 22 : model.hovered ? 14 : 10)
                .fill(.black)
                .overlay(alignment: .bottom) {
                    if model.dropping {
                        DropHint()
                            .frame(height: NotchHitWindow.dropDepth - 12)
                            .padding(.horizontal, 14 + NotchShape.flare)
                            .padding(.bottom, 10)
                            .transition(.scale(scale: 0.8, anchor: .top).combined(with: .opacity))
                    }
                }
                .overlay(alignment: .topLeading) {
                    if let mode = model.announced {
                        ModeAnnouncement.Icon(mode: mode, trigger: model.announcementID)
                            .id(mode)
                            .padding(.leading, NotchShape.flare + 14)
                            .frame(height: NotchShape.topBleed + model.notchSize.height, alignment: .center)
                            .padding(.top, NotchShape.topBleed / 2)
                            .transition(.blurReplace)
                    } else if model.badge {
                        AnimatedMascot(activity: model.dropping ? .attention : model.activity)
                            .padding(.leading, NotchShape.flare + 10)
                            .frame(height: NotchShape.topBleed + model.notchSize.height, alignment: .center)
                            .padding(.top, NotchShape.topBleed / 2)
                            .transition(.opacity)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if let mode = model.announced {
                        ModeAnnouncement.Name(mode: mode)
                            .id(mode)
                            .padding(.trailing, NotchShape.flare + 14)
                            .frame(height: NotchShape.topBleed + model.notchSize.height, alignment: .center)
                            .padding(.top, NotchShape.topBleed / 2)
                            .transition(.blurReplace)
                    } else if model.badge {
                        ClaudeStatus(activity: model.activity)
                            .padding(.trailing, NotchShape.flare + 8)
                            .frame(height: NotchShape.topBleed + model.notchSize.height, alignment: .center)
                            .padding(.top, NotchShape.topBleed / 2)
                            .transition(.opacity)
                    }
                }
                .frame(width: model.notchSize.width + 2 * extra, height: NotchShape.topBleed + model.notchSize.height + drop)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }

    private final class ClickView: NSView {
        let onClick: () -> Void
        let onDrop: ([URL]) -> Void
        let makeMenu: @MainActor () -> NSMenu?
        var onHover: (Bool) -> Void = { _ in }
        /// Grows the notch under a dragged file, without opening anything.
        var onDragOver: (Bool) -> Void = { _ in }
        var acceptsDrops = false
        private var enterRect = CGRect.zero
        private var exitRect = CGRect.zero
        private var hovered = false

        init(onClick: @escaping () -> Void, onDrop: @escaping ([URL]) -> Void, menu: @escaping @MainActor () -> NSMenu?) {
            self.onClick = onClick
            self.onDrop = onDrop
            self.makeMenu = menu
            super.init(frame: .zero)
            registerForDraggedTypes([.fileURL])
        }

        required init?(coder: NSCoder) { fatalError("not used") }

        /// Hover starts over the notch and lasts until the pointer leaves the grown shape.
        func setTracking(enter: CGRect, exit: CGRect) {
            enterRect = enter
            exitRect = exit
            updateTrackingAreas()
        }

        // Claude Code mode: a file dropped on the notch goes into the session. The notch only
        // grows while a file is over it; the terminal opens once the file is dropped.
        override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
            guard acceptsDrops else { return [] }
            onDragOver(true)
            return .copy
        }

        override func draggingExited(_ sender: (any NSDraggingInfo)?) {
            onDragOver(false)
        }

        override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
            guard acceptsDrops else { return false }
            let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self],
                                                             options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
            onDragOver(false)
            onDrop(urls)
            return !urls.isEmpty
        }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            trackingAreas.forEach(removeTrackingArea)
            addTrackingArea(NSTrackingArea(rect: enterRect, options: [.mouseEnteredAndExited, .activeAlways],
                                           owner: self, userInfo: ["zone": "enter"]))
            addTrackingArea(NSTrackingArea(rect: exitRect, options: [.mouseEnteredAndExited, .activeAlways],
                                           owner: self, userInfo: ["zone": "exit"]))
        }

        override func mouseEntered(with event: NSEvent) {
            guard !hovered, event.trackingArea?.userInfo?["zone"] as? String == "enter" else { return }
            hovered = true
            onHover(true)
        }

        override func mouseExited(with event: NSEvent) {
            guard hovered, event.trackingArea?.userInfo?["zone"] as? String == "exit" else { return }
            hovered = false
            onHover(false)
        }

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        // The shape view on top would take the click; send every hit to this view.
        override func hitTest(_ point: NSPoint) -> NSView? { frame.contains(point) ? self : nil }
        override func mouseDown(with event: NSEvent) {
            if event.modifierFlags.contains(.control) {
                rightMouseDown(with: event)
            } else {
                onClick()
            }
        }

        override func rightMouseDown(with event: NSEvent) {
            guard let menu = makeMenu() else { return }
            // Just below the notch, under the pointer.
            let point = convert(event.locationInWindow, from: nil)
            menu.popUp(positioning: nil, at: CGPoint(x: point.x, y: enterRect.minY - 4), in: self)
        }
    }
}
