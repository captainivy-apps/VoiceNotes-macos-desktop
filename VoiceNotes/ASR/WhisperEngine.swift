import Foundation
import whisper

enum WhisperError: Error, LocalizedError {
    case modelMissing
    case couldNotInitializeContext
    case emptyAudio
    case transcriptionFailed

    var errorDescription: String? {
        switch self {
        case .modelMissing: return "模型未下载，请先在设置页下载"
        case .couldNotInitializeContext: return "无法加载 ASR 模型"
        case .emptyAudio: return "录音文件为空"
        case .transcriptionFailed: return "识别失败"
        }
    }
}

private final class ProgressBox: @unchecked Sendable {
    let handler: @Sendable (Int) -> Void
    var lastReported = -10

    init(handler: @escaping @Sendable (Int) -> Void) {
        self.handler = handler
    }
}

private func whisperProgressCallback(
    _ ctx: OpaquePointer?,
    _ state: OpaquePointer?,
    _ progress: Int32,
    _ userData: UnsafeMutableRawPointer?
) {
    guard let userData else { return }
    let box = Unmanaged<ProgressBox>.fromOpaque(userData).takeUnretainedValue()
    if progress < box.lastReported + 2 && progress < 100 { return }
    box.lastReported = Int(progress)
    box.handler(Int(progress))
}

/// Runs `body` with a C string pointer for `string`, or `nil` when absent.
private func withCStringOptional<T>(
    _ string: String?,
    _ body: (UnsafePointer<CChar>?) throws -> T
) rethrows -> T {
    guard let string else { return try body(nil) }
    return try string.withCString { try body($0) }
}

/// Physical (non-hyperthreaded) core count, used to avoid oversubscribing
/// ggml's CPU thread pool on Intel Macs.
private func physicalCoreCount() -> Int {
    var count: Int32 = 0
    var size = MemoryLayout<Int32>.size
    if sysctlbyname("hw.physicalcpu", &count, &size, nil, 0) == 0, count > 0 {
        return Int(count)
    }
    return 0
}

/// Wraps a whisper.cpp context. Actor isolation satisfies whisper's
/// single-thread constraint.
actor WhisperContext {
    private var context: OpaquePointer

    init(context: OpaquePointer) {
        self.context = context
    }

    deinit {
        whisper_free(context)
    }

    func transcribe(
        samples: [Float],
        language: String,
        initialPrompt: String?,
        vadModelPath: String?,
        onProgress: (@Sendable (Int) -> Void)?
    ) throws -> String {
        var params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)
        params.print_realtime = false
        params.print_progress = false
        params.print_timestamps = false
        params.print_special = false
        params.translate = false
        params.n_threads = Int32(Self.preferredThreadCount)
        params.offset_ms = 0
        // Keep decodes independent (whisper.cpp default). Conditioning on the
        // previous transcript lets a single bad segment seed the next one, so a
        // repetition loop can propagate and compound across a whole recording.
        params.no_context = true
        params.single_segment = false
        params.carry_initial_prompt = false
        // Restore the default (5) parallel decoders. At temperature 0 greedy
        // decoding always uses a single decoder regardless of `best_of`, so this
        // costs nothing in the common case; it only widens the candidate pool
        // during temperature fallback, where quality matters.
        params.greedy.best_of = 5
        // Keep the default temperature fallback (0.2). The entropy check flags
        // repetitive low-entropy output as failed, but the decoder is only
        // retried at a higher temperature when more temperatures are available.
        // Disabling this (temperature_inc = 0) emits repetition loops verbatim.
        params.temperature_inc = 0.2
        // Suppress non-speech tokens, a known source of hallucinated text.
        params.suppress_nst = true

        let box = ProgressBox(handler: onProgress ?? { _ in })
        params.progress_callback = whisperProgressCallback
        params.progress_callback_user_data = Unmanaged.passUnretained(box).toOpaque()

        func runFull() throws -> String {
            whisper_reset_timings(context)
            let result = samples.withUnsafeBufferPointer { buffer in
                whisper_full(context, params, buffer.baseAddress, Int32(samples.count))
            }
            guard result == 0 else { throw WhisperError.transcriptionFailed }
            var text = ""
            let count = whisper_full_n_segments(context)
            for index in 0..<count {
                if let segment = whisper_full_get_segment_text(context, index) {
                    text += String(cString: segment)
                }
            }
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let isChinese = language.hasPrefix("zh")
        let prompt = isChinese ? initialPrompt : nil

        return try withCStringOptional(prompt) { promptPtr in
            params.initial_prompt = promptPtr
            params.carry_initial_prompt = promptPtr != nil
            return try withCStringOptional(vadModelPath) { vadPtr in
                params.vad = vadPtr != nil
                params.vad_model_path = vadPtr
                if vadPtr != nil {
                    params.vad_params = whisper_vad_default_params()
                }
                return try language.withCString { lang in
                    params.language = lang
                    return try runFull()
                }
            }
        }
    }

    static var preferredThreadCount: Int {
        let physical = physicalCoreCount()
        let cores = physical > 0 ? physical : ProcessInfo.processInfo.processorCount
        return max(1, min(8, cores))
    }
}

