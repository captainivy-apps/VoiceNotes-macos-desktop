import Foundation

/// Downloads whisper ggml models with progress reporting and mirror support.
final class ModelDownloader: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let fileManager = FileManager.default
    private let modelsDir: URL

    private let lock = NSLock()
    private var continuation: CheckedContinuation<URL, Error>?
    private var progressHandler: ((Double) -> Void)?
    private var destination: URL?
    private var isBusy = false

    private lazy var session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 60 * 60
        return URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }()

    override convenience init() {
        self.init(modelsDir: Paths.modelsDir)
    }

    init(modelsDir: URL) {
        self.modelsDir = modelsDir
        try? FileManager.default.createDirectory(at: modelsDir, withIntermediateDirectories: true)
        super.init()
    }

    func modelFile(_ model: AsrModelInfo) -> URL {
        modelsDir.appendingPathComponent(model.fileName)
    }

    func isDownloaded(_ model: AsrModelInfo) -> Bool {
        let file = modelFile(model)
        guard let attributes = try? fileManager.attributesOfItem(atPath: file.path),
              let size = attributes[.size] as? NSNumber else { return false }
        return size.int64Value > 1024 * 1024
    }

    func downloadedAt(_ model: AsrModelInfo) -> Date? {
        guard isDownloaded(model) else { return nil }
        let file = modelFile(model)
        return (try? fileManager.attributesOfItem(atPath: file.path))?[.modificationDate] as? Date
    }

    func download(
        _ model: AsrModelInfo,
        useMirror: Bool = false,
        onProgress: @escaping (Double) -> Void
    ) async throws -> URL {
        let urlString: String
        if useMirror {
            guard let mirror = model.mirrorDownloadURL else {
                throw NSError(domain: "VoiceNotes.Download", code: -1,
                              userInfo: [NSLocalizedDescriptionKey: "该模型暂无镜像"])
            }
            urlString = mirror
        } else {
            urlString = model.downloadURL
        }
        guard let url = URL(string: urlString) else {
            throw NSError(domain: "VoiceNotes.Download", code: -2,
                          userInfo: [NSLocalizedDescriptionKey: "下载地址无效"])
        }

        lock.lock()
        if isBusy {
            lock.unlock()
            throw NSError(domain: "VoiceNotes.Download", code: -3,
                          userInfo: [NSLocalizedDescriptionKey: "已有下载任务进行中"])
        }
        isBusy = true
        lock.unlock()

        let target = modelFile(model)
        let temp = target.appendingPathExtension("download")
        try? fileManager.removeItem(at: temp)

        lock.lock()
        destination = temp
        progressHandler = onProgress
        lock.unlock()

        let task = session.downloadTask(with: url)

        do {
            let downloaded = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
                lock.lock()
                self.continuation = continuation
                lock.unlock()
                task.resume()
            }
            if fileManager.fileExists(atPath: target.path) {
                try? fileManager.removeItem(at: target)
            }
            try fileManager.moveItem(at: downloaded, to: target)
            finish()
            return target
        } catch {
            finish()
            throw error
        }
    }

    func delete(_ model: AsrModelInfo) -> Bool {
        let file = modelFile(model)
        if fileManager.fileExists(atPath: file.path) {
            return (try? fileManager.removeItem(at: file)) != nil
        }
        return true
    }

    private func finish() {
        lock.lock()
        isBusy = false
        continuation = nil
        progressHandler = nil
        destination = nil
        lock.unlock()
    }

    // MARK: - URLSessionDownloadDelegate

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        lock.lock()
        let handler = progressHandler
        lock.unlock()
        handler?(min(max(progress, 0), 1))
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        // `location` is deleted after this callback returns; move it now.
        lock.lock()
        let destination = self.destination
        lock.unlock()
        guard let destination else { return }
        do {
            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }
            try fileManager.moveItem(at: location, to: destination)
            lock.lock()
            let continuation = self.continuation
            self.continuation = nil
            lock.unlock()
            continuation?.resume(returning: destination)
        } catch {
            lock.lock()
            let continuation = self.continuation
            self.continuation = nil
            lock.unlock()
            continuation?.resume(throwing: error)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error else { return }
        lock.lock()
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()
        if let response = task.response as? HTTPURLResponse, response.statusCode >= 400 {
            continuation?.resume(throwing: NSError(
                domain: "VoiceNotes.Download",
                code: response.statusCode,
                userInfo: [NSLocalizedDescriptionKey: "下载失败: HTTP \(response.statusCode)"]
            ))
        } else {
            continuation?.resume(throwing: error)
        }
    }
}
