import NotchyCore
import SwiftUI

/// The black dropdown: the notch itself, grown wider and taller.
struct NotchView: View {
    @Bindable var controller: NotchController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // The dropdown is an overlay pinned to the top of a clear fill, so a panel that is briefly
    // shorter than its content cuts the bottom off instead of centring the content up under the notch.
    var body: some View {
        Color.clear
            .overlay(alignment: .top) { dropdown }
            .environment(\.colorScheme, .dark)
    }

    // The content is always laid out at full size, so its height is known before expanding.
    // The black shape grows from the notch's size to the content's size behind it, and the
    // content fades in once there is room. With Reduce Motion the shape does not grow; the
    // whole dropdown fades instead.
    private var dropdown: some View {
        let expanded = controller.expanded
        let open = expanded || reduceMotion
        return VStack(alignment: .leading, spacing: 10) {
            Color.clear.frame(height: NotchShape.topBleed + controller.notchHeight)
            content
        }
        .padding(.horizontal, 18 + NotchShape.flare)
        .padding(.bottom, 16)
        .frame(width: controller.width, alignment: .topLeading)

        .fixedSize(horizontal: false, vertical: true)
        .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { height in
            controller.contentHeightChanged(height)
        }
        .opacity(expanded ? 1 : 0)
        // Fades in; hides at once on close, since a fade-out lagged the shrink by a frame (gray flicker).
        .animation(expanded ? Animation.easeOut(duration: 0.15).delay(0.09).speed(controller.animationSpeed) : nil,
                   value: expanded)
        // The content is masked by the same animated shape, so nothing draws outside the black
        // while it grows or shrinks.
        .mask(alignment: .top) { shape(open: open) }
        .background(alignment: .top) { shape(open: open).foregroundStyle(.black) }
        .opacity(reduceMotion && !expanded ? 0 : 1)
        .overlay {
            if controller.debugFrames { Rectangle().stroke(.red, lineWidth: 1) }
        }
    }

    private func shape(open: Bool) -> some View {
        NotchShape(bottomRadius: open ? 22 : 10)
            .frame(width: open ? controller.width : controller.collapsedWidth,
                   height: open ? controller.contentHeight : NotchShape.topBleed + controller.notchHeight)
    }

    @ViewBuilder
    private var content: some View {
        if controller.showsWelcome {
            WelcomeView(controller: controller)
        } else if controller.showsTerminal {
            // Kept the same size while hidden, so the dropdown grows to the terminal's size.
            Group {
                if controller.terminalReady {
                    TerminalHost(view: controller.terminal.view)
                } else {
                    Color.clear
                }
            }
            .frame(height: controller.terminalHeight)
        } else {
            answerContent
        }
    }

    @ViewBuilder
    private var answerContent: some View {
        switch controller.shownState {
        case .idle, .capturing:
            EmptyView()
        case .composing:
            ComposeView(controller: controller)
        case .streaming, .done:
            AnswerView(controller: controller)
        case let .error(error):
            if !controller.answer.isEmpty { AnswerView(controller: controller) }
            ErrorRow(error: error, controller: controller)
        case .onboarding:
            PermissionNeededView()
        }
    }
}

private struct ComposeView: View {
    @Bindable var controller: NotchController
    @FocusState private var focused: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            if let thumbnail = controller.thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 96, height: 62)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(.white.opacity(0.2)))
            }
            VStack(alignment: .leading, spacing: 6) {
                TextField("Ask about this window…", text: $controller.question)
                    .textFieldStyle(.plain)
                    .font(.body)
                    .focused($focused)
                    .onSubmit { controller.submit() }
                HStack(spacing: 8) {
                    Text("Enter to ask · Esc to hide · \(controller.captureInfo)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    NewScreenshotButton(controller: controller)
                }
            }
        }
        // The panel becomes key in the same update, so focus on the next turn, when it is key.
        .onAppear { requestFocus() }
        .onChange(of: controller.focusRequest) { requestFocus() }
    }

    /// Off, then on: setting it to true when it already is would not hand the field the keyboard again.
    private func requestFocus() {
        focused = false
        Task { @MainActor in focused = true }
    }
}

