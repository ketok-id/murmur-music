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
        default: return .other
        }
    }
}
