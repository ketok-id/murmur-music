import SwiftUI

/// A zoomed-in waveform showing `viewWindowSeconds` of audio around the current
/// playhead. The playhead stays fixed at the horizontal center of the view;
/// the audio scrolls left as the track plays.
///
/// Reuses Phase 9's frequency coloring (`bandPeaks`) when available.
/// Renders beat-grid lines using the same `firstBeat` + `bpm` model as
/// `BeatGridOverlay`.
struct DetailWaveformView: View {
    let peaks: [Float]
    let bandPeaks: [Float]
    let bpm: Double
    let firstBeat: Double
    let duration: Double
    let currentTimeSeconds: Double
    var tint: Color = .cyan
    /// Total seconds visible in the view window (split equally before/after the playhead).
    var viewWindowSeconds: Double = 10

    var body: some View {
        Canvas { context, size in
            guard peaks.count >= 2, duration > 0 else {
                drawPlaceholder(context: context, size: size)
                return
            }
            let pairCount = peaks.count / 2
            let useBands = bandPeaks.count >= pairCount * 3

            let half = viewWindowSeconds / 2
            let viewStart = currentTimeSeconds - half
            let viewEnd = currentTimeSeconds + half
            let pxPerSecond = size.width / CGFloat(viewWindowSeconds)
            let midY = size.height / 2

            let firstBin = max(0, Int((viewStart / duration) * Double(pairCount)))
            let lastBin = min(pairCount, Int((viewEnd / duration) * Double(pairCount)) + 1)
            guard lastBin > firstBin else {
                drawPlaceholder(context: context, size: size)
                return
            }

            let visibleBins = lastBin - firstBin
            let stride = max(1, visibleBins / 200)

            var i = firstBin
            while i < lastBin {
                let binCenterT = (Double(i) + 0.5) / Double(pairCount) * duration
                let x = CGFloat(binCenterT - viewStart) * pxPerSecond
                guard x >= -2 && x <= size.width + 2 else {
                    i += stride
                    continue
                }
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
                let widthPx = max(1.5, CGFloat(stride) * pxPerSecond * (duration / Double(pairCount)))
                context.stroke(path, with: .color(color), lineWidth: widthPx)
                i += stride
            }

            if bpm > 0 {
                let beatInterval = 60.0 / bpm
                var beatT = firstBeat
                if beatT > viewStart {
                    let count = ceil((beatT - viewStart) / beatInterval)
                    beatT -= count * beatInterval
                } else {
                    let count = floor((viewStart - beatT) / beatInterval)
                    beatT += count * beatInterval
                }
                var beatIndex = Int(round((beatT - firstBeat) / beatInterval))
                while beatT <= viewEnd {
                    let x = CGFloat(beatT - viewStart) * pxPerSecond
                    if x >= 0 && x <= size.width {
                        let isBar = (beatIndex % 4 == 0)
                        var line = Path()
                        line.move(to: CGPoint(x: x, y: 0))
                        line.addLine(to: CGPoint(x: x, y: size.height))
                        context.stroke(
                            line,
                            with: .color(isBar ? tint.opacity(0.55) : tint.opacity(0.20)),
                            lineWidth: isBar ? 1.5 : 0.5
                        )
                    }
                    beatIndex += 1
                    beatT += beatInterval
                }
            }

            let center = size.width / 2
            var head = Path()
            head.move(to: CGPoint(x: center, y: 0))
            head.addLine(to: CGPoint(x: center, y: size.height))
            context.stroke(head, with: .color(.white), lineWidth: 2)

            var tri = Path()
            tri.move(to: CGPoint(x: center - 5, y: 0))
            tri.addLine(to: CGPoint(x: center + 5, y: 0))
            tri.addLine(to: CGPoint(x: center, y: 6))
            tri.closeSubpath()
            context.fill(tri, with: .color(.white))
        }
        .background(Color.black.opacity(0.55))
        .cornerRadius(4)
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
    }

    private func drawPlaceholder(context: GraphicsContext, size: CGSize) {
        let center = size.width / 2
        var head = Path()
        head.move(to: CGPoint(x: center, y: 0))
        head.addLine(to: CGPoint(x: center, y: size.height))
        context.stroke(head, with: .color(.white.opacity(0.3)), lineWidth: 1)
    }
}
