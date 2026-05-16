import SwiftUI

/// Overlays hot-cue flags and the active loop region on top of the waveform.
///
/// Cue flags render as thin vertical lines in each cue's color, with a small
/// triangle "flag" at the top. The loop region is a tinted band between the
/// IN and OUT seconds.
struct CueAndLoopOverlay: View {
    let hotCues: [HotCue]
    @ObservedObject var loop: LoopState
    let duration: Double
    var loopTint: Color = .cyan

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                if let inT = loop.inSeconds, let outT = loop.outSeconds, duration > 0 {
                    let x1 = CGFloat(inT / duration) * geo.size.width
                    let x2 = CGFloat(outT / duration) * geo.size.width
                    Rectangle()
                        .fill(loopTint.opacity(loop.isActive ? 0.28 : 0.15))
                        .frame(width: max(2, x2 - x1), height: geo.size.height)
                        .offset(x: x1, y: 0)
                }

                ForEach(hotCues) { cue in
                    if duration > 0 {
                        let x = CGFloat(cue.seconds / duration) * geo.size.width
                        let color = Color(hex: cue.colorHex) ?? .white
                        ZStack(alignment: .top) {
                            Rectangle()
                                .fill(color)
                                .frame(width: 2, height: geo.size.height)
                            Text("\(cue.id + 1)")
                                .font(.system(size: 8, weight: .bold, design: .monospaced))
                                .foregroundColor(.black)
                                .frame(width: 14, height: 12)
                                .background(color)
                        }
                        .offset(x: x - 1, y: 0)
                    }
                }
            }
            .allowsHitTesting(false)
        }
    }
}
