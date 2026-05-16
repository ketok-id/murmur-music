import Foundation

/// One hot-cue: a time offset on a track plus a color tag.
///
/// `colorHex` is a CSS-style 6-char hex string (e.g. "ff6b6b"). Stored as
/// hex rather than RGBA floats so the JSON cache stays human-readable.
struct HotCue: Codable, Equatable, Identifiable {
    /// Pad index 0…7.
    let id: Int
    /// Seconds offset into the track.
    var seconds: Double
    /// CSS-style hex (no leading #).
    var colorHex: String

    /// Default palette indexed by pad id.
    static let defaultPalette: [String] = [
        "ff6b6b", "fbbf77", "ffe066", "6ee7ff",
        "a78bfa", "ff7ab6", "5eead4", "f97316",
    ]

    static func defaultColor(for id: Int) -> String {
        defaultPalette[id % defaultPalette.count]
    }
}
