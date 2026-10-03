import Foundation

/// Thin wrapper around the system Core ML compiler (`coremlc`) used to turn
/// a `.mlpackage` / `.mlmodel` into a compiled `.mlmodelc` bundle.
enum CoreMLCompiler {
    enum CompileError: Error, LocalizedError {
        case sourceMissing
        case compilerFailed(String)
        case outputMissing

        var errorDescription: String? {
            switch self {
            case .sourceMissing:
                return "未找到 Core ML 源文件，请重新选择"
            case .compilerFailed(let message):
                return "Core ML 编译失败：\(message)"
            case .outputMissing:
                return "Core ML 编译未生成结果"
            }
        }
    }

    /// Compiles `source` and returns the directory containing the produced
    /// `.mlmodelc` bundle.
    static func compile(source: URL, into outputDir: URL, derivedData: URL?) async throws -> URL {
        guard FileManager.default.fileExists(atPath: source.path) else {
            throw CompileError.sourceMissing
        }
        try? FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
        if let derivedData {
            try? FileManager.default.createDirectory(at: derivedData, withIntermediateDirectories: true)
        }

        return try await Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
            var arguments = ["coremlc", "compile", source.path, outputDir.path]
            if let derivedData {
                arguments.append(contentsOf: ["--output-partial-path", derivedData.path])
            }
            process.arguments = arguments

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe

            do {
                try process.run()
            } catch {
                throw CompileError.compilerFailed(error.localizedDescription)
            }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()

            guard process.terminationStatus == 0 else {
                let output = String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                throw CompileError.compilerFailed(output.isEmpty ? "coremlc 退出码 \(process.terminationStatus)" : output)
            }

            let name = source.deletingPathExtension().lastPathComponent + ".mlmodelc"
            let compiled = outputDir.appendingPathComponent(name, isDirectory: true)
            let fm = FileManager.default
            if !fm.fileExists(atPath: compiled.appendingPathComponent("model.mil").path) {
                throw CompileError.outputMissing
            }
            // Move aside so the caller can relocate it atomically; return a
            // unique copy under derivedData when provided.
            if let derivedData {
                let moved = derivedData.appendingPathComponent(name, isDirectory: true)
                try? fm.removeItem(at: moved)
                try fm.moveItem(at: compiled, to: moved)
                return moved
            }
            return outputDir
        }.value
    }
}
