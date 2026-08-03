import Foundation

enum TogetherAPIError: LocalizedError, Equatable {
    case invalidResponse
    case emptyResponse
    case outputTruncated
    case incompleteResponse(reason: String?)
    case authenticationFailed
    case rateLimited
    case serviceUnavailable
    case requestFailed(statusCode: Int, message: String?)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Together returned an unreadable response."
        case .emptyResponse:
            return "The model returned no text."
        case .outputTruncated:
            return "The transcription reached SnapText’s \(AppConfiguration.maximumOutputTokens)-token output cap. Capture a smaller region."
        case let .incompleteResponse(reason):
            if let reason, !reason.isEmpty {
                return "Together ended the transcription with finish reason \(reason). The clipboard was left unchanged."
            }
            return "Together returned no finish reason. The clipboard was left unchanged."
        case .authenticationFailed:
            return "The Together API key was rejected."
        case .rateLimited:
            return "Together rate-limited the request. Try again shortly."
        case .serviceUnavailable:
            return "Together is temporarily unavailable."
        case let .requestFailed(statusCode, message):
            if let message, !message.isEmpty {
                return "Together returned HTTP \(statusCode): \(message)"
            }
            return "Together returned HTTP \(statusCode)."
        }
    }
}

actor TogetherAPIClient {
    private let session: URLSession
    private let redirectDelegate: RedirectRejectingSessionDelegate?
    private let endpoint: URL

    init(endpoint: URL = AppConfiguration.apiEndpoint) {
        let configuration = Self.defaultSessionConfiguration()
        let redirectDelegate = RedirectRejectingSessionDelegate()
        self.redirectDelegate = redirectDelegate
        self.session = Self.makeSession(
            configuration: configuration,
            redirectDelegate: redirectDelegate
        )
        self.endpoint = endpoint
    }

    init(
        configuration: URLSessionConfiguration,
        endpoint: URL = AppConfiguration.apiEndpoint
    ) {
        let redirectDelegate = RedirectRejectingSessionDelegate()
        self.redirectDelegate = redirectDelegate
        self.session = Self.makeSession(
            configuration: configuration,
            redirectDelegate: redirectDelegate
        )
        self.endpoint = endpoint
    }

    nonisolated static func makeSession(
        configuration: URLSessionConfiguration,
        redirectDelegate: RedirectRejectingSessionDelegate
    ) -> URLSession {
        URLSession(
            configuration: configuration,
            delegate: redirectDelegate,
            delegateQueue: nil
        )
    }

    private static func defaultSessionConfiguration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        configuration.urlCredentialStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.timeoutIntervalForRequest = 45
        configuration.timeoutIntervalForResource = 60
        configuration.waitsForConnectivity = false
        configuration.httpMaximumConnectionsPerHost = 1
        return configuration
    }

    func transcribe(
        imageData: Data,
        mimeType: String = "image/png",
        apiKey: String,
        model: VisionModel
    ) async throws -> String {
        try Task.checkCancellation()
        let request = try Self.makeRequest(
            endpoint: endpoint,
            imageData: imageData,
            mimeType: mimeType,
            apiKey: apiKey,
            model: model
        )
        try Task.checkCancellation()
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw TogetherAPIError.invalidResponse
        }
        return try Self.parseResponse(data: data, statusCode: httpResponse.statusCode)
    }

    static func makeRequest(
        endpoint: URL = AppConfiguration.apiEndpoint,
        imageData: Data,
        mimeType: String = "image/png",
        apiKey: String,
        model: VisionModel
    ) throws -> URLRequest {
        let imageURL = "data:\(mimeType);base64,\(imageData.base64EncodedString())"
        let body = ChatRequest(
            model: model.rawValue,
            messages: [
                ChatMessage(role: "system", content: .text(TranscriptionPrompt.system)),
                ChatMessage(
                    role: "user",
                    content: .parts([
                        ContentPart(type: "text", text: TranscriptionPrompt.user, imageURL: nil),
                        ContentPart(type: "image_url", text: nil, imageURL: ImageURL(url: imageURL))
                    ])
                )
            ],
            temperature: 0,
            maximumTokens: AppConfiguration.maximumOutputTokens,
            numberOfChoices: 1,
            reasoning: model == .fast ? Reasoning(enabled: false) : nil,
            chatTemplateArguments: model == .fast
                ? ChatTemplateArguments(enableThinking: false)
                : nil
        )

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 45
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(body)
        return request
    }

    static func parseResponse(data: Data, statusCode: Int) throws -> String {
        guard (200..<300).contains(statusCode) else {
            let envelope = try? JSONDecoder().decode(APIErrorEnvelope.self, from: data)
            switch statusCode {
            case 401:
                throw TogetherAPIError.authenticationFailed
            case 429:
                throw TogetherAPIError.rateLimited
            case 500...599:
                throw TogetherAPIError.serviceUnavailable
            default:
                throw TogetherAPIError.requestFailed(
                    statusCode: statusCode,
                    message: envelope?.error.message
                )
            }
        }

        guard let response = try? JSONDecoder().decode(ChatResponse.self, from: data) else {
            throw TogetherAPIError.invalidResponse
        }
        guard let choice = response.choices.first else {
            throw TogetherAPIError.emptyResponse
        }
        if choice.finishReason == "length" {
            throw TogetherAPIError.outputTruncated
        }
        guard choice.finishReason == "stop" || choice.finishReason == "eos" else {
            throw TogetherAPIError.incompleteResponse(reason: choice.finishReason)
        }
        guard let text = choice.message.content else {
            throw TogetherAPIError.emptyResponse
        }
        let normalized: String
        do {
            normalized = try TranscriptionOutputNormalizer.normalizeResponse(text)
        } catch {
            throw TogetherAPIError.invalidResponse
        }
        guard !normalized.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw TogetherAPIError.emptyResponse
        }
        return normalized
    }
}

