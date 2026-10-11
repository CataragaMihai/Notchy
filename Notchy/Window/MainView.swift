import AppKit
import KeyboardShortcuts
import NotchyCore
import SwiftUI

struct MainView: View {
    @Bindable var navigation: Navigation
    let settings: SettingsStore
    let usage: UsageStore
    let finishOnboarding: () -> Void
    let replayWelcome: () -> Void

    var body: some View {
        if settings.onboardingDone {
            sections
        } else {
            OnboardingView(settings: settings, onFinish: finishOnboarding)
        }
    }

    private var sections: some View {
        NavigationSplitView {
            List(AppSection.allCases, selection: $navigation.section) { section in
                Label(section.title, systemImage: section.symbol).tag(section)
            }
            .navigationSplitViewColumnWidth(170)
        } detail: {
            switch navigation.section ?? .setup {
            case .setup: SetupPane(navigation: navigation)
            case .settings: SettingsPane(settings: settings)
            case .usage: UsagePane(usage: usage, model: settings.model)
            case .help: HelpPane(replayWelcome: replayWelcome)
            }
        }
        .frame(minWidth: 620, minHeight: 420)
    }
}

// MARK: Setup

private struct SetupPane: View {
    let navigation: Navigation
    @State private var hasKey = KeychainStore.hasAPIKey
    @State private var hasPermission = ScreenPermission.isGranted
    @State private var shortcut = KeyboardShortcuts.getShortcut(for: .capture)

    var body: some View {
        Form {
            Section {
                Text(allDone ? "Notchy is ready. Press \(shortcutText) or click the notch."
                             : "Three things before Notchy can answer.")
                    .font(.headline)
            }
            Step(done: hasKey, title: "Anthropic API key",
                 detail: hasKey ? "Saved in the Keychain." : "Create one at platform.claude.com, then paste it here.") {
                if !hasKey { APIKeyField { hasKey = KeychainStore.hasAPIKey } }
            }
            Step(done: hasPermission, title: "Screen Recording",
                 detail: hasPermission ? "Granted." : "Lets Notchy capture the frontmost window when you ask. Turn Notchy on, then relaunch.") {
                if !hasPermission {
                    HStack {
                        Button("Open System Settings") {
                            ScreenPermission.request()
                            ScreenPermission.openSystemSettings()
                        }
                        Button("Relaunch Notchy") { ScreenPermission.relaunch() }
                    }
                }
            }
            Step(done: shortcut != nil, title: "Shortcut",
                 detail: shortcut != nil ? "Opens Notchy from any app." : "Pick a key combination.") {
                KeyboardShortcuts.Recorder("Shortcut:", name: .capture) { shortcut = $0 }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Setup")
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            hasKey = KeychainStore.hasAPIKey
            hasPermission = ScreenPermission.isGranted
        }
    }

    private var allDone: Bool { hasKey && hasPermission && shortcut != nil }
    private var shortcutText: String { shortcut?.description ?? "the shortcut" }
}

private struct Step<Action: View>: View {
    let done: Bool
    let title: String
    let detail: String
    @ViewBuilder let action: Action

    var body: some View {
        Section {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: done ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(done ? .green : .secondary)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.body.weight(.semibold))
                    Text(detail).font(.callout).foregroundStyle(.secondary)
                }
            }
            action
        }
    }
}

// MARK: Settings

private struct SettingsPane: View {
    @Bindable var settings: SettingsStore
    @State private var claudeInstalled = ClaudeCLI.isInstalled

