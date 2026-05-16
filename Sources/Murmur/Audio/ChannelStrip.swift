import AVFoundation

/// One deck's audio chain.
///
/// Signal path: [SourcePlayer.outputNode]
///                   ↓
///               [eq3band]   3 parametric bands (low shelf, mid bell, high shelf)
///                   ↓
///               [filterEQ]  combined HP/LP filter sweep (one band, hp_lp mode)
///                   ↓
///               [volume]    AVAudioMixerNode used as a fader
///                   ↓
///        connected externally to either submixA or submixB
final class ChannelStrip {
    private let engine: AVAudioEngine

    /// 3-band EQ: low shelf @ 100Hz, mid bell @ 1kHz, high shelf @ 8kHz.
    let eq3band: AVAudioUnitEQ
    /// Single-band EQ used as a sweepable filter. Centre at 1kHz; mode toggled
    /// based on `filterPosition` sign (positive = HPF, negative = LPF).
    let filterEQ: AVAudioUnitEQ
    /// Final fader for the strip. Connect this to the desired group submixer.
    let volume = AVAudioMixerNode()

    /// EQ gains in dB, -24…+24 each.
    var lowGain: Float {
        get { eq3band.bands[0].gain }
        set { eq3band.bands[0].gain = max(-24, min(24, newValue)) }
    }
    var midGain: Float {
        get { eq3band.bands[1].gain }
        set { eq3band.bands[1].gain = max(-24, min(24, newValue)) }
    }
    var highGain: Float {
        get { eq3band.bands[2].gain }
        set { eq3band.bands[2].gain = max(-24, min(24, newValue)) }
    }

    /// Linear gain 0…1.5 (allows up to +3.5dB).
    var fader: Float {
        get { volume.outputVolume }
        set { volume.outputVolume = max(0, min(1.5, newValue)) }
    }

    /// Filter sweep -1…+1. -1 = full LPF cutoff ~100Hz, 0 = bypass,
    /// +1 = full HPF cutoff ~10kHz. Logarithmic mapping between.
    var filterPosition: Float = 0 {
        didSet { applyFilter(position: filterPosition) }
    }

    init(engine: AVAudioEngine) {
        self.engine = engine

        // --- 3-band EQ ---
        eq3band = AVAudioUnitEQ(numberOfBands: 3)
        let low = eq3band.bands[0]
        low.filterType = .lowShelf
        low.frequency = 100
        low.gain = 0
        low.bypass = false

        let mid = eq3band.bands[1]
        mid.filterType = .parametric
        mid.frequency = 1000
        mid.bandwidth = 1.0
        mid.gain = 0
        mid.bypass = false

        let high = eq3band.bands[2]
        high.filterType = .highShelf
        high.frequency = 8000
        high.gain = 0
        high.bypass = false

        // --- Filter EQ (single band, mode flipped per direction) ---
        filterEQ = AVAudioUnitEQ(numberOfBands: 1)
        let f = filterEQ.bands[0]
        f.filterType = .highPass
        f.frequency = 20
        f.bypass = true
        f.gain = 0

        engine.attach(eq3band)
        engine.attach(filterEQ)
        engine.attach(volume)

        // Internal connections: eq3band → filterEQ → volume.
        engine.connect(eq3band, to: filterEQ, format: nil)
        engine.connect(filterEQ, to: volume, format: nil)
    }

    /// Connect a source's output node into the head of this strip.
    func connectSource(_ source: SourcePlayer) {
        engine.connect(source.outputNode, to: eq3band, format: nil)
    }

    private func applyFilter(position: Float) {
        let p = max(-1, min(1, position))
        let band = filterEQ.bands[0]
        if abs(p) < 0.02 {
            band.bypass = true
            return
        }
        band.bypass = false
        if p > 0 {
            band.filterType = .highPass
            band.frequency = 100 * pow(100, p)
        } else {
            band.filterType = .lowPass
            band.frequency = 10000 * pow(100, p)
        }
    }
}
