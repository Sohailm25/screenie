import Foundation
import Testing
@testable import Screenie

@Suite("Together API client")
struct TogetherAPIClientTests {
    @Test("Fast request encodes the vision model and low-latency options")
    func makeRequestEncodesFastVisionRequest() throws {
        let endpoint = try #require(URL(string: "https://example.test/v1/chat/completions"))
        let imageData = Data([0x89, 0x50, 0x4E, 0x47])
        let request = try TogetherAPIClient.makeRequest(
            endpoint: endpoint,
            imageData: imageData,
            apiKey: "unit-test-key",
            model: .fast
        )

        #expect(request.url == endpoint)
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer unit-test-key")

        let bodyData = try #require(request.httpBody)
        let body = try #require(
            JSONSerialization.jsonObject(with: bodyData) as? [String: Any]
        )

        #expect(body["model"] as? String == VisionModel.fast.rawValue)
        #expect(body["model"] as? String == "Qwen/Qwen3.5-9B")
        #expect(body["temperature"] as? Double == 0)
        #expect(body["max_tokens"] as? Int == AppConfiguration.maximumOutputTokens)
        #expect(body["n"] as? Int == 1)

        let reasoning = try #require(body["reasoning"] as? [String: Any])
        #expect(reasoning["enabled"] as? Bool == false)

        let chatTemplate = try #require(body["chat_template_kwargs"] as? [String: Any])
        #expect(chatTemplate["enable_thinking"] as? Bool == false)

        let messages = try #require(body["messages"] as? [[String: Any]])
        #expect(messages.count == 2)
        #expect(messages[0]["role"] as? String == "system")
        #expect(messages[0]["content"] as? String == TranscriptionPrompt.system)
        #expect(messages[1]["role"] as? String == "user")

        let parts = try #require(messages[1]["content"] as? [[String: Any]])
        #expect(parts.count == 2)
        #expect(parts[0]["type"] as? String == "text")
        #expect(parts[0]["text"] as? String == TranscriptionPrompt.user)
        #expect(parts[1]["type"] as? String == "image_url")

