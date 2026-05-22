import Foundation

enum VideoCategoryHint: String, Equatable {
    case music
    case podcast
    case talk
    case other

    var emoji: String {
        switch self {
        case .music:   return "🎵"
        case .podcast: return "🎙️"
        case .talk:    return "💬"
        case .other:   return ""
        }
    }

    static func classify(categoryId: String, title: String) -> VideoCategoryHint {
        let lower = title.lowercased()
        if lower.contains("podcast")
            || lower.range(of: #"\bepisode\s+\d"#, options: .regularExpression) != nil
            || lower.range(of: #"\bep[\s.]?\d"#, options: .regularExpression) != nil
            || lower.range(of: #"#\d{1,3}"#, options: .regularExpression) != nil {
            return .podcast
        }
        switch categoryId {
        case "10": return .music
        case "25", "27", "28": return .talk
        case "": return classifyFromTitle(lower: lower, original: title)
        default: return .other
        }
    }

    /// Title-only fallback when the caller doesn't have a YouTube categoryId.
    /// The IFrame embed API never exposes categoryId, so this drives the
    /// `categoryHint` published by `PlayerController`.
    private static func classifyFromTitle(lower: String, original: String) -> VideoCategoryHint {
        let musicMarkers = [
            "official video", "official music video", "official audio",
            "lyric video", "lyrics video", "official lyric", "(audio)",
            "music video", "visualizer",
        ]
        if musicMarkers.contains(where: { lower.contains($0) }) {
            return .music
        }
        if TrackQuery.split(TrackQuery.clean(original)) != nil {
            return .music
        }
        return .other
    }
}
