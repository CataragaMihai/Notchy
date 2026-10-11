import AppKit
import NotchyCore
import os
import SwiftTerm
import SwiftUI

/// Claude Code mode: the interactive `claude` CLI in a terminal, living in the dropdown.
///
/// One session for the life of the app: hiding the dropdown keeps it; quitting Notchy ends it,
/// and `/clear` inside Claude Code starts over. Screenshots are written to a private temporary
/// folder (the one exception to "captures stay in memory", chosen by the owner) and pasted into
/// the prompt as paths, which Claude Code turns into images. That folder is emptied at launch and
/// at quit. Files dropped on the terminal are pasted as paths the same way.
@MainActor
final class ClaudeTerminal: NSObject, LocalProcessTerminalViewDelegate {
    /// What Claude Code seems to be doing, for the mascot and the status beside the notch.
    /// Read from the terminal: steady output that is not the echo of typing means it is working.
    enum Activity: Equatable {
        case off
        case idle
        case working(since: Date, verb: String)
        /// Finished, or asking for permission, while the dropdown was hidden.
        case attention
    }

    /// Holds the terminal and takes file drops.
    let view: DropView
    private let terminal: WatchedTerminalView
    var onActivity: (Activity) -> Void = { _ in }
    private(set) var activity: Activity = .off {
        didSet { if activity != oldValue { onActivity(activity) } }
    }
    private var isShown = false
    private var focusPending = false
    private var scrollMonitor: Any?
    private var scrollRemainder: CGFloat = 0
    private var lastKeystroke = Date.distantPast
    private var quietTask: Task<Void, Never>?
    /// In the spirit of Claude Code's own spinner words.
    private static let verbs = ["Vibing", "Clauding", "Brewing", "Cooking", "Noodling", "Musing", "Pondering", "Scheming"]
    private let logger = Logger(subsystem: AppInfo.logSubsystem, category: "claude-code")
    private let isMock: Bool
    private(set) var isRunning = false

    static let screenshotFolder: URL = FileManager.default.temporaryDirectory
        .appending(path: "NotchyScreenshots", directoryHint: .isDirectory)

