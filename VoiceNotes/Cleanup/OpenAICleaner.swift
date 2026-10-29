import Foundation

struct ChatCompletionResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable {
            var content: String?
        }

        var message: Message
    }

    var choices: [Choice]
}

struct APIErrorEnvelope: Decodable {
    struct Body: Decodable {
        var message: String
    }

    var error: Body
}

struct OpenAICleaner: Sendable {
    var session: URLSession = .shared

    func clean(transcript: String, apiKey: String, model: String) async throws -> String {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else { throw DictationError.missingAPIKey }
        let modelName = model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? CleanupPrompt.defaultModel
            : model.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            return try await send(
                transcript: transcript,
                apiKey: trimmedKey,
                model: modelName,
                includeReasoningEffort: true
            )
        } catch is ReasoningRejected {
            return try await send(
                transcript: transcript,
                apiKey: trimmedKey,
                model: modelName,
                includeReasoningEffort: false
            )
        } catch {
            throw error
        }
    }

    private func send(
        transcript: String,
        apiKey: String,
        model: String,
        includeReasoningEffort: Bool
    ) async throws -> String {
        var request = URLRequest(url: CleanupPrompt.endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try CleanupPrompt.requestBody(
            model: model,
            transcript: transcript,
            includeReasoningEffort: includeReasoningEffort
        )

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw DictationError.openaiUnreachable
        }

        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let body = String(data: data, encoding: .utf8) ?? ""
        if CleanupPrompt.shouldRetryWithoutReasoning(status: status, body: body), includeReasoningEffort {
            throw ReasoningRejected()
        }
        guard (200..<300).contains(status) else {
            throw DictationError.cleanupFailed(message(for: status, body: body))
        }
        let decoded = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
        let text = CleanupPrompt.sanitize(decoded.choices.first?.message.content ?? "")
        guard !text.isEmpty else {
            throw DictationError.cleanupFailed("OpenAI returned an empty cleanup. The raw note was saved.")
        }
        return text
    }

    private func message(for status: Int, body: String) -> String {
        let apiMessage = (try? JSONDecoder().decode(APIErrorEnvelope.self, from: Data(body.utf8)))?.error.message
        switch status {
        case 401:
            return "The OpenAI API key was rejected. The raw note was saved."
        case 429:
            return "OpenAI is rate limiting requests. The raw note was saved."
        default:
            let detail = apiMessage.map { String($0.prefix(160)) } ?? "Cleanup failed (\(status))."
            return "\(detail) The raw note was saved."
        }
    }
}

private struct ReasoningRejected: Error {}
