import Foundation

/// One curated ambient source the user can pick from for an Ambient Layer channel.
struct AmbientSource: Codable, Equatable, Identifiable, Hashable {
    enum Kind: String, Codable {
        case rain, fire, cafe, nature, beats, vinyl, white
    }

    let id: String          // YouTube video ID
    let name: String
    let kind: Kind

    static let catalog: [AmbientSource] = [
        // Rain
        AmbientSource(id: "mPZkdNFkNps", name: "Rain on Window",            kind: .rain),
        AmbientSource(id: "qRTVg8HHzUo", name: "Heavy Rain & Thunder",      kind: .rain),
        AmbientSource(id: "q76bMs-NwRk", name: "Light Drizzle",             kind: .rain),
        AmbientSource(id: "yIQd2Ya0Ziw", name: "Rain in a Forest",          kind: .rain),
        AmbientSource(id: "RrkrdYm3HPQ", name: "Tent in a Storm",           kind: .rain),

        // Fire
        AmbientSource(id: "L_LUpnjgPso", name: "Fireplace Crackle",         kind: .fire),
        AmbientSource(id: "UgHKb_7884o", name: "Campfire at Night",         kind: .fire),
        AmbientSource(id: "rdc-bcQrZfY", name: "Wood Stove Ambience",       kind: .fire),
        AmbientSource(id: "L0MK7qz13bU", name: "Bonfire on the Beach",      kind: .fire),

        // Cafe
        AmbientSource(id: "BOdLmxy06H0", name: "Coffee Shop Ambience",      kind: .cafe),
        AmbientSource(id: "h2zkV-l_TbY", name: "Paris Cafe",                kind: .cafe),
        AmbientSource(id: "DeumyOzKqgI", name: "Library Whispers",          kind: .cafe),
        AmbientSource(id: "VTH7c-3VPCw", name: "Bookstore Ambience",        kind: .cafe),
        AmbientSource(id: "fOFzbgVQRMI", name: "Restaurant Murmur",         kind: .cafe),

        // Nature
        AmbientSource(id: "eKFTSSKCzWA", name: "Forest Birds",              kind: .nature),
        AmbientSource(id: "lTRiuFIWV54", name: "Ocean Waves",               kind: .nature),
        AmbientSource(id: "d0tU18Ybcvk", name: "Mountain Stream",           kind: .nature),
        AmbientSource(id: "OdIJ2x3nxzQ", name: "Distant Thunder Field",     kind: .nature),
        AmbientSource(id: "9zS9OdMzGqg", name: "Crickets at Dusk",          kind: .nature),
        AmbientSource(id: "xNN7iTA57jM", name: "Jungle at Dawn",            kind: .nature),

        // Beats
        AmbientSource(id: "jfKfPfyJRdk", name: "Lofi Girl — beats to study",kind: .beats),
        AmbientSource(id: "rUxyKA_-grg", name: "Lofi Girl — beats to sleep",kind: .beats),
        AmbientSource(id: "tNkZsRW7h2c", name: "ChilledCow Late Night",     kind: .beats),
        AmbientSource(id: "5qap5aO4i9A", name: "Lofi Hip Hop Radio",        kind: .beats),
        AmbientSource(id: "DWcJFNfaw9c", name: "Jazz Hop Cafe",             kind: .beats),
        AmbientSource(id: "4xDzrJKXOOY", name: "Synthwave Radio",           kind: .beats),

        // Vinyl
        AmbientSource(id: "n61ULEU7CO0", name: "Vinyl Crackle",             kind: .vinyl),
        AmbientSource(id: "Q0jXavyolwk", name: "Old Record Player",         kind: .vinyl),
        AmbientSource(id: "qK7-XGM6jrI", name: "Tape Hiss",                 kind: .vinyl),
        AmbientSource(id: "5XK7QmqlpoY", name: "Cassette Warmth",           kind: .vinyl),

        // Noise
        AmbientSource(id: "nMfPqeZjc2c", name: "Brown Noise",               kind: .white),
        AmbientSource(id: "vGUTFOLYIEM", name: "Pink Noise",                kind: .white),
        AmbientSource(id: "WPnUNXuyA1Y", name: "White Noise",               kind: .white),
        AmbientSource(id: "wAPCSnAhhC8", name: "Fan Noise",                 kind: .white),
        AmbientSource(id: "Q4fHCqr0V0w", name: "Airplane Cabin",            kind: .white),
        AmbientSource(id: "OkahfaPGOps", name: "Train Carriage",            kind: .white),
    ]

    /// Pretty kind label for UI.
    var kindLabel: String {
        switch kind {
        case .rain:    return "Rain"
        case .fire:    return "Fire"
        case .cafe:    return "Cafe"
        case .nature:  return "Nature"
        case .beats:   return "Beats"
        case .vinyl:   return "Vinyl"
        case .white:   return "Noise"
        }
    }
}
