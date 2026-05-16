import SwiftUI

/// Horizontal phase meter — needle drifts left/right of center as the slave
/// deck's beats lead/trail the master's. Goes green near zero (within ±0.05 beat).
struct PhaseMeterView: View {
    /// Phase offset in beats, -0.5…+0.5.
    let offsetBeats: Double

    private var locked: Bool { abs(offsetBeats) < 0.05 }

    var body: some View {
        VStack(spacing: 4) {
            Text("PHASE")
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .tracking(1.5)
                .foregroundColor(.white.opacity(0.5))

            GeometryReader { geo in
                ZStack {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.white.opacity(0.06))
                    Rectangle()
                        .fill(Color.white.opacity(0.25))
                        .frame(width: 1)
                    Rectangle()
                        .fill(locked ? Color.green : Color.cyan)
                        .frame(width: 4, height: geo.size.height + 6)
                        .shadow(color: (locked ? Color.green : Color.cyan).opacity(0.7), radius: 4)
                        .offset(x: CGFloat(max(-0.5, min(0.5, offsetBeats))) * geo.size.width)
                }
            }
            .frame(height: 10)
        }
    }
}
