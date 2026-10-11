import AppKit
import NotchyCore
import Observation
import os
import SwiftUI

/// Owns the dropdown's state and runs the side effects: capture, stream, open, collapse.
///
/// What the dropdown holds (`state`) is separate from whether it is open (`expanded`). Collapsing
/// keeps the capture and answer in memory; hovering the notch reopens them without a new
/// screenshot. Only the shortcut, a click on the empty notch or New screenshot capture again.
/// Esc hides, except in the terminal, which keeps Esc. A new screenshot replaces what is held, and
/// 10 minutes collapsed clears it.
@MainActor
@Observable
final class NotchController {
    private(set) var state: PanelState = .idle
    /// What the dropdown shows: the last visible state, kept while it shrinks back into the notch
    /// so the content fades out instead of vanishing mid-animation.
    private(set) var shownState: PanelState = .idle
    private(set) var thumbnail: NSImage?
    private(set) var captureInfo = ""
    private(set) var askedQuestion = ""
    private(set) var answer = ""
    private(set) var copied = false
    /// Bumped when the question field should take the cursor (shortcut and clicks, not hover).
    private(set) var focusRequest = 0
    private(set) var notchHeight: CGFloat = 32
    private(set) var notchWidth: CGFloat = 0
    /// Drives the grow and shrink animation; the panel stays on screen until shrinking finishes.
    private(set) var expanded = false
    private(set) var contentHeight: CGFloat = 120
    private(set) var maxAnswerHeight: CGFloat = 360
    var question = ""

    /// Narrow for a question, wide once an answer is long or a conversation starts.
    private(set) var width = NotchController.narrowWidth
    static let narrowWidth: CGFloat = 460
    static let wideWidth: CGFloat = 680
    static let terminalWidth: CGFloat = 760
    var mode: AnswerMode { settings.mode }
    /// The closed shape: the notch, plus the mascot's room in Claude Code mode.
    var collapsedWidth: CGFloat {
        notchWidth + (settings.mode == .claudeCode ? 2 * NotchHitWindow.badgeWidth : 0)
    }

    /// Claude Code mode: the terminal session, made on first use and kept until quit.
    @ObservationIgnored private(set) lazy var terminal: ClaudeTerminal = {
        let terminal = ClaudeTerminal(isMock: isMock)
        terminal.onActivity = { [weak self] activity in self?.hitWindow?.setActivity(activity) }
        return terminal
    }()
    /// The dropdown shows the terminal instead of a question and answer.
    private(set) var showsTerminal = false
    /// The terminal is an AppKit view the shape's mask cannot clip, so it appears once the
    /// dropdown has finished growing and goes before it shrinks.
    private(set) var terminalReady = false
    private(set) var terminalHeight: CGFloat = 420
    /// First launch: the dropdown shows the welcome instead of a question and answer.
    private(set) var showsWelcome = false
    let debugFrames: Bool
    /// 1 normally; 0.1 with `--slow-motion`, to inspect the animation frame by frame.
    let animationSpeed: Double

    @ObservationIgnored private let settings: SettingsStore
    @ObservationIgnored private let usage: UsageStore
    @ObservationIgnored private let capturer: any Capturer
    @ObservationIgnored private let client: any ClaudeClient
    @ObservationIgnored private let isMock: Bool
    @ObservationIgnored private let dumpImages: Bool
    @ObservationIgnored private let showSettings: () -> Void
    @ObservationIgnored private let panel = NotchPanel()
    @ObservationIgnored private var hitWindow: NotchHitWindow?
    @ObservationIgnored private let logger = Logger(subsystem: AppInfo.logSubsystem, category: "notch")

    @ObservationIgnored private var capture: CapturedImage?
    @ObservationIgnored private var captureTask: Task<Void, Never>?
    @ObservationIgnored private var streamTask: Task<Void, Never>?
    @ObservationIgnored private var collapseGeneration = 0
    @ObservationIgnored private var activatedAt = ContinuousClock.now
    @ObservationIgnored private var clickMonitor: Any?
    @ObservationIgnored private var keyMonitor: Any?
    @ObservationIgnored private var moveMonitors: [Any] = []
    @ObservationIgnored private var pointerWasInside = false
    @ObservationIgnored private var expiryTask: Task<Void, Never>?
    @ObservationIgnored private var welcomeDone: (() -> Void)?

