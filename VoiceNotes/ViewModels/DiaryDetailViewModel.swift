import Foundation

@MainActor
final class DiaryDetailViewModel: ObservableObject {
    @Published var loading = true
    @Published var createdAt: Int64 = 0
    @Published var updatedAt: Int64 = 0
    @Published var audioPath: String?
    @Published var transcript = ""
    @Published var diaryText = ""
    @Published var prevId: Int64?
    @Published var nextId: Int64?
    @Published var llmProfiles: [LlmProfile] = []
    @Published var selectedLlmProfileId = ""
    @Published var isProcessing = false
    @Published var statusMessage = ""
    @Published var asrProgress: Float?
    @Published var asrElapsedMs: Int64 = 0
    @Published var llmProgress: Float?
    @Published var llmElapsedMs: Int64 = 0
    @Published var error: String?
    @Published var toast: String?
    @Published var navigateBack = false

    let entryId: Int64
    private let services: AppServices
    private var ticker: Timer?
    private var processingStart: Date?
    private var isLlmProcessing = false

    init(services: AppServices, entryId: Int64) {
        self.services = services
        self.entryId = entryId
        refreshLlmProfiles()
    }

    func refreshLlmProfiles() {
        let profiles = AppSettings.llmProfiles
        llmProfiles = profiles
        if !profiles.contains(where: { $0.id == selectedLlmProfileId }) {
            selectedLlmProfileId = AppSettings.activeLlmProfileId
        }
    }

    func selectLlmProfile(_ id: String) {
        guard llmProfiles.contains(where: { $0.id == id }) else { return }
        selectedLlmProfileId = id
    }

    func load() async {
        do {
            guard let entry = try await services.store.get(entryId) else {
                loading = false
                error = "记事不存在"
                return
            }
            let neighbors = try await services.store.neighborIds(currentId: entryId)
            createdAt = entry.createdAt
            updatedAt = entry.updatedAt
            audioPath = entry.audioPath
            transcript = entry.transcriptText ?? ""
            diaryText = entry.diaryText ?? ""
            prevId = neighbors.prev
            nextId = neighbors.next
            loading = false
            error = nil
        } catch {
            loading = false
            self.error = error.localizedDescription
        }
    }

    func updateTranscript(_ text: String) {
        transcript = text
        Task { try? await services.store.saveTranscript(id: entryId, transcript: text) }
    }

    func updateDiaryText(_ text: String) {
        diaryText = text
        Task { try? await services.store.saveDiaryText(id: entryId, diaryText: text) }
    }

    // MARK: - ASR

    func runAsr() {
        guard let audioPath else { return }
        isProcessing = true
        asrProgress = nil
        asrElapsedMs = 0
        statusMessage = AsrProgressMessages.format(.loadingModel, 0)
        error = nil
        startProcessingTimer(llm: false)
        let modelId = AppSettings.selectedAsrModel

        Task {
            do {
                let text = try await services.whisper.transcribe(modelId: modelId, wavURL: URL(fileURLWithPath: audioPath)) { [weak self] progress, phase in
                    Task { @MainActor in
                        self?.asrProgress = phase == .loadingModel ? nil : progress
                        self?.statusMessage = AsrProgressMessages.format(phase, progress)
                    }
                }
                try await services.store.saveTranscript(id: entryId, transcript: text)
                isProcessing = false
                asrProgress = nil
                asrElapsedMs = 0
                stopProcessingTimer()
                transcript = text
                statusMessage = ""
                toast = "识别完成"
            } catch {
                isProcessing = false
                asrProgress = nil
                asrElapsedMs = 0
                stopProcessingTimer()
                statusMessage = ""
                self.error = error.localizedDescription
                toast = error.localizedDescription
            }
        }
    }

    func copyTranscriptToDiary() {
        let text = transcript
        diaryText = text
        toast = "已当作润色稿"
        Task { try? await services.store.saveDiaryText(id: entryId, diaryText: text) }
    }

    // MARK: - LLM

