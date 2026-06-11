import Foundation

/// Key-less YouTube search/browse. `YouTubeSearchAPI` delegates here whenever
/// no Data API key is configured, so search works out of the box — the
/// `YouTubeLiveResolver` scrape approach, generalized.
///
/// Three techniques (all verified June 2026):
///   - Search + channel search: parse the `ytInitialData` JSON embedded in
///     `/results` HTML (`videoRenderer` / `channelRenderer` entries).
///   - Playlists + channel uploads: POST the page's own InnerTube
///     `youtubei/v1/browse` endpoint (public, baked into every YouTube page,
///     no user credential) — logged-out playlist HTML no longer embeds items;
///     the browse response carries them as `lockupViewModel`s.
///   - Channel resolution: channel-page HTML (`"channelId":"UC…"` + og: tags),
///     with the `UC…` → `UU…` uploads-playlist derivation.
///
/// Capability vs the Data API: first page only (~20 search results, ~100
/// playlist items, no pageToken), durations only where the markup carries
/// them, and **no trending** — YouTube retired the public trending feed, so
/// that one genuinely needs a key.
enum YouTubeSearchScraper {
    enum ScrapeError: Error, LocalizedError {
        case badPage
        case channelNotFound

        var errorDescription: String? {
            switch self {
            case .badPage:         return "YouTube returned an unexpected page."
            case .channelNotFound: return "Couldn't find that channel."
            }
        }
    }

    private static let browserUA =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36"

    // MARK: - Search (videos / channels)

    static func search(query: String, maxResults: Int = 20) async throws -> [YTSearchResult] {
        let escaped = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        guard let url = URL(string: "https://www.youtube.com/results?search_query=\(escaped)") else {
            throw ScrapeError.badPage
        }
        let root = try await initialData(from: url)
        var seen = Set<String>()
        return collect(key: "videoRenderer", in: root)
            .compactMap(videoResult(from:))
            .filter { seen.insert($0.videoID).inserted }
            .prefix(maxResults)
            .map { $0 }
    }

    static func searchChannels(query: String, maxResults: Int = 10) async throws -> [YTChannelResult] {
        let escaped = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        // sp=EgIQAg%3D%3D is the protobuf-encoded "type: channel" filter chip.
        guard let url = URL(string: "https://www.youtube.com/results?search_query=\(escaped)&sp=EgIQAg%3D%3D") else {
            throw ScrapeError.badPage
        }
        let root = try await initialData(from: url)
        var seen = Set<String>()
        return collect(key: "channelRenderer", in: root)
            .compactMap { r -> YTChannelResult? in
                guard let id = r["channelId"] as? String,
                      let title = text(r["title"]) else { return nil }
                var thumb: URL? = nil
                if let t = r["thumbnail"] as? [String: Any],
                   let list = t["thumbnails"] as? [[String: Any]],
                   var urlString = list.last?["url"] as? String {
                    if urlString.hasPrefix("//") { urlString = "https:" + urlString }
                    thumb = URL(string: urlString)
                }
                return YTChannelResult(channelId: id, title: title, thumbnailURL: thumb)
            }
            .filter { seen.insert($0.channelId).inserted }
            .prefix(maxResults)
            .map { $0 }
    }

    // MARK: - Playlists / channel uploads (InnerTube browse)

