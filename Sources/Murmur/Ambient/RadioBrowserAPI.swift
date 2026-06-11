import Foundation

struct RadioStation: Identifiable, Equatable {
    let uuid: String
    let name: String
    let streamURL: URL
    let faviconURL: URL?
    let tags: String
    let countryCode: String
    let codec: String
    let bitrate: Int

    var id: String { uuid }

    /// "jazz, smooth · MP3 320 · US" — the row's subtitle.
    var subtitle: String {
        var parts: [String] = []
        if !tags.isEmpty {
            parts.append(tags.split(separator: ",").prefix(3).joined(separator: ", "))
        }
        if !codec.isEmpty { parts.append(bitrate > 0 ? "\(codec) \(bitrate)" : codec) }
        if !countryCode.isEmpty { parts.append(countryCode) }
        return parts.joined(separator: " · ")
    }
}

/// radio-browser.info client — community directory of ~58k internet radio
/// stations, key-less. Honors the project's fair-use contract:
///   1. a "speaking" User-Agent,
///   2. server discovery via `all.api.radio-browser.info/json/servers`
///      (randomized, cached per session; never hardcode one mirror as the
///      only option),
///   3. a click report per station play (`/json/url/{uuid}`) — that's what
///      feeds the popularity ranking everyone's results are ordered by.
enum RadioBrowserAPI {
    enum RadioError: Error { case badResponse }

    private static let userAgent = "Murmur/macOS (https://github.com/ketok-id/murmur-music)"
    private static var cachedServer: String?

    /// Stations matching a free-text name, a tag, and/or a country — top
    /// results by community click count, broken stations filtered out.
    static func search(
        name: String? = nil,
        tag: String? = nil,
        countryCode: String? = nil,
        limit: Int = 30
    ) async throws -> [RadioStation] {
        var components = URLComponents()
        components.scheme = "https"
        components.host = await server()
        components.path = "/json/stations/search"
        var items = [
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "hidebroken", value: "true"),
            URLQueryItem(name: "order", value: "clickcount"),
            URLQueryItem(name: "reverse", value: "true"),
        ]
        if let name, !name.isEmpty { items.append(URLQueryItem(name: "name", value: name)) }
        if let tag, !tag.isEmpty { items.append(URLQueryItem(name: "tag", value: tag)) }
        if let countryCode, !countryCode.isEmpty {
            items.append(URLQueryItem(name: "countrycode", value: countryCode))
        }
        components.queryItems = items
        guard let url = components.url else { throw RadioError.badResponse }

        let (data, _) = try await URLSession.shared.data(for: request(url))
        let raw = try JSONDecoder().decode([RawStation].self, from: data)
        return raw.compactMap { s -> RadioStation? in
            guard let streamURL = URL(string: s.url_resolved), !s.name.isEmpty else { return nil }
            return RadioStation(
                uuid: s.stationuuid,
                name: s.name.trimmingCharacters(in: .whitespacesAndNewlines),
                streamURL: streamURL,
                faviconURL: s.favicon.isEmpty ? nil : URL(string: s.favicon),
                tags: s.tags,
                countryCode: s.countrycode,
                codec: s.codec,
                bitrate: s.bitrate
            )
        }
    }

    /// Fire-and-forget play report — feeds the directory's popularity data.
    static func reportClick(uuid: String) {
        Task {
            let host = await server()
            guard let url = URL(string: "https://\(host)/json/url/\(uuid)") else { return }
            _ = try? await URLSession.shared.data(for: request(url))
        }
    }

    // MARK: - Plumbing

    private static func request(_ url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        return request
    }

    /// Discover the API servers and stick with one random pick per session;
    /// falls back to de1 if discovery itself is unreachable.
    private static func server() async -> String {
        if let cachedServer { return cachedServer }
        var hosts = ["de1.api.radio-browser.info"]
        if let url = URL(string: "https://all.api.radio-browser.info/json/servers"),
           let (data, _) = try? await URLSession.shared.data(for: request(url)),
           let list = try? JSONDecoder().decode([ServerEntry].self, from: data) {
            let names = Set(list.map(\.name)).filter { !$0.isEmpty }
            if !names.isEmpty { hosts = Array(names) }
        }
        let chosen = hosts.randomElement() ?? "de1.api.radio-browser.info"
        cachedServer = chosen
        return chosen
    }

    private struct ServerEntry: Decodable { let name: String }

    private struct RawStation: Decodable {
        let stationuuid: String
        let name: String
        let url_resolved: String
        let favicon: String
        let tags: String
        let countrycode: String
        let codec: String
        let bitrate: Int
    }
}