private struct AnswerView: View {
    let controller: NotchController
    @State private var contentHeight: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        VStack(alignment: .leading, spacing: 8) {
                            if !controller.askedQuestion.isEmpty {
                                QuestionText(text: controller.askedQuestion)
                            }
                            if controller.answer.isEmpty {
                                if case .streaming = controller.shownState {
                                    HStack(spacing: 8) {
                                        ProgressView().controlSize(.small)
                                        Text("Thinking…").foregroundStyle(.secondary)
                                    }
                                }
                            } else {
                                MarkdownView(text: controller.answer)
                            }
                        }
                        Color.clear.frame(height: 1).id("end")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { contentHeight = $0 }
                }
                .frame(height: min(contentHeight, controller.maxAnswerHeight))
                .onChange(of: controller.answer) { proxy.scrollTo("end", anchor: .bottom) }
            }
            HStack {
                NewScreenshotButton(controller: controller)
                Spacer()
                if case .streaming = controller.shownState {
                    Button("Stop") { controller.stop() }
                }
                if controller.shownState == .done {
                    Button(controller.copied ? "Copied" : "Copy") { controller.copy() }
                }
            }
            .controlSize(.small)
        }
    }
}

private struct QuestionText: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .lineLimit(3)
    }
}

private struct ErrorRow: View {
    let error: NotchyError
    let controller: NotchController

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
            Text(error.message)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            switch error.action {
            case .openSettings: Button("Open Settings") { controller.openSettings() }
            case .retry: Button("Retry") { controller.retry() }
            case .none: EmptyView()
            }
        }
        .controlSize(.small)
    }
}

private struct PermissionNeededView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Notchy needs Screen Recording permission").font(.headline)
            Text("It captures the frontmost window only when you press the shortcut. Turn Notchy on in System Settings › Privacy & Security › Screen & System Audio Recording, then relaunch.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Open System Settings") { ScreenPermission.openSystemSettings() }
                Button("Relaunch Notchy") { ScreenPermission.relaunch() }
            }
            .controlSize(.small)
        }
    }
}

/// First launch: the notch drops open and says hello, one piece at a time.
private struct WelcomeView: View {
    let controller: NotchController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// How many pieces are showing: icon, title, subtitle, button.
    @State private var shown = 0

    var body: some View {
        VStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 64, height: 64)
                .scaleEffect(shown >= 1 ? 1 : 0.5)
                .opacity(shown >= 1 ? 1 : 0)
            Text("Welcome to Notchy")
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .modifier(Reveal(visible: shown >= 2))
            Text("Ask Claude about anything on your screen, right from the notch.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .modifier(Reveal(visible: shown >= 3))
            Button("Get started") { controller.finishWelcome() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.top, 6)
                .modifier(Reveal(visible: shown >= 4))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .task { await reveal() }
    }

    /// Waits for the notch to finish growing, then brings the pieces in one after another.
    private func reveal() async {
        if reduceMotion {
            shown = 4
            return
        }
        try? await Task.sleep(for: .seconds(0.3 / controller.animationSpeed))
        for step in 1...4 {
            withAnimation(.spring(duration: 0.45, bounce: 0.3).speed(controller.animationSpeed)) { shown = step }
            try? await Task.sleep(for: .seconds(0.14 / controller.animationSpeed))
        }
    }

    private struct Reveal: ViewModifier {
        let visible: Bool

        func body(content: Content) -> some View {
            content
                .opacity(visible ? 1 : 0)
                .offset(y: visible ? 0 : 8)
                .blur(radius: visible ? 0 : 4)
        }
    }
}

/// Replaces what is held with a fresh capture of the frontmost window.
private struct NewScreenshotButton: View {
    let controller: NotchController

    var body: some View {
        Button { controller.newCapture() } label: {
            Label("New screenshot", systemImage: "camera.viewfinder")
        }
        .buttonStyle(.borderless)
        .controlSize(.small)
        .help("Capture the frontmost window again")
    }
}

/// The Claude Code terminal, an AppKit view owned by the controller so it outlives this view.
private struct TerminalHost: NSViewRepresentable {
    let view: NSView

    func makeNSView(context: Context) -> NSView { view }
    func updateNSView(_ nsView: NSView, context: Context) {}
}
