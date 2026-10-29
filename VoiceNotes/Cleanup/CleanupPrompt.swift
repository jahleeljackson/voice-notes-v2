import Foundation

enum CleanupPrompt {
    static let defaultModel = "gpt-5-mini"
    static let endpoint = URL(string: "https://api.openai.com/v1/chat/completions")!

    static let system = """
    You edit dictated speech into the text the speaker meant to write. Return only that text.

    Rules:
    - Remove filler and disfluencies such as um, uh, er, ah, like, you know, sort of, kind of, and I mean, when they are not part of the intended wording.
    - Apply self-corrections. If the speaker replaces an earlier word or phrase, keep only the corrected version.
    - Fix grammar, punctuation, and capitalization.
    - Preserve the speaker's meaning, names, numbers, and tone. Do not add facts, greetings, apologies, or commentary.
    - When the speaker is listing items, format them as a real list. Use lines that start with a bullet (•) for an unordered list, or 1. 2. 3. for an ordered list. Use paragraphs for ordinary prose.
    - Honor spoken formatting such as new line, new paragraph, bullet, and number.
    - Do not wrap the result in quotes or code fences.
    """

    static func sanitize(_ text: String) -> String {
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("```") {
            if let newline = trimmed.firstIndex(of: "\n") {
                trimmed = String(trimmed[trimmed.index(after: newline)...])
            }
            if let fence = trimmed.range(of: "```", options: .backwards) {
                trimmed = String(trimmed[..<fence.lowerBound])
            }
            trimmed = trimmed.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if trimmed.count >= 2, trimmed.hasPrefix("\""), trimmed.hasSuffix("\"") {
            trimmed = String(trimmed.dropFirst().dropLast())
        }
        return trimmed.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func shouldRetryWithoutReasoning(status: Int, body: String) -> Bool {
        status == 400 && body.localizedCaseInsensitiveContains("reasoning_effort")
    }

    static func requestBody(model: String, transcript: String, includeReasoningEffort: Bool) throws -> Data {
        try JSONEncoder().encode(
            ChatRequest(
                model: model,
                messages: [
                    .init(role: "system", content: system),
                    .init(role: "user", content: "Transcript:\n\(transcript)")
                ],
                maxCompletionTokens: 2048,
                reasoningEffort: includeReasoningEffort ? "minimal" : nil
            )
        )
    }
}

struct ChatRequest: Encodable {
    struct Message: Encodable {
        var role: String
        var content: String
    }

    var model: String
    var messages: [Message]
    var maxCompletionTokens: Int
    var reasoningEffort: String?

    enum CodingKeys: String, CodingKey {
        case model
        case messages
        case maxCompletionTokens = "max_completion_tokens"
        case reasoningEffort = "reasoning_effort"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(model, forKey: .model)
        try container.encode(messages, forKey: .messages)
        try container.encode(maxCompletionTokens, forKey: .maxCompletionTokens)
        try container.encodeIfPresent(reasoningEffort, forKey: .reasoningEffort)
    }
}
