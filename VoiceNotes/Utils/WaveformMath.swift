import CoreGraphics
import Foundation

enum WaveformMath {
    static let windowMs: Int64 = 30_000
    static let barsPerWindow = 120

    static func windowStartMs(durationMs: Int64, playbackPositionMs: Int64) -> Int64 {
        if durationMs <= windowMs { return 0 }
        let maxStart = durationMs - windowMs
        let followOffset = Int64(Double(windowMs) * 0.7)
        return min(max(playbackPositionMs - followOffset, 0), maxStart)
    }

    static func windowSlice(allBars: [Float], durationMs: Int64, windowStartMs: Int64) -> [Float] {
        guard !allBars.isEmpty else { return [] }
        if durationMs <= windowMs { return allBars }
        let totalBars = allBars.count
        let startBar = min(
            max(Int(Double(windowStartMs) / Double(durationMs) * Double(totalBars)), 0),
            max(totalBars - barsPerWindow, 0)
        )
        let endBar = min(startBar + barsPerWindow, totalBars)
        return Array(allBars[startBar..<endBar])
    }

    static func playheadFraction(durationMs: Int64, windowStartMs: Int64, playbackPositionMs: Int64) -> CGFloat {
        guard durationMs > 0 else { return 0 }
        let windowDurationMs = min(windowMs, durationMs - windowStartMs)
        guard windowDurationMs > 0 else { return 0 }
        let fraction = Double(playbackPositionMs - windowStartMs) / Double(windowDurationMs)
        return CGFloat(min(max(fraction, 0), 1))
    }
}
