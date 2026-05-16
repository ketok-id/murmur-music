import SwiftUI

/// Renders an interleaved min/max peaks array as a stereo-look waveform with
/// a playhead. Beat-grid markers are drawn by a separate overlay
/// (`BeatGridOverlay`) so this view stays focused.
struct WaveformView: View {
    /// Interleaved min/max pairs (e.g., `[min0, max0, min1, max1, ...]`).
    let peaks: [Float]
    /// 0…1 representing the current playhead position.
    let progress: Double
    /// Color of the rendered waveform.
    var tint: Color = .cyan

    var body: some View {
        Canvas { context, size in
            guard peaks.count >= 2 else { return }
            let pairCount = peaks.count / 2
            let stepX = size.width / CGFloat(pairCount)
            let midY = size.height / 2

            var path = Path()
            for i in 0..<pairCount {
                let x = CGFloat(i) * stepX + stepX / 2
                let minV = CGFloat(peaks[i * 2])
                let maxV = CGFloat(peaks[i * 2 + 1])
                path.move(to: CGPoint(x: x, y: midY - maxV * midY))
                path.addLine(to: CGPoint(x: x, y: midY - minV * midY))
            }
            context.stroke(path, with: .color(tint.opacity(0.85)), lineWidth: max(1, stepX * 0.9))

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
