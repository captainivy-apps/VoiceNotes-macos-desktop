import AVFoundation
import Foundation

/// Lightweight AVAudioPlayer wrapper exposing playback state to SwiftUI.
@MainActor
final class AudioPlayer: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published private(set) var isPlaying = false
    @Published private(set) var currentTime: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0

    private var player: AVAudioPlayer?
    private var timer: Timer?

    func play(url: URL) throws {
        stop(resetPosition: true)
        let player = try AVAudioPlayer(contentsOf: url)
        player.delegate = self
        player.prepareToPlay()
        player.play()
        self.player = player
        duration = max(player.duration, 0)
        currentTime = 0
        isPlaying = true
        startTimer()
    }

    func stop(resetPosition: Bool = true) {
        timer?.invalidate()
        timer = nil
        if let player, player.isPlaying {
            player.stop()
        }
        player = nil
        isPlaying = false
        if resetPosition { currentTime = 0 }
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in self.stop(resetPosition: true) }
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        Task { @MainActor in self.stop(resetPosition: true) }
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let player = self.player else { return }
                self.currentTime = player.currentTime
                self.duration = max(player.duration, self.duration)
            }
        }
    }
}
