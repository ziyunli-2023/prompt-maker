import Foundation

@MainActor
enum ServiceFactory {
    static func make() -> AICompletionService {
        let backend = UserDefaults.standard.string(forKey: "backend") ?? "deepseek"
        let modelOverride = UserDefaults.standard.string(forKey: "geminiModel") ?? ""

        switch backend {
        case "deepseek":
            let stored = KeychainHelper.shared.read(key: "deepseekAPIKey") ?? ""
            let key = stored.isEmpty ? DEEPSEEK_FALLBACK_KEY : stored
            let model = modelOverride.isEmpty ? "deepseek-chat" : modelOverride
            return DeepSeekService(apiKey: key, model: model)

        case "api":
            let key = KeychainHelper.shared.read(key: "geminiAPIKey") ?? ""
            let model = modelOverride.isEmpty ? "gemini-2.0-flash" : modelOverride
            return GeminiAPIService(apiKey: key, model: model)

        default: // "cli"
            return GeminiCLIService(model: modelOverride.isEmpty ? nil : modelOverride)
        }
    }
}
