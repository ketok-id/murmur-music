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
}
