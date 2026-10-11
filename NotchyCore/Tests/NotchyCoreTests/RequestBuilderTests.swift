import Foundation
import Testing
@testable import NotchyCore

struct RequestBuilderTests {
    private func decode(_ data: Data) throws -> [String: Any] {
        try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @Test func sonnetRequestShape() throws {
        let json = try decode(RequestBuilder.body(model: .sonnet55, imageBase64: "QUJD", question: "  What is this?  "))
        #expect(json["model"] as? String == "claude-sonnet-5-5")
        #expect(json["max_tokens"] as? Int == 8192)
        #expect(json["stream"] as? Bool == true)
        #expect(json["system"] as? String == Prompts.system)
        #expect((json["output_config"] as? [String: Any])?["effort"] as? String == "low")
        #expect(json["temperature"] == nil)
        #expect(json["thinking"] == nil)

        let messages = try #require(json["messages"] as? [[String: Any]])
        #expect(messages.count == 1)
        #expect(messages[0]["role"] as? String == "user")
        let content = try #require(messages[0]["content"] as? [[String: Any]])
        #expect(content[0]["type"] as? String == "image")
        let source = try #require(content[0]["source"] as? [String: Any])
        #expect(source["type"] as? String == "base64")
        #expect(source["media_type"] as? String == "image/jpeg")
        #expect(source["data"] as? String == "QUJD")
        #expect(content[1]["type"] as? String == "text")
        #expect(content[1]["text"] as? String == "What is this?")
    }

    @Test func emptyQuestionUsesDefaultPrompt() throws {
        let json = try decode(RequestBuilder.body(model: .sonnet55, imageBase64: "x", question: " \n"))
        let content = try #require((json["messages"] as? [[String: Any]])?.first?["content"] as? [[String: Any]])
        #expect(content[1]["text"] as? String == Prompts.emptyQuestion)
    }

    @Test func haikuOmitsEffort() throws {
        let json = try decode(RequestBuilder.body(model: .haiku45, imageBase64: "x", question: "q"))
        #expect(json["model"] as? String == "claude-haiku-4-5")
        #expect(json["output_config"] == nil)
    }

    @Test func answerOnlyUsesItsPrompts() throws {
        let json = try decode(RequestBuilder.body(model: .sonnet55, imageBase64: "x", question: "", answerOnly: true))
        #expect(json["system"] as? String == Prompts.answerOnlySystem)
        let content = try #require((json["messages"] as? [[String: Any]])?.first?["content"] as? [[String: Any]])
        #expect(content[1]["text"] as? String == Prompts.answerOnlyEmptyQuestion)
    }
}
