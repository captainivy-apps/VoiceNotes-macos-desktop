import AVFoundation
import CoreMedia
import Foundation

/// Records microphone input to a 16 kHz mono 16-bit PCM WAV file and exposes
/// a rolling window of normalized amplitudes for the waveform view.
///
/// Uses `AVCaptureSession`, which (unlike `AVAudioEngine`) can bind to an
/// arbitrary input device, including input-only microphones.
final class AudioRecorder: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate {
    /// `AVCaptureDevice.uniqueID` of the device to record from; nil or empty uses the system default.
    var inputDeviceUID: String?

    /// Voice-activated recording configuration. Snapshot on `start(url:)`.
    var voiceActivationEnabled = false
    var silencePauseSeconds: TimeInterval = 5
    var silenceStopSeconds: TimeInterval = 20
    /// RMS threshold (0...1) above which a buffer is considered audible.
    var silenceThreshold: Float = 0.01

    /// Called on the main queue when voice activation pauses / resumes / stops.
    var onAutoPause: (() -> Void)?
    var onAutoResume: (() -> Void)?
    var onAutoStop: (() -> Void)?

    private let session = AVCaptureSession()
    private let audioOutput = AVCaptureAudioDataOutput()
    /// Serial queue for all capture callbacks and file/state mutation.
    private let stateQueue = DispatchQueue(label: "com.dafei.voicenotes.recorder.state")

    private let targetFormat = AVAudioFormat(
        commonFormat: .pcmFormatInt16,
        sampleRate: Double(WavFile.sampleRate),
        channels: 1,
        interleaved: true
    )!

    // State accessed only on `stateQueue`.
    private var fileHandle: FileHandle?
    private var converter: AVAudioConverter?
    private var converterInputFormat: AVAudioFormat?
    private var totalPcmBytes: UInt64 = 0
    private var displayGain: Float = 0.08

    // Voice activity state, accessed only on `stateQueue`.
    private var voiceGate: VoiceActivityGate?
    private var autoStopFired = false
    private var voicePaused = false

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

    /// Duration of audio actually written to disk (excludes paused silence).
    var recordedDurationMs: Int64 {
        stateQueue.sync {
            Int64(totalPcmBytes) * 1000 / Int64(WavFile.sampleRate * 2)
        }
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

        stateQueue.sync {
            fileHandle = handle
            totalPcmBytes = 0
            converter = nil
            converterInputFormat = nil
            lastError = nil
            displayGain = 0.08
            autoStopFired = false
            voicePaused = false
            if voiceActivationEnabled {
                voiceGate = VoiceActivityGate(
                    pauseAfter: silencePauseSeconds,
                    stopAfter: silenceStopSeconds,
                    threshold: silenceThreshold,
                    start: Date()
                )
            } else {
                voiceGate = nil
            }
            amplitudeLock.lock()
            amplitudeHistory.removeAll()
            amplitudeLock.unlock()
        }

        let device = resolveDevice()
        guard let device else {
            try? handle.close()
            stateQueue.sync { fileHandle = nil }
            throw NSError(domain: "VoiceNotes.Audio", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "未检测到可用的音频输入设备"])
        }

        let deviceInput: AVCaptureDeviceInput
        do {
            deviceInput = try AVCaptureDeviceInput(device: device)
        } catch {
            try? handle.close()
            stateQueue.sync { fileHandle = nil }
            throw NSError(domain: "VoiceNotes.Audio", code: -2,
                          userInfo: [NSLocalizedDescriptionKey: "无法使用所选录音设备：\(error.localizedDescription)"])
        }

