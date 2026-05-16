import SwiftUI

/// Overlays vertical beat-grid markers on top of a waveform.
///
/// Tap anywhere on the waveform to align the grid: the nearest beat snaps
/// to the click position. The yellow line shows where the first downbeat
/// currently sits.
///
/// Bar lines (every 4 beats) render brighter than off-bar beats.
struct BeatGridOverlay: View {
    let bpm: Double
    let duration: Double
    @Binding var firstBeat: Double
    var tint: Color = .cyan.opacity(0.5)

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                // Beat grid lines + downbeat indicator, drawn together in one Canvas.
                Canvas { context, size in
                    guard bpm > 0, duration > 0 else { return }
                    let beatInterval = 60.0 / bpm

                    // 1) Beat grid.
                    var beatIndex = 0
                    var t = firstBeat
                    while t < duration {
                        let x = CGFloat(t / duration) * size.width
                        var line = Path()
                        line.move(to: CGPoint(x: x, y: 0))
                        line.addLine(to: CGPoint(x: x, y: size.height))
                        let isBar = (beatIndex % 4 == 0)
                        context.stroke(
                            line,
                            with: .color(isBar ? tint.opacity(0.9) : tint.opacity(0.35)),
                            lineWidth: isBar ? 1.5 : 0.5
                        )
                        beatIndex += 1
                        t += beatInterval
                    }

                    // 2) Yellow downbeat indicator at firstBeat.
                    let downbeatX = max(2, CGFloat(firstBeat / duration) * size.width)
                    var marker = Path()
                    marker.move(to: CGPoint(x: downbeatX, y: 0))
                    marker.addLine(to: CGPoint(x: downbeatX, y: size.height))
                    context.stroke(marker, with: .color(.yellow), lineWidth: 3)
                }
                .allowsHitTesting(false)
            }
            // The whole waveform area is the click target. Click = "set the
            // nearest beat to here." This is far more reliable than dragging
            // a small handle, and matches what DJs actually want to do
            // (point at a kick, snap the grid to it).
            .contentShape(Rectangle())
            .onTapGesture { location in
                guard duration > 0, bpm > 0, geo.size.width > 0 else { return }
                let clickTime = Double(location.x / geo.size.width) * duration
                let beatInterval = 60.0 / bpm
                // Compute firstBeat such that the grid has a beat at clickTime.
                var newFirstBeat = clickTime.truncatingRemainder(dividingBy: beatInterval)
                while newFirstBeat < 0 { newFirstBeat += beatInterval }
                while newFirstBeat >= beatInterval { newFirstBeat -= beatInterval }
                firstBeat = newFirstBeat
            }
        }
    }
}
