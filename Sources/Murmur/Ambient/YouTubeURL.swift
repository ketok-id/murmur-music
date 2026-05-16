import Foundation

/// Tolerant YouTube URL → video ID parser.
enum YouTubeURL {
    private static let idLength = 11
    private static let idCharSet = CharacterSet.alphanumerics
        .union(CharacterSet(charactersIn: "-_"))

    static func parse(_ input: String) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }

        if trimmed.count == idLength && trimmed.unicodeScalars.allSatisfy({ idCharSet.contains($0) }) {
            return trimmed
        }

        let urlString: String
        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
            urlString = trimmed
        } else if trimmed.hasPrefix("youtu.be/") || trimmed.hasPrefix("youtube.com/") || trimmed.hasPrefix("www.youtube.com/") {
            urlString = "https://" + trimmed
        } else {
            return nil
        }
        guard let url = URL(string: urlString) else { return nil }
        let host = (url.host ?? "").lowercased()

        if host == "youtu.be" {
            return extractIDFromPath(url.path)
        }

        if host.hasSuffix("youtube.com") {
            let path = url.path
            if path == "/watch" {
                if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                   let item = components.queryItems?.first(where: { $0.name == "v" }),
                   let v = item.value,
                   isValidID(v) {
                    return v
                }
            }
            for prefix in ["/embed/", "/shorts/", "/live/"] {
                if path.hasPrefix(prefix) {
                    let id = String(path.dropFirst(prefix.count))
                    if let extracted = extractIDFromPath("/" + id) {
                        return extracted
                    }
                }
            }
        }

        return nil
    }

    private static func extractIDFromPath(_ path: String) -> String? {
        let parts = path.split(separator: "/", omittingEmptySubsequences: true)
        guard let first = parts.first else { return nil }
        let candidate = String(first)
        let cleaned = candidate.split(separator: "?").first.map(String.init) ?? candidate
        return isValidID(cleaned) ? cleaned : nil
    }

    private static func isValidID(_ s: String) -> Bool {
        s.count == idLength && s.unicodeScalars.allSatisfy { idCharSet.contains($0) }
    }
}
