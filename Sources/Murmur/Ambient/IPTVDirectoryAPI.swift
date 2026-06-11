import Foundation

struct IPTVChannel: Identifiable {
    let name: String          // display name, annotations stripped
    let streamURL: URL
    let logoURL: URL?
    let group: String         // "News", "General", … (m3u group-title)
    let quality: String       // "1080p" / "" — parsed from the raw name
    let flags: [String]       // "Geo-blocked", "Not 24/7", …

    var id: String { streamURL.absoluteString }

    /// "News · 1080p · Geo-blocked"
    var subtitle: String {
        var parts: [String] = []
        if !group.isEmpty { parts.append(group) }
        if !quality.isEmpty { parts.append(quality) }
        parts.append(contentsOf: flags)
        return parts.joined(separator: " · ")
    }
}

struct IPTVCountry: Identifiable, Decodable {
    let name: String
    let code: String
    let flag: String

    var id: String { code }
}

/// iptv-org directory client — the community-maintained index of publicly
/// available TV streams (same project whose Indonesia list pointed us at
/// TVRI's official origin). Key-less static files on GitHub Pages:
///   - countries:  iptv-org.github.io/api/countries.json
///   - channels:   iptv-org.github.io/iptv/countries/<code>.m3u
/// The per-country playlists exclude NSFW content (that lives in a separate
/// opt-in list upstream). Streams are whatever broadcasters publish — some
/// are geo-locked or off-air, which the rows surface via name annotations.
enum IPTVDirectoryAPI {
    enum IPTVError: Error { case badResponse }

    private static var cachedCountries: [IPTVCountry] = []

    static func countries() async throws -> [IPTVCountry] {
        if !cachedCountries.isEmpty { return cachedCountries }
        guard let url = URL(string: "https://iptv-org.github.io/api/countries.json") else {
            throw IPTVError.badResponse
        }
        let (data, _) = try await URLSession.shared.data(from: url)
        let list = try JSONDecoder().decode([IPTVCountry].self, from: data)
        cachedCountries = list
        return list
    }

    static func channels(country code: String) async throws -> [IPTVChannel] {
        guard let url = URL(string: "https://iptv-org.github.io/iptv/countries/\(code.lowercased()).m3u") else {
            throw IPTVError.badResponse
        }
        let (data, response) = try await URLSession.shared.data(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let text = String(data: data, encoding: .utf8)
        else { throw IPTVError.badResponse }
        return parse(m3u: text)
    }

    // MARK: - M3U parsing

    /// `#EXTINF:-1 tvg-logo="…" group-title="…",Name (1080p) [Geo-blocked]`
    /// followed by the stream URL on the next non-comment line.
    static func parse(m3u: String) -> [IPTVChannel] {
        var channels: [IPTVChannel] = []
        var pendingInfo: String? = nil

        // components(separatedBy: .newlines), NOT split(separator: "\n") —
        // the playlists ship CRLF, and Swift treats "\r\n" as a single
        // Character, so a "\n" split never matches and the whole file
        // arrives as one "line". CharacterSet splitting works on scalars.
        for rawLine in m3u.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            if line.hasPrefix("#EXTINF") {
                pendingInfo = line
            } else if !line.hasPrefix("#"), let info = pendingInfo {
                pendingInfo = nil
                guard let streamURL = URL(string: line),
                      let channel = channel(from: info, streamURL: streamURL)
                else { continue }
                channels.append(channel)
            }
        }
        return channels
    }

    private static func channel(from info: String, streamURL: URL) -> IPTVChannel? {
        // Name sits after the attribute block: after the last `",` when
        // attributes exist, else after the first comma.
        let rawName: String
        if let r = info.range(of: "\",", options: .backwards) {
            rawName = String(info[r.upperBound...]).trimmingCharacters(in: .whitespaces)
        } else if let comma = info.firstIndex(of: ",") {
            rawName = String(info[info.index(after: comma)...]).trimmingCharacters(in: .whitespaces)
        } else {
            return nil
        }
        guard !rawName.isEmpty else { return nil }

        var name = rawName
        var quality = ""
        var flags: [String] = []
        if let r = name.range(of: #"\(([0-9]+[pi])\)"#, options: .regularExpression) {
            quality = String(name[r]).trimmingCharacters(in: CharacterSet(charactersIn: "()"))
        }
        for match in matches(of: #"\[([^\]]+)\]"#, in: name) {
            flags.append(match)
        }
        name = name
            .replacingOccurrences(of: #"\s*\([0-9]+[pi]\)"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s*\[[^\]]+\]"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)

        return IPTVChannel(
            name: name.isEmpty ? rawName : name,
            streamURL: streamURL,
            logoURL: attribute("tvg-logo", in: info).flatMap(URL.init(string:)),
            group: attribute("group-title", in: info) ?? "",
            quality: quality,
            flags: flags
        )
    }

    private static func attribute(_ key: String, in line: String) -> String? {
        guard let r = line.range(of: "\(key)=\"") else { return nil }
        let rest = line[r.upperBound...]
        guard let end = rest.firstIndex(of: "\"") else { return nil }
        let value = String(rest[..<end])
        return value.isEmpty ? nil : value
    }

    private static func matches(of pattern: String, in text: String) -> [String] {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return re.matches(in: text, range: range).compactMap { m in
            guard m.numberOfRanges > 1, let r = Range(m.range(at: 1), in: text) else { return nil }
            return String(text[r])
        }
    }
}
