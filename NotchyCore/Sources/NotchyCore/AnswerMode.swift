/// How Notchy answers. Chosen in the app window.
public enum AnswerMode: String, CaseIterable, Sendable, Identifiable {
    /// The Messages API with an API key: explained answers, tuned for speed.
    case quick
    /// No animation, sent as soon as the screenshot is taken, answers only. Shown on hover.
    case lightning
    /// The interactive `claude` CLI in a terminal in the notch, on the owner's subscription.
    case claudeCode

    public static let `default` = AnswerMode.quick

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .quick: "Quick"
        case .lightning: "Lightning Fast"
        case .claudeCode: "Claude Code"
        }
    }

    public var summary: String {
        switch self {
        case .quick: "Explained answers in a few seconds. Uses your API key."
        case .lightning: "The shortcut sends at once, with no animation. Hover the notch to see the answer only, no explanation. Uses your API key."
        case .claudeCode: "The real Claude Code terminal in the notch, on your subscription. The shortcut adds a screenshot to the session. Esc goes to Claude Code; move the pointer away or click elsewhere to hide it."
        }
    }

    /// The prompts to use: explained, or the answer alone.
    public var answerOnly: Bool { self == .lightning }
}
