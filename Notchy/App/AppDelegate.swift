import AppKit
import KeyboardShortcuts
import NotchyCore
import os

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let logger = Logger(subsystem: AppInfo.logSubsystem, category: "app")
    private let settings = SettingsStore()
    private let usage = UsageStore()
    private var statusItem: NSStatusItem?
    private var controller: NotchController?
    private var mainWindow: MainWindow?
    private var isMock = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        let arguments = ProcessInfo.processInfo.arguments
        isMock = arguments.contains("--mock")

        // The dropdown lives in the notch; there is nowhere to put it on other Macs.
        if !isMock, !NotchController.hasNotch {
            refuseWithoutNotch()
            return
        }

        if !isMock, MoveToApplications.offerIfNeeded() { return }

        let mainWindow = MainWindow(settings: settings, usage: usage,
                                    replayWelcome: { [weak self] in self?.startOnboarding() })
        self.mainWindow = mainWindow
        NSApp.mainMenu = makeMainMenu()

        let controller = NotchController(
            settings: settings,
            usage: usage,
            capturer: isMock ? MockCapturer() : WindowCapturer(),
            client: isMock ? MockClaudeClient() : AnthropicClient(),
            isMock: isMock,
            dumpImages: arguments.contains("--dump-images"),
            debugFrames: arguments.contains("--debug-frames"),
            slowMotion: arguments.contains("--slow-motion"),
            showSettings: { mainWindow.show(.settings) }
        )
        self.controller = controller
        settings.onModeChange = { [weak controller] in controller?.modeChanged() }

        KeyboardShortcuts.onKeyDown(for: .capture) { [weak controller] in
            MainActor.assumeIsolated { controller?.toggle() }
        }
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak controller] _ in
            MainActor.assumeIsolated { controller?.screenParametersChanged() }
        }
        // Screens can come back from sleep with new geometry without a parameters notification.
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak controller] _ in
            MainActor.assumeIsolated { controller?.screenParametersChanged() }
        }

        statusItem = makeStatusItem()
        controller.logGeometry()
        if isMock {
            startOnboarding() // every launch in mock mode, to work on the welcome
        } else if settings.onboardingDone {
            mainWindow.show(.help)
        } else if settings.onboardingStep == 0 {
            startOnboarding()
        } else {
            mainWindow.show() // back from the Screen Recording relaunch, mid-guide
        }
        logger.info("Launched\(self.isMock ? " in mock mode" : "", privacy: .public)")
    }

    /// The welcome in the notch, then the setup guide in the window.
    private func startOnboarding() {
        settings.onboardingDone = false
        settings.onboardingStep = 0
        mainWindow?.close()
        // A moment after launch, so the welcome is not lost in the app's own start-up.
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(0.6))
            self?.controller?.showWelcome { [weak self] in self?.mainWindow?.show() }
        }
    }

    private func refuseWithoutNotch() {
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = "Notchy needs a Mac with a notch"
        alert.informativeText = "Notchy lives in the camera notch at the top of the screen, so it only runs on MacBooks that have one. If your MacBook's lid is closed, open it and launch Notchy again."
        alert.addButton(withTitle: "Quit")
        alert.runModal()
        NSApp.terminate(nil)
    }

    private func makeStatusItem() -> NSStatusItem {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let image = NSImage(resource: .menuBarIcon)
        image.accessibilityDescription = "Notchy"
        item.button?.image = image
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        return item
    }

    /// Rebuilt on every open so the mode's checkmark and Claude Code's availability are current.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        if isMock {
            let label = NSMenuItem(title: "Mock mode: no capture, no network", action: nil, keyEquivalent: "")
            label.isEnabled = false
            menu.addItem(label)
            menu.addItem(.separator())
        }
        ModeMenu.addItems(to: menu, settings: settings)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Open Notchy", action: #selector(openWindow), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Notchy", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller?.quit()
    }

    /// Clicking the Dock icon with no window open.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if !hasVisibleWindows { mainWindow?.show() }
        return true
    }

    @objc private func openWindow() {
        mainWindow?.show()
    }

    @objc private func openSettings() {
        mainWindow?.show(.settings)
    }

    /// A regular app needs its own menus; Edit makes ⌘V work in the key field.
    private func makeMainMenu() -> NSMenu {
        let main = NSMenu()

        let app = NSMenu()
        app.addItem(withTitle: "About Notchy", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        app.addItem(.separator())
        app.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",").target = self
        app.addItem(.separator())
        app.addItem(withTitle: "Hide Notchy", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        app.addItem(withTitle: "Quit Notchy", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        let window = NSMenu(title: "Window")
        window.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        window.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")

        for submenu in [app, edit, window] {
            main.addItem(withTitle: submenu.title, action: nil, keyEquivalent: "").submenu = submenu
        }
        NSApp.windowsMenu = window
        return main
    }
}
