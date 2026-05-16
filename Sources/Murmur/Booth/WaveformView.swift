import SwiftUI

/// Renders an interleaved min/max peaks array as a stereo-look waveform with
/// a playhead. When `bandPeaks` is non-empty, each bin is tinted by an RGB
/// blend of its low/mid/high frequency energy (Serato-style): bass→red,
/// mid→green, high→blue. White = full-range mix.
struct WaveformView: View {
    let peaks: [Float]
    let bandPeaks: [Float]   // Interleaved low/mid/high per bin, 0..1. Empty = plain tint.
    let progress: Double
    var tint: Color = .cyan

    var body: some View {
        Canvas { context, size in
            guard peaks.count >= 2 else { return }
            let pairCount = peaks.count / 2
            let stepX = size.width / CGFloat(pairCount)
            let midY = size.height / 2
            let useBands = bandPeaks.count >= pairCount * 3

            for i in 0..<pairCount {
                let x = CGFloat(i) * stepX + stepX / 2
                let minV = CGFloat(peaks[i * 2])
                let maxV = CGFloat(peaks[i * 2 + 1])

                let color: Color
                if useBands {
                    let low = CGFloat(bandPeaks[i * 3])
                    let mid = CGFloat(bandPeaks[i * 3 + 1])
                    let high = CGFloat(bandPeaks[i * 3 + 2])
                    color = Color(
                        red:   min(1, 0.15 + low * 1.2),
                        green: min(1, 0.15 + mid * 1.2),
                        blue:  min(1, 0.15 + high * 1.2),
                        opacity: 0.95
                    )
                } else {
                    color = tint.opacity(0.85)
                }

                var path = Path()
                path.move(to: CGPoint(x: x, y: midY - maxV * midY))
                path.addLine(to: CGPoint(x: x, y: midY - minV * midY))
                context.stroke(path, with: .color(color), lineWidth: max(1, stepX * 0.9))
            }

            let px = CGFloat(progress) * size.width
            var head = Path()
            head.move(to: CGPoint(x: px, y: 0))
            head.addLine(to: CGPoint(x: px, y: size.height))
            context.stroke(head, with: .color(.white), lineWidth: 1.5)
        }
        .background(Color.black.opacity(0.4))
        .cornerRadius(4)
    }
}