    /// Kept content is cleared after this long collapsed.
    private static let keepFor: Duration = .seconds(10 * 60)

    init(settings: SettingsStore, usage: UsageStore, capturer: any Capturer, client: any ClaudeClient,

         isMock: Bool, dumpImages: Bool, debugFrames: Bool, slowMotion: Bool,
         showSettings: @escaping () -> Void) {
        self.settings = settings
        self.usage = usage
        self.capturer = capturer
        self.client = client
        self.isMock = isMock
        self.dumpImages = dumpImages
        self.debugFrames = debugFrames
        self.animationSpeed = slowMotion ? 0.1 : 1
        self.showSettings = showSettings
        panel.setRootView(NotchView(controller: self))
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            // Esc hides; what is held stays for the next hover. The terminal keeps Esc: Claude Code
            // needs it for its menus and to interrupt, and moving the pointer away hides it there.
            guard event.keyCode == 53, let self, self.expanded, !self.showsTerminal else { return event }
            self.collapse()
            return nil
        }
        panel.acceptsMouseMovedEvents = true
        hitWindow = NotchHitWindow(
            onClick: { [weak self] in MainActor.assumeIsolated { self?.notchClicked() } },
            onHover: { [weak self] in MainActor.assumeIsolated { self?.notchHovered() } },
            onDrop: { [weak self] urls in MainActor.assumeIsolated { self?.droppedOnNotch(urls) } },
            menu: { [weak self] in self?.notchMenu() }
        )
        hitWindow?.setBadge(settings.mode == .claudeCode)
        updateGeometry()
    }

    // MARK: Actions

    /// The shortcut: collapse when open, otherwise take a new screenshot.
    /// Claude Code mode: add a screenshot to the session, opening it if needed.
    func toggle() {
        if settings.mode == .claudeCode {
            openClaudeCode(withScreenshot: true)
            return
        }
        if expanded {
            collapse()
        } else {
            newCapture()
        }
    }

    /// A click on the notch: reopen what is held, or capture if nothing is.
    func notchClicked() {
        if settings.mode == .claudeCode {
            openClaudeCode(withScreenshot: false) // screenshots only from the shortcut
            return
        }
        if state.isVisible {
            open(focus: true)
        } else {
            newCapture()
        }
    }

    /// Hover shows what is held. It never captures.
    func notchHovered() {
        if settings.mode == .claudeCode {
            if terminal.isRunning, !expanded { showTerminal(focus: true) }
            return
        }
        if state.isVisible, !expanded { open(focus: true) }
    }

    /// Right-click on the notch: switch modes, or open the app.
    private func notchMenu() -> NSMenu {
        let menu = NSMenu()
        ModeMenu.addItems(to: menu, settings: settings)
        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem(title: "Settings…") { [weak self] in self?.openSettings() })
        return menu
    }

    // MARK: Welcome

    /// First launch: the notch grows into a welcome. However it closes (Get started, Esc, a click
    /// elsewhere), `done` runs once, and opens the setup guide.
    func showWelcome(then done: @escaping () -> Void) {
        welcomeDone = done
        showsTerminal = false
        showsWelcome = true
        width = Self.narrowWidth
        open(focus: true)
    }

    func finishWelcome() {
        collapse()
    }

    // MARK: Claude Code mode

    /// Opens the terminal (starting Claude Code if needed) and, with `withScreenshot`, pastes a
    /// screenshot of the frontmost window into the prompt.
    func openClaudeCode(withScreenshot: Bool) {
        let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let pointer = Self.pointerInGlobalCoordinates()
        if withScreenshot, !isMock, !ScreenPermission.isGranted {
            ScreenPermission.request()
            showsTerminal = false
            state = .idle
            apply(.activate)
            apply(.permissionMissing)
            open(focus: true)
            return
        }
        terminal.startIfNeeded(in: settings.claudeCodeFolder)
        showTerminal(focus: true)
        guard withScreenshot else { return }
        let limits = ClaudeModel.opus55.imageLimits
        captureTask?.cancel()
        captureTask = Task {
            do {
                let image = try await capturer.capture(limits: limits, frontmostPID: frontmostPID, pointer: pointer)
                if dumpImages { dump(image) }
                terminal.add(image)
            } catch {
                logger.error("Capture for Claude Code failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Claude Code mode: files dropped on the collapsed notch go into the prompt, then it opens.
    func droppedOnNotch(_ urls: [URL]) {
        guard settings.mode == .claudeCode, !urls.isEmpty else { return }
        terminal.startIfNeeded(in: settings.claudeCodeFolder)
        terminal.paste(paths: urls.map(\.path))
        showTerminal(focus: true)
    }

    private func showTerminal(focus: Bool) {
        showsWelcome = false
        if !showsTerminal {
            showsTerminal = true
            terminalReady = false
        }
        width = Self.terminalWidth
        open(focus: focus)
        if terminalReady, focus { terminal.focus() }
    }

    /// The notch confirms the new mode. Leaving Claude Code mode hides the terminal; the session
    /// ends only at quit.
    func modeChanged() {
        hitWindow?.setBadge(settings.mode == .claudeCode)
        hitWindow?.announce(settings.mode)
        guard settings.mode != .claudeCode, showsTerminal else { return }
        collapse()
        showsTerminal = false
        width = Self.narrowWidth
    }

    func quit() {
        terminal.stop()
    }

    /// Captures the frontmost window, replacing anything held, then opens with the question field focused.
    func newCapture() {
        guard state.handling(.activate) == .capturing, state != .capturing else { return }
        showsTerminal = false
        showsWelcome = false
        captureTask?.cancel()
        streamTask?.cancel()
        capture = nil
        if !expanded { clearContent() }
        state = .capturing
        activatedAt = .now

        let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let pointer = Self.pointerInGlobalCoordinates()

        if !isMock && !ScreenPermission.isGranted {
            ScreenPermission.request()
            apply(.permissionMissing)
            open(focus: true)
            return
        }

        let limits = settings.model.imageLimits
        captureTask = Task {
            do {
                let image = try await capturer.capture(limits: limits, frontmostPID: frontmostPID, pointer: pointer)
                guard state == .capturing else { return }
                capture = image
                thumbnail = NSImage(data: image.jpeg)
                captureInfo = "\(image.size) · \(image.tokens) tokens"
                question = ""
                askedQuestion = ""
                answer = ""
                copied = false
                updateWidth()
                if dumpImages { dump(image) }
                apply(.captured)
                if settings.mode == .lightning {
                    submit() // straight away, nothing shown: hover the notch for the answer
                } else {
                    open(focus: true)
                }
                logger.info("Dropdown shown \(Self.milliseconds(since: self.activatedAt)) ms after the hotkey")
            } catch {
                guard state == .capturing else { return }
                apply(.captureFailed(error as? NotchyError ?? .captureFailed(error.localizedDescription)))
                open(focus: true)
            }
        }
    }

    func submit() {
        guard state == .composing, let capture else { return }
        let mode = settings.mode
        let apiKey: String
        if isMock {
            apiKey = "mock"
        } else if let key = KeychainStore.readAPIKey() {
            apiKey = key
        } else {
            apply(.failed(.noAPIKey))
            return
        }

        askedQuestion = question.trimmingCharacters(in: .whitespacesAndNewlines)
        question = ""
        answer = ""
        copied = false
        apply(.submit)

        let model = settings.model
        let events = client.stream(model: model, image: capture, question: askedQuestion,
                                   answerOnly: mode.answerOnly, apiKey: apiKey)
        consume(events, mode: mode, model: model, countsUsage: !isMock)
    }

    /// Streams one answer into `answer`. `countsUsage` is off for mock and for the subscription.
    private func consume(_ events: AsyncThrowingStream<StreamEvent, any Error>, mode: AnswerMode,
                         model: ClaudeModel, countsUsage: Bool) {
        let sentAt = ContinuousClock.now
        streamTask = Task {
            var stopError: NotchyError?
            do {
                for try await event in events {
                    switch event {
                    case let .textDelta(text):
                        if answer.isEmpty {
                            apply(.firstText)
                            logger.info("First token after \(Self.milliseconds(since: sentAt)) ms (\(mode.rawValue, privacy: .public), \(model.rawValue, privacy: .public))")
                        }
                        answer += text
                        updateWidth()
                    case let .messageStart(inputTokens):
                        logger.info("Input tokens: \(inputTokens ?? -1)")
                        if countsUsage, let inputTokens { usage.addInput(inputTokens, model: model) }
                    case let .messageDelta(stopReason, outputTokens):
                        stopError = NotchyError.fromStopReason(stopReason)
                        logger.info("Stop: \(stopReason ?? "none", privacy: .public), output tokens: \(outputTokens ?? -1)")
                        if countsUsage, let outputTokens { usage.addOutput(outputTokens, model: model) }
                    default:
                        break
                    }
                }
                guard !Task.isCancelled else { return }
                logger.info("Answer finished after \(Self.milliseconds(since: sentAt)) ms")
                apply(stopError.map { .failed($0) } ?? .finished)
                if !expanded { scheduleExpiry() } // finished while collapsed
            } catch {
                guard !Task.isCancelled else { return }
                apply(.failed(error as? NotchyError ?? .unexpected(error.localizedDescription)))
            }
        }
    }

    private func updateWidth() {
        let target = answer.count > 280 ? Self.wideWidth : Self.narrowWidth
        guard width != target else { return }
        withAnimation(.spring(duration: 0.3, bounce: 0.08).speed(animationSpeed)) { width = target }
    }

    func stop() {
        streamTask?.cancel()
        apply(.finished)
    }

    func retry() {
        guard case .error = state else { return }
        guard capture != nil else {
            newCapture()
            return
        }
        apply(.retry)
        question = askedQuestion
        submit()
    }

    func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(answer, forType: .string)
        copied = true
    }

    func openSettings() {
        collapse()
        showSettings()
    }

    /// Expiry, or a failed capture's retry: drop the capture and answer.
    func dismiss() {
        captureTask?.cancel()
        streamTask?.cancel()
        expiryTask?.cancel()
        capture = nil
        apply(.dismiss)
    }

    /// Drops what the dropdown displayed. Runs once it has shrunk back into the notch.
    private func clearContent() {
        thumbnail = nil
        captureInfo = ""
        question = ""
        askedQuestion = ""
        answer = ""
        copied = false
        width = Self.narrowWidth
        shownState = .idle
    }

    // MARK: Layout

    func contentHeightChanged(_ height: CGFloat) {
        contentHeight = height.rounded(.up)
        // Not `panel.isVisible`: the first measurement arrives while the panel is still being
        // ordered in, when it does not count as visible yet, and the frame would stay stale.
        if expanded { placePanel() }
    }

    func screenParametersChanged() {
        updateGeometry()
        if panel.isVisible { placePanel() }
    }

    func logGeometry() {
        guard let screen = Self.notchScreen else { return }
        let notch = Self.notchRect(on: screen)
        logger.info("Screen \(NSStringFromRect(screen.frame), privacy: .public), safe area top \(screen.safeAreaInsets.top), notch \(notch.map(NSStringFromRect) ?? "none", privacy: .public)")
    }

    // MARK: Private

    /// Updates what is held. Opening and collapsing are separate, so an answer can arrive while collapsed.
    private func apply(_ event: PanelEvent) {
        state = state.handling(event)
        if state.isVisible {
            shownState = state
        } else {
            collapse(clearing: true)
        }
    }

    /// `focus` makes the panel key so the field takes typing: for the shortcut and clicks, not for hover.
    private func open(focus: Bool) {
        expiryTask?.cancel()
        placePanel()
        if !panel.isVisible {
            panel.orderFrontRegardless()
            NotchSpace.shared.add(panel)
            placePanel() // Ordering in runs the first layout, which may have measured a new height.
        }
        if focus {
            panel.makeKey()
            focusRequest += 1
        }
        if showsTerminal { terminal.setShown(true) }
        if !expanded {
            installMonitors()
            collapseGeneration += 1 // reopening mid-collapse must not order the panel out afterwards
            if isInstant {
                withoutAnimation { expanded = true }
            } else {
                withAnimation(motion(expanding: true)) {
                    expanded = true
                } completion: { [weak self] in
                    guard let self, self.expanded, self.showsTerminal else { return }
                    self.terminalReady = true
                    if self.panel.isKeyWindow { self.terminal.focus() } // carried out once it is attached
                }
            }
        }
    }

    /// Shrinks back into the notch. Content is kept unless `clearing`.
    private func collapse(clearing: Bool = false) {
        removeMonitors()
        terminalReady = false
        if showsTerminal { terminal.setShown(false) }
        if clearing { expiryTask?.cancel() } else if state.isVisible { scheduleExpiry() }
        if let done = welcomeDone {
            welcomeDone = nil
            done()
        }
        guard panel.isVisible, expanded else {
            panel.orderOut(nil)
            showsWelcome = false
            if clearing { clearContent() }
            return
        }
        collapseGeneration += 1
        if isInstant {
            withoutAnimation { expanded = false }
            panel.orderOut(nil)
            showsWelcome = false
            if clearing { clearContent() }
            return
        }
        let generation = collapseGeneration
        // `.removed`, not the default `.logicallyComplete`: a spring is "logically" done while the
        // shape is still a few points tall, and ordering out then cut off the end of the shrink.
        withAnimation(motion(expanding: false), completionCriteria: .removed) {
            expanded = false
        } completion: { [weak self] in
            guard let self, generation == self.collapseGeneration, !self.expanded else { return }
            self.panel.orderOut(nil)
            self.showsWelcome = false
            if clearing { self.clearContent() }
        }
    }

    /// Lightning Fast opens and closes at once. The welcome always animates.
    private var isInstant: Bool { settings.mode == .lightning && !showsWelcome }

    /// Lightning Fast opens and closes at once; this also skips the view's own fades.
    private func withoutAnimation(_ change: () -> Void) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction, change)
    }

    private func scheduleExpiry() {
        expiryTask?.cancel()
        guard !showsTerminal else { return } // the Claude Code session lasts until quit
        expiryTask = Task { [weak self] in
            try? await Task.sleep(for: Self.keepFor)
            guard let self, !Task.isCancelled, !self.expanded, self.state != .capturing else { return }
            if case .streaming = self.state { return }
            self.logger.info("Kept content expired")
            self.dismiss()
        }
    }

    /// Transparent room around the dropdown so the spring's overshoot is not clipped by the panel's edge.
    /// Clicks there pass through to whatever is underneath.
    private static let overshootMargin: CGFloat = 16

    /// A spring out of the notch and a quicker one back in; a short fade with Reduce Motion.
    private func motion(expanding: Bool) -> Animation {
        let animation: Animation = if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            .easeInOut(duration: 0.15)
        } else {
            expanding ? .spring(duration: 0.32, bounce: 0.08) : .spring(duration: 0.22, bounce: 0)
        }
        return animation.speed(animationSpeed)
    }

    private func placePanel() {
        guard let screen = Self.notchScreen else { return }
        let frame = NotchGeometry.dropdownFrame(notch: Self.notchRect(on: screen),
                                                screenFrame: screen.frame,
                                                size: CGSize(width: Self.terminalWidth + 2 * Self.overshootMargin,
                                                             height: contentHeight + Self.overshootMargin))
        // Raised by the bleed so its top sits above the screen's edge (allowed by NotchPanel).
        panel.setFrame(frame.offsetBy(dx: 0, dy: NotchShape.topBleed), display: true)
    }

    private func updateGeometry() {
        guard let screen = Self.notchScreen else { return }
        let notch = Self.notchRect(on: screen)
        notchHeight = notch?.height ?? (screen.frame.maxY - screen.visibleFrame.maxY)
        notchWidth = notch?.width ?? 0
        hitWindow?.place(over: notch)
        maxAnswerHeight = (screen.frame.height * 0.45 - notchHeight - 80).rounded()
        terminalHeight = min(440, (screen.frame.height * 0.5 - notchHeight).rounded())
    }

    /// While open: a click in another app collapses, and so does the pointer leaving the dropdown
    /// after having been over it. A half-typed question, or the Claude Code session, is kept.
    private func installMonitors() {
        removeMonitors()
        pointerWasInside = false // the first move inside hands the keyboard over
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.collapseIfOpen() }
        }
        let moved: (NSEvent) -> Void = { [weak self] _ in
            MainActor.assumeIsolated { self?.pointerMoved() }
        }
        if let global = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved, handler: moved) { moveMonitors.append(global) }
        if let local = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved, handler: { moved($0); return $0 }) {
            moveMonitors.append(local)
        }
    }

    private func removeMonitors() {
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
        clickMonitor = nil
        moveMonitors.forEach(NSEvent.removeMonitor)
        moveMonitors = []
    }

    /// The pointer is over the dropdown: typing and arrow keys go to it, no click needed.
    /// Notchy stays non-activating, so the app underneath stays frontmost.
    private func takeKeyboard() {
        let before = panel.isKeyWindow
        panel.makeKeyAndOrderFront(nil)
        focusRequest += 1
        if showsTerminal { terminal.focus() }
        logger.info("Keyboard to dropdown: key before \(before), after \(self.panel.isKeyWindow), app active \(NSApp.isActive)")
    }

    private func collapseIfOpen() {
        if expanded { collapse() }
    }

    private func pointerMoved() {
        guard expanded else { return }
        if dropdownRect.insetBy(dx: -6, dy: -6).contains(NSEvent.mouseLocation) {
            // Every time the pointer comes back in, not only when the panel thinks it lost focus:
            // after typing in another app it can still report itself as key.
            if !pointerWasInside { takeKeyboard() }
            pointerWasInside = true
        } else if pointerWasInside {
            collapseIfOpen()
        }
    }


    /// The black dropdown on screen, including the bleed. The panel is always wide enough for
    /// the widest dropdown, so this is its current width, centred.
    private var dropdownRect: CGRect {
        let frame = panel.frame
        let margin = Self.overshootMargin
        return CGRect(x: frame.midX - width / 2, y: frame.minY + margin,
                      width: width, height: frame.height - margin)
    }

    private func dump(_ image: CapturedImage) {
        let folder = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Developer/Notchy/DebugDumps", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let name = "capture-\(Int(Date().timeIntervalSince1970)).jpg"
        try? image.jpeg.write(to: folder.appending(path: name))
        logger.info("Dumped capture to \(folder.path, privacy: .public)/\(name, privacy: .public)")
    }

    /// False on Macs without a notch, and on a MacBook with its lid closed.
    static var hasNotch: Bool {
        NSScreen.screens.contains { notchRect(on: $0) != nil }
    }

    private static var notchScreen: NSScreen? {
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main
    }

    private static func notchRect(on screen: NSScreen) -> CGRect? {
        NotchGeometry.notchRect(screenFrame: screen.frame,
                                safeAreaTop: screen.safeAreaInsets.top,
                                leftAreaWidth: screen.auxiliaryTopLeftArea?.width,
                                rightAreaWidth: screen.auxiliaryTopRightArea?.width)
    }

    /// ScreenCaptureKit display frames use a top-left origin; AppKit's pointer location is bottom-left.
    private static func pointerInGlobalCoordinates() -> CGPoint {
        let location = NSEvent.mouseLocation
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        return CGPoint(x: location.x, y: primaryHeight - location.y)
    }

    private static func milliseconds(since start: ContinuousClock.Instant) -> Int {
        let elapsed = ContinuousClock.now - start
        return Int(elapsed.components.seconds * 1000 + elapsed.components.attoseconds / 1_000_000_000_000_000)
    }
}
