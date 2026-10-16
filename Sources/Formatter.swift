import Foundation

protocol TextFormatter {
    var name: String { get }
    func format(_ raw: String) async throws -> String
}

struct PassthroughFormatter: TextFormatter {
    let name = "off (raw transcript)"
    func format(_ raw: String) async throws -> String { raw }
}

// Cleanup pass via the Anthropic Messages API. Only the transcribed text is
// sent, never audio. Any failure or timeout means the caller inserts the raw
// transcript instead. The formatter must never add content: output that is
// clearly longer than the input is rejected.
final class ClaudeFormatter: TextFormatter {
    let name: String
    let model: String
    let baseTimeout: TimeInterval

    static let apiURL = URL(string: "https://api.anthropic.com/v1/messages")!

    static let systemPrompt = """
    You clean up dictated speech transcripts. Output only the cleaned text, nothing else.
    Rules:
    - Remove filler words (um, uh, you know, like, "so" at the start of a sentence), repeated words and false starts.
    - Fix punctuation and capitalisation. Join fragments into proper sentences.
    - Every sentence ends with a full stop, question mark or exclamation mark, followed by a single space before the next sentence. The last sentence ends with its punctuation too.
    - Keep the speaker's language. English stays English, German stays German. Never translate.
    - Keep every fact, name, number and the speaker's meaning exactly. Never add, answer, summarise, expand or comment.
    - If the speech is clearly a list of items, format it as a plain list with "- " bullets. Otherwise plain prose, no markdown.
    - Never add greetings, sign-offs or headings the speaker did not say.
    - If the transcript is already clean, return it unchanged.
    """

    private let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.waitsForConnectivity = false
        return URLSession(configuration: c)
    }()

    init(model: String, timeout: TimeInterval) {
        self.model = model
        self.baseTimeout = timeout
        self.name = "Claude \(model)"
    }

    // Timeout grows with input so a long dictation is not cut off by the
    // 2 s base: base + 1 s per 400 characters, capped at base + 4 s.
    func timeout(for raw: String) -> TimeInterval {
        let extra = min(4.0, Double(raw.count) / 400.0)
        return baseTimeout + extra
    }

    func format(_ raw: String) async throws -> String {
        guard let key = Keychain.readAPIKey() else { throw DictateError.noAPIKey }
        let estimatedTokens = max(64, raw.utf8.count / 3)
        let maxTokens = min(8192, max(512, estimatedTokens * 2))
        let payload: [String: Any] = [
            "model": model,
            "max_tokens": maxTokens,
            "system": Self.systemPrompt,
            "output_config": ["effort": "low"],
            "messages": [["role": "user", "content": raw]],
        ]
        var req = URLRequest(url: Self.apiURL)
        req.httpMethod = "POST"
        req.timeoutInterval = timeout(for: raw)
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(key, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        req.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw DictateError.formatterFailed("no HTTP response") }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw DictateError.formatterFailed("non-JSON response")
        }
        if http.statusCode != 200 {
            let err = json["error"] as? [String: Any]
            throw DictateError.formatterFailed("HTTP \(http.statusCode) \(err?["type"] ?? "") \(err?["message"] ?? "")")
        }
        if let stop = json["stop_reason"] as? String, stop == "refusal" {
            throw DictateError.formatterFailed("refusal")
        }
        guard let content = json["content"] as? [[String: Any]] else {
            throw DictateError.formatterFailed("no content")
        }
        let text = content.compactMap { $0["type"] as? String == "text" ? $0["text"] as? String : nil }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw DictateError.formatterFailed("empty output") }
        // Invented content guard: cleanup only ever shortens or keeps length.
        let limit = Int(Double(raw.count) * 1.3) + 40
        guard text.count <= limit else {
            throw DictateError.formatterFailed("output longer than input (\(text.count) > \(limit)), rejected")
        }
        return Self.stripWrappingQuotes(text)
    }

    static func stripWrappingQuotes(_ s: String) -> String {
        guard s.count >= 2, let f = s.first, let l = s.last else { return s }
        if (f == "\"" && l == "\"") || (f == "“" && l == "”") {
            return String(s.dropFirst().dropLast())
        }
        return s
    }
}
