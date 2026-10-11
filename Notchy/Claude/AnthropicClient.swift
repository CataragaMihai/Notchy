import Foundation
import NotchyCore

/// Streams a Messages API response over URLSession. The only host Notchy talks to.
struct AnthropicClient: ClaudeClient {
    private static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!

    private let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 60   // between received bytes; pings keep it alive
        configuration.timeoutIntervalForResource = 180 // whole request
        return URLSession(configuration: configuration)
    }()

    func stream(model: ClaudeModel, image: CapturedImage, question: String, answerOnly: Bool, apiKey: String)
        -> AsyncThrowingStream<StreamEvent, any Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var request = URLRequest(url: Self.endpoint)
                    request.httpMethod = "POST"
                    request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
                    request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
                    request.setValue("application/json", forHTTPHeaderField: "content-type")
                    request.httpBody = try RequestBuilder.body(model: model,
                                                               imageBase64: image.jpeg.base64EncodedString(),
                                                               question: question,
                                                               answerOnly: answerOnly)

                    let (bytes, response) = try await session.bytes(for: request)
                    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                    guard status == 200 else {
                        var body = Data()
                        for try await byte in bytes { body.append(byte) }
                        throw NotchyError.fromHTTP(status: status, body: body)
                    }

                    var sawStop = false
                    for try await line in bytes.lines {
                        guard let event = SSEParser.event(fromLine: line) else { continue }
                        if case let .error(type, message) = event {
                            throw NotchyError.fromStreamError(type: type, message: message)
                        }
                        if event == .messageStop { sawStop = true }
                        continuation.yield(event)
                    }
                    guard sawStop else { throw NotchyError.interrupted }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch let error as URLError where error.code == .cancelled {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: Self.map(error))
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private static func map(_ error: any Error) -> NotchyError {
        if let error = error as? NotchyError { return error }
        if let error = error as? URLError {
            switch error.code {
            case .notConnectedToInternet, .networkConnectionLost, .cannotFindHost,
                 .cannotConnectToHost, .dnsLookupFailed, .dataNotAllowed:
                return .offline
            case .timedOut:
                return .timeout
            default:
                return .unexpected(error.localizedDescription)
            }
        }
        return .unexpected(error.localizedDescription)
    }
}
