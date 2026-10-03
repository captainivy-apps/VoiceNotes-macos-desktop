import Foundation

struct AsrLanguage: Identifiable, Equatable {
    let id: String
    let displayName: String
}

enum AsrLanguages {
    static let autoId = "auto"

    static let all: [AsrLanguage] = [
        AsrLanguage(id: autoId, displayName: "自动检测"),
        AsrLanguage(id: "zh", displayName: "中文"),
        AsrLanguage(id: "en", displayName: "English"),
        AsrLanguage(id: "ja", displayName: "日本語"),
        AsrLanguage(id: "ko", displayName: "한국어")
    ]

    static func displayName(_ id: String) -> String {
        all.first { $0.id == id }?.displayName ?? id
    }
}

struct AsrModelInfo: Identifiable, Equatable {
    let id: String
    let displayName: String
    let fileName: String
    let sizeLabel: String
    let downloadURL: String
    let mirrorDownloadURL: String?

    /// ggml name suffix for the Core ML encoder, e.g. "base" or "large-v3-turbo".
    /// Matches whisper.cpp's `ggml-<name>-encoder.mlmodelc` lookup.
    let coremlName: String
    /// Downloadable zip containing `ggml-<coremlName>-encoder.mlmodelc`.
    let coremlDownloadURL: String?
    let coremlSizeLabel: String?
    let coremlSHA256: String?

    var hasMirror: Bool { mirrorDownloadURL != nil }
    var hasCoreML: Bool { coremlDownloadURL != nil }
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
            mirrorDownloadURL: nil,
            coremlName: "tiny",
            coremlDownloadURL: nil,
            coremlSizeLabel: nil,
            coremlSHA256: nil
        ),
        AsrModelInfo(
            id: "base",
            displayName: "Base",
            fileName: "ggml-base.bin",
            sizeLabel: "142 MB",
            downloadURL: "\(baseURL)/ggml-base.bin",
            mirrorDownloadURL: "\(mirrorBaseURL)/ggml-base.bin",
            coremlName: "base",
            coremlDownloadURL: "\(mirrorBaseURL)/ggml-base-encoder.mlmodelc.zip",
            coremlSizeLabel: "36 MB",
            coremlSHA256: "20990320cd2ed8f4677b5c144245078651bc25464d5edcebc23f6e2a138ffee5"
        ),
        AsrModelInfo(
            id: "small",
            displayName: "Small",
            fileName: "ggml-small.bin",
            sizeLabel: "466 MB",
            downloadURL: "\(baseURL)/ggml-small.bin",
            mirrorDownloadURL: nil,
            coremlName: "small",
            coremlDownloadURL: "\(mirrorBaseURL)/ggml-small-encoder.mlmodelc.zip",
            coremlSizeLabel: "155 MB",
            coremlSHA256: "d5a7e7d6ebe65531e078fe6c40e4f13259bc063bf8680986d5e0c72d5bf49c98"
        ),
        AsrModelInfo(
            id: "medium",
            displayName: "Medium",
            fileName: "ggml-medium.bin",
            sizeLabel: "1.5 GB",
            downloadURL: "\(baseURL)/ggml-medium.bin",
            mirrorDownloadURL: nil,
            coremlName: "medium",
            coremlDownloadURL: "\(mirrorBaseURL)/ggml-medium-encoder.mlmodelc.zip",
            coremlSizeLabel: "541 MB",
            coremlSHA256: "1a58621b1b5f47016904f5d7a61e3571b82313e924c68d14326138e85fa0b6b2"
        ),
        AsrModelInfo(
            id: "large-v3-turbo-q5_0",
            displayName: "Large v3 Turbo Q5",
            fileName: "ggml-large-v3-turbo-q5_0.bin",
            sizeLabel: "547 MB",
            downloadURL: "\(baseURL)/ggml-large-v3-turbo-q5_0.bin",
            mirrorDownloadURL: "\(mirrorBaseURL)/ggml-large-v3-turbo-q5_0.bin",
            coremlName: "large-v3-turbo",
            coremlDownloadURL: "\(mirrorBaseURL)/ggml-large-v3-turbo-encoder.mlmodelc.zip",
            coremlSizeLabel: "1.1 GB",
            coremlSHA256: "97984bdd48d588e41115d1f3d435a91b204ed238868d3b8429091887082e3202"
        )
    ]

    static func find(_ id: String) -> AsrModelInfo? {
        all.first { $0.id == id }
    }
}
