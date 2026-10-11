import Foundation
import NotchyCore

protocol ClaudeClient: Sendable {
    func stream(model: ClaudeModel, image: CapturedImage, question: String, answerOnly: Bool, apiKey: String)
        -> AsyncThrowingStream<StreamEvent, any Error>
}
