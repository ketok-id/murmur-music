import Combine
import Foundation

/// Per-deck loop state. Observed by the UI; mutated by `DeckController`.
///
/// A loop is "armed" when both `inSeconds` and `outSeconds` are set.
/// `isActive` controls whether playback actually loops.
final class LoopState: ObservableObject {
    @Published var inSeconds: Double? = nil
    @Published var outSeconds: Double? = nil
    @Published var isActive: Bool = false

    /// True when both endpoints are set.
    var isArmed: Bool { inSeconds != nil && outSeconds != nil }

    /// Loop length in seconds, or nil if not fully set.
    var length: Double? {
        guard let i = inSeconds, let o = outSeconds, o > i else { return nil }
        return o - i
    }

    func clear() {
        inSeconds = nil
        outSeconds = nil
        isActive = false
    }
}
