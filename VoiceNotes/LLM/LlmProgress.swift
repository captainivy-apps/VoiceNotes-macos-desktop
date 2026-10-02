import Foundation

enum LlmPhase {
    case preparing
    case connecting
    case sending
    case waiting
    case receiving
    case parsing
}

enum LlmProgressMessages {
    static func format(_ phase: LlmPhase, _ progress: Float) -> String {
        let percent = min(max(Int((progress * 100).rounded()), 0), 100)
        switch phase {
        case .preparing: return "正在准备润色请求… \(percent)%"
        case .connecting: return "正在连接 LLM 服务… \(percent)%"
        case .sending: return "正在发送识别稿… \(percent)%"
        case .waiting: return "正在等待模型生成润色稿… \(percent)%"
        case .receiving: return "正在接收润色稿… \(percent)%"
        case .parsing: return "正在解析润色结果… \(percent)%"
        }
    }
}
