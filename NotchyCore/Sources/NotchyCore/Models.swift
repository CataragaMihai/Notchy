/// How large an image a model accepts before the API downscales it.
public struct ImageLimits: Sendable, Equatable {
    public let maxLongEdge: Int
    public let maxVisualTokens: Int

    /// Claude 4.7 and later.
    public static let highResolution = ImageLimits(maxLongEdge: 2576, maxVisualTokens: 4784)
    /// All other models, including Haiku 4.5.
    public static let standard = ImageLimits(maxLongEdge: 1568, maxVisualTokens: 1568)
}

/// The models Notchy offers. IDs and capabilities checked against the docs on 2026-10-09.
public enum ClaudeModel: String, CaseIterable, Sendable, Identifiable {
    case sonnet55 = "claude-sonnet-5-5"
    case opus55 = "claude-opus-5-5"
    case haiku45 = "claude-haiku-4-5"

    public static let `default` = ClaudeModel.sonnet55

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .sonnet55: "Claude Sonnet 5.5 (fast, strong)"
        case .opus55: "Claude Opus 5.5 (hardest questions)"
        case .haiku45: "Claude Haiku 4.5 (cheapest)"
        }
    }

    public var imageLimits: ImageLimits {
        self == .haiku45 ? .standard : .highResolution
    }

    /// Haiku 4.5 rejects `output_config.effort`.
    public var supportsEffort: Bool { self != .haiku45 }
}
