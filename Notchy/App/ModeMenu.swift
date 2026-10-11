import AppKit
import NotchyCore
import SwiftUI

/// The answer modes as menu items, for the notch's right-click menu and the menu bar icon.
@MainActor
enum ModeMenu {
    static func addItems(to menu: NSMenu, settings: SettingsStore) {
        menu.autoenablesItems = false // or AppKit re-enables Claude Code when it is not installed
        let header = NSMenuItem(title: "Mode", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        for mode in AnswerMode.allCases {
            let installed = mode != .claudeCode || ClaudeCLI.isInstalled
            let title = installed ? mode.displayName : "\(mode.displayName) (not installed)"
            let item = ClosureMenuItem(title: title) { settings.mode = mode }
            item.state = settings.mode == mode ? .on : .off
            item.isEnabled = installed
            item.toolTip = mode.summary
            item.image = NSImage(systemSymbolName: mode.symbol, accessibilityDescription: nil)
            menu.addItem(item)
        }
    }
}

/// A menu item that runs a closure.
final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(title: String, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: "")
        target = self
    }

    required init(coder: NSCoder) { fatalError("not used") }

    @objc private func run() { handler() }
}

extension AnswerMode {
    var symbol: String {
        switch self {
        case .quick: "text.bubble.fill"
        case .lightning: "bolt.fill"
        case .claudeCode: "terminal.fill"
        }
    }

    @MainActor var tint: Color {
        switch self {
        case .quick: .accentColor
        case .lightning: .yellow
        case .claudeCode: ClaudeMascot.color
        }
    }
}

/// The two halves of a mode switch shown beside the notch: the icon left of the camera, the name right of it.
enum ModeAnnouncement {
    struct Icon: View {
        let mode: AnswerMode
        let trigger: Int

        var body: some View {
            Image(systemName: mode.symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(mode.tint)
                .symbolEffect(.bounce, value: trigger)
        }
    }

    struct Name: View {
        let mode: AnswerMode

        var body: some View {
            Text(mode.displayName)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
                .fixedSize()
        }
    }
}
