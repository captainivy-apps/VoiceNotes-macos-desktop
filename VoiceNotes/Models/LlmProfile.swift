import Foundation

struct LlmProfile: Identifiable, Equatable, Codable {
    var id: String
    var name: String
    var baseURL: String
    var apiKey: String
    var model: String
    var systemPrompt: String

    static let defaultProfileID = "default"

    var summary: String { "\(name) · \(model)" }

    func toConfig() -> LlmConfig {
        LlmConfig(baseURL: baseURL, apiKey: apiKey, model: model, systemPrompt: systemPrompt)
    }

    static func createDefault(
        id: String = UUID().uuidString,
        name: String = "新配置"
    ) -> LlmProfile {
        LlmProfile(
            id: id,
            name: name,
            baseURL: AppSettings.defaultLLMBaseURL,
            apiKey: "",
            model: AppSettings.defaultLLMModel,
            systemPrompt: AppSettings.defaultLLMSystemPrompt
        )
    }

    enum CodingKeys: String, CodingKey {
        case id, name, baseURL, apiKey, model, systemPrompt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(String.self, forKey: .id)) ?? UUID().uuidString
        name = (try? c.decode(String.self, forKey: .name)) ?? "未命名"
        baseURL = (try? c.decode(String.self, forKey: .baseURL)) ?? AppSettings.defaultLLMBaseURL
        apiKey = (try? c.decode(String.self, forKey: .apiKey)) ?? ""
        model = (try? c.decode(String.self, forKey: .model)) ?? AppSettings.defaultLLMModel
        systemPrompt = (try? c.decode(String.self, forKey: .systemPrompt)) ?? AppSettings.defaultLLMSystemPrompt
    }

    init(id: String, name: String, baseURL: String, apiKey: String, model: String, systemPrompt: String) {
        self.id = id
        self.name = name
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.model = model
        self.systemPrompt = systemPrompt
    }
}

struct LlmConfig: Equatable {
    var baseURL: String
    var apiKey: String
    var model: String
    var systemPrompt: String
}
