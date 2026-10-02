import AppKit
import UniformTypeIdentifiers

enum ExportError: LocalizedError {
    case cancelled
    case missingSource
    case emptyText
    case writeFailed(String)

    var errorDescription: String? {
        switch self {
        case .cancelled: return "已取消"
        case .missingSource: return "文件不存在"
        case .emptyText: return "内容为空"
        case .writeFailed(let m): return m
        }
    }
}

enum Exporter {
    /// Presents a save panel and writes text. Runs on the main actor (NSSavePanel requirement).
    @MainActor
    static func exportText(_ content: String, suggestedName: String) throws -> URL {
        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ExportError.emptyText
        }
        let destination = try chooseDestination(suggestedName: suggestedName, contentType: .plainText)
        try content.write(to: destination, atomically: true, encoding: .utf8)
        return destination
    }

    /// Presents a save panel and copies the audio file.
    @MainActor
    static func exportAudio(from sourceURL: URL, suggestedName: String) throws -> URL {
        guard FileManager.default.fileExists(atPath: sourceURL.path) else {
            throw ExportError.missingSource
        }
        let contentType = UTType(filenameExtension: sourceURL.pathExtension) ?? .audio
        let destination = try chooseDestination(suggestedName: suggestedName, contentType: contentType)
        if FileManager.default.fileExists(atPath: destination.path) {
            try? FileManager.default.removeItem(at: destination)
        }
        do {
            try FileManager.default.copyItem(at: sourceURL, to: destination)
        } catch {
            throw ExportError.writeFailed(error.localizedDescription)
        }
        return destination
    }

    @MainActor
    private static func chooseDestination(suggestedName: String, contentType: UTType) throws -> URL {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = suggestedName
        panel.canCreateDirectories = true
        panel.directoryURL = Paths.downloadsDirectory
        if let type = contentType.preferredMIMEType {
            _ = type
        }
        panel.allowedContentTypes = [contentType]
        panel.isExtensionHidden = false
        let response = panel.runModal()
        guard response == .OK, let url = panel.url else { throw ExportError.cancelled }
        return url
    }
}
