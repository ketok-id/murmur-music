import Foundation

/// A serialized snapshot of the full mixer state.
struct Scene: Codable, Equatable, Identifiable {
    let id: UUID
    var name: String

    var crossfade: Float
    var masterVolume: Float

    var deck1: DeckSnapshot
    var deck2: DeckSnapshot

    var ambient1Source: String?
    var ambient1Volume: Float
    var ambient1Muted: Bool
    var ambient2Source: String?
    var ambient2Volume: Float
    var ambient2Muted: Bool

    var moodAngle: Double
}

/// Per-deck portion of a scene.
struct DeckSnapshot: Codable, Equatable {
    var volume: Float
    var lowGain: Float
    var midGain: Float
    var highGain: Float
    var filter: Float
    var tempoRate: Float
    var keyLock: Bool
    var echoEnabled: Bool
    var echoWet: Float
    var echoDivider: Int
    var reverbEnabled: Bool
    var reverbWet: Float
}
