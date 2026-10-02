import AVFoundation
import Foundation

/// Decodes an arbitrary audio file (wav/mp3/m4a/…) into a 16 kHz mono
/// 16-bit PCM WAV file.
enum AudioImporter {
    private static let targetFormat = AVAudioFormat(
        commonFormat: .pcmFormatInt16,
        sampleRate: Double(WavFile.sampleRate),
        channels: 1,
        interleaved: true
    )!

    @discardableResult
    static func importToWav(source: URL, destination: URL) throws -> Int64 {
        let inputFile: AVAudioFile
        do {
            inputFile = try AVAudioFile(forReading: source)
        } catch {
            throw NSError(domain: "VoiceNotes.Import", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "无法读取音频文件：\(error.localizedDescription)"])
        }

        let sourceFormat = inputFile.processingFormat
        guard sourceFormat.sampleRate > 0, sourceFormat.channelCount > 0 else {
            throw NSError(domain: "VoiceNotes.Import", code: -2,
                          userInfo: [NSLocalizedDescriptionKey: "不支持的音频格式"])
        }
        guard let converter = AVAudioConverter(from: sourceFormat, to: targetFormat) else {
            throw NSError(domain: "VoiceNotes.Import", code: -3,
                          userInfo: [NSLocalizedDescriptionKey: "无法创建音频转换器"])
        }

        FileManager.default.createFile(atPath: destination.path, contents: nil)
        let handle = try FileHandle(forWritingTo: destination)
        try WavFile.writeHeader(handle: handle, pcmBytes: 0)
        try handle.seekToEnd()

        var totalPcmBytes: UInt64 = 0
        let chunkFrames: AVAudioFrameCount = 8192
        let readBuffer = AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: chunkFrames)!

        while inputFile.framePosition < inputFile.length {
            let remaining = AVAudioFrameCount(inputFile.length - inputFile.framePosition)
            let toRead = min(chunkFrames, remaining)
            readBuffer.frameLength = 0
            try inputFile.read(into: readBuffer, frameCount: toRead)
            if readBuffer.frameLength == 0 { break }

            let ratio = targetFormat.sampleRate / sourceFormat.sampleRate
            let capacity = AVAudioFrameCount(Double(readBuffer.frameLength) * ratio) + 1024
            guard let output = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else { break }

            var conversionError: NSError?
            var supplied = false
            let status = converter.convert(to: output, error: &conversionError) { _, outStatus in
                if supplied {
                    outStatus.pointee = .noDataNow
                    return nil
                }
                supplied = true
                outStatus.pointee = .haveData
                return readBuffer
            }
            if status == .error {
                try? handle.close()
                throw NSError(domain: "VoiceNotes.Import", code: -4,
                              userInfo: [NSLocalizedDescriptionKey: conversionError?.localizedDescription ?? "音频转换失败"])
            }
            guard output.frameLength > 0, let channel = output.int16ChannelData?[0] else { continue }
            let count = Int(output.frameLength)
            var pcm = Data(count: count * 2)
            pcm.withUnsafeMutableBytes { raw in
                let destination = raw.bindMemory(to: Int16.self)
                for i in 0..<count { destination[i] = channel[i] }
            }
            try handle.write(contentsOf: pcm)
            totalPcmBytes += UInt64(pcm.count)
        }

        guard totalPcmBytes > 0 else {
            try? handle.close()
            try? FileManager.default.removeItem(at: destination)
            throw NSError(domain: "VoiceNotes.Import", code: -5,
                          userInfo: [NSLocalizedDescriptionKey: "音频文件为空"])
        }
        try WavFile.writeHeader(handle: handle, pcmBytes: totalPcmBytes)
        try? handle.synchronize()
        try? handle.close()
        return Int64(totalPcmBytes) * 1000 / Int64(WavFile.sampleRate * 2)
    }
}
