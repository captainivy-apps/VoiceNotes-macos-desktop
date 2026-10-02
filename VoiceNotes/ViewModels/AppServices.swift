import Foundation

/// Shared, long-lived services injected through the SwiftUI environment.
@MainActor
final class AppServices: ObservableObject {
    let store: DiaryStore
    let downloader: ModelDownloader
    let whisper: WhisperEngine
    let llm: OpenAiCompatibleClient

    init() {
        do {
            store = try DiaryStore()
        } catch {
            fatalError("无法初始化数据库：\(error.localizedDescription)")
        }
        downloader = ModelDownloader()
        whisper = WhisperEngine(downloader: downloader)
        llm = OpenAiCompatibleClient()
    }
}
