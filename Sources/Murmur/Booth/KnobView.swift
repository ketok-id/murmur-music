import SwiftUI

/// A circular knob that controls a `Float` value.
///
/// Drag vertically to change. -∞→+∞ pixels map to `range.lowerBound`→`range.upperBound`.
/// The indicator dot sweeps from -135° (min) to +135° (max). At default (`defaultValue`),
/// double-click resets.
struct KnobView: View {
    @Binding var value: Float
    let range: ClosedRange<Float>
    let defaultValue: Float
    var label: String
    var tint: Color = .cyan
    var diameter: CGFloat = 44

    @State private var dragStartValue: Float = 0

    private var normalized: Float {
        (value - range.lowerBound) / (range.upperBound - range.lowerBound)
    }

    private var angleDegrees: Double {
        Double(normalized) * 270 - 135
    }

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [Color(white: 0.25), Color(white: 0.10)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: diameter, height: diameter)
                    .shadow(color: .black.opacity(0.5), radius: 4, x: 0, y: 2)

                Rectangle()
                    .fill(tint)
                    .frame(width: 2, height: diameter * 0.35)
                    .offset(y: -diameter * 0.2)
                    .rotationEffect(.degrees(angleDegrees))
                    .shadow(color: tint.opacity(0.7), radius: 3)
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        if drag.translation == .zero {
                            dragStartValue = value
                        }
                        let delta = Float(-drag.translation.height) / 200 *
                            (range.upperBound - range.lowerBound)
                        value = max(range.lowerBound, min(range.upperBound, dragStartValue + delta))
                    }
            )
            .onTapGesture(count: 2) { value = defaultValue }

            Text(label)
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundColor(.white.opacity(0.6))
                .textCase(.uppercase)
                .tracking(1)
        }
    }
}
