import SwiftUI

/// Overlays vertical beat-grid markers on top of a waveform. The first
/// downbeat is draggable horizontally to align the grid with the audio.
///
/// Bar lines (every 4 beats) render brighter than off-bar beats.
struct BeatGridOverlay: View {
    let bpm: Double
    let duration: Double
    @Binding var firstBeat: Double
    var tint: Color = .cyan.opacity(0.5)

    @State private var dragStartFirstBeat: Double = 0

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                Canvas { context, size in
                    guard bpm > 0, duration > 0 else { return }
                    let beatInterval = 60.0 / bpm
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
                }

                if bpm > 0, duration > 0 {
                    // Clamp visual so the handle is never half-clipped at the edges.
                    let rawHandleX = CGFloat(firstBeat / duration) * geo.size.width
                    let handleX = max(3, min(geo.size.width - 3, rawHandleX))
                    ZStack {
                        // Wide transparent hit area — 20px lets fingers/cursors actually grab.
                        Color.clear
                            .frame(width: 20, height: geo.size.height + 8)
                        // Visible bar.
                        Rectangle()
                            .fill(Color.yellow)
                            .frame(width: 4, height: geo.size.height)
                            .shadow(color: .yellow.opacity(0.6), radius: 3)
                    }
                    .contentShape(Rectangle())
                    .position(x: handleX, y: geo.size.height / 2)
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { drag in
                                if drag.translation == .zero {
                                    dragStartFirstBeat = firstBeat
                                }
                                let dt = Double(drag.translation.width / geo.size.width) * duration
                                let beatInterval = 60.0 / bpm
                                var newFirstBeat = dragStartFirstBeat + dt
                                while newFirstBeat < 0 { newFirstBeat += beatInterval }
                                while newFirstBeat >= beatInterval { newFirstBeat -= beatInterval }
                                firstBeat = newFirstBeat
                            }
                    )
                }
            }
            .allowsHitTesting(true)
        }
    }
}
