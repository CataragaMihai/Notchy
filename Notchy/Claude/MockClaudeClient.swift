import Foundation
import NotchyCore

/// Streams canned Markdown with realistic pacing. No network.
struct MockClaudeClient: ClaudeClient {
    private static let answer = """
        This is a **router config** for `R1`. The interface `Gi0/1` has the address \
        `192.168.10.1/26`, so its subnet holds *62 usable hosts*.

        Things to check:
        - The default route points at `10.0.0.2`.
        - OSPF advertises only `192.168.10.0/26`.
        1. Run `show ip route` to confirm.
        2. Then `show ip ospf neighbor`.

        ```
        R1# show ip interface brief
        GigabitEthernet0/1  192.168.10.1  YES manual up  up
        ```
        """

    func stream(model: ClaudeModel, image: CapturedImage, question: String, answerOnly: Bool, apiKey: String)
        -> AsyncThrowingStream<StreamEvent, any Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                continuation.yield(.messageStart(inputTokens: image.tokens + 300))
                continuation.yield(.thinkingStarted)
                try? await Task.sleep(for: .milliseconds(700))
                for word in Self.answer.split(separator: " ", omittingEmptySubsequences: false) {
                    if Task.isCancelled { break }
                    continuation.yield(.textDelta(String(word) + " "))
                    try? await Task.sleep(for: .milliseconds(25))
                }
                continuation.yield(.messageDelta(stopReason: "end_turn", outputTokens: 180))
                continuation.yield(.messageStop)
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
