import Foundation
import CryptoKit

/// Small helpers for handling the Core ML encoder archives: SHA-256
/// verification and extraction via the system `ditto` tool (which preserves
/// bundle structure and resource forks).
enum ZipUtil {
    enum ZipError: Error, LocalizedError {
        case unzipFailed(String)
        case hashFailed

        var errorDescription: String? {
            switch self {
            case .unzipFailed(let message):
                return "解压失败：\(message)"
            case .hashFailed:
                return "无法读取文件校验值"
            }
        }
    }

    static func sha256(ofFile url: URL) throws -> String {
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            throw ZipError.hashFailed
        }
        defer { try? handle.close() }
        var hasher = SHA256()
        while autoreleasepool(invoking: {
            let data = (try? handle.read(upToCount: 1 << 20)) ?? nil
            if let data, !data.isEmpty {
                hasher.update(data: data)
                return true
            }
            return false
        }) {}
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    static func unzip(archive: URL, to destination: URL) throws {
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-x", "-k", archive.path, destination.path]
        let pipe = Pipe()
        process.standardError = pipe
        process.standardOutput = pipe
        do {
            try process.run()
        } catch {
            throw ZipError.unzipFailed(error.localizedDescription)
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let message = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            throw ZipError.unzipFailed(message.isEmpty ? "ditto 退出码 \(process.terminationStatus)" : message)
        }
    }
}
