import AppKit
import KeyboardShortcuts
import NotchyCore
import SwiftUI

/// The first-run guide: one page per step, after the welcome in the notch. The page is saved, so
/// the guide picks up where it left off when macOS relaunches Notchy for Screen Recording.
struct OnboardingView: View {
    enum Step: Int, CaseIterable {
        case welcome, permission, apiKey, shortcut, modes, done
    }

    @Bindable var settings: SettingsStore
    let onFinish: () -> Void
    @State private var forward = true
    @State private var hasPermission = ScreenPermission.isGranted
    @State private var hasKey = KeychainStore.hasAPIKey

    private var step: Step { Step(rawValue: settings.onboardingStep) ?? .welcome }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                page
                    .id(step)
                    .transition(.asymmetric(
                        insertion: .move(edge: forward ? .trailing : .leading).combined(with: .opacity),
                        removal: .move(edge: forward ? .leading : .trailing).combined(with: .opacity)))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            footer
        }
        .frame(minWidth: 620, minHeight: 440)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            hasPermission = ScreenPermission.isGranted
            hasKey = KeychainStore.hasAPIKey
        }
    }

    @ViewBuilder
    private var page: some View {
        switch step {
        case .welcome: WelcomePage()
        case .permission: PermissionPage(granted: hasPermission)
        case .apiKey: APIKeyPage(hasKey: $hasKey)
        case .shortcut: ShortcutPage()
        case .modes: ModesPage(settings: settings)
        case .done: DonePage()
        }
    }

    private var footer: some View {
        HStack {
            if step != .welcome {
                Button("Back") { go(to: step.rawValue - 1) }
            }
            Spacer()
            HStack(spacing: 6) {
                ForEach(Step.allCases, id: \.self) { item in
                    Capsule()
                        .fill(item == step ? Color.accentColor : Color.secondary.opacity(0.3))
                        .frame(width: item == step ? 16 : 6, height: 6)
                }
            }
            .animation(.spring(duration: 0.3), value: step)
            .accessibilityHidden(true)
            Spacer()
            if step == .permission, !hasPermission {
                Button("Skip for now") { go(to: step.rawValue + 1) }
                    .buttonStyle(.borderless)
            }
            Button(primaryTitle) { primaryAction() }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(step == .permission && !hasPermission)
        }
        .controlSize(.large)
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }

    private var primaryTitle: String {
        switch step {
        case .welcome: "Set up Notchy"
        case .apiKey: hasKey ? "Continue" : "Skip"
        case .done: "Start using Notchy"
        default: "Continue"
        }
    }

    private func primaryAction() {
        if step == .done {
            settings.onboardingStep = 0
            settings.onboardingDone = true
            onFinish()
        } else {
            go(to: step.rawValue + 1)
        }
    }

    private func go(to index: Int) {
        forward = index > step.rawValue
        withAnimation(.spring(duration: 0.4, bounce: 0.1)) {
            settings.onboardingStep = min(max(index, 0), Step.allCases.count - 1)
        }
    }
}

// MARK: Pages

/// The icon, title and text every page starts with.
private struct PageHeader: View {
    let symbol: String
    let title: String
    let text: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 30, weight: .medium))
                .foregroundStyle(.tint)
                .frame(width: 64, height: 64)
                .background(.tint.opacity(0.12), in: .rect(cornerRadius: 16))
            Text(title).font(.title.weight(.semibold))
            Text(text)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct Page<Content: View>: View {
    @ViewBuilder let content: Content

    // Centred when it fits, scrolls when the window is too short.
    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 22) { content }
                    .frame(maxWidth: 460)
                    .padding(28)
                    .frame(width: proxy.size.width)
                    .frame(minHeight: proxy.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }
}

private struct WelcomePage: View {
    var body: some View {
        Page {
            VStack(spacing: 10) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 88, height: 88)
                Text("Welcome to Notchy").font(.largeTitle.weight(.bold))
                Text("Press a shortcut in any app and Notchy captures the window in front of you. Ask a question and Claude answers, right in the notch.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: 10) {
                Feature(symbol: "camera.viewfinder", text: "Captures only when you ask, and only the front window.")
                Feature(symbol: "lock", text: "Nothing leaves your Mac until you press Enter.")
                Feature(symbol: "clock", text: "Setup takes about a minute.")
            }
        }
    }
}

private struct Feature: View {
    let symbol: String
    let text: String

    var body: some View {
        Label {
            Text(text)
        } icon: {
            Image(systemName: symbol).foregroundStyle(.tint).frame(width: 20)
        }
    }
}

private struct PermissionPage: View {
    let granted: Bool