    init(isMock: Bool) {
        self.isMock = isMock
        terminal = WatchedTerminalView(frame: NSRect(x: 0, y: 0, width: 760, height: 420))
        view = DropView(frame: terminal.frame)
        super.init()
        terminal.processDelegate = self
        terminal.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        terminal.nativeBackgroundColor = .black
        terminal.nativeForegroundColor = NSColor(white: 0.92, alpha: 1)
        terminal.optionAsMetaKey = true
        terminal.translatesAutoresizingMaskIntoConstraints = true
        terminal.autoresizingMask = [.width, .height]
        view.addSubview(terminal)
        view.onDrop = { [weak self] urls in self?.paste(paths: urls.map(\.path)) }
        view.onAttached = { [weak self] in
            guard let self, self.focusPending else { return }
            self.focus()
        }
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            let handled = MainActor.assumeIsolated { self?.scroll(event) ?? false }
            return handled ? nil : event
        }
        terminal.onOutput = { [weak self] in self?.outputArrived() }
        terminal.onKeystroke = { [weak self] in self?.lastKeystroke = .now }
        terminal.onBell = { [weak self] in
            guard let self, !self.isShown, self.isRunning else { return }
            self.activity = .attention
        }
        Self.emptyScreenshotFolder()
    }

    /// Starts Claude Code in `folder` if no session is running.
    func startIfNeeded(in folder: URL) {
        guard !isRunning else { return }
        var environment = ProcessInfo.processInfo.environment
        environment["TERM"] = "xterm-256color"
        environment["COLORTERM"] = "truecolor"
        environment["LANG"] = environment["LANG"] ?? "en_US.UTF-8"
        let path = environment["PATH"] ?? "/usr/bin:/bin"
        environment["PATH"] = "\(NSString(string: "~/.local/bin").expandingTildeInPath):/opt/homebrew/bin:/usr/local/bin:\(path)"
        let pairs = environment.map { "\($0.key)=\($0.value)" }

        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: Self.screenshotFolder, withIntermediateDirectories: true,
                                                 attributes: [.posixPermissions: 0o700])
        if isMock {
            // Mock mode: a plain shell, no Claude Code and no network.
            terminal.startProcess(executable: "/bin/zsh", args: ["-f"], environment: pairs,
                                  currentDirectory: folder.path)
        } else if let claude = ClaudeCLI.executable {
            // The screenshot folder is added so Claude Code can read screenshots without asking.
            terminal.startProcess(executable: claude.path, args: ["--add-dir", Self.screenshotFolder.path],
                                  environment: pairs, execName: "claude", currentDirectory: folder.path)
        } else {
            terminal.feed(text: "Claude Code was not found. Install it from claude.com/code, then quit and reopen Notchy. Or right-click the notch to switch to Quick mode.\r\n")
            return
        }
        isRunning = true
        activity = .idle
        logger.info("Claude Code session started")
    }

    /// Saves the screenshot and pastes its path into the prompt, ready for a question.
    func add(_ image: CapturedImage) {
        let url = Self.screenshotFolder.appending(path: "screenshot-\(Int(Date().timeIntervalSince1970 * 1000)).jpg")
        do {
            try image.jpeg.write(to: url, options: [.atomic])
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            paste(paths: [url.path])
        } catch {
            logger.error("Could not save the screenshot: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// The dropdown opened or closed. Opening it answers "needs you".
    func setShown(_ shown: Bool) {
        isShown = shown
        if shown, activity == .attention { activity = .idle }
    }

    /// Output more than half a second after a keystroke is Claude Code at work; 1.5 s of quiet ends it.
    private func outputArrived() {
        guard isRunning, Date().timeIntervalSince(lastKeystroke) > 0.5 else { return }
        if case .working = activity {} else {
            activity = .working(since: .now, verb: Self.verbs.randomElement() ?? "Vibing")
        }
        quietTask?.cancel()
        quietTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            guard let self, !Task.isCancelled, self.isRunning else { return }
            self.activity = self.isShown ? .idle : .attention
        }
    }

    /// SwiftTerm only scrolls its own scrollback. When Claude Code asks for mouse events, the wheel
    /// goes to it as wheel buttons; on the alternate screen without them, as arrow keys, like
    /// Terminal.app. Trackpad deltas are added up into whole lines. Returns true if handled.
    private func scroll(_ event: NSEvent) -> Bool {
        guard event.window === terminal.window, terminal.window != nil else { return false }
        let point = terminal.convert(event.locationInWindow, from: nil)
        guard terminal.bounds.contains(point) else { return false }
        let state = terminal.getTerminal()
        guard state.mouseMode != .off || state.isCurrentBufferAlternate else { return false }
        scrollRemainder += event.hasPreciseScrollingDeltas ? event.scrollingDeltaY / 12 : event.scrollingDeltaY
        let lines = Int(scrollRemainder)
        guard lines != 0 else { return true }
        scrollRemainder -= CGFloat(lines)
        let up = lines > 0
        let bounds = terminal.bounds
        let column = max(0, min(state.cols - 1, Int(point.x / max(bounds.width, 1) * CGFloat(state.cols))))
        let row = max(0, min(state.rows - 1, Int((bounds.height - point.y) / max(bounds.height, 1) * CGFloat(state.rows))))
        for _ in 0..<min(abs(lines), 10) {
            if state.mouseMode != .off {
                let flags = state.encodeButton(button: up ? 4 : 5, release: false, shift: false, meta: false, control: false)
                state.sendEvent(buttonFlags: flags, x: column, y: row)
            } else {
                terminal.send(data: ArraySlice<UInt8>(up ? [0x1B, 0x5B, 0x41] : [0x1B, 0x5B, 0x42]))
            }
        }
        return true
    }

    /// Takes the keyboard. The terminal leaves the window while the dropdown is collapsed, so a
    /// request that arrives before it is back is kept and carried out when it is attached.
    func focus() {
        if let window = terminal.window {
            window.makeFirstResponder(terminal)
            focusPending = false
        } else {
            focusPending = true
        }
    }

    /// Ends the session. Called at quit.
    func stop() {
        if isRunning { terminal.terminate() }
        isRunning = false
        activity = .off
        Self.emptyScreenshotFolder()
    }

    /// Pastes paths as a bracketed paste, which Claude Code reads like a drag from Finder.
    func paste(paths: [String]) {
        guard isRunning, !paths.isEmpty else { return }
        let escaped = paths.map { $0.replacingOccurrences(of: " ", with: "\\ ") }.joined(separator: " ")
        let text = "\u{1b}[200~\(escaped) \u{1b}[201~"
        terminal.send(data: ArraySlice(Array(text.utf8)))
    }

    private static func emptyScreenshotFolder() {
        try? FileManager.default.removeItem(at: screenshotFolder)
    }

    // MARK: LocalProcessTerminalViewDelegate

    nonisolated func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}
    nonisolated func setTerminalTitle(source: LocalProcessTerminalView, title: String) {}
    nonisolated func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}

    /// `/exit`, or a crash: the next open starts a new session.
    nonisolated func processTerminated(source: TerminalView, exitCode: Int32?) {
        Task { @MainActor in
            self.isRunning = false
            self.quietTask?.cancel()
            self.activity = .off
            self.terminal.feed(text: "\r\n[Session ended. Open Notchy again to start a new one.]\r\n")
            self.logger.info("Claude Code session ended (\(exitCode ?? -1))")
        }
    }
}

/// Reports output, keystrokes (including Notchy's own pastes) and the bell.
private final class WatchedTerminalView: LocalProcessTerminalView {
    var onOutput: () -> Void = {}
    var onKeystroke: () -> Void = {}
    var onBell: () -> Void = {}

    override func dataReceived(slice: ArraySlice<UInt8>) {
        super.dataReceived(slice: slice)
        onOutput()
    }

    override func send(source: TerminalView, data: ArraySlice<UInt8>) {
        onKeystroke()
        super.send(source: source, data: data)
    }

    override func bell(source: Terminal) {
        super.bell(source: source)
        onBell()
    }
}

/// Accepts files dragged onto the terminal, showing a drop hint while one is over it.
final class DropView: NSView {
    var onDrop: ([URL]) -> Void = { _ in }
    var onAttached: () -> Void = {}

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil { onAttached() }
    }
    private let hint: NSView = NSHostingView(rootView: DropHint().padding(10).background(Color.black.opacity(0.8)))

    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL])
        hint.frame = bounds
        hint.autoresizingMask = [.width, .height]
        hint.isHidden = true
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        if hint.superview == nil { addSubview(hint) } // above the terminal
        hint.isHidden = false
        return .copy
    }

    override func draggingExited(_ sender: (any NSDraggingInfo)?) {
        hint.isHidden = true
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        hint.isHidden = true
        let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self],
                                                         options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        onDrop(urls)
        return !urls.isEmpty
    }
}
