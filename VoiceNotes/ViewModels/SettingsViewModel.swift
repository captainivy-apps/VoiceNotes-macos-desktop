import Foundation

@MainActor
final class SettingsViewModel: ObservableObject {
    @Published var models: [AsrModelInfo] = AsrModels.all
    @Published var downloadedIds: Set<String> = []
    @Published var selectedModelId: String = AppSettings.defaultAsrModel
    @Published var asrLanguages: [AsrLanguage] = AsrLanguages.all
    @Published var asrLanguage: String = AppSettings.asrLanguage
    @Published var mirrorBaseURL: String = AppSettings.mirrorBaseURL
    @Published var downloadProgress: [String: Double] = [:]
    @Published var downloadingIds: Set<String> = []
    @Published var modelDownloadTimes: [String: Date] = [:]
    @Published var coremlInstalledIds: Set<String> = []
    @Published var coremlInstallingIds: Set<String> = []
    @Published var coremlDownloadProgress: [String: Double] = [:]
    @Published var llmProfiles: [LlmProfile] = []
    @Published var activeLlmProfileId = ""

    @Published var inputDevices: [AudioInputDevice] = []
    @Published var selectedInputDeviceUID = AppSettings.selectedInputDeviceUID

    @Published var voiceSilencePauseSeconds = AppSettings.voiceSilencePauseSeconds
    @Published var voiceSilenceStopSeconds = AppSettings.voiceSilenceStopSeconds

    @Published var editorOpen = false
    @Published var editorIsNew = false
    @Published var editingId = ""
    @Published var formName = ""
    @Published var formBaseURL = AppSettings.defaultLLMBaseURL
    @Published var formApiKey = ""
    @Published var formModel = AppSettings.defaultLLMModel
    @Published var formSystemPrompt = AppSettings.defaultLLMSystemPrompt

    @Published var message: String?
    @Published var error: String?
    @Published var toast: String?

    private let services: AppServices

    init(services: AppServices) {
        self.services = services
        refresh()
    }

    var isDownloadingAny: Bool { !downloadingIds.isEmpty }

    func refresh() {
        downloadedIds = Set(AsrModels.all.filter { services.downloader.isDownloaded($0) }.map(\.id))
        let selected = AppSettings.selectedAsrModel
        if let model = AsrModels.find(selected), downloadedIds.contains(model.id) {
            selectedModelId = model.id
        } else {
            selectedModelId = downloadedIds.sorted().first ?? AppSettings.defaultAsrModel
        }
        var times: [String: Date] = [:]
        for model in AsrModels.all {
            if let date = services.downloader.downloadedAt(model) { times[model.id] = date }
        }
        modelDownloadTimes = times
        coremlInstalledIds = Set(AsrModels.all
            .filter { services.downloader.isCoreMLEncoderInstalled($0) }
            .map(\.id))
        asrLanguage = AppSettings.asrLanguage
        mirrorBaseURL = AppSettings.mirrorBaseURL
        llmProfiles = AppSettings.llmProfiles
        activeLlmProfileId = AppSettings.activeLlmProfileId
        voiceSilencePauseSeconds = AppSettings.voiceSilencePauseSeconds
        voiceSilenceStopSeconds = AppSettings.voiceSilenceStopSeconds
        refreshInputDevices()
    }

    func setVoiceSilencePauseSeconds(_ value: Int) {
        AppSettings.voiceSilencePauseSeconds = value
        voiceSilencePauseSeconds = AppSettings.voiceSilencePauseSeconds
        voiceSilenceStopSeconds = AppSettings.voiceSilenceStopSeconds
        message = "静音 \(voiceSilencePauseSeconds) 秒自动暂停"
        error = nil
    }

    func setVoiceSilenceStopSeconds(_ value: Int) {
        AppSettings.voiceSilenceStopSeconds = value
        voiceSilenceStopSeconds = AppSettings.voiceSilenceStopSeconds
        voiceSilencePauseSeconds = AppSettings.voiceSilencePauseSeconds
        message = "静音 \(voiceSilenceStopSeconds) 秒自动停止"
        error = nil
    }

    func refreshInputDevices() {
        inputDevices = AudioInputDevices.all()
        selectedInputDeviceUID = AppSettings.selectedInputDeviceUID
    }

