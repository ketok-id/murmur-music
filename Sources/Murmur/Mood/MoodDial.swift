import Combine
import Foundation

/// 4 mood anchors arranged on a unit circle.
///
/// `angle` is the dial's current position in radians (0 = right, π/2 = top, etc.).
/// Each anchor has a target ambient-bias level + suggested effect preset that
/// the rest of the app can read.
final class MoodDial: ObservableObject {
    enum Mood: String, CaseIterable {
        case calm, focus, cozy, energy
    }

    /// 0…2π. Top of the dial is π/2; we map clockwise from top.
    @Published var angle: Double = 0 {
        didSet { recomputeBlend() }
    }

    /// Current bias on the Ambient Layer's overall volume. 0…1.
    @Published private(set) var ambientBias: Float = 0.7
    /// Currently dominant mood (the closest anchor).
    @Published private(set) var dominant: Mood = .focus

    /// Returns the angle (radians) for a given mood anchor on the dial.
    static func anchorAngle(_ mood: Mood) -> Double {
        switch mood {
        case .focus:  return  .pi / 2     // top
        case .energy: return  0           // right
        case .cozy:   return  -.pi / 2    // bottom (or 3π/2)
        case .calm:   return  .pi         // left
        }
    }

    /// Ambient bias per anchor (how loud the ambient layer should be in this mood).
    static func anchorAmbient(_ mood: Mood) -> Float {
        switch mood {
        case .calm:   return 0.85
        case .focus:  return 0.55
        case .cozy:   return 0.80
        case .energy: return 0.30
        }
    }

    init(initial: Mood = .focus) {
        self.angle = Self.anchorAngle(initial)
        recomputeBlend()
    }

    /// Click an anchor to snap to it.
    func snap(to mood: Mood) {
        angle = Self.anchorAngle(mood)
    }

    private func recomputeBlend() {
        var bestMood: Mood = .focus
        var bestDelta: Double = .infinity
        for m in Mood.allCases {
            let a = Self.anchorAngle(m)
            var delta = abs(angle - a).truncatingRemainder(dividingBy: 2 * .pi)
            if delta > .pi { delta = 2 * .pi - delta }
            if delta < bestDelta {
                bestDelta = delta
                bestMood = m
            }
        }
        dominant = bestMood
        ambientBias = Self.anchorAmbient(bestMood)
    }
}