    /// Works for `PL…` playlists and `UU…` uploads lists alike. First ~100
    /// items, no pagination.
    static func playlistItems(playlistId: String) async throws -> [YTSearchResult] {
        guard let url = URL(string: "https://www.youtube.com/youtubei/v1/browse") else {
            throw ScrapeError.badPage
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(browserUA, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "context": ["client": ["clientName": "WEB", "clientVersion": "2.20250520.01.00", "hl": "en"]],
            "browseId": "VL\(playlistId)",
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, _) = try await URLSession.shared.data(for: request)
        guard let root = try? JSONSerialization.jsonObject(with: data) else { throw ScrapeError.badPage }

        var seen = Set<String>()
        // New UI ships lockupViewModels; keep the legacy renderer as a
        // fallback for whichever shape YouTube serves.
        let lockups = collect(key: "lockupViewModel", in: root).compactMap(lockupResult(from:))
        let legacy = collect(key: "playlistVideoRenderer", in: root).compactMap(videoResult(from:))
        return (lockups + legacy).filter { seen.insert($0.videoID).inserted }
    }

    // MARK: - Channel resolution

    static func channelByHandle(_ handle: String) async throws
        -> (channelId: String, title: String, thumbnailURL: URL?, uploadsPlaylistId: String) {
        let clean = handle.hasPrefix("@") ? handle : "@" + handle
        guard let url = URL(string: "https://www.youtube.com/\(clean)") else { throw ScrapeError.channelNotFound }
        let html = try await fetchHTML(url)
        guard let idRange = html.range(of: #""channelId":"UC[0-9A-Za-z_-]{22}""#, options: .regularExpression) else {
            throw ScrapeError.channelNotFound
        }
        let channelId = String(html[idRange].dropFirst("\"channelId\":\"".count).dropLast(1))
        return (
            channelId: channelId,
            title: ogContent("og:title", in: html) ?? clean,
            thumbnailURL: ogContent("og:image", in: html).flatMap(URL.init(string:)),
            uploadsPlaylistId: uploadsPlaylist(for: channelId)
        )
    }

    static func channelDetails(channelId: String) async throws
        -> (title: String, thumbnailURL: URL?, uploadsPlaylistId: String) {
        guard let url = URL(string: "https://www.youtube.com/channel/\(channelId)") else {
            throw ScrapeError.channelNotFound
        }
        let html = try await fetchHTML(url)
        guard let title = ogContent("og:title", in: html) else { throw ScrapeError.channelNotFound }
        return (
            title: title,
            thumbnailURL: ogContent("og:image", in: html).flatMap(URL.init(string:)),
            uploadsPlaylistId: uploadsPlaylist(for: channelId)
        )
    }

    /// A channel's uploads playlist is its id with the `UC` prefix swapped
    /// for `UU` — a stable YouTube invariant, no lookup needed.
    private static func uploadsPlaylist(for channelId: String) -> String {
        channelId.hasPrefix("UC") ? "UU" + channelId.dropFirst(2) : channelId
    }

    // MARK: - Renderer → result mapping

    private static func videoResult(from r: [String: Any]) -> YTSearchResult? {
        guard let id = r["videoId"] as? String,
              let title = text(r["title"]), !title.isEmpty
        else { return nil }
        var result = YTSearchResult(
            videoID: id,
            title: title,
            channelTitle: text(r["ownerText"]) ?? text(r["shortBylineText"]) ?? "",
            thumbnailURL: URL(string: "https://i.ytimg.com/vi/\(id)/mqdefault.jpg")
        )
        if let clock = text(r["lengthText"]), let seconds = parseClock(clock) {
            result.duration = seconds          // absent on live streams
        } else if let lengthSeconds = r["lengthSeconds"] as? String, let s = TimeInterval(lengthSeconds) {
            result.duration = s                // playlistVideoRenderer shape
        }
        result.categoryHint = VideoCategoryHint.classify(categoryId: "", title: title)
        return result
    }

    private static func lockupResult(from r: [String: Any]) -> YTSearchResult? {
        guard (r["contentType"] as? String) == "LOCKUP_CONTENT_TYPE_VIDEO",
              let id = r["contentId"] as? String
        else { return nil }
        let metadata = (r["metadata"] as? [String: Any])?["lockupMetadataViewModel"] as? [String: Any]
        let title = ((metadata?["title"] as? [String: Any])?["content"] as? String) ?? ""
        guard !title.isEmpty else { return nil }
        // First metadata row is the byline ("HYBE LABELS", "Lofi Girl", …).
        var channel = ""
        if let rows = (((metadata?["metadata"] as? [String: Any])?["contentMetadataViewModel"]
                        as? [String: Any])?["metadataRows"]) as? [[String: Any]],
           let parts = rows.first?["metadataParts"] as? [[String: Any]],
           let first = (parts.first?["text"] as? [String: Any])?["content"] as? String {
            channel = first
        }
        var result = YTSearchResult(
            videoID: id,
            title: title,
            channelTitle: channel,
            thumbnailURL: URL(string: "https://i.ytimg.com/vi/\(id)/mqdefault.jpg")
        )
        result.categoryHint = VideoCategoryHint.classify(categoryId: "", title: title)
        return result
    }

    // MARK: - ytInitialData plumbing

    private static func fetchHTML(_ url: URL) async throws -> String {
        var request = URLRequest(url: url)
        request.setValue(browserUA, forHTTPHeaderField: "User-Agent")
        request.setValue("en", forHTTPHeaderField: "Accept-Language")
        // Skips the EU consent interstitial, which otherwise replaces the page.
        request.setValue("CONSENT=YES+cb; SOCS=CAI", forHTTPHeaderField: "Cookie")
        let (data, _) = try await URLSession.shared.data(for: request)
        guard let html = String(data: data, encoding: .utf8) else { throw ScrapeError.badPage }
        return html
    }

    /// The embedded JSON ends at the literal `;</script>` — safe because
    /// YouTube escapes `<` as `<` inside JSON string values.
    private static func initialData(from url: URL) async throws -> Any {
        let html = try await fetchHTML(url)
        guard let start = html.range(of: "var ytInitialData = "),
              let end = html.range(of: ";</script>", range: start.upperBound..<html.endIndex),
              let data = String(html[start.upperBound..<end.lowerBound]).data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data)
        else { throw ScrapeError.badPage }
        return root
    }

    /// Every dictionary stored under `key`, anywhere in the tree. Array
    /// traversal preserves YouTube's result ordering; renderers of interest
    /// always live in `contents` arrays.
    private static func collect(key: String, in root: Any) -> [[String: Any]] {
        var out: [[String: Any]] = []
        func walk(_ node: Any) {
            if let dict = node as? [String: Any] {
                if let hit = dict[key] as? [String: Any] { out.append(hit) }
                for (_, value) in dict { walk(value) }
            } else if let array = node as? [Any] {
                for value in array { walk(value) }
            }
        }
        walk(root)
        return out
    }

    /// "12:34" / "1:23:45" → seconds.
    private static func parseClock(_ s: String) -> TimeInterval? {
        let parts = s.split(separator: ":").map(String.init).compactMap(Double.init)
        guard parts.count >= 1, parts.count <= 3, parts.count == s.split(separator: ":").count else { return nil }
        return parts.reversed().enumerated().reduce(0) { $0 + $1.element * pow(60, Double($1.offset)) }
    }

    /// `simpleText` or joined `runs` from a YouTube text node.
    private static func text(_ any: Any?) -> String? {
        guard let dict = any as? [String: Any] else { return nil }
        if let simple = dict["simpleText"] as? String { return simple }
        if let runs = dict["runs"] as? [[String: Any]] {
            let joined = runs.compactMap { $0["text"] as? String }.joined()
            return joined.isEmpty ? nil : joined
        }
        return nil
    }

    private static func ogContent(_ property: String, in html: String) -> String? {
        guard let range = html.range(
            of: #"<meta property="\#(property)" content="([^"]*)""#,
            options: .regularExpression
        ) else { return nil }
        let match = String(html[range])
        guard let contentStart = match.range(of: "content=\"") else { return nil }
        return String(match[contentStart.upperBound...].dropLast())
    }
}