    var body: some View {
        Page {
            PageHeader(symbol: "rectangle.dashed.badge.record", title: "Allow Screen Recording",
                       text: "Notchy needs it to see the window you ask about. It only captures when you press the shortcut or click the notch.")
            if granted {
                StatusRow(done: true, text: "Screen Recording is on.")
            } else {
                VStack(spacing: 12) {
                    HStack {
                        Button("Open System Settings") {
                            ScreenPermission.request()
                            ScreenPermission.openSystemSettings()
                        }
                        .buttonStyle(.borderedProminent)
                        Button("Relaunch Notchy") { ScreenPermission.relaunch() }
                    }
                    Text("Turn on Notchy in the list. When macOS offers to quit and reopen it, say yes: this guide picks up right here.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

private struct APIKeyPage: View {
    @Binding var hasKey: Bool

    var body: some View {
        Page {
            PageHeader(symbol: "key", title: "Add your Anthropic API key",
                       text: "Quick and Lightning Fast modes send your screenshot to Claude with your own key, so you pay Anthropic directly for what you use. It is stored in your Keychain.")
            VStack(alignment: .leading, spacing: 10) {
                if hasKey { StatusRow(done: true, text: "Key saved.") }
                APIKeyField { hasKey = KeychainStore.hasAPIKey }
                Link("Create a key at platform.claude.com", destination: URL(string: "https://platform.claude.com/")!)
                    .font(.callout)
            }
            .textFieldStyle(.roundedBorder)
            Text("Only using Claude Code mode? You can skip this.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }
}

private struct ShortcutPage: View {
    var body: some View {
        Page {
            PageHeader(symbol: "command", title: "Pick your shortcut",
                       text: "Press it in any app to capture the window in front of you and ask about it. Press it again to hide Notchy.")
            KeyboardShortcuts.Recorder("Shortcut:", name: .capture)
            Text("You can also just click the notch.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }
}

private struct ModesPage: View {
    @Bindable var settings: SettingsStore
    @State private var claudeInstalled = ClaudeCLI.isInstalled

    var body: some View {
        Page {
            PageHeader(symbol: "dial.medium", title: "Choose how Notchy answers",
                       text: "Switch any time: right-click the notch, use the menu bar icon, or open Settings.")
            VStack(spacing: 8) {
                ForEach(AnswerMode.allCases) { mode in
                    ModeCard(mode: mode, selected: settings.mode == mode,
                             available: mode != .claudeCode || claudeInstalled) {
                        withAnimation(.spring(duration: 0.3, bounce: 0.2)) { settings.mode = mode }
                    }
                }
            }
            if !claudeInstalled {
                ClaudeCodeMissing { claudeInstalled = ClaudeCLI.isInstalled }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            claudeInstalled = ClaudeCLI.isInstalled
        }
    }
}

private struct ModeCard: View {
    let mode: AnswerMode
    let selected: Bool
    let available: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selected ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                    .font(.title3)
                    .contentTransition(.symbolEffect(.replace))
                VStack(alignment: .leading, spacing: 2) {
                    Label {
                        Text(mode.displayName)
                    } icon: {
                        Image(systemName: mode.symbol)
                            .foregroundStyle(mode.tint)
                            .symbolEffect(.bounce, value: selected)
                    }
                    .font(.headline)
                    Text(mode.summary)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selected ? AnyShapeStyle(.tint.opacity(0.1)) : AnyShapeStyle(.quaternary.opacity(0.5)),
                        in: .rect(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(selected ? AnyShapeStyle(.tint) : AnyShapeStyle(.clear)))
            .contentShape(.rect(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .disabled(!available)
        .opacity(available ? 1 : 0.5)
    }
}

private struct DonePage: View {
    @State private var shortcut = KeyboardShortcuts.getShortcut(for: .capture)

    var body: some View {
        Page {
            PageHeader(symbol: "checkmark.seal", title: "You're all set",
                       text: "Notchy is waiting in your notch.")
            VStack(alignment: .leading, spacing: 10) {
                Feature(symbol: "keyboard", text: "Press \(shortcut?.description ?? "your shortcut") in any app, or click the notch.")
                Feature(symbol: "text.bubble", text: "Type a question, or just press Enter for an explanation.")
                Feature(symbol: "cursorarrow.motionlines", text: "Hover the notch to see your last answer again.")
                Feature(symbol: "contextualmenu.and.cursorarrow", text: "Right-click the notch to switch modes.")
            }
            Text("Reopen this window from the Dock or the menu bar icon for Settings and Usage.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }
}

// MARK: Shared

struct StatusRow: View {
    let done: Bool
    let text: String

    var body: some View {
        Label(text, systemImage: done ? "checkmark.circle.fill" : "exclamationmark.circle")
            .foregroundStyle(done ? .green : .orange)
    }
}

/// Claude Code mode needs the `claude` CLI. Shown in the guide and in Settings.
struct ClaudeCodeMissing: View {
    var recheck: () -> Void
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Claude Code mode needs Claude Code installed, and a Claude subscription.", systemImage: "info.circle")
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            Text("Paste this in Terminal to install it:")
                .font(.callout)
                .foregroundStyle(.secondary)
            Text(ClaudeCLI.installCommand)
                .font(.callout.monospaced())
                .textSelection(.enabled)
                .padding(6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary, in: .rect(cornerRadius: 6))
            HStack {
                Button(copied ? "Copied" : "Copy") {
                    ClaudeCLI.copyInstallCommand()
                    copied = true
                }
                Button("Check again") { recheck() }
                Spacer()
                Link("About Claude Code", destination: ClaudeCLI.homepage)
            }
            .controlSize(.small)
        }
    }
}
