import AVFoundation

/// Per-deck FX bus: Echo (delay) + Reverb in series, inserted between the
/// filter and the volume fader.
///
/// Each unit exposes wet/dry + on-off. Echo additionally has a beat-divider
/// (1/4, 1/8, 1/16 = 4, 8, 16) — call `setEchoBeatDivider(_:bpm:)` whenever
/// the deck's effective BPM changes so the delay time stays musical.
final class EffectsChain {
    private let engine: AVAudioEngine
    let delay = AVAudioUnitDelay()
    let reverb = AVAudioUnitReverb()

    /// 0.0…1.0. 1.0 = fully wet.
    var echoWet: Float {
        get { delay.wetDryMix / 100 }
        set { delay.wetDryMix = max(0, min(100, newValue * 100)) }
    }

    /// 0.0…1.0.
    var reverbWet: Float {
        get { reverb.wetDryMix / 100 }
        set { reverb.wetDryMix = max(0, min(100, newValue * 100)) }
    }

    /// Bypass the echo unit entirely.
    var echoEnabled: Bool {
        get { !delay.bypass }
        set { delay.bypass = !newValue }
    }

    /// Bypass the reverb unit entirely.
    var reverbEnabled: Bool {
        get { !reverb.bypass }
        set { reverb.bypass = !newValue }
    }

    init(engine: AVAudioEngine) {
        self.engine = engine

        delay.delayTime = 0.5
        delay.feedback = 35
        delay.wetDryMix = 0
        delay.bypass = true

        reverb.loadFactoryPreset(.mediumHall)
        reverb.wetDryMix = 0
        reverb.bypass = true

        engine.attach(delay)
        engine.attach(reverb)
        engine.connect(delay, to: reverb, format: nil)
    }

    /// Set the echo's delay time from a beat-divider and an effective BPM.
    func setEchoBeatDivider(_ divider: Int, bpm: Double) {
        guard bpm > 0, divider > 0 else { return }
        let quarter = 60.0 / bpm
        let secondsPerNote = quarter * (4.0 / Double(divider))
        delay.delayTime = max(0, min(2.0, secondsPerNote))
    }

    /// Input node — connect upstream signal here.
    var input: AVAudioNode { delay }
    /// Output node — connect this to the deck's volume fader.
    var output: AVAudioNode { reverb }
}
