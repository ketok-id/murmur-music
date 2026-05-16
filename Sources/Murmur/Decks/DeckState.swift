import Combine
import Foundation

/// Observable state for one deck. UI binds to this; `DeckController` writes to it.
///
/// `volume`, `lowGain`, `midGain`, `highGain`, `filter` are mirrored into the
/// `ChannelStrip` by `DeckController`. The UI never touches the strip directly.
final class DeckState: ObservableObject {
    @Published var displayName: String = "—"
    @Published var isLoaded: Bool = false
    @Published var isPlaying: Bool = false
    @Published var currentTimeSeconds: Double = 0
    @Published var durationSeconds: Double = 0

    /// 0…1.5. 1.0 = unity.
    @Published var volume: Float = 1.0
    /// dB, -24…+24.
    @Published var lowGain: Float = 0
    @Published var midGain: Float = 0
    @Published var highGain: Float = 0
    /// -1…+1. 0 = bypass; +1 = HPF closed; -1 = LPF closed.
    @Published var filter: Float = 0

    // ── Phase 2a: analysis + beatmatching ─────────────────────────────────

    /// Detected BPM, or 0 if not yet analyzed.
    @Published var bpm: Double = 0
    /// Seconds offset to the first downbeat (user-adjustable post-analysis).
    @Published var firstBeat: Double = 0
    /// Waveform peaks: interleaved min/max pairs. Empty until analysis completes.
    @Published var peaks: [Float] = []

    /// Tempo rate, 0.92…1.08 for ±8%. 1.0 = unmodified.
    @Published var tempoRate: Float = 1.0
    /// When true, tempo changes preserve pitch (uses TimePitch.rate only).
    /// When false, varispeed: pitch shifts with rate.
    @Published var keyLock: Bool = true
    /// True when this deck is the sync master.
    @Published var isMaster: Bool = false

    // ── Phase 2b: performance controls ────────────────────────────────────

    /// Hot cues for the currently loaded track.
    @Published var hotCues: [HotCue] = []
    /// Observable loop state.
    let loop = LoopState()

    // ── Phase 3: effects + key display ────────────────────────────────────

    /// Musical key name (e.g. "D minor"), empty if not yet detected.
    @Published var keyName: String = ""
    /// Camelot wheel notation (e.g. "7A"), empty if not yet detected.
    @Published var camelot: String = ""

    /// Echo on/off.
    @Published var echoEnabled: Bool = false
    /// Echo wet/dry, 0…1.
    @Published var echoWet: Float = 0.3
    /// Beat divider for echo time: 4 = quarter, 8 = eighth, 16 = 16th.
    @Published var echoDivider: Int = 8

    /// Reverb on/off.
    @Published var reverbEnabled: Bool = false
    /// Reverb wet/dry, 0…1.
    @Published var reverbWet: Float = 0.3

    // ── Phase 5: track metadata + artwork ─────────────────────────────────

    /// Track title from metadata. Falls back to filename if empty.
    @Published var title: String = ""
    @Published var artist: String = ""
    @Published var album: String = ""
    /// Filename of artwork PNG in `LibraryIndex.artworkDirectory`. Empty = no art.
    @Published var artworkPath: String = ""

    /// Interleaved low/mid/high band energies per peak bin, 0..1 normalized.
    /// Empty when not yet analyzed.
    @Published var bandPeaks: [Float] = []
}
