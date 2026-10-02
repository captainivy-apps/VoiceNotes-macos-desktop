import Foundation

/// Minimal OpenAI-compatible chat completions client with SSE streaming.
final class OpenAiCompatibleClient: @unchecked Sendable {
    private let session: URLSession

    init() {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 60 * 60
        session = URLSession(configuration: configuration)
    }

    func polishTranscript(
        config: LlmConfig,
        transcript: String,
        onProgress: (@Sendable (Float, LlmPhase) -> Void)? = nil
    ) async throws -> String {
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw NSError(domain: "VoiceNotes.LLM", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "识别稿为空"])
        }

        let base = config.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let urlString = base.hasSuffix("/v1") ? "\(base)/chat/completions" : "\(base)/v1/chat/completions"
        guard let url = URL(string: urlString) else {
            throw NSError(domain: "VoiceNotes.LLM", code: -2,
                          userInfo: [NSLocalizedDescriptionKey: "Base URL 无效"])
        }

        onProgress?(0.05, .preparing)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        if !config.apiKey.isEmpty {
            request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        }
        let body: [String: Any] = [
            "model": config.model,
            "temperature": 0.3,
            "stream": true,
            "messages": [
                ["role": "system", "content": config.systemPrompt],
                ["role": "user", "content": transcript]
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        onProgress?(0.12, .connecting)
        let (bytes, response): (URLSession.AsyncBytes, URLResponse)
        do {
            (bytes, response) = try await session.bytes(for: request)
        } catch {
            throw NSError(domain: "VoiceNotes.LLM", code: -3,
                          userInfo: [NSLocalizedDescriptionKey: "连接失败：\(error.localizedDescription)"])
        }

        guard let http = response as? HTTPURLResponse else {
            throw NSError(domain: "VoiceNotes.LLM", code: -4,
                          userInfo: [NSLocalizedDescriptionKey: "响应无效"])
        }
        guard (200..<300).contains(http.statusCode) else {
            var errorBody = ""
            do {
                for try await line in bytes.lines {
                    errorBody += line
                    if errorBody.count > 2000 { break }
                }
            } catch { /* ignore */ }
            throw NSError(domain: "VoiceNotes.LLM", code: http.statusCode,
                          userInfo: [NSLocalizedDescriptionKey: "LLM 请求失败 (\(http.statusCode)): \(errorBody)"])
        }

        onProgress?(0.22, .sending)
        onProgress?(0.35, .waiting)

        var content = ""
        do {
            for try await line in bytes.lines {
                guard line.hasPrefix("data:") else { continue }
                let payload = line.dropFirst("data:".count).trimmingCharacters(in: .whitespaces)
                if payload == "[DONE]" { break }
                guard !payload.isEmpty,
                      let data = payload.data(using: .utf8),
                      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let choices = object["choices"] as? [[String: Any]],
                      let delta = choices.first?["delta"] as? [String: Any],
                      let piece = delta["content"] as? String,
                      !piece.isEmpty else { continue }
                content += piece
                onProgress?(streamProgress(receivedCharacters: content.count), .receiving)
            }
        } catch {
            throw NSError(domain: "VoiceNotes.LLM", code: -5,
                          userInfo: [NSLocalizedDescriptionKey: "接收 LLM 响应失败：\(error.localizedDescription)"])
        }

        let result = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !result.isEmpty else {
            throw NSError(domain: "VoiceNotes.LLM", code: -6,
                          userInfo: [NSLocalizedDescriptionKey: "LLM 未返回内容"])
        }
        onProgress?(0.95, .parsing)
        return result
    }

    func testConnection(config: LlmConfig) async throws -> String {
        try await polishTranscript(config: config, transcript: "你好，请回复 OK。", onProgress: nil)
    }

    private func streamProgress(receivedCharacters: Int) -> Float {
        min(0.9, 0.4 + 0.5 * (1 - 1 / (1 + Float(receivedCharacters) / 400)))
    }
}
