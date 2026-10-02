import Foundation

/// 16 kHz mono 16-bit PCM WAV helpers, matching the Android implementation.
enum WavFile {
    static let sampleRate: Int = 16_000
    static let bytesPerSample: Int = 2
    static let formatLabel = "WAV · 16 kHz · 单声道 · PCM 16-bit"

    struct Info {
        let dataOffset: UInt64
        let sampleCount: Int

        var durationMs: Int64 {
            Int64(sampleCount) * 1000 / Int64(WavFile.sampleRate)
        }
    }

    static func readInfo(url: URL) throws -> Info {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let fileSize = try handle.seekToEnd()
        guard fileSize > 44 else { return Info(dataOffset: 44, sampleCount: 0) }
        let dataOffset = try findDataOffset(handle: handle, fileSize: fileSize)
        let pcmBytes = fileSize >= dataOffset ? fileSize - dataOffset : 0
        return Info(dataOffset: dataOffset, sampleCount: Int(pcmBytes / UInt64(bytesPerSample)))
    }

    static func readAsFloatArray(url: URL) throws -> [Float] {
        let info = try readInfo(url: url)
        return try readFloatRange(url: url, startSample: 0, count: info.sampleCount, info: info)
    }

    static func readFloatRange(url: URL, startSample: Int, count: Int, info: Info? = nil) throws -> [Float] {
        guard count > 0 else { return [] }
        let info = try info ?? readInfo(url: url)
        let maxSamples = info.sampleCount
        let start = min(max(0, startSample), maxSamples)
        let n = min(count, maxSamples - start)
        guard n > 0 else { return [] }

        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        try handle.seek(toOffset: info.dataOffset + UInt64(start * bytesPerSample))

        var samples = [Float](repeating: 0, count: n)
        var filled = 0
        let chunkSamples = 8192
        while filled < n {
            let toRead = min(chunkSamples, n - filled)
            guard let data = try handle.read(upToCount: toRead * bytesPerSample), !data.isEmpty else { break }
            data.withUnsafeBytes { raw in
                let bound = raw.bindMemory(to: Int16.self)
                for i in 0..<bound.count where filled < n {
                    samples[filled] = Float(Int16(littleEndian: bound[i])) / 32768.0
                    filled += 1
                }
            }
        }
        return filled == n ? samples : Array(samples.prefix(filled))
    }

    static func readWaveformPeaks(url: URL, windowMs: Int64, barsPerWindow: Int) throws -> (peaks: [Float], durationMs: Int64) {
        let info = try readInfo(url: url)
        let sampleCount = info.sampleCount
        guard sampleCount > 0 else { return ([], 0) }
        let durationMs = Int64(sampleCount) * 1000 / Int64(sampleRate)
        let totalBars = durationMs <= windowMs
            ? barsPerWindow
            : max(barsPerWindow, Int((Double(durationMs) / Double(windowMs) * Double(barsPerWindow))))

        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        try handle.seek(toOffset: info.dataOffset)

        if sampleCount <= totalBars {
            var peaks = [Float]()
            peaks.reserveCapacity(sampleCount)
            var remaining = sampleCount
            while remaining > 0 {
                guard let data = try handle.read(upToCount: min(8192, remaining) * bytesPerSample), !data.isEmpty else { break }
                data.withUnsafeBytes { raw in
                    let bound = raw.bindMemory(to: Int16.self)
                    for i in 0..<bound.count where remaining > 0 {
                        peaks.append(abs(Float(Int16(littleEndian: bound[i]))) / 32768.0)
                        remaining -= 1
                    }
                }
            }
            return (peaks, durationMs)
        }

        let blockSize = max(1, sampleCount / totalBars)
        var peaks = [Float](repeating: 0, count: totalBars)
        var sampleIndex = 0
        var barIndex = 0
        var blockPeak: Float = 0
        while sampleIndex < sampleCount && barIndex < totalBars {
            guard let data = try handle.read(upToCount: 8192 * bytesPerSample), !data.isEmpty else { break }
            data.withUnsafeBytes { raw in
                let bound = raw.bindMemory(to: Int16.self)
                var i = 0
                while i < bound.count && barIndex < totalBars {
                    let amplitude = abs(Float(Int16(littleEndian: bound[i]))) / 32768.0
                    if amplitude > blockPeak { blockPeak = amplitude }
                    sampleIndex += 1
                    i += 1
                    let barEnd = barIndex == totalBars - 1 ? sampleCount : (barIndex + 1) * blockSize
                    if sampleIndex >= barEnd {
                        peaks[barIndex] = blockPeak
                        barIndex += 1
                        blockPeak = 0
                    }
                }
            }
        }
        return (peaks, durationMs)
    }

    static func writeHeader(handle: FileHandle, pcmBytes: UInt64) throws {
        let totalDataLen = UInt32(truncatingIfNeeded: pcmBytes + 36)
        let byteRate = UInt32(sampleRate * bytesPerSample)
        var data = Data()
        data.append(contentsOf: Array("RIFF".utf8))
        data.append(littleEndian: totalDataLen)
        data.append(contentsOf: Array("WAVE".utf8))
        data.append(contentsOf: Array("fmt ".utf8))
        data.append(littleEndian: UInt32(16))
        data.append(littleEndian: UInt16(1))
        data.append(littleEndian: UInt16(1))
        data.append(littleEndian: UInt32(sampleRate))
        data.append(littleEndian: byteRate)
        data.append(littleEndian: UInt16(bytesPerSample))
        data.append(littleEndian: UInt16(16))
        data.append(contentsOf: Array("data".utf8))
        data.append(littleEndian: UInt32(truncatingIfNeeded: pcmBytes))
        try handle.seek(toOffset: 0)
        try handle.write(contentsOf: data)
    }

    private static func findDataOffset(handle: FileHandle, fileSize: UInt64) throws -> UInt64 {
        try handle.seek(toOffset: 0)
        guard let header = try handle.read(upToCount: 12), header.count >= 12 else { return 44 }
        var position: UInt64 = 12
        while position + 8 < fileSize {
            try handle.seek(toOffset: position)
            guard let chunkHeader = try handle.read(upToCount: 8), chunkHeader.count == 8 else { break }
            let chunkId = String(decoding: chunkHeader.prefix(4), as: UTF8.self)
            let chunkSize = chunkHeader.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 4, as: UInt32.self) }
            if chunkId == "data" { return position + 8 }
            position += 8 + UInt64(chunkSize)
        }
        return 44
    }
}

private extension Data {
    mutating func append(littleEndian value: UInt32) {
        var little = value.littleEndian
        Swift.withUnsafeBytes(of: &little) { append(contentsOf: $0) }
    }

    mutating func append(littleEndian value: UInt16) {
        var little = value.littleEndian
        Swift.withUnsafeBytes(of: &little) { append(contentsOf: $0) }
    }
}
