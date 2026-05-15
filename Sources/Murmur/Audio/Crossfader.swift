import AVFoundation
import Foundation

/// Equal-power crossfade between two submix nodes.
///
/// `position` ∈ [-1, +1]:
///   -1.0 → submixA at full gain, submixB silent
///    0.0 → both at -3dB (≈0.707 linear) — equal-power center
///   +1.0 → submixB at full gain, submixA silent
///
/// Uses cos/sin so that aGain² + bGain² = 1 across the sweep (constant perceived
/// loudness when both decks contain uncorrelated content).
final class Crossfader {
    let submixA: AVAudioMixerNode
    let submixB: AVAudioMixerNode

    var position: Float = 0 {
        didSet { apply(position: position) }
    }

    init(submixA: AVAudioMixerNode, submixB: AVAudioMixerNode) {
        self.submixA = submixA
        self.submixB = submixB
        apply(position: 0)
    }

    static func gains(forPosition rawPosition: Float) -> (a: Float, b: Float) {
        let p = max(-1, min(1, rawPosition))
        let angle = (p + 1) * (.pi / 4)
        let a = cosf(angle)
        let b = sinf(angle)
        return (a, b)
    }

    private func apply(position: Float) {
        let (a, b) = Crossfader.gains(forPosition: position)
        submixA.outputVolume = a
        submixB.outputVolume = b
    }
}
