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
        AmbientSource(id: "mPZkdNFkNps", name: "Rain on Window",          kind: .rain),
        AmbientSource(id: "qRTVg8HHzUo", name: "Heavy Rain & Thunder",    kind: .rain),
        AmbientSource(id: "L_LUpnjgPso", name: "Fireplace Crackle",       kind: .fire),
        AmbientSource(id: "BOdLmxy06H0", name: "Coffee Shop Ambience",    kind: .cafe),
        AmbientSource(id: "eKFTSSKCzWA", name: "Forest Birds",            kind: .nature),
        AmbientSource(id: "lTRiuFIWV54", name: "Ocean Waves",             kind: .nature),
        AmbientSource(id: "jfKfPfyJRdk", name: "Lofi Girl Stream",        kind: .beats),
        AmbientSource(id: "n61ULEU7CO0", name: "Vinyl Crackle",           kind: .vinyl),
        AmbientSource(id: "nMfPqeZjc2c", name: "Brown Noise",             kind: .white),
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
