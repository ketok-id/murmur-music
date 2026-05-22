import Foundation

enum TrackQuery {
    static func clean(_ raw: String) -> String {
        var s = raw
        let noise: [String] = [
            #"\([^)]*\b(official|lyrics?|audio|video|mv|hd|4k|hq|visualizer|remaster(ed)?)\b[^)]*\)"#,
            #"\[[^\]]*\b(official|lyrics?|audio|video|mv|hd|4k|hq|visualizer|remaster(ed)?)\b[^\]]*\]"#,
            #"\s+\|\s+.*$"#,
            #"\s+(feat\.?|ft\.?)\s+.+$"#,
        ]
        for pattern in noise {
            s = s.replacingOccurrences(
                of: pattern,
                with: "",
                options: [.regularExpression, .caseInsensitive]
            )
        }
        return s
            .replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func split(_ cleaned: String) -> (artist: String, track: String)? {
        let separators = [" – ", " — ", " - "]
        for sep in separators {
            if let range = cleaned.range(of: sep) {
                let artist = String(cleaned[..<range.lowerBound])
                    .trimmingCharacters(in: .whitespaces)
                let track = String(cleaned[range.upperBound...])
                    .trimmingCharacters(in: .whitespaces)
                if !artist.isEmpty && !track.isEmpty {
                    return (artist, track)
                }
            }
        }
        return nil
    }
}
