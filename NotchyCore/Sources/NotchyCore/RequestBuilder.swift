import Foundation

/// Builds the JSON body for `POST /v1/messages`.
public enum RequestBuilder {
    public static let maxTokens = 8192
    public static let effort = "low"

    public static func body(
        model: ClaudeModel,
        imageBase64: String,
        mediaType: String = "image/jpeg",
        question: String,
        answerOnly: Bool = false
    ) throws -> Data {
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = Body(
            model: model.rawValue,
            maxTokens: maxTokens,
            stream: true,
            system: Prompts.system(answerOnly: answerOnly),
            outputConfig: model.supportsEffort ? OutputConfig(effort: effort) : nil,
            messages: [
                Message(role: "user", content: [
                    .image(mediaType: mediaType, data: imageBase64),
                    .text(trimmed.isEmpty ? Prompts.emptyQuestion(answerOnly: answerOnly) : trimmed),
                ]),
            ]
        )
        return try JSONEncoder().encode(body)
    }

    private struct Body: Encodable {
        let model: String
        let maxTokens: Int
        let stream: Bool
        let system: String
        let outputConfig: OutputConfig?
        let messages: [Message]

        enum CodingKeys: String, CodingKey {
            case model, stream, system, messages
            case maxTokens = "max_tokens"
            case outputConfig = "output_config"
        }
    }

    private struct OutputConfig: Encodable {
        let effort: String
    }

    private struct Message: Encodable {
        let role: String
        let content: [ContentBlock]
    }

    private enum ContentBlock: Encodable {
        case image(mediaType: String, data: String)
        case text(String)

        private enum Keys: String, CodingKey { case type, source, text }
        private enum SourceKeys: String, CodingKey {
            case type, data
            case mediaType = "media_type"
        }

        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: Keys.self)
            switch self {
            case let .image(mediaType, data):
                try container.encode("image", forKey: .type)
                var source = container.nestedContainer(keyedBy: SourceKeys.self, forKey: .source)
                try source.encode("base64", forKey: .type)
                try source.encode(mediaType, forKey: .mediaType)
                try source.encode(data, forKey: .data)
            case let .text(text):
                try container.encode("text", forKey: .type)
                try container.encode(text, forKey: .text)
            }
        }
    }
}
