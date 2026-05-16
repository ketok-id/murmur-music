import SwiftUI

/// Circular mood dial with 4 anchors. Drag to rotate; click an anchor to snap.
struct MoodDialView: View {
    @ObservedObject var mood: MoodDial
    var size: CGFloat = 84

    @State private var dragStartAngle: Double = 0

    var body: some View {
        VStack(spacing: 4) {
            Text("MOOD")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .tracking(1.5)
                .foregroundColor(.white.opacity(0.5))

            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
                    .frame(width: size, height: size)

                ForEach(MoodDial.Mood.allCases, id: \.self) { mood in
                    let a = MoodDial.anchorAngle(mood)
                    let x = cos(a) * Double(size) / 2 * 0.85
                    let y = -sin(a) * Double(size) / 2 * 0.85
                    VStack(spacing: 2) {
                        Circle()
                            .fill(self.mood.dominant == mood ? anchorColor(mood) : Color.white.opacity(0.2))
                            .frame(width: 8, height: 8)
                            .shadow(color: self.mood.dominant == mood ? anchorColor(mood).opacity(0.7) : .clear, radius: 4)
                        Text(label(for: mood))
                            .font(.system(size: 7, weight: .semibold, design: .monospaced))
                            .tracking(1)
                            .foregroundColor(self.mood.dominant == mood ? anchorColor(mood) : .white.opacity(0.35))
                    }
                    .offset(x: x, y: y)
                    .onTapGesture { self.mood.snap(to: mood) }
                }

                Rectangle()
                    .fill(anchorColor(mood.dominant))
                    .frame(width: 2, height: size * 0.32)
                    .offset(y: -size * 0.16)
                    .rotationEffect(.radians(-mood.angle + .pi / 2))
                    .shadow(color: anchorColor(mood.dominant).opacity(0.5), radius: 3)
            }
            .frame(width: size, height: size)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        let dx = drag.translation.width / 80
                        if drag.translation == .zero {
                            dragStartAngle = mood.angle
                        }
                        mood.angle = (dragStartAngle - dx).truncatingRemainder(dividingBy: 2 * .pi)
                    }
            )
        }
    }

    private func label(for m: MoodDial.Mood) -> String {
        switch m {
        case .calm:   return "CALM"
        case .focus:  return "FOCUS"
        case .cozy:   return "COZY"
        case .energy: return "ENERGY"
        }
    }

    private func anchorColor(_ m: MoodDial.Mood) -> Color {
        switch m {
        case .calm:   return Color(red: 0.43, green: 0.77, blue: 1.0)
        case .focus:  return Color(red: 0.66, green: 0.55, blue: 0.98)
        case .cozy:   return Color(red: 1.0, green: 0.75, blue: 0.47)
        case .energy: return Color(red: 1.0, green: 0.48, blue: 0.71)
        }
    }
}
