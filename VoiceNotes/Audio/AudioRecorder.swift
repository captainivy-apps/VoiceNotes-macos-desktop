import AVFoundation
import Foundation

/// Records microphone input to a 16 kHz mono 16-bit PCM WAV file and exposes
/// a rolling window of normalized amplitudes for the waveform view.
final class AudioRecorder {
    private let engine = AVAudioEngine()
    private let targetFormat = AVAudioFormat(
        commonFormat: .pcmFormatInt16,
        sampleRate: Double(WavFile.sampleRate),
        channels: 1,
        interleaved: true
    )!

    private var fileHandle: FileHandle?
    private var converter: AVAudioConverter?
    private var totalPcmBytes: UInt64 = 0
    private var displayGain: Float = 0.08
    private let amplitudeLock = NSLock()
    private var amplitudeHistory: [Float] = []
    private let maxAmplitudeHistory = 120

    private(set) var isRecording = false
    private(set) var startedAt: Date?
    private(set) var lastError: String?

    var amplitudes: [Float] {
        amplitudeLock.lock()
        defer { amplitudeLock.unlock() }
        return amplitudeHistory
    }

    static func requestPermission() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .audio)
        default:
            return false
        }
    }

    func start(url: URL) throws {
        cancel()

        FileManager.default.createFile(atPath: url.path, contents: nil)
        let handle = try FileHandle(forWritingTo: url)
        try WavFile.writeHeader(handle: handle, pcmBytes: 0)
        try handle.seekToEnd()
        fileHandle = handle
        totalPcmBytes = 0
        lastError = nil
        displayGain = 0.08
        amplitudeLock.lock()
        amplitudeHistory.removeAll()
        amplitudeLock.unlock()

        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            try? handle.close()
            fileHandle = nil
            throw NSError(domain: "VoiceNotes.Audio", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "未检测到可用的音频输入设备"])
        }
        guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            try? handle.close()
            fileHandle = nil
            throw NSError(domain: "VoiceNotes.Audio", code: -2,
                          userInfo: [NSLocalizedDescriptionKey: "无法创建音频转换器"])
        }
        self.converter = converter

        input.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            self?.process(buffer)
        }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            try? handle.close()
            fileHandle = nil
            throw NSError(domain: "VoiceNotes.Audio", code: -3,
                          userInfo: [NSLocalizedDescriptionKey: "无法启动录音：\(error.localizedDescription)"])
        }
        isRecording = true
        startedAt = Date()
    }

    @discardableResult
    func stop() -> Int64 {
        guard isRecording else { return 0 }
        isRecording = false
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        if let handle = fileHandle {
            try? WavFile.writeHeader(handle: handle, pcmBytes: totalPcmBytes)
            try? handle.synchronize()
            try? handle.close()
        }
        fileHandle = nil
        converter = nil
        startedAt = nil
        return Int64(totalPcmBytes) * 1000 / Int64(WavFile.sampleRate * 2)
    }

    func cancel() {
        if isRecording {
            isRecording = false
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }
        if let handle = fileHandle {
            try? WavFile.writeHeader(handle: handle, pcmBytes: totalPcmBytes)
            try? handle.close()
        }
        fileHandle = nil
        converter = nil
        startedAt = nil
    }

    private func process(_ buffer: AVAudioPCMBuffer) {
        guard isRecording, let converter, let handle = fileHandle else { return }
        let ratio = targetFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1024
        guard let output = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else { return }

        var conversionError: NSError?
        var supplied = false
        let status = converter.convert(to: output, error: &conversionError) { _, outStatus in
            if supplied {
                outStatus.pointee = .noDataNow
                return nil
            }
            supplied = true
            outStatus.pointee = .haveData
            return buffer
        }
        if status == .error {
            lastError = conversionError?.localizedDescription ?? "音频转换失败"
            return
        }
        guard output.frameLength > 0, let channel = output.int16ChannelData?[0] else { return }

        let count = Int(output.frameLength)
        var pcm = Data(count: count * 2)
        var peak: Int = 0
        pcm.withUnsafeMutableBytes { raw in
            let destination = raw.bindMemory(to: Int16.self)
            for i in 0..<count {
                let sample = channel[i]
                destination[i] = sample
                let magnitude = abs(Int(sample))
                if magnitude > peak { peak = magnitude }
            }
        }
        do {
            try handle.write(contentsOf: pcm)
            totalPcmBytes += UInt64(pcm.count)
        } catch {
            lastError = error.localizedDescription
            return
        }

        let rawAmplitude = Float(peak) / 32768.0
        displayGain = max(rawAmplitude * 1.2, displayGain * 0.98)
        let normalized = (rawAmplitude / max(displayGain, 0.08)).clamped(to: 0...1)
        amplitudeLock.lock()
        amplitudeHistory.append(normalized)
        while amplitudeHistory.count > maxAmplitudeHistory {
            amplitudeHistory.removeFirst()
        }
        amplitudeLock.unlock()
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
