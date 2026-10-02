import Foundation

@MainActor
final class RecordViewModel: ObservableObject {
    @Published var isRecording = false
    @Published var isProcessing = false
    @Published var audioPath: String?
    @Published var durationMs: Int64 = 0
    @Published var transcript: String?
    @Published var entryId: Int64?
    @Published var awaitingAsrPrompt = false
    @Published var waveform: [Float] = []
    @Published var llmProfiles: [LlmProfile] = []
    @Published var selectedLlmProfileId = ""
    @Published var statusMessage = ""
    @Published var asrProgress: Float?
    @Published var asrElapsedMs: Int64 = 0
    @Published var llmProgress: Float?
    @Published var llmElapsedMs: Int64 = 0
    @Published var error: String?
    @Published var toast: String?

    private let services: AppServices
    private let recorder = AudioRecorder()
    private var ticker: Timer?
    private var recordingStart: Date?
    private var processingStart: Date?
    private var isLlmProcessing = false

    init(services: AppServices) {
        self.services = services
        refreshLlmProfiles()
    }

    var elapsedMs: Int64 {
        guard isRecording, let recordingStart else { return durationMs }
        return Int64(Date().timeIntervalSince(recordingStart) * 1000)
    }

    func refreshLlmProfiles() {
        let profiles = AppSettings.llmProfiles
        let activeId = AppSettings.activeLlmProfileId
        if profiles.contains(where: { $0.id == selectedLlmProfileId }) {
            // keep current selection
        } else {
            selectedLlmProfileId = activeId
        }
        llmProfiles = profiles
    }

    func selectLlmProfile(_ id: String) {
        guard llmProfiles.contains(where: { $0.id == id }) else { return }
        selectedLlmProfileId = id
    }

    // MARK: - Recording

    func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    func startRecording() {
        Task {
            let granted = await AudioRecorder.requestPermission()
            guard granted else {
                error = "需要麦克风权限才能录音，请在系统设置中授权。"
                return
            }
            let url = Paths.newRecordingFile()
            do {
                try recorder.start(url: url)
            } catch {
                self.error = error.localizedDescription
                return
            }
            waveform = []
            durationMs = 0
            transcript = nil
            entryId = nil
            awaitingAsrPrompt = false
            error = nil
            statusMessage = ""
            isRecording = true
            audioPath = url.path
            recordingStart = Date()
            startTicker()
        }
    }

    func stopRecording() {
        guard isRecording else { return }
        let duration = recorder.stop()
        isRecording = false
        recordingStart = nil
        stopTicker()
        let path = audioPath ?? ""
        Task { await finalizeAudio(path: path, durationMs: duration) }
    }

    func onRecordingFailed(_ message: String) {
        isRecording = false
        recordingStart = nil
        stopTicker()
        audioPath = nil
        error = message
    }

    // MARK: - Import

    func importAudio(from url: URL) {
        isProcessing = true
        statusMessage = "正在导入录音…"
        error = nil
        transcript = nil
        entryId = nil
        awaitingAsrPrompt = false
        Task {
            let destination = Paths.newRecordingFile()
            do {
                let duration = try await Task.detached(priority: .userInitiated) {
                    try AudioImporter.importToWav(source: url, destination: destination)
                }.value
                await finalizeAudio(path: destination.path, durationMs: duration)
            } catch {
                isProcessing = false
                statusMessage = ""
                self.error = error.localizedDescription
            }
        }
    }

    private func finalizeAudio(path: String, durationMs: Int64) async {
        do {
            let entry = try await services.store.createDraft(audioPath: path, durationMs: durationMs)
            audioPath = path
            self.durationMs = durationMs
            entryId = entry.id
            awaitingAsrPrompt = true
            isProcessing = false
            statusMessage = ""
        } catch {
            isProcessing = false
            statusMessage = ""
            self.error = error.localizedDescription
        }
    }

    func dismissAsrPrompt() {
        awaitingAsrPrompt = false
    }

    // MARK: - ASR

    func startTranscription() {
        guard let path = audioPath, let entryId else { return }
        awaitingAsrPrompt = false
        isProcessing = true
        asrProgress = 0
        asrElapsedMs = 0
        statusMessage = AsrProgressMessages.format(.loadingModel, 0)
        error = nil
        startProcessingTimer(llm: false)
        let modelId = AppSettings.selectedAsrModel

        Task {
            do {
                let text = try await services.whisper.transcribe(modelId: modelId, wavURL: URL(fileURLWithPath: path)) { [weak self] progress, phase in
                    Task { @MainActor in
                        self?.asrProgress = progress
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
            } catch {
                isProcessing = false
                asrProgress = nil
                asrElapsedMs = 0
                stopProcessingTimer()
                statusMessage = ""
                self.error = error.localizedDescription
            }
        }
    }

    func updateTranscript(_ text: String) {
        transcript = text
    }

    // MARK: - Save

    func saveDirect(onSaved: @escaping (Int64) -> Void) {
        guard let transcript, let entryId else { return }
        Task {
            try? await services.store.saveTranscript(id: entryId, transcript: transcript)
            try? await services.store.saveDiaryText(id: entryId, diaryText: transcript)
            onSaved(entryId)
            reset()
        }
    }

    func saveWithLlm(onSaved: @escaping (Int64) -> Void) {
        guard let transcript, let entryId else { return }
        beginLlmProcessing()
        let config = AppSettings.llmConfig(profileId: selectedLlmProfileId)
        Task {
            do {
                let diary = try await services.llm.polishTranscript(config: config, transcript: transcript) { [weak self] progress, phase in
                    Task { @MainActor in self?.updateLlmProgress(progress: progress, phase: phase) }
                }
                stopProcessingTimer()
                endLlmProcessing()
                try await services.store.saveTranscript(id: entryId, transcript: transcript)
                try await services.store.saveDiaryText(id: entryId, diaryText: diary)
                onSaved(entryId)
                reset()
            } catch {
                endLlmProcessing()
                isProcessing = false
                statusMessage = ""
                toast = error.localizedDescription
            }
        }
    }

    func reset() {
        stopTicker()
        stopProcessingTimer()
        recorder.cancel()
        isRecording = false
        isProcessing = false
        audioPath = nil
        durationMs = 0
        transcript = nil
        entryId = nil
        awaitingAsrPrompt = false
        waveform = []
        statusMessage = ""
        asrProgress = nil
        asrElapsedMs = 0
        llmProgress = nil
        llmElapsedMs = 0
        error = nil
        refreshLlmProfiles()
    }

    // MARK: - LLM progress

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

    // MARK: - Timers

    private func startTicker() {
        ticker?.invalidate()
        ticker = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isRecording else { return }
                self.waveform = self.recorder.amplitudes
            }
        }
    }

    private func stopTicker() {
        ticker?.invalidate()
        ticker = nil
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
        if !isRecording {
            ticker?.invalidate()
            ticker = nil
        }
    }
}
