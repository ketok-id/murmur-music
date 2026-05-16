import Foundation

enum YouTubeChannelURL {
    enum Result: Equatable {
        case channelId(String)
        case handle(String)
    }

    static func parse(_ input: String) -> Result? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }

        if isChannelId(trimmed) { return .channelId(trimmed) }
        if trimmed.hasPrefix("@"), trimmed.count >= 4 { return .handle(trimmed) }

        let urlString: String
        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
            urlString = trimmed
        } else if trimmed.hasPrefix("youtube.com/") || trimmed.hasPrefix("www.youtube.com/") || trimmed.hasPrefix("m.youtube.com/") {
            urlString = "https://" + trimmed
        } else {
            return nil
        }

        guard let url = URL(string: urlString) else { return nil }
        guard let host = url.host?.lowercased(), host.hasSuffix("youtube.com") else { return nil }

        let path = url.path
        if path.hasPrefix("/@") {
            let handle = String(path.dropFirst())
            return handle.count >= 4 ? .handle(handle) : nil
        }
        if path.hasPrefix("/channel/") {
            let id = String(path.dropFirst("/channel/".count))
                .split(separator: "/").first.map(String.init) ?? ""
            return isChannelId(id) ? .channelId(id) : nil
        }
        return nil
    }

    private static func isChannelId(_ s: String) -> Bool {
        guard s.hasPrefix("UC"), s.count == 24 else { return false }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        return s.unicodeScalars.allSatisfy { allowed.contains($0) }
    }
}