/// Loads and caches whisper models, and splits long audio into overlapping
/// ~5 minute windows like the Android implementation.
actor WhisperEngine {
    private var context: WhisperContext?
    private var loadedModelId: String?
    private let downloader: ModelDownloader

    private static let segmentSamples = WavFile.sampleRate * 300
    private static let overlapSamples = WavFile.sampleRate

    /// Bundled Silero VAD model (also honored if dropped into the models dir).
    /// Used to skip silence before decoding, which speeds up pause-heavy notes.
    private static var vadModelPath: String? {
        if let url = Bundle.main.url(forResource: "ggml-silero-v5.1.2", withExtension: "bin"),
           FileManager.default.fileExists(atPath: url.path) {
            return url.path
        }
        let local = Paths.modelsDir.appendingPathComponent("ggml-silero-v5.1.2.bin")
        if FileManager.default.fileExists(atPath: local.path) {
            return local.path
        }
        return nil
    }

    init(downloader: ModelDownloader) {
        self.downloader = downloader
    }

    func transcribe(
        modelId: String,
        wavURL: URL,
        language: String = AsrLanguages.autoId,
        onProgress: (@Sendable (Float, AsrPhase) -> Void)? = nil
    ) async throws -> String {
        guard let model = AsrModels.find(modelId) else {
            throw NSError(domain: "VoiceNotes.ASR", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "未知模型: \(modelId)"])
        }
        guard downloader.isDownloaded(model) else { throw WhisperError.modelMissing }
        let modelPath = downloader.modelFile(model).path

        if loadedModelId != modelId || context == nil {
            onProgress?(0, .loadingModel)
            context = nil
            let newContext = try WhisperContext.create(modelPath: modelPath)
            context = newContext
            loadedModelId = modelId
            onProgress?(0.10, .loadingModel)
        } else {
            onProgress?(0.10, .loadingModel)
        }

        onProgress?(0.10, .readingAudio)
        let info = try WavFile.readInfo(url: wavURL)
        guard info.sampleCount > 0 else { throw WhisperError.emptyAudio }
        onProgress?(0.15, .readingAudio)

        guard let engine = context else { throw WhisperError.couldNotInitializeContext }

        if info.sampleCount <= Self.segmentSamples {
            let audio = try WavFile.readFloatRange(url: wavURL, startSample: 0, count: info.sampleCount, info: info)
            let progress: @Sendable (Int) -> Void = { percent in
                onProgress?(0.15 + Float(percent) / 100 * 0.85, .transcribing)
            }
            let raw = try await engine.transcribe(samples: audio, language: language, initialPrompt: Self.initialPrompt(for: language), vadModelPath: Self.vadModelPath, onProgress: progress)
            return RepetitionFilter.removeRepetition(raw)
        }

        let step = Self.segmentSamples - Self.overlapSamples
        var segmentStarts: [Int] = []
        var start = 0
        while start < info.sampleCount {
            segmentStarts.append(start)
            if start + Self.segmentSamples >= info.sampleCount { break }
            start += step
        }
        let segmentCount = segmentStarts.count
        var parts: [String] = []
        for (index, segmentStart) in segmentStarts.enumerated() {
            let segmentEnd = min(segmentStart + Self.segmentSamples, info.sampleCount)
            let audio = try WavFile.readFloatRange(url: wavURL, startSample: segmentStart, count: segmentEnd - segmentStart, info: info)
            let progress: @Sendable (Int) -> Void = { percent in
                let segmentProgress = (Float(index) + Float(percent) / 100) / Float(segmentCount)
                onProgress?(0.15 + segmentProgress * 0.85, .transcribing)
            }
            let raw = try await engine.transcribe(samples: audio, language: language, initialPrompt: Self.initialPrompt(for: language), vadModelPath: Self.vadModelPath, onProgress: progress)
            let text = RepetitionFilter.removeRepetition(raw)
            if !text.isEmpty { parts.append(text) }
            onProgress?(0.15 + Float(index + 1) / Float(segmentCount) * 0.85, .transcribing)
        }
        let joined = parts.joined(separator: "\n")
        return RepetitionFilter.removeRepetition(joined).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func release() {
        context = nil
        loadedModelId = nil
    }

    private static func initialPrompt(for language: String) -> String? {
        language.hasPrefix("zh") ? "以下是普通话句子，请使用中文标点符号。" : nil
    }
}

extension WhisperContext {
    static func create(modelPath: String) throws -> WhisperContext {
        var params = whisper_context_default_params()
        #if arch(arm64)
        // Apple Silicon: Metal + flash attention is correct and much faster.
        params.use_gpu = true
        params.flash_attn = true
        #else
        // Intel Macs: the Metal backend can produce incorrect transcriptions,
        // so fall back to CPU (Accelerate/BLAS).
        params.use_gpu = false
        params.flash_attn = false
        #endif
        guard let context = whisper_init_from_file_with_params(modelPath, params) else {
            throw WhisperError.couldNotInitializeContext
        }
        return WhisperContext(context: context)
    }
}
