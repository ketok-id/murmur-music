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
                // Beat grid lines — never interactive.
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
                .allowsHitTesting(false)

                // Draggable downbeat handle. Use .offset() rather than .position()
                // because .position() returns a parent-filling view whose hit
                // testing interacts poorly with contentShape inside a ZStack.
                if bpm > 0, duration > 0 {
                    let rawHandleX = CGFloat(firstBeat / duration) * geo.size.width
                    let handleX = max(0, min(geo.size.width - 14, rawHandleX - 7))
                    Rectangle()
                        .fill(Color.yellow)
                        .frame(width: 14, height: geo.size.height + 6)
                        .shadow(color: .yellow.opacity(0.7), radius: 3)
                        .offset(x: handleX, y: -3)
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
        }
    }
}
