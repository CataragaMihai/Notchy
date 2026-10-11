import AppKit
import Observation
import SwiftUI

enum AppSection: String, CaseIterable, Identifiable {
    case setup, settings, usage, help

    var id: Self { self }

    var title: String {
        switch self {
        case .setup: "Setup"
        case .settings: "Settings"
        case .usage: "Usage"
        case .help: "How to use"
        }
    }

    var symbol: String {
        switch self {
        case .setup: "checklist"
        case .settings: "gearshape"
        case .usage: "chart.bar"
        case .help: "questionmark.circle"
        }
    }
}

@MainActor
@Observable
final class Navigation {
    var section: AppSection? = .setup
}

/// The app's one window. It activates Notchy (the dropdown never does) so its fields take typing.
@MainActor
final class MainWindow {
    private let window: NSWindow
    private let navigation = Navigation()

    /// `replayWelcome` restarts first-run setup from the welcome in the notch.
    init(settings: SettingsStore, usage: UsageStore, replayWelcome: @escaping () -> Void) {
        var close: () -> Void = {}
        let root = MainView(navigation: navigation, settings: settings, usage: usage,
                            finishOnboarding: { close() }, replayWelcome: replayWelcome)
        window = NSWindow(contentViewController: NSHostingController(rootView: root))
        window.title = "Notchy"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.setContentSize(NSSize(width: 680, height: 460))
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("MainWindow")
        close = { [weak self] in self?.close() }
    }

    func close() {
        navigation.section = .help
        window.close()
    }

    func show(_ section: AppSection? = nil) {
        if let section { navigation.section = section }
        if !window.isVisible, window.frameAutosaveName.isEmpty || !window.setFrameUsingName("MainWindow") {
            window.center()
        }
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }
}