        let imageURL = try #require(parts[1]["image_url"] as? [String: Any])
        #expect(
            imageURL["url"] as? String
                == "data:image/png;base64,\(imageData.base64EncodedString())"
        )

        let bodyText = try #require(String(data: bodyData, encoding: .utf8))
        #expect(!bodyText.contains("unit-test-key"))
    }

    @Test("Request uses the selected accurate model")
    func makeRequestUsesSelectedAccurateModel() throws {
        let request = try TogetherAPIClient.makeRequest(
            imageData: Data([0x01]),
            apiKey: "unit-test-key",
            model: .accurate
        )
        let bodyData = try #require(request.httpBody)
        let body = try #require(
            JSONSerialization.jsonObject(with: bodyData) as? [String: Any]
        )

        #expect(body["model"] as? String == VisionModel.accurate.rawValue)
        #expect(body["reasoning"] == nil)
        #expect(body["chat_template_kwargs"] == nil)
    }

    @Test("Request preserves a JPEG image data URI")
    func makeRequestPreservesJPEGMIMEType() throws {
        let imageData = Data([0xFF, 0xD8, 0xFF])
        let request = try TogetherAPIClient.makeRequest(
            imageData: imageData,
            mimeType: "image/jpeg",
            apiKey: "unit-test-key",
            model: .fast
        )
        let bodyData = try #require(request.httpBody)
        let body = try #require(
            JSONSerialization.jsonObject(with: bodyData) as? [String: Any]
        )
        let messages = try #require(body["messages"] as? [[String: Any]])
        let parts = try #require(messages[1]["content"] as? [[String: Any]])
        let imageURL = try #require(parts[1]["image_url"] as? [String: Any])

        #expect(
            imageURL["url"] as? String
                == "data:image/jpeg;base64,\(imageData.base64EncodedString())"
        )
    }

    @Test("The production session rejects redirects")
    func rejectsRedirects() throws {
        let configuration = URLSessionConfiguration.ephemeral
        let delegate = RedirectRejectingSessionDelegate()
        let session = TogetherAPIClient.makeSession(
            configuration: configuration,
            redirectDelegate: delegate
        )
        #expect(session.delegate === delegate)

        let sourceURL = try #require(URL(string: "https://api.together.xyz/v1/chat/completions"))
        let redirectURL = try #require(URL(string: "https://redirect.example/collect"))
        let task = session.dataTask(with: sourceURL)
        let response = try #require(
            HTTPURLResponse(
                url: sourceURL,
                statusCode: 307,
                httpVersion: "HTTP/1.1",
                headerFields: ["Location": redirectURL.absoluteString]
            )
        )
        let result = RedirectCompletionResult()

        delegate.urlSession(
            session,
            task: task,
            willPerformHTTPRedirection: response,
            newRequest: URLRequest(url: redirectURL)
        ) { request in
            result.store(request)
        }

        #expect(result.wasCalled)
        #expect(result.request == nil)
        session.invalidateAndCancel()
    }

    @Test("Successful response removes blank wrapper lines and preserves content spaces")
    func parseResponsePreservesMeaningfulWhitespace() throws {
        let data = Data(
            #"{"choices":[{"message":{"content":"  \n# Heading\n\nBody text.  \t"},"finish_reason":"stop"}]}"#.utf8
        )

        let result = try TogetherAPIClient.parseResponse(data: data, statusCode: 200)

        #expect(result == "# Heading\n\nBody text.  \t")
    }

    @Test("Successful response preserves original scripts and ignores extra fields")
    func parseResponsePreservesUnicodeWithExtraFields() throws {
        let content = "العَرَبِيَّة\nCafe\u{301} 👩‍💻"
        let payload = try JSONSerialization.data(withJSONObject: [
            "choices": [[
                "message": ["content": content, "reasoning": "unused"],
                "finish_reason": "stop",
                "warnings": ["unused"]
            ]],
            "warnings": ["unused"]
        ])

        let result = try TogetherAPIClient.parseResponse(data: payload, statusCode: 200)

        #expect(result == content)
    }

    @Test("Successful response normalizes chart drawing glyphs")
    func parseResponseNormalizesChartDrawingGlyphs() throws {
        let content = "```ascii\n10 ┤ ███\n 0 └───\n```"
        let payload = try JSONSerialization.data(withJSONObject: [
            "choices": [[
                "message": ["content": content],
                "finish_reason": "stop"
            ]]
        ])

        let result = try TogetherAPIClient.parseResponse(data: payload, statusCode: 200)

        #expect(result == "```ascii\n10 + @@@\n 0 +---\n```")
    }

    @Test("An oversized ASCII chart is rejected instead of copied")
    func parseResponseRejectsOversizedASCIIChart() throws {
        let chartLine = String(
            repeating: "#",
            count: AppConfiguration.maximumASCIIChartCharactersPerLine + 1
        )
        let payload = try JSONSerialization.data(withJSONObject: [
            "choices": [[
                "message": ["content": "```ascii\n\(chartLine)\n```"],
                "finish_reason": "stop"
            ]]
        ])

        #expect(throws: TogetherAPIError.invalidResponse) {
            try TogetherAPIClient.parseResponse(data: payload, statusCode: 200)
        }
    }

    @Test("HTTP 401 maps to authentication failure")
    func parseResponseMapsAuthenticationFailure() {
        #expect(parseError(statusCode: 401) == .authenticationFailed)
    }

    @Test("HTTP 429 maps to rate limiting")
    func parseResponseMapsRateLimit() {
        #expect(parseError(statusCode: 429) == .rateLimited)
    }

    @Test("All server errors map to service unavailable")
    func parseResponseMapsEveryServerErrorToServiceUnavailable() {
        for statusCode in [500, 503, 599] {
            #expect(parseError(statusCode: statusCode) == .serviceUnavailable)
        }
    }

    @Test("Custom HTTP error preserves its status and message")
    func parseResponsePreservesCustomStatusAndMessage() {
        let data = Data(#"{"error":{"message":"unsupported image"}}"#.utf8)

        #expect(
            parseError(data: data, statusCode: 422)
                == .requestFailed(statusCode: 422, message: "unsupported image")
        )
    }

    @Test("Custom HTTP error tolerates an unreadable envelope")
    func parseResponseHandlesCustomErrorWithoutDecodableEnvelope() {
        #expect(
            parseError(data: Data("not json".utf8), statusCode: 418)
                == .requestFailed(statusCode: 418, message: nil)
        )
    }

    @Test("Successful status rejects unreadable JSON")
    func parseResponseRejectsUnreadableSuccessPayload() {
        #expect(
            parseError(data: Data("not json".utf8), statusCode: 200) == .invalidResponse
        )
    }

    @Test("Successful status rejects an empty choice list")
    func parseResponseRejectsMissingChoice() {
        let data = Data(#"{"choices":[]}"#.utf8)

        #expect(parseError(data: data, statusCode: 200) == .emptyResponse)
    }

    @Test("Successful status rejects null content")
    func parseResponseRejectsNullContent() {
        let data = Data(
            #"{"choices":[{"message":{"content":null},"finish_reason":"stop"}]}"#.utf8
        )

        #expect(parseError(data: data, statusCode: 200) == .emptyResponse)
    }

    @Test("Successful status rejects whitespace-only content")
    func parseResponseRejectsWhitespaceOnlyContent() {
        let data = Data(
            #"{"choices":[{"message":{"content":" \n\t "},"finish_reason":"stop"}]}"#.utf8
        )

        #expect(parseError(data: data, statusCode: 200) == .emptyResponse)
    }

    @Test("A token-limited response is rejected instead of copied as complete")
    func parseResponseRejectsTruncatedOutput() {
        let data = Data(
            #"{"choices":[{"message":{"content":"partial text"},"finish_reason":"length"}]}"#.utf8
        )

        #expect(parseError(data: data, statusCode: 200) == .outputTruncated)
    }

    @Test("A missing finish reason is rejected")
    func parseResponseRejectsMissingFinishReason() {
        let data = Data(#"{"choices":[{"message":{"content":"text"}}]}"#.utf8)

        #expect(
            parseError(data: data, statusCode: 200)
                == .incompleteResponse(reason: nil)
        )
    }

    @Test("An unexpected finish reason is rejected")
    func parseResponseRejectsUnexpectedFinishReason() {
        let data = Data(
            #"{"choices":[{"message":{"content":"partial"},"finish_reason":"tool_calls"}]}"#.utf8
        )

        #expect(
            parseError(data: data, statusCode: 200)
                == .incompleteResponse(reason: "tool_calls")
        )
    }

    @Test("EOS is accepted as a complete terminal response")
    func parseResponseAcceptsEOSFinishReason() throws {
        let data = Data(
            #"{"choices":[{"message":{"content":"complete"},"finish_reason":"eos"}]}"#.utf8
        )

        #expect(try TogetherAPIClient.parseResponse(data: data, statusCode: 200) == "complete")
    }

    @Test("An unterminated ASCII chart is rejected")
    func parseResponseRejectsUnterminatedASCIIChart() {
        let data = Data(
            #"{"choices":[{"message":{"content":"```ascii\n10 ┤ ███"},"finish_reason":"stop"}]}"#.utf8
        )

        #expect(parseError(data: data, statusCode: 200) == .invalidResponse)
    }

    private func parseError(
        data: Data = Data(#"{"error":{"message":"ignored for mapped errors"}}"#.utf8),
        statusCode: Int
    ) -> TogetherAPIError? {
        do {
            _ = try TogetherAPIClient.parseResponse(data: data, statusCode: statusCode)
            Issue.record("Expected parseResponse to throw for HTTP \(statusCode).")
            return nil
        } catch {
            return error as? TogetherAPIError
        }
    }
}

private final class RedirectCompletionResult: @unchecked Sendable {
    private let lock = NSLock()
    private var storedRequest: URLRequest??

    var wasCalled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return storedRequest != nil
    }

    var request: URLRequest? {
        lock.lock()
        defer { lock.unlock() }
        return storedRequest ?? nil
    }

    func store(_ request: URLRequest?) {
        lock.lock()
        storedRequest = .some(request)
        lock.unlock()
    }
}
