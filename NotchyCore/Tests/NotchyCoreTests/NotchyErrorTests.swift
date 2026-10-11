import Foundation
import Testing
@testable import NotchyCore

struct NotchyErrorTests {
    private func body(_ type: String, _ message: String) -> Data {
        Data(#"{"type":"error","error":{"type":"\#(type)","message":"\#(message)"}}"#.utf8)
    }

    @Test func httpStatuses() {
        #expect(NotchyError.fromHTTP(status: 401, body: body("authentication_error", "invalid x-api-key")) == .unauthorized)
        #expect(NotchyError.fromHTTP(status: 400, body: body("invalid_request_error",
            "Your credit balance is too low to access the Anthropic API.")) == .lowCredit)
        #expect(NotchyError.fromHTTP(status: 400, body: body("invalid_request_error", "bad image")) == .invalidRequest("bad image"))
        #expect(NotchyError.fromHTTP(status: 429, body: body("rate_limit_error", "slow down")) == .rateLimited)
        #expect(NotchyError.fromHTTP(status: 529, body: body("overloaded_error", "Overloaded")) == .overloaded)
        #expect(NotchyError.fromHTTP(status: 503, body: Data()) == .overloaded)
        #expect(NotchyError.fromHTTP(status: 418, body: Data()) == .unexpected("HTTP 418"))
    }

    @Test func streamErrors() {
        #expect(NotchyError.fromStreamError(type: "overloaded_error", message: "") == .overloaded)
        #expect(NotchyError.fromStreamError(type: "rate_limit_error", message: "") == .rateLimited)
    }

    @Test func stopReasons() {
        #expect(NotchyError.fromStopReason("refusal") == .refusal)
        #expect(NotchyError.fromStopReason("max_tokens") == .truncated)
        #expect(NotchyError.fromStopReason("end_turn") == nil)
        #expect(NotchyError.fromStopReason(nil) == nil)
    }

    @Test func actions() {
        #expect(NotchyError.noAPIKey.action == .openSettings)
        #expect(NotchyError.overloaded.action == .retry)
        #expect(NotchyError.lowCredit.action == NotchyError.Action.none)
    }
}