        session.beginConfiguration()
        session.inputs.forEach { session.removeInput($0) }
        session.outputs.forEach { session.removeOutput($0) }
        guard session.canAddInput(deviceInput) else {
            session.commitConfiguration()
            try? handle.close()
            stateQueue.sync { fileHandle = nil }
            throw NSError(domain: "VoiceNotes.Audio", code: -3,
                          userInfo: [NSLocalizedDescriptionKey: "无法添加录音设备"])
        }
        session.addInput(deviceInput)
        guard session.canAddOutput(audioOutput) else {
            session.commitConfiguration()
            try? handle.close()
            stateQueue.sync { fileHandle = nil }
            throw NSError(domain: "VoiceNotes.Audio", code: -4,
                          userInfo: [NSLocalizedDescriptionKey: "无法初始化录音输出"])
        }
        session.addOutput(audioOutput)
        audioOutput.setSampleBufferDelegate(self, queue: stateQueue)
        session.commitConfiguration()

        session.startRunning()
        guard session.isRunning else {
            audioOutput.setSampleBufferDelegate(nil, queue: nil)
            try? handle.close()
            stateQueue.sync { fileHandle = nil }
            throw NSError(domain: "VoiceNotes.Audio", code: -5,
                          userInfo: [NSLocalizedDescriptionKey: "无法启动录音"])
        }

