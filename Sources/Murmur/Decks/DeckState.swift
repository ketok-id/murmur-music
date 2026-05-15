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
}
