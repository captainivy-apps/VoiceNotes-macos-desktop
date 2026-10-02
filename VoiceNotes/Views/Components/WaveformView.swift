import SwiftUI

struct WaveformView: View {
    var samples: [Float]
    var playheadFraction: CGFloat?
    var barColor: Color = .accentColor
    var emptyColor: Color = Color.gray.opacity(0.35)
    var playheadColor: Color = .red

    var body: some View {
        Canvas { context, size in
            let midY = size.height / 2
            if samples.isEmpty {
                var path = Path()
                path.move(to: CGPoint(x: 0, y: midY))
                path.addLine(to: CGPoint(x: size.width, y: midY))
                context.stroke(path, with: .color(emptyColor), lineWidth: 2)
            } else {
                let barWidth = size.width / CGFloat(samples.count)
                for (index, amplitude) in samples.enumerated() {
                    let x = CGFloat(index) * barWidth
                    let height = CGFloat(amplitude) * size.height * 0.8
                    var path = Path()
                    path.move(to: CGPoint(x: x, y: midY - height / 2))
                    path.addLine(to: CGPoint(x: x, y: midY + height / 2))
                    context.stroke(path, with: .color(barColor), lineWidth: max(barWidth, 2))
                }
            }
            if let playheadFraction {
                let x = min(max(playheadFraction, 0), 1) * size.width
                var path = Path()
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
                context.stroke(path, with: .color(playheadColor), lineWidth: 2)
            }
        }
    }
}
