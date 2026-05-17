import Foundation

struct CompletionResult: Sendable {
    let translation: String
    let optimized: String
}

protocol AICompletionService: Sendable {
    func complete(input: String) async throws -> CompletionResult
}

enum CompletionError: LocalizedError {
    case cliNotFound
    case nonZeroExit(Int32, String)
    case invalidResponse(String)
    case missingAPIKey
    case httpError(Int, String)

    var errorDescription: String? {
        switch self {
        case .cliNotFound:
            return "未找到 gemini CLI。请先安装并运行 `gemini auth login`。"
        case .nonZeroExit(let code, let stderr):
            return "Gemini CLI 退出码 \(code)：\(stderr.prefix(300))"
        case .invalidResponse(let raw):
            return "无法解析响应：\(raw.prefix(300))"
        case .missingAPIKey:
            return "未设置 API Key。请去设置里填入。"
        case .httpError(let code, let body):
            return "HTTP \(code)：\(body.prefix(300))"
        }
    }
}

let SYSTEM_PROMPT = """
You receive a draft prompt written in Chinese, English, or a mix. The user will paste your "optimized" output directly into Claude or ChatGPT. Your job is POLISH ONLY — never authoring.

Return STRICT JSON, exactly two fields:
{
  "translation": "literal English translation; word-for-word faithful; idiomatic but minimal in interpretation",
  "optimized":   "polished English version: same content, fixed grammar, idiomatic phrasing, accurate terminology"
}

HARD CONSTRAINTS — violating any of these is a failure. The optimized version MUST:
1. Contain NO persona/role framing the source lacks. NEVER inject "You are an expert…", "As a senior…", "Act as…" if the source has no such phrase.
2. Contain NO output-format instructions the source lacks. NEVER inject "Output in markdown", "Cover the following aspects:", "List the steps", "Use bullet points", "Include examples".
3. Contain NO added context/audience/scope/assumptions. NEVER inject "Assume the reader has…", "for beginners", "in detail", "with examples".
4. Have a sentence count within 1 of the source. Do NOT decompose a single ask into a numbered plan.
5. Have a length within 1.5x the source. If the source is short, the optimized version is short.

When in doubt: change wording, not content. If unsure whether something belongs, leave it out.

Output JSON only. No markdown fences. No commentary before or after.
"""

func parseCompletionJSON(_ raw: String) throws -> CompletionResult {
    let cleaned = stripCodeFences(raw)
    guard let data = cleaned.data(using: .utf8) else {
        throw CompletionError.invalidResponse(raw)
    }
    struct Payload: Decodable {
        let translation: String
        let optimized: String
    }
    do {
        let p = try JSONDecoder().decode(Payload.self, from: data)
        return CompletionResult(translation: p.translation, optimized: p.optimized)
    } catch {
        throw CompletionError.invalidResponse(raw)
    }
}

private func stripCodeFences(_ s: String) -> String {
    var t = s.trimmingCharacters(in: .whitespacesAndNewlines)
    if t.hasPrefix("```") {
        if let nl = t.firstIndex(of: "\n") {
            t = String(t[t.index(after: nl)...])
        }
    }
    if t.hasSuffix("```") {
        t = String(t.dropLast(3)).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    if let firstBrace = t.firstIndex(of: "{"),
       let lastBrace = t.lastIndex(of: "}"),
       firstBrace < lastBrace {
        t = String(t[firstBrace...lastBrace])
    }
    return t
}
