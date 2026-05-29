import Foundation
import TikiTimeCore

struct AIAPIClient {
    private let apiKey: String
    private let provider: UserSettings.AIProvider

    private static let anthropicEndpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    private static let openAIEndpoint = URL(string: "https://api.openai.com/v1/chat/completions")!
    private static let geminiModel = "gemini-2.0-flash"

    init(apiKey: String, provider: UserSettings.AIProvider) {
        self.apiKey = apiKey
        self.provider = provider
    }

    func respond(to userMessage: String) async throws -> String {
        switch provider {
        case .anthropic: return try await respondViaAnthropic(userMessage)
        case .openai: return try await respondViaOpenAI(userMessage)
        case .gemini: return try await respondViaGemini(userMessage)
        }
    }

    private func respondViaAnthropic(_ userMessage: String) async throws -> String {
        var request = URLRequest(url: Self.anthropicEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        let body: [String: Any] = [
            "model": "claude-haiku-4-5-20251001",
            "max_tokens": 100,
            "system": systemPrompt,
            "messages": [["role": "user", "content": userMessage]]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw APIError.requestFailed
        }

        struct Response: Decodable {
            let content: [Block]
            struct Block: Decodable { let text: String }
        }
        return try JSONDecoder().decode(Response.self, from: data).content.first?.text ?? "..."
    }

    private func respondViaOpenAI(_ userMessage: String) async throws -> String {
        var request = URLRequest(url: Self.openAIEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let body: [String: Any] = [
            "model": "gpt-4o-mini",
            "max_tokens": 100,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userMessage]
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw APIError.requestFailed
        }

        struct Response: Decodable {
            let choices: [Choice]
            struct Choice: Decodable {
                let message: Message
                struct Message: Decodable { let content: String }
            }
        }
        return try JSONDecoder().decode(Response.self, from: data).choices.first?.message.content ?? "..."
    }

    private func respondViaGemini(_ userMessage: String) async throws -> String {
        let urlString = "https://generativelanguage.googleapis.com/v1beta/models/\(Self.geminiModel):generateContent?key=\(apiKey)"
        guard let url = URL(string: urlString) else { throw APIError.requestFailed }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "systemInstruction": ["parts": [["text": systemPrompt]]],
            "contents": [["role": "user", "parts": [["text": userMessage]]]],
            "generationConfig": ["maxOutputTokens": 150]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw APIError.requestFailed
        }

        struct Response: Decodable {
            let candidates: [Candidate]
            struct Candidate: Decodable {
                let content: Content
                struct Content: Decodable {
                    let parts: [Part]
                    struct Part: Decodable { let text: String }
                }
            }
        }
        return try JSONDecoder().decode(Response.self, from: data)
            .candidates.first?.content.parts.first?.text ?? "..."
    }

    var systemPrompt: String {
        """
        당신은 귀엽고 사랑스러운 데스크탑 마스코트예요.
        반드시 아래 JSON 형식으로만 응답하세요. 다른 텍스트는 절대 포함하지 마세요:
        {"emotion":"감정키","text":"한국어 한 문장 대사 (이모지 1개 포함)"}
        감정키는 반드시 다음 중 하나: idle, happy, sad, angry, fearful, disgusted, surprised
        대사는 짧고 귀엽게, 상황에 맞는 감정키를 선택하세요.
        """
    }

    struct AIResponse {
        let emotion: String
        let text: String

        static func parse(_ raw: String) -> AIResponse {
            guard let data = raw.data(using: .utf8),
                  let json = try? JSONDecoder().decode([String: String].self, from: data),
                  let emotion = json["emotion"],
                  let text = json["text"]
            else { return AIResponse(emotion: "idle", text: raw) }
            return AIResponse(emotion: emotion, text: text)
        }
    }

    enum APIError: LocalizedError {
        case requestFailed
        var errorDescription: String? { "API 요청에 실패했어요 😿" }
    }
}
