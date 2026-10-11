/// List prices in US dollars per million tokens (checked 2026-10-09).
/// Thinking tokens are billed as output.
public struct ModelPrice: Sendable, Equatable {
    public let inputPerMillion: Double
    public let outputPerMillion: Double
}

extension ClaudeModel {
    public var price: ModelPrice {
        switch self {
        case .sonnet55: ModelPrice(inputPerMillion: 2, outputPerMillion: 10)
        case .opus55: ModelPrice(inputPerMillion: 4, outputPerMillion: 20)
        case .haiku45: ModelPrice(inputPerMillion: 1, outputPerMillion: 5)
        }
    }
}

/// Token counts and estimated cost, added up from each response's `usage`.
public struct UsageTotals: Sendable, Equatable {
    public private(set) var questions = 0
    public private(set) var inputTokens = 0
    public private(set) var outputTokens = 0
    public private(set) var cost: Double = 0

    public init() {}

    /// From `message_start`: one question sent.
    public mutating func addInput(_ tokens: Int, model: ClaudeModel) {
        questions += 1
        inputTokens += tokens
        cost += Double(tokens) * model.price.inputPerMillion / 1_000_000
    }

    /// From `message_delta`: the answer's output tokens, thinking included.
    public mutating func addOutput(_ tokens: Int, model: ClaudeModel) {
        outputTokens += tokens
        cost += Double(tokens) * model.price.outputPerMillion / 1_000_000
    }
}
