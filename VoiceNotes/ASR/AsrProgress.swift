import Foundation

enum AsrPhase {
    case loadingModel
    case readingAudio
    case transcribing
}

enum AsrProgressMessages {
    static func format(_ phase: AsrPhase, _ progress: Float) -> String {
        let percent = Int((progress * 100).rounded()).clamped(0, 100)
        switch phase {
        case .loadingModel: return "正在加载模型… \(percent)%"
        case .readingAudio: return "正在读取音频… \(percent)%"
        case .transcribing: return "正在识别… \(percent)%"
        }
    }
}

private extension Int {
    func clamped(_ lower: Int, _ upper: Int) -> Int { Swift.min(Swift.max(self, lower), upper) }
}
