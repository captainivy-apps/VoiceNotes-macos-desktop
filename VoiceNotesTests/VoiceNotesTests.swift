import XCTest
@testable import VoiceNotes

final class WavFileTests: XCTestCase {
    private func makeWav(samples: [Int16]) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-\(UUID().uuidString).wav")
        FileManager.default.createFile(atPath: url.path, contents: nil)
        let handle = try FileHandle(forWritingTo: url)
        try WavFile.writeHeader(handle: handle, pcmBytes: 0)
        try handle.seekToEnd()
        var data = Data()
        for sample in samples {
            var value = sample.littleEndian
            withUnsafeBytes(of: &value) { data.append(contentsOf: $0) }
        }
        try handle.write(contentsOf: data)
        try WavFile.writeHeader(handle: handle, pcmBytes: UInt64(data.count))
        try handle.close()
        return url
    }

    func testReadInfoAndSamples() throws {
        let samples: [Int16] = [0, 16384, -16384, 32767, -32768]
        let url = try makeWav(samples: samples)
        defer { try? FileManager.default.removeItem(at: url) }

        let info = try WavFile.readInfo(url: url)
        XCTAssertEqual(info.sampleCount, samples.count)

        let floats = try WavFile.readFloatRange(url: url, startSample: 0, count: samples.count, info: info)
        XCTAssertEqual(floats.count, samples.count)
        XCTAssertEqual(floats[0], 0, accuracy: 0.0001)
        XCTAssertEqual(floats[1], 0.5, accuracy: 0.001)
        XCTAssertEqual(floats[2], -0.5, accuracy: 0.001)
        XCTAssertGreaterThan(floats[3], 0.99)
    }

    func testWaveformPeaks() throws {
        let oneSecond = [Int16](repeating: 16000, count: WavFile.sampleRate)
        let url = try makeWav(samples: oneSecond)
        defer { try? FileManager.default.removeItem(at: url) }

        let result = try WavFile.readWaveformPeaks(url: url, windowMs: WaveformMath.windowMs, barsPerWindow: WaveformMath.barsPerWindow)
        XCTAssertGreaterThan(result.peaks.count, 0)
        if let peak = result.peaks.max() {
            XCTAssertEqual(peak, 16000.0 / 32768.0, accuracy: 0.001)
        }
        XCTAssertEqual(result.durationMs, 1000)
    }
}

final class ZipUtilTests: XCTestCase {
    func testSHA256() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("hash-\(UUID().uuidString).txt")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("hello".utf8).write(to: url)
        let expected = "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824"
        XCTAssertEqual(try ZipUtil.sha256(ofFile: url), expected)
    }

    func testUnzipPreservesBundleLayout() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("zip-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let bundle = root.appendingPathComponent("ggml-base-encoder.mlmodelc", isDirectory: true)
        try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
        try Data("mil".utf8).write(to: bundle.appendingPathComponent("model.mil"))

        let archive = root.appendingPathComponent("encoder.zip")
        let zip = Process()
        zip.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        zip.arguments = ["-c", "-k", "--keepParent", bundle.path, archive.path]
        try zip.run()
        zip.waitUntilExit()
        XCTAssertEqual(zip.terminationStatus, 0)
        try FileManager.default.removeItem(at: bundle)

        let out = root.appendingPathComponent("out", isDirectory: true)
        try ZipUtil.unzip(archive: archive, to: out)
        let restored = out.appendingPathComponent("ggml-base-encoder.mlmodelc/model.mil")
        XCTAssertTrue(FileManager.default.fileExists(atPath: restored.path))
    }
}

final class ExportFileNamesTests: XCTestCase {
    func testNameShape() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let name = ExportFileNames.build(type: ExportFileNames.typeRecord, extension: "wav", timestamp: date)
        XCTAssertTrue(name.hasPrefix("voicenotes-record-"))
        XCTAssertTrue(name.hasSuffix(".wav"))
    }
}

final class RepetitionFilterTests: XCTestCase {
    func testCollapsesReportedLoop() {
        let loop = String(repeating: "to operate on the defense ", count: 60)
        let text = "and yet you were one of the first AI companies. " + loop
        let cleaned = RepetitionFilter.removeRepetition(text)
        XCTAssertEqual(cleaned, "and yet you were one of the first AI companies. to operate on the defense")
    }

    func testKeepsLegitimateEmphasis() {
        XCTAssertEqual(RepetitionFilter.removeRepetition("no no no"), "no no no")
        XCTAssertEqual(RepetitionFilter.removeRepetition("very very good"), "very very good")
    }

    func testKeepsDoublePhrase() {
        let text = "to sign a contract to sign a contract with the defense"
        XCTAssertEqual(RepetitionFilter.removeRepetition(text), text)
    }

    func testLeavesNormalTextUnchanged() {
        let text = "The quick brown fox jumps over the lazy dog."
        XCTAssertEqual(RepetitionFilter.removeRepetition(text), text)
    }

    func testPreservesKeptSpacingAndNewlines() {
        let text = "line one\nline two"
        XCTAssertEqual(RepetitionFilter.removeRepetition(text), text)
    }
}

final class DiaryStoreTests: XCTestCase {
    func testCRUDAndNeighbors() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("store-\(UUID().uuidString).db")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = try DiaryStore(databaseURL: url)

        let first = try await store.createDraft(audioPath: "/tmp/a.wav", durationMs: 1000)
        let second = try await store.createDraft(audioPath: "/tmp/b.wav", durationMs: 2000)

        try await store.saveTranscript(id: first.id, transcript: "识别稿")
        try await store.saveDiaryText(id: first.id, diaryText: "润色稿")

        let loaded = try await store.get(first.id)
        XCTAssertEqual(loaded?.transcriptText, "识别稿")
        XCTAssertEqual(loaded?.diaryText, "润色稿")

        let neighbors = try await store.neighborIds(currentId: second.id)
        XCTAssertEqual(neighbors.prev, first.id)
        XCTAssertNil(neighbors.next)

        let all = try await store.allOrdered()
        XCTAssertEqual(all.count, 2)

        try await store.deleteEntry(id: second.id)
        let remaining = try await store.allOrdered()
        XCTAssertEqual(remaining.count, 1)
        XCTAssertEqual(remaining.first?.id, first.id)
    }
}
