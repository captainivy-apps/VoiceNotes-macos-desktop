import Foundation

struct AsrModelInfo: Identifiable, Equatable {
    let id: String
    let displayName: String
    let fileName: String
    let sizeLabel: String
    let downloadURL: String
    let mirrorDownloadURL: String?

    var hasMirror: Bool { mirrorDownloadURL != nil }
}

enum AsrModels {
    private static let baseURL = "https://huggingface.co/ggerganov/whisper.cpp/resolve/main"
    private static let mirrorBaseURL = "https://www.galaxyrover.com/mirrors"

    static let all: [AsrModelInfo] = [
        AsrModelInfo(
            id: "tiny",
            displayName: "Tiny",
            fileName: "ggml-tiny.bin",
            sizeLabel: "75 MB",
            downloadURL: "\(baseURL)/ggml-tiny.bin",
            mirrorDownloadURL: nil
        ),
        AsrModelInfo(
            id: "base",
            displayName: "Base",
            fileName: "ggml-base.bin",
            sizeLabel: "142 MB",
            downloadURL: "\(baseURL)/ggml-base.bin",
            mirrorDownloadURL: "\(mirrorBaseURL)/ggml-base.bin"
        ),
        AsrModelInfo(
            id: "small",
            displayName: "Small",
            fileName: "ggml-small.bin",
            sizeLabel: "466 MB",
            downloadURL: "\(baseURL)/ggml-small.bin",
            mirrorDownloadURL: nil
        ),
        AsrModelInfo(
            id: "medium",
            displayName: "Medium",
            fileName: "ggml-medium.bin",
            sizeLabel: "1.5 GB",
            downloadURL: "\(baseURL)/ggml-medium.bin",
            mirrorDownloadURL: nil
        ),
        AsrModelInfo(
            id: "large-v3-turbo-q5_0",
            displayName: "Large v3 Turbo Q5",
            fileName: "ggml-large-v3-turbo-q5_0.bin",
            sizeLabel: "547 MB",
            downloadURL: "\(baseURL)/ggml-large-v3-turbo-q5_0.bin",
            mirrorDownloadURL: "\(mirrorBaseURL)/ggml-large-v3-turbo-q5_0.bin"
        )
    ]

    static func find(_ id: String) -> AsrModelInfo? {
        all.first { $0.id == id }
    }
}
