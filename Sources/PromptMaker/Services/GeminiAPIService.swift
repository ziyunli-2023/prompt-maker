import Foundation

actor GeminiAPIService: AICompletionService {
    private let apiKey: String
    private let model: String

    init(apiKey: String, model: String = "gemini-2.0-flash") {
        self.apiKey = apiKey
        self.model = model
    }

    func complete(input: String) async throws -> CompletionResult {
        guard !apiKey.isEmpty else { throw CompletionError.missingAPIKey }

        let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent?key=\(apiKey)")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "contents": [[
                "role": "user",
                "parts": [["text": SYSTEM_PROMPT + "\n\n---INPUT---\n" + input]]
            ]],
            "generationConfig": [
                "responseMimeType": "application/json",
                "responseSchema": [
                    "type": "OBJECT",
                    "properties": [
                        "translation": ["type": "STRING"],
                        "optimized": ["type": "STRING"]
                    ],
                    "required": ["translation", "optimized"]
                ]
            ]
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw CompletionError.invalidResponse(String(data: data, encoding: .utf8) ?? "")
        }
        guard http.statusCode == 200 else {
            throw CompletionError.httpError(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }

        struct GeminiResponse: Decodable {
            struct Candidate: Decodable {
                struct Content: Decodable {
                    struct Part: Decodable { let text: String? }
                    let parts: [Part]?
                }
                let content: Content?
            }
            let candidates: [Candidate]?
        }

        let g = try JSONDecoder().decode(GeminiResponse.self, from: data)
        guard let text = g.candidates?.first?.content?.parts?.first?.text else {
            throw CompletionError.invalidResponse(String(data: data, encoding: .utf8) ?? "")
        }

        return try parseCompletionJSON(text)
    }

    func customComplete(input: String, instruction: String) async throws -> String {
        guard !apiKey.isEmpty else { throw CompletionError.missingAPIKey }

        let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent?key=\(apiKey)")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let userMessage = "\(CUSTOM_SYSTEM_PROMPT)\n\nInstruction: \(instruction)\n\n---TEXT---\n\(input)"
        let body: [String: Any] = [
            "contents": [[
                "role": "user",
                "parts": [["text": userMessage]]
            ]]
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw CompletionError.invalidResponse(String(data: data, encoding: .utf8) ?? "")
        }
        guard http.statusCode == 200 else {
            throw CompletionError.httpError(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }

        struct GeminiResponse: Decodable {
            struct Candidate: Decodable {
                struct Content: Decodable {
                    struct Part: Decodable { let text: String? }
                    let parts: [Part]?
                }
                let content: Content?
            }
            let candidates: [Candidate]?
        }

        let g = try JSONDecoder().decode(GeminiResponse.self, from: data)
        guard let text = g.candidates?.first?.content?.parts?.first?.text else {
            throw CompletionError.invalidResponse(String(data: data, encoding: .utf8) ?? "")
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