    func selectInputDevice(_ uid: String) {
        AppSettings.selectedInputDeviceUID = uid
        selectedInputDeviceUID = uid
        let name = inputDevices.first { $0.id == uid }?.name
        message = uid.isEmpty ? "已选择系统默认麦克风" : "已选择「\(name ?? uid)」"
        error = nil
    }

    func selectAsrLanguage(_ id: String) {
        guard AsrLanguages.all.contains(where: { $0.id == id }) else { return }
        AppSettings.asrLanguage = id
        asrLanguage = id
        message = "识别语言已设为「\(AsrLanguages.displayName(id))」"
        error = nil
    }

    // MARK: - Mirror

    func saveMirrorBaseURL() {
        AppSettings.mirrorBaseURL = mirrorBaseURL
        mirrorBaseURL = AppSettings.mirrorBaseURL
        message = mirrorBaseURL.isEmpty ? "镜像地址已清空" : "镜像地址已保存"
        error = nil
    }

    func clearMirrorBaseURL() {
        AppSettings.mirrorBaseURL = ""
        mirrorBaseURL = ""
        message = "镜像地址已清空"
        error = nil
    }

    func selectModel(_ id: String) {
        guard let model = AsrModels.find(id) else { return }
        guard services.downloader.isDownloaded(model) else {
            error = "请先下载该模型"
            return
        }
        AppSettings.selectedAsrModel = id
        refresh()
    }

    func downloadModel(_ id: String, useMirror: Bool = false) {
        guard let model = AsrModels.find(id) else { return }
        error = nil
        message = useMirror ? "开始从镜像下载 \(model.displayName)" : "开始下载 \(model.displayName)"
        downloadingIds.insert(id)
        Task {
            do {
                _ = try await services.downloader.download(model, useMirror: useMirror) { [weak self] progress in
                    Task { @MainActor in self?.downloadProgress[id] = progress }
                }
                downloadProgress[id] = nil
                downloadingIds.remove(id)
                message = "\(model.displayName) 下载完成"
                toast = "\(model.displayName) 下载完成"
                let selected = AsrModels.find(AppSettings.selectedAsrModel)
                if selected == nil || !services.downloader.isDownloaded(selected!) {
                    AppSettings.selectedAsrModel = id
                }
                refresh()
            } catch {
                downloadProgress[id] = nil
                downloadingIds.remove(id)
                let detail = error.localizedDescription
                let message = "\(detail)。请检查网络连接或代理设置后重试。"
                self.error = message
                toast = message
            }
        }
    }

    // MARK: - Core ML encoder

    func downloadCoreMLEncoder(_ id: String, useMirror: Bool = false) {
        guard let model = AsrModels.find(id), model.hasCoreML else { return }
        coremlInstallingIds.insert(id)
        error = nil
        message = useMirror
            ? "正在从镜像下载 \(model.displayName) 的 Core ML 编码器…"
            : "正在下载 \(model.displayName) 的 Core ML 编码器…"
        Task {
            do {
                try await services.downloader.downloadCoreMLEncoder(model, useMirror: useMirror) { [weak self] progress in
                    Task { @MainActor in self?.coremlDownloadProgress[id] = progress }
                }
                coremlDownloadProgress[id] = nil
                coremlInstallingIds.remove(id)
                message = "\(model.displayName) Core ML 编码器已就绪，将在 Apple Silicon 上自动启用"
                toast = message
                refresh()
            } catch {
                coremlDownloadProgress[id] = nil
                coremlInstallingIds.remove(id)
                let detail = error.localizedDescription
                self.error = detail
                toast = detail
            }
        }
    }

    func installCoreMLEncoder(_ id: String, from url: URL) {
        guard let model = AsrModels.find(id) else { return }
        coremlInstallingIds.insert(id)
        error = nil
        message = "正在编译 Core ML 编码器…"
        Task {
            do {
                try await services.downloader.installCoreMLEncoder(model, from: url)
                coremlInstallingIds.remove(id)
                message = "\(model.displayName) Core ML 编码器已就绪，将在 Apple Silicon 上自动启用"
                toast = message
                refresh()
            } catch {
                coremlInstallingIds.remove(id)
                let detail = error.localizedDescription
                self.error = detail
                toast = detail
            }
        }
    }