    func runLlm() {
        let transcript = transcript
        beginLlmProcessing()
        let config = AppSettings.llmConfig(profileId: selectedLlmProfileId)
        Task {
            do {
                let diary = try await services.llm.polishTranscript(config: config, transcript: transcript) { [weak self] progress, phase in
                    Task { @MainActor in self?.updateLlmProgress(progress: progress, phase: phase) }
                }
                endLlmProcessing()
                try await services.store.saveDiaryText(id: entryId, diaryText: diary)
                diaryText = diary
                toast = "润色完成"
            } catch {
                endLlmProcessing()
                self.error = error.localizedDescription
                toast = error.localizedDescription
            }
        }
    }

    // MARK: - Delete

    func deleteAudio() {
        Task {
            try? await services.store.deleteAudio(id: entryId)
            audioPath = nil
            toast = "录音已删除"
        }
    }

    func deleteTranscript() {
        Task {
            try? await services.store.deleteTranscript(id: entryId)
            transcript = ""
            toast = "识别稿已删除"
        }
    }

    func deleteDiaryText() {
        Task {
            try? await services.store.deleteDiaryText(id: entryId)
            diaryText = ""
            toast = "润色稿已删除"
        }
    }

    func deleteEntry() {
        Task {
            try? await services.store.deleteEntry(id: entryId)
            toast = "记事已删除"
            navigateBack = true
        }
    }

    // MARK: - Export

    func exportAudio() {
        guard let audioPath else { toast = "无录音"; return }
        let source = URL(fileURLWithPath: audioPath)
        let name = ExportFileNames.build(type: ExportFileNames.typeRecord, extension: ExportFileNames.audioExtension(for: source))
        do {
            let url = try Exporter.exportAudio(from: source, suggestedName: name)
            toast = "已保存到 \(url.path)"
        } catch ExportError.cancelled {
            // no-op
        } catch {
            toast = error.localizedDescription
        }
    }

    func exportTranscript() {
        let name = ExportFileNames.build(type: ExportFileNames.typeFirst, extension: "txt")
        do {
            let url = try Exporter.exportText(transcript, suggestedName: name)
            toast = "已保存到 \(url.path)"
        } catch ExportError.cancelled {
        } catch {
            toast = error.localizedDescription
        }
    }

    func exportDiaryText() {
        let name = ExportFileNames.build(type: ExportFileNames.typeFinal, extension: "txt")
        do {
            let url = try Exporter.exportText(diaryText, suggestedName: name)
            toast = "已保存到 \(url.path)"
        } catch ExportError.cancelled {
        } catch {
            toast = error.localizedDescription
        }
    }

    // MARK: - Progress helpers

    private func beginLlmProcessing() {
        isProcessing = true
        llmProgress = 0.05
        llmElapsedMs = 0
        statusMessage = LlmProgressMessages.format(.preparing, 0.05)
        error = nil
        isLlmProcessing = true
        startProcessingTimer(llm: true)
    }

    private func updateLlmProgress(progress: Float, phase: LlmPhase) {
        if phase == .receiving { isLlmProcessing = false }
        llmProgress = progress
        statusMessage = LlmProgressMessages.format(phase, progress)
    }

    private func endLlmProcessing() {
        isLlmProcessing = false
        llmProgress = nil
        llmElapsedMs = 0
        statusMessage = ""
        stopProcessingTimer()
    }

    private func startProcessingTimer(llm: Bool) {
        processingStart = Date()
        ticker?.invalidate()
        ticker = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let start = self.processingStart else { return }
                let elapsed = Int64(Date().timeIntervalSince(start) * 1000)
                if llm {
                    self.llmElapsedMs = elapsed
                    if self.isLlmProcessing, let progress = self.llmProgress, progress < 0.9 {
                        let pulsed = min(0.9, progress + 0.004)
                        self.llmProgress = pulsed
                        self.statusMessage = LlmProgressMessages.format(.waiting, pulsed)
                    }
                } else {
                    self.asrElapsedMs = elapsed
                }
            }
        }
    }

    private func stopProcessingTimer() {
        processingStart = nil
        ticker?.invalidate()
        ticker = nil
    }
}
