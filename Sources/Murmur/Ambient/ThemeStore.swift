import SwiftUI

/// Accent theme — the one knob behind the site's "highly customizable"
/// promise that's safe to expose: every accent-colored token in the app
/// resolves through `MurmurColor.accent`/`accentLight`/`glow`, which read
/// this store's cached colors.
///
/// The main panel observes the store so a change applies live there;
/// auxiliary windows pick it up on their next open (cheap and good enough —
/// no environment plumbing through every scene).
final class ThemeStore: ObservableObject {
    static let shared = ThemeStore()
    private static let key = "youtube-audio-widget.theme.accent"

    struct Accent: Identifiable, Equatable {
        let name: String
        let base: String    // hex
        let light: String   // hex, hover/active variant
        var id: String { name }
    }

    /// First entry is the shipped default (the original Murmur ember).
    static let accents: [Accent] = [
        Accent(name: "Ember",  base: "#FF9F6E", light: "#FFC19C"),
        Accent(name: "Ocean",  base: "#6EC1FF", light: "#9CD8FF"),
        Accent(name: "Mint",   base: "#7FE0B2", light: "#A9F0CD"),
        Accent(name: "Violet", base: "#B79CFF", light: "#D2C1FF"),
        Accent(name: "Rose",   base: "#FF8FB1", light: "#FFB3CB"),
        Accent(name: "Gold",   base: "#F5C25B", light: "#FFDB8E"),
    ]

    @Published private(set) var accent: Accent

    /// Cached Colors so `MurmurColor`'s static reads stay allocation-free.
    private(set) var accentColor: Color
    private(set) var accentLightColor: Color
    private(set) var glowColor: Color

    private init() {
        let savedName = UserDefaults.standard.string(forKey: Self.key) ?? ""
        let chosen = Self.accents.first { $0.name == savedName } ?? Self.accents[0]
        accent = chosen
        accentColor = Color.murmurHex(chosen.base)
        accentLightColor = Color.murmurHex(chosen.light)
        glowColor = Color.murmurHex(chosen.base).opacity(0.35)
    }

    func select(_ chosen: Accent) {
        accent = chosen
        accentColor = Color.murmurHex(chosen.base)
        accentLightColor = Color.murmurHex(chosen.light)
        glowColor = Color.murmurHex(chosen.base).opacity(0.35)
        UserDefaults.standard.set(chosen.name, forKey: Self.key)
    }
}