    var body: some View {
        Form {
            Section("Mode") {
                Picker("Mode", selection: $settings.mode) {
                    ForEach(AnswerMode.allCases) { Text($0.displayName).tag($0) }
                }
                .pickerStyle(.segmented)
                Text(settings.mode.summary).font(.callout).foregroundStyle(.secondary)
                if settings.mode == .claudeCode, !claudeInstalled {
                    ClaudeCodeMissing { claudeInstalled = ClaudeCLI.isInstalled }
                }
            }
            Section("Model") {
                Picker("Model", selection: $settings.model) {
                    ForEach(ClaudeModel.allCases) { Text($0.displayName).tag($0) }
                }
                Text(priceText(settings.model)).font(.callout).foregroundStyle(.secondary)
            }
            Section("Shortcut") {
                KeyboardShortcuts.Recorder("Open Notchy:", name: .capture)
            }
            Section("Claude Code") {
                LabeledContent("Starts in") {
                    HStack {
                        Text(settings.claudeCodeFolder.path(percentEncoded: false))
                            .lineLimit(1).truncationMode(.middle)
                        Button("Choose…") { chooseFolder() }
                    }
                }
                Text("Takes effect the next time Notchy starts a Claude Code session.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Section("Anthropic API key") {
                APIKeyField()
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            claudeInstalled = ClaudeCLI.isInstalled
        }
    }

    private func chooseFolder() {
        let picker = NSOpenPanel()
        picker.canChooseFiles = false
        picker.canChooseDirectories = true
        picker.directoryURL = settings.claudeCodeFolder
        picker.prompt = "Choose"
        if picker.runModal() == .OK, let url = picker.url { settings.claudeCodeFolder = url }
    }

    private func priceText(_ model: ClaudeModel) -> String {
        "$\(model.price.inputPerMillion.formatted()) in / $\(model.price.outputPerMillion.formatted()) out per million tokens."
    }
}

/// Save, replace or remove the key. Never shows a saved key.
struct APIKeyField: View {
    var onChange: () -> Void = {}
    @State private var input = ""
    @State private var hasKey = KeychainStore.hasAPIKey
    @State private var status = ""

    var body: some View {
        SecureField(hasKey ? "Saved. Paste a new key to replace it." : "sk-ant-…", text: $input)
        HStack {
            Button("Save") { save() }
                .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            if hasKey {
                Button("Remove", role: .destructive) {
                    KeychainStore.deleteAPIKey()
                    hasKey = false
                    status = "Removed."
                    onChange()
                }
            }
            Spacer()
            Text(status).foregroundStyle(.secondary)
        }
    }

    private func save() {
        if KeychainStore.saveAPIKey(input.trimmingCharacters(in: .whitespacesAndNewlines)) {
            hasKey = true
            input = ""
            status = "Saved in Keychain."
            onChange()
        } else {
            status = "Could not save to Keychain."
        }
    }
}

// MARK: Usage

private struct UsagePane: View {
    let usage: UsageStore
    let model: ClaudeModel

    var body: some View {
        let totals = usage.totals
        Form {
            Section {
                LabeledContent("Questions", value: totals.questions.formatted())
                LabeledContent("Input tokens", value: totals.inputTokens.formatted())
                LabeledContent("Output tokens", value: totals.outputTokens.formatted())
                LabeledContent("Estimated cost", value: totals.cost.formatted(.currency(code: "USD").precision(.fractionLength(2...4))))
            } footer: {
                Text("Since Notchy launched. Estimated from list prices; the Claude Console shows the real bill.")
            }
            Section {
                Button("Reset") { usage.reset() }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Usage")
    }
}

// MARK: How to use

private struct HelpPane: View {
    let replayWelcome: () -> Void
    @State private var shortcut = KeyboardShortcuts.getShortcut(for: .capture)

    var body: some View {
        Form {
            Section("Ask about any window") {
                step(1, "Press \(shortcut?.description ?? "your shortcut") or click the notch.")
                step(2, "Check the thumbnail: it is exactly what will be sent.")
                step(3, "Type a question, or press Enter for a general explanation.")
                step(4, "Copy the answer if you need it. Esc, moving away or a click elsewhere hides it; hover the notch to see it again.")
            }
            Section("Good to know") {
                Text("Nothing leaves your Mac until you press Enter. Screenshots stay in memory and are discarded on close.")
                Text("Pressing the shortcut again closes Notchy.")
                Text("Right-click the notch, or use the menu bar icon, to switch modes.")
                Text("Sonnet 5.5 reads small text best. Haiku 4.5 is cheaper but sees less detail.")
            }
            Section {
                Button("Show the welcome again") { replayWelcome() }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("How to use")
    }

    private func step(_ number: Int, _ text: String) -> some View {
        Label { Text(text) } icon: { Text("\(number)").font(.callout.monospacedDigit().weight(.semibold)) }
    }
}
