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
    /// Relative path of the model file on the mirror (host comes from
    /// `AppSettings.mirrorBaseURL`).
    let mirrorPath: String?

    /// ggml name suffix for the Core ML encoder, e.g. "base" or "large-v3-turbo".
    /// Matches whisper.cpp's `ggml-<name>-encoder.mlmodelc` lookup.
    let coremlName: String
    /// Original (HuggingFace) zip containing `ggml-<coremlName>-encoder.mlmodelc`.
    let coremlDownloadURL: String?
    /// Relative path of the encoder zip on the mirror (host comes from
    /// `AppSettings.mirrorBaseURL`).
    let coremlMirrorPath: String?
    let coremlSizeLabel: String?
    /// SHA-256 of the mirror encoder zip. The original HF zip is byte-different
    /// and therefore is not checksum-verified.
    let coremlMirrorSHA256: String?

    /// Expected SHA-256 of the downloaded model file (checked when present).
    var sha256: String? = nil
    /// CPU-oriented quantized model. No Core ML encoder is offered in the UI.
    var quantized: Bool = false

    var hasMirror: Bool { mirrorPath != nil && AppSettings.isMirrorConfigured }
    var hasCoreML: Bool { coremlDownloadURL != nil }
    var hasCoreMLMirror: Bool { coremlMirrorPath != nil && AppSettings.isMirrorConfigured }
}

enum AsrModels {
    private static let baseURL = "https://huggingface.co/ggerganov/whisper.cpp/resolve/main"

    static let all: [AsrModelInfo] = [
        AsrModelInfo(
            id: "tiny",
            displayName: "Tiny",
            fileName: "ggml-tiny.bin",
            sizeLabel: "75 MB",
            downloadURL: "\(baseURL)/ggml-tiny.bin",
            mirrorPath: nil,
            coremlName: "tiny",
            coremlDownloadURL: "\(baseURL)/ggml-tiny-encoder.mlmodelc.zip",
            coremlMirrorPath: "ggml-tiny-encoder.mlmodelc.zip",
            coremlSizeLabel: "14 MB",
            coremlMirrorSHA256: "c88cbd2648e1f5415092bcf5256add463a0f19943e6938f46e8d4ffdebd47739"
        ),
        AsrModelInfo(
            id: "tiny-q5_1",
            displayName: "Tiny Q5（CPU 优化）",
            fileName: "ggml-tiny-q5_1.bin",
            sizeLabel: "30.7 MB",
            downloadURL: "\(baseURL)/ggml-tiny-q5_1.bin",
            mirrorPath: "ggml-tiny-q5_1.bin",
            coremlName: "tiny-q5_1",
            coremlDownloadURL: nil,
            coremlMirrorPath: nil,
            coremlSizeLabel: nil,
            coremlMirrorSHA256: nil,
            sha256: "818710568da3ca15689e31a743197b520007872ff9576237bda97bd1b469c3d7",
            quantized: true
        ),
        AsrModelInfo(
            id: "base",
            displayName: "Base",
            fileName: "ggml-base.bin",
            sizeLabel: "142 MB",
            downloadURL: "\(baseURL)/ggml-base.bin",
            mirrorPath: "ggml-base.bin",
            coremlName: "base",
            coremlDownloadURL: "\(baseURL)/ggml-base-encoder.mlmodelc.zip",
            coremlMirrorPath: "ggml-base-encoder.mlmodelc.zip",
            coremlSizeLabel: "36 MB",
            coremlMirrorSHA256: "20990320cd2ed8f4677b5c144245078651bc25464d5edcebc23f6e2a138ffee5"
        ),
        AsrModelInfo(
            id: "base-q5_1",
            displayName: "Base Q5（CPU 优化）",
            fileName: "ggml-base-q5_1.bin",
            sizeLabel: "56.9 MB",
            downloadURL: "\(baseURL)/ggml-base-q5_1.bin",
            mirrorPath: "ggml-base-q5_1.bin",
            coremlName: "base-q5_1",
            coremlDownloadURL: nil,
            coremlMirrorPath: nil,
            coremlSizeLabel: nil,
            coremlMirrorSHA256: nil,
            sha256: "422f1ae452ade6f30a004d7e5c6a43195e4433bc370bf23fac9cc591f01a8898",
            quantized: true
        ),
        AsrModelInfo(
            id: "small",
            displayName: "Small",
            fileName: "ggml-small.bin",
            sizeLabel: "466 MB",
            downloadURL: "\(baseURL)/ggml-small.bin",
            mirrorPath: nil,
            coremlName: "small",
            coremlDownloadURL: "\(baseURL)/ggml-small-encoder.mlmodelc.zip",
            coremlMirrorPath: "ggml-small-encoder.mlmodelc.zip",
            coremlSizeLabel: "155 MB",
            coremlMirrorSHA256: "d5a7e7d6ebe65531e078fe6c40e4f13259bc063bf8680986d5e0c72d5bf49c98"
        ),
        AsrModelInfo(
            id: "small-q5_1",
            displayName: "Small Q5（CPU 优化）",
            fileName: "ggml-small-q5_1.bin",
            sizeLabel: "181.3 MB",
            downloadURL: "\(baseURL)/ggml-small-q5_1.bin",
            mirrorPath: "ggml-small-q5_1.bin",
            coremlName: "small-q5_1",
            coremlDownloadURL: nil,
            coremlMirrorPath: nil,
            coremlSizeLabel: nil,
            coremlMirrorSHA256: nil,
            sha256: "ae85e4a935d7a567bd102fe55afc16bb595bdb618e11b2fc7591bc08120411bb",
            quantized: true
        ),
        AsrModelInfo(
            id: "medium",
            displayName: "Medium",
            fileName: "ggml-medium.bin",
            sizeLabel: "1.5 GB",
            downloadURL: "\(baseURL)/ggml-medium.bin",
            mirrorPath: nil,
            coremlName: "medium",
            coremlDownloadURL: "\(baseURL)/ggml-medium-encoder.mlmodelc.zip",
            coremlMirrorPath: "ggml-medium-encoder.mlmodelc.zip",
            coremlSizeLabel: "541 MB",
            coremlMirrorSHA256: "1a58621b1b5f47016904f5d7a61e3571b82313e924c68d14326138e85fa0b6b2"
        ),
        AsrModelInfo(
            id: "large-v3-turbo-q5_0",
            displayName: "Large v3 Turbo Q5",
            fileName: "ggml-large-v3-turbo-q5_0.bin",
            sizeLabel: "547 MB",
            downloadURL: "\(baseURL)/ggml-large-v3-turbo-q5_0.bin",
            mirrorPath: "ggml-large-v3-turbo-q5_0.bin",
            coremlName: "large-v3-turbo",
            coremlDownloadURL: "\(baseURL)/ggml-large-v3-turbo-encoder.mlmodelc.zip",
            coremlMirrorPath: "ggml-large-v3-turbo-encoder.mlmodelc.zip",
            coremlSizeLabel: "1.1 GB",
            coremlMirrorSHA256: "97984bdd48d588e41115d1f3d435a91b204ed238868d3b8429091887082e3202"
        )
    ]

    static func find(_ id: String) -> AsrModelInfo? {
        all.first { $0.id == id }
    }
}
