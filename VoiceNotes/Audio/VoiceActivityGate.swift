import Foundation

/// Pure, time-injected state machine for voice-activated recording.
///
/// It receives the current audio level and decides when to pause (silence for
/// `pauseAfter` seconds), resume (sound returns while paused) or stop (silence
/// for `stopAfter` seconds). Once stopped it never resumes.
struct VoiceActivityGate {
    enum Transition: Equatable {
        case none
        case paused
        case resumed
        case stopped
    }

    let pauseAfter: TimeInterval
    let stopAfter: TimeInterval
    let threshold: Float

    private(set) var isPaused = false
    private(set) var isStopped = false
    private var lastSoundAt: Date

    init(pauseAfter: TimeInterval,
         stopAfter: TimeInterval,
         threshold: Float,
         start: Date) {
        self.pauseAfter = max(0, pauseAfter)
        self.stopAfter = max(stopAfter, self.pauseAfter + 1)
        self.threshold = threshold
        self.lastSoundAt = start
    }

    /// Consumes one level sample. `level` is expected to be normalized (0...1).
    mutating func consume(level: Float, at now: Date) -> Transition {
        guard !isStopped else { return .none }

        if level >= threshold {
            lastSoundAt = now
            if isPaused {
                isPaused = false
                return .resumed
            }
            return .none
        }

        let silence = now.timeIntervalSince(lastSoundAt)
        if silence >= stopAfter {
            isStopped = true
            return .stopped
        }
        if !isPaused && silence >= pauseAfter {
            isPaused = true
            return .paused
        }
        return .none
    }
}
