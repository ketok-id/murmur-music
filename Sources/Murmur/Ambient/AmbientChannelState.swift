import Foundation

/// Observable state for one Ambient Layer channel.
final class AmbientChannelState: ObservableObject {
    /// nil = empty slot (no source loaded).
    @Published var source: AmbientSource? = nil
    /// Per-channel volume 0…1. Final audible volume is `volume * moodBias`.
    @Published var volume: Float = 0.6
    @Published var muted: Bool = false

    /// Effective base volume considering mute.
    var baseGain: Float { muted ? 0 : volume }
}