        stateQueue.sync {
            isRecording = true
            startedAt = Date()
        }
    }

    @discardableResult
    func stop() -> Int64 {
        var duration: Int64 = 0
        stateQueue.sync {
            guard isRecording else { return }
            isRecording = false
            voiceGate = nil
            voicePaused = false
            duration = finalizeFileLocked()
        }
        session.stopRunning()
        audioOutput.setSampleBufferDelegate(nil, queue: nil)
        return duration
    }

    func cancel() {
        session.stopRunning()
        audioOutput.setSampleBufferDelegate(nil, queue: nil)
        stateQueue.sync {
            isRecording = false
            voiceGate = nil
            voicePaused = false
            _ = finalizeFileLocked()
        }
    }

    // MARK: - Capture

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard isRecording,
              !autoStopFired,
              let input = Self.makeMonoBuffer(from: sampleBuffer) else { return }

        if var gate = voiceGate {
            let transition = gate.consume(level: Self.rmsLevel(input), at: Date())
            voiceGate = gate
            switch transition {
            case .paused:
                voicePaused = true
                let callback = onAutoPause
                DispatchQueue.main.async { callback?() }
            case .resumed:
                voicePaused = false
                let callback = onAutoResume
                DispatchQueue.main.async { callback?() }
            case .stopped:
                voicePaused = true
                autoStopFired = true
                let callback = onAutoStop
                DispatchQueue.main.async { callback?() }
            case .none:
                break
            }
            if voicePaused {
                appendSilentAmplitude()
                return
            }
        }

        write(input)
    }

    /// Converts an already-downmixed mono buffer to the 16 kHz mono Int16 target.
    private func write(_ input: AVAudioPCMBuffer) {
        guard let handle = fileHandle else { return }

        if converter == nil || converterInputFormat != input.format {
            converter = AVAudioConverter(from: input.format, to: targetFormat)
            converterInputFormat = input.format
        }
        guard let converter else {
            lastError = "无法创建音频转换器"
            return
        }

        let ratio = targetFormat.sampleRate / input.format.sampleRate
        let capacity = AVAudioFrameCount(Double(input.frameLength) * ratio) + 1024
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
            return input
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

    // MARK: - Helpers

    /// Appends a zero amplitude so the waveform renders flat while paused.
    private func appendSilentAmplitude() {
        amplitudeLock.lock()
        amplitudeHistory.append(0)
        while amplitudeHistory.count > maxAmplitudeHistory {
            amplitudeHistory.removeFirst()
        }
        amplitudeLock.unlock()
    }

    /// Root-mean-square level of a mono Float32 buffer, normalized to 0...1.
    private static func rmsLevel(_ buffer: AVAudioPCMBuffer) -> Float {
        guard let channel = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return 0 }
        let count = Int(buffer.frameLength)
        var sum: Float = 0
        for i in 0..<count {
            let sample = channel[i]
            sum += sample * sample
        }
        return (sum / Float(count)).squareRoot()
    }

    private func resolveDevice() -> AVCaptureDevice? {
        if let uid = inputDeviceUID, !uid.isEmpty,
           let device = AudioInputDevices.captureDevice(forUID: uid) {
            return device
        }
        return AudioInputDevices.defaultDevice()
    }

    /// Called on `stateQueue` only.
    private func finalizeFileLocked() -> Int64 {
        if let handle = fileHandle {
            try? WavFile.writeHeader(handle: handle, pcmBytes: totalPcmBytes)
            try? handle.synchronize()
            try? handle.close()
        }
        fileHandle = nil
        converter = nil
        converterInputFormat = nil
        startedAt = nil
        return Int64(totalPcmBytes) * 1000 / Int64(WavFile.sampleRate * 2)
    }

    /// Builds a mono Float32 buffer at the source sample rate by averaging the
    /// first two channels of the captured sample buffer. Working directly on the
    /// audio buffers avoids `AVAudioFormat(streamDescription:)`, which rejects
    /// high channel counts such as BlackHole 64ch.
    private static func makeMonoBuffer(from sampleBuffer: CMSampleBuffer) -> AVAudioPCMBuffer? {
        guard let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer),
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription) else {
            return nil
        }
        let frames = CMSampleBufferGetNumSamples(sampleBuffer)
        let channelCount = Int(asbd.pointee.mChannelsPerFrame)
        let sampleRate = asbd.pointee.mSampleRate
        guard frames > 0, channelCount > 0, sampleRate > 0 else { return nil }

        let listSize = MemoryLayout<AudioBufferList>.size
            + (channelCount - 1) * MemoryLayout<AudioBuffer>.size
        let raw = UnsafeMutableRawPointer.allocate(
            byteCount: listSize, alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { raw.deallocate() }
        let sourceList = raw.assumingMemoryBound(to: AudioBufferList.self)

        var retainedBlockBuffer: CMBlockBuffer?
        let status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: nil,
            bufferListOut: sourceList,
            bufferListSize: listSize,
            blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil,
            flags: kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment,
            blockBufferOut: &retainedBlockBuffer
        )
        guard status == noErr else { return nil }
        let source = UnsafeMutableAudioBufferListPointer(sourceList)

        guard let monoFormat = AVAudioFormat(
                  commonFormat: .pcmFormatFloat32,
                  sampleRate: sampleRate,
                  channels: 1,
                  interleaved: false
              ),
              let mono = AVAudioPCMBuffer(pcmFormat: monoFormat, frameCapacity: AVAudioFrameCount(frames)),
              let destination = mono.floatChannelData?[0] else {
            return nil
        }
        mono.frameLength = AVAudioFrameCount(frames)

        let mixCount = min(2, channelCount)
        let scale = 1 / Float(mixCount)
        let isFloat = (asbd.pointee.mFormatFlags & kAudioFormatFlagIsFloat) != 0
        let isNonInterleaved = (asbd.pointee.mFormatFlags & kAudioFormatFlagIsNonInterleaved) != 0
        let bitsPerChannel = Int(asbd.pointee.mBitsPerChannel)

        for frame in 0..<frames {
            var sum: Float = 0
            for channel in 0..<mixCount {
                let bufferIndex = isNonInterleaved ? channel : 0
                guard bufferIndex < source.count, let data = source[bufferIndex].mData else { continue }
                let index = isNonInterleaved ? frame : frame * channelCount + channel
                if isFloat {
                    if bitsPerChannel == 32 {
                        sum += data.assumingMemoryBound(to: Float.self)[index]
                    } else if bitsPerChannel == 64 {
                        sum += Float(data.assumingMemoryBound(to: Double.self)[index])
                    }
                } else if bitsPerChannel == 16 {
                    sum += Float(data.assumingMemoryBound(to: Int16.self)[index]) / 32768.0
                } else if bitsPerChannel == 32 {
                    sum += Float(data.assumingMemoryBound(to: Int32.self)[index]) / 2_147_483_648.0
                }
            }
            destination[frame] = sum * scale
        }
        return mono
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
