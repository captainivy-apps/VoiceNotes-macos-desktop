import Foundation

/// UserDefaults-backed preferences, mirroring the Android `AppPrefs`.
enum AppSettings {
    static let defaultAsrModel = "base"
    static let defaultLLMBaseURL = "https://api.openai.com"
    static let defaultLLMModel = "gpt-4o-mini"
    static let defaultLLMSystemPrompt =
        "你是记事整理助手。将用户的口语识别稿整理为简洁、通顺的记事正文。" +
        "去除口语赘词和重复，修正逻辑顺序，保留原意与情感，不要添加未提及的内容。"

    private static let keySelectedAsrModel = "selected_asr_model"
    private static let keyLlmProfiles = "llm_profiles_json"
    private static let keyActiveLlmProfileId = "active_llm_profile_id"

    private static var defaults: UserDefaults { .standard }

    // MARK: - ASR

    static var selectedAsrModel: String {
        get { defaults.string(forKey: keySelectedAsrModel) ?? defaultAsrModel }
        set { defaults.set(newValue, forKey: keySelectedAsrModel) }
    }

    // MARK: - LLM profiles

    static var llmProfiles: [LlmProfile] {
        get {
            ensureLlmProfilesMigrated()
            guard let data = defaults.data(forKey: keyLlmProfiles),
                  let profiles = try? JSONDecoder().decode([LlmProfile].self, from: data) else {
                return []
            }
            return profiles
        }
        set {
            guard !newValue.isEmpty else { return }
            if let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: keyLlmProfiles)
            }
            let active = activeLlmProfileId
            if !newValue.contains(where: { $0.id == active }) {
                activeLlmProfileId = newValue.first!.id
            }
        }
    }

    static var activeLlmProfileId: String {
        get {
            ensureLlmProfilesMigrated()
            let profiles = llmProfiles
            if let stored = defaults.string(forKey: keyActiveLlmProfileId),
               profiles.contains(where: { $0.id == stored }) {
                return stored
            }
            let fallback = profiles.first?.id ?? LlmProfile.defaultProfileID
            defaults.set(fallback, forKey: keyActiveLlmProfileId)
            return fallback
        }
        set { defaults.set(newValue, forKey: keyActiveLlmProfileId) }
    }

    static var activeLlmProfile: LlmProfile? {
        let id = activeLlmProfileId
        return llmProfiles.first { $0.id == id } ?? llmProfiles.first
    }

    static func llmProfile(id: String) -> LlmProfile? {
        llmProfiles.first { $0.id == id }
    }

    static func llmConfig(profileId: String?) -> LlmConfig {
        let id = profileId ?? activeLlmProfileId
        let profile = llmProfile(id: id) ?? activeLlmProfile
            ?? LlmProfile.createDefault(id: LlmProfile.defaultProfileID, name: "默认")
        return profile.toConfig()
    }

    private static func ensureLlmProfilesMigrated() {
        if defaults.data(forKey: keyLlmProfiles) != nil { return }
        let legacy = LlmProfile(
            id: LlmProfile.defaultProfileID,
            name: "默认",
            baseURL: defaultLLMBaseURL,
            apiKey: "",
            model: defaultLLMModel,
            systemPrompt: defaultLLMSystemPrompt
        )
        llmProfiles = [legacy]
        activeLlmProfileId = legacy.id
    }
}
