import Foundation

/// Every failure the owner can see, each with one line of text and one action.
public enum NotchyError: Error, Equatable, Sendable {
    case noAPIKey
    case unauthorized
    case lowCredit
    case invalidRequest(String)
    case rateLimited
    case overloaded
    case refusal
    case truncated
    case offline
    case timeout
    case interrupted
    case captureFailed(String)
    case unexpected(String)

    public enum Action: Sendable, Equatable {
        case openSettings
        case retry
        case none
    }

    public var message: String {
        switch self {
        case .noAPIKey: "Add your Anthropic API key in Settings."
        case .unauthorized: "The API key was rejected. Check it in Settings."
        case .lowCredit: "Your Anthropic credit balance is too low. Top up in the Claude Console."
        case let .invalidRequest(detail): "The request was rejected: \(detail)"
        case .rateLimited: "Rate limited by the API. Wait a moment and retry."
        case .overloaded: "Claude is overloaded or unavailable right now. Retry shortly."
        case .refusal: "Claude declined to answer this one. Try another model or rephrase."
        case .truncated: "The answer was cut off at the length limit."
        case .offline: "You appear to be offline."
        case .timeout: "The request timed out."
        case .interrupted: "The connection dropped before the answer finished."
        case let .captureFailed(detail): "Could not capture the window: \(detail)"
        case let .unexpected(detail): "Something went wrong: \(detail)"
        }
    }

    public var action: Action {
        switch self {
        case .noAPIKey, .unauthorized: .openSettings
        case .lowCredit, .truncated: .none
        default: .retry
        }
    }

    /// Maps a non-200 response from the Messages API.
    public static func fromHTTP(status: Int, body: Data) -> NotchyError {
        let detail = errorMessage(in: body)
        switch status {
        case 401: return .unauthorized
        case 400 where detail.localizedCaseInsensitiveContains("credit balance"): return .lowCredit
        case 400, 413: return .invalidRequest(detail.isEmpty ? "HTTP \(status)" : detail)
        case 429: return .rateLimited
        case 500...599: return .overloaded
        default: return .unexpected(detail.isEmpty ? "HTTP \(status)" : detail)
        }
    }

    /// Maps an `error` event received mid-stream.
    public static func fromStreamError(type: String, message: String) -> NotchyError {
        switch type {
        case "overloaded_error", "api_error": .overloaded
        case "rate_limit_error": .rateLimited
        case "authentication_error": .unauthorized
        case "invalid_request_error":
            message.localizedCaseInsensitiveContains("credit balance") ? .lowCredit : .invalidRequest(message)
        default: .unexpected(message.isEmpty ? type : message)
        }
    }

    /// Stop reasons that mean the answer is not complete.
    public static func fromStopReason(_ reason: String?) -> NotchyError? {
        switch reason {
        case "refusal": .refusal
        case "max_tokens": .truncated
        default: nil
        }
    }

    private static func errorMessage(in body: Data) -> String {
        guard let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              let error = object["error"] as? [String: Any],
              let message = error["message"] as? String
        else { return "" }
        return message
    }
}
