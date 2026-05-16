import SwiftUI

/// Vertical-ish tempo slider with detent at 1.0 (unity).
/// Range: 0.92…1.08 (±8%). Double-click to reset to 1.0.
struct TempoSliderView: View {
    @Binding var rate: Float
    var tint: Color = .cyan

    var body: some View {
        VStack(spacing: 4) {
            Text(percentString(rate))
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .tracking(0.5)
                .foregroundColor(tint)
                .frame(width: 50)

            Slider(value: Binding(
                get: { Double(rate) },
                set: { rate = Float($0) }
            ), in: 0.92...1.08)
                .frame(width: 50)
                .onTapGesture(count: 2) { rate = 1.0 }

            Text("TEMPO")
                .font(.system(size: 8, weight: .medium, design: .monospaced))
                .tracking(1)
                .foregroundColor(.white.opacity(0.5))
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.03))
        .cornerRadius(4)
    }

    private func percentString(_ rate: Float) -> String {
        let pct = (rate - 1.0) * 100
        let sign = pct >= 0 ? "+" : ""
        return String(format: "%@%.1f%%", sign, pct)
    }
}