    func removeCoreMLEncoder(_ id: String) {
        guard let model = AsrModels.find(id) else { return }
        services.downloader.removeCoreMLEncoder(model)
        message = "已移除 \(model.displayName) 的 Core ML 编码器"
        error = nil
        refresh()
    }

    func deleteModel(_ id: String) {
        guard let model = AsrModels.find(id) else { return }
        _ = services.downloader.delete(model)
        if AppSettings.selectedAsrModel == id {
            let fallback = AsrModels.all.first(where: { services.downloader.isDownloaded($0) })?.id
                ?? AppSettings.defaultAsrModel
            AppSettings.selectedAsrModel = fallback
        }
        refresh()
    }

    // MARK: - LLM profiles

    func setActiveLlmProfile(_ id: String) {
        guard llmProfiles.contains(where: { $0.id == id }) else { return }
        AppSettings.activeLlmProfileId = id
        activeLlmProfileId = id
        message = nil
        error = nil
    }

    func openAddLlmProfile() {
        let newProfile = LlmProfile.createDefault(name: "配置 \(llmProfiles.count + 1)")
        editorOpen = true
        editorIsNew = true
        editingId = newProfile.id
        formName = newProfile.name
        formBaseURL = newProfile.baseURL
        formApiKey = newProfile.apiKey
        formModel = newProfile.model
        formSystemPrompt = newProfile.systemPrompt
        message = nil
        error = nil
    }

    func openEditLlmProfile(_ id: String) {
        guard let profile = llmProfiles.first(where: { $0.id == id }) else { return }
        editorOpen = true
        editorIsNew = false
        editingId = profile.id
        formName = profile.name
        formBaseURL = profile.baseURL
        formApiKey = profile.apiKey
        formModel = profile.model
        formSystemPrompt = profile.systemPrompt
        message = nil
        error = nil
    }

    func closeEditor() {
        editorOpen = false
        editorIsNew = false
        editingId = ""
        message = nil
        error = nil
    }

    func deleteLlmProfile(_ id: String) {
        guard llmProfiles.count > 1 else {
            error = "至少保留一组 LLM 配置"
            return
        }
        let profiles = llmProfiles.filter { $0.id != id }
        AppSettings.llmProfiles = profiles
        refresh()
        message = "已删除配置"
        error = nil
    }

    func saveLlmSettings() {
        guard !editingId.isEmpty else { error = "配置无效"; return }
        let draft = draftProfile()
        var profiles = llmProfiles
        if editorIsNew {
            profiles.append(draft)
        } else if let index = profiles.firstIndex(where: { $0.id == editingId }) {
            profiles[index] = draft
        } else {
            profiles.append(draft)
        }
        AppSettings.llmProfiles = profiles
        let savedMessage = editorIsNew ? "已添加「\(draft.name)」" : "「\(draft.name)」已保存"
        closeEditor()
        refresh()
        message = savedMessage
        error = nil
    }

    func testLlm() {
        let config = draftProfile().toConfig()
        toast = "正在测试连接…"
        Task {
            do {
                _ = try await services.llm.testConnection(config: config)
                toast = "连接成功"
            } catch {
                toast = error.localizedDescription
            }
        }
    }

    private func draftProfile() -> LlmProfile {
        LlmProfile(
            id: editingId,
            name: formName.trimmingCharacters(in: .whitespaces).isEmpty ? "未命名" : formName.trimmingCharacters(in: .whitespaces),
            baseURL: formBaseURL.trimmingCharacters(in: .whitespaces).isEmpty ? AppSettings.defaultLLMBaseURL : formBaseURL.trimmingCharacters(in: .whitespaces),
            apiKey: formApiKey.trimmingCharacters(in: .whitespaces),
            model: formModel.trimmingCharacters(in: .whitespaces).isEmpty ? AppSettings.defaultLLMModel : formModel.trimmingCharacters(in: .whitespaces),
            systemPrompt: formSystemPrompt.isEmpty ? AppSettings.defaultLLMSystemPrompt : formSystemPrompt
        )
    }
}