final class RedirectRejectingSessionDelegate: NSObject, URLSessionTaskDelegate,
    @unchecked Sendable
{
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}

private struct ChatRequest: Encodable {
    let model: String
    let messages: [ChatMessage]
    let temperature: Double
    let maximumTokens: Int
    let numberOfChoices: Int
    let reasoning: Reasoning?
    let chatTemplateArguments: ChatTemplateArguments?

    enum CodingKeys: String, CodingKey {
        case model
        case messages
        case temperature
        case maximumTokens = "max_tokens"
        case numberOfChoices = "n"
        case reasoning
        case chatTemplateArguments = "chat_template_kwargs"
    }
}

private struct ChatMessage: Encodable {
    let role: String
    let content: ChatMessageContent
}

private enum ChatMessageContent: Encodable {
    case text(String)
    case parts([ContentPart])

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .text(value):
            try container.encode(value)
        case let .parts(parts):
            try container.encode(parts)
        }
    }
}

private struct ContentPart: Encodable {
    let type: String
    let text: String?
    let imageURL: ImageURL?

    enum CodingKeys: String, CodingKey {
        case type
        case text
        case imageURL = "image_url"
    }
}

private struct ImageURL: Encodable {
    let url: String
}

private struct Reasoning: Encodable {
    let enabled: Bool
}

private struct ChatTemplateArguments: Encodable {
    let enableThinking: Bool

    enum CodingKeys: String, CodingKey {
        case enableThinking = "enable_thinking"
    }
}

private struct ChatResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable {
            let content: String?
        }

        let message: Message
        let finishReason: String?

        enum CodingKeys: String, CodingKey {
            case message
            case finishReason = "finish_reason"
        }
    }

    let choices: [Choice]
}

private struct APIErrorEnvelope: Decodable {
    struct APIErrorBody: Decodable {
        let message: String?
    }

    let error: APIErrorBody
}
