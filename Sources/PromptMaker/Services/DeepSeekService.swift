import Foundation

actor DeepSeekService: AICompletionService {
    private let apiKey: String
    private let model: String

    init(apiKey: String, model: String = "deepseek-chat") {
        self.apiKey = apiKey
        self.model = model
    }

    func complete(input: String) async throws -> CompletionResult {
        guard !apiKey.isEmpty else { throw CompletionError.missingAPIKey }

        let url = URL(string: "https://api.deepseek.com/chat/completions")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 60

        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": SYSTEM_PROMPT],
                ["role": "user", "content": input]
            ],
            "response_format": ["type": "json_object"],
            "temperature": 0.0,
            "stream": false
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw CompletionError.invalidResponse(String(data: data, encoding: .utf8) ?? "")
        }
        guard http.statusCode == 200 else {
            throw CompletionError.httpError(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }

        struct ChatResponse: Decodable {
            struct Choice: Decodable {
                struct Message: Decodable { let content: String? }
                let message: Message?
            }
            let choices: [Choice]?
        }

        let r = try JSONDecoder().decode(ChatResponse.self, from: data)
        guard let text = r.choices?.first?.message?.content else {
            throw CompletionError.invalidResponse(String(data: data, encoding: .utf8) ?? "")
        }
        return try parseCompletionJSON(text)
    }

    func freeformComplete(prompt: String) async throws -> String {
        guard !apiKey.isEmpty else { throw CompletionError.missingAPIKey }

        let url = URL(string: "https://api.deepseek.com/chat/completions")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 60

        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": FREEFORM_SYSTEM_PROMPT],
                ["role": "user", "content": prompt]
            ],
            "temperature": 0.3,
            "stream": false
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw CompletionError.invalidResponse(String(data: data, encoding: .utf8) ?? "")
        }
        guard http.statusCode == 200 else {
            throw CompletionError.httpError(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }

        struct ChatResponse: Decodable {
            struct Choice: Decodable {
                struct Message: Decodable { let content: String? }
                let message: Message?
            }
            let choices: [Choice]?
        }

        let r = try JSONDecoder().decode(ChatResponse.self, from: data)
        guard let text = r.choices?.first?.message?.content else {
            throw CompletionError.invalidResponse(String(data: data, encoding: .utf8) ?? "")
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func customComplete(input: String, instruction: String) async throws -> String {
        guard !apiKey.isEmpty else { throw CompletionError.missingAPIKey }

        let url = URL(string: "https://api.deepseek.com/chat/completions")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 60

        let userMessage = "Instruction: \(instruction)\n\n---TEXT---\n\(input)"
        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": CUSTOM_SYSTEM_PROMPT],
                ["role": "user", "content": userMessage]
            ],
            "temperature": 0.0,
            "stream": false
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw CompletionError.invalidResponse(String(data: data, encoding: .utf8) ?? "")
        }
        guard http.statusCode == 200 else {
            throw CompletionError.httpError(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }

        struct ChatResponse: Decodable {
            struct Choice: Decodable {
                struct Message: Decodable { let content: String? }
                let message: Message?
            }
            let choices: [Choice]?
        }

        let r = try JSONDecoder().decode(ChatResponse.self, from: data)
        guard let text = r.choices?.first?.message?.content else {
            throw CompletionError.invalidResponse(String(data: data, encoding: .utf8) ?? "")
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
