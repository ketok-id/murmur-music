import Foundation

struct OfficialNewsSource: Codable, Identifiable, Equatable {
    enum Kind: String, Codable { case youtube, tiktok }
    let id: UUID
    let kind: Kind
    /// Display label — YouTube channel title, or "@handle" for TikTok.
    var name: String
    /// What the fetcher needs: YouTube → the "UC…" channel id (RSS URL takes
    /// only ids, not handles); TikTok → the handle without "@".
    var feedKey: String
}

/// User-added official news feeds for the News tab — TikTok accounts and
/// YouTube channels merged into `WorldCupNewsStore` alongside the built-ins
/// (ESPN, FIFA's YouTube channel, @fifaworldcup). Same shape as
/// `WorldCupCustomSourcesStore`: JSON in UserDefaults, built-ins stay
/// hardcoded in the news store so removing user feeds can't break defaults.
final class WorldCupNewsSourcesStore: ObservableObject {
    static let shared = WorldCupNewsSourcesStore()
    private static let key = "youtube-audio-widget.worldcup.newsSources"

    @Published private(set) var items: [OfficialNewsSource]

    private static let browserUA =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36"

    private init() {
        let data = UserDefaults.standard.data(forKey: Self.key) ?? Data()
        items = (try? JSONDecoder().decode([OfficialNewsSource].self, from: data)) ?? []
    }

    /// One free-form input: a TikTok "@handle" (or tiktok.com URL), a YouTube
    /// channel URL, or a bare "UC…" channel id. Validates by fetching the
    /// feed once, so a typo never lands a permanently-dead source. Returns a
    /// user-facing error string, or nil on success.
    @MainActor
    func add(input: String) async -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Enter a TikTok @handle or a YouTube channel." }

        let lower = trimmed.lowercased()
        let isYouTube = lower.contains("youtube.com/") || lower.contains("youtu.be/")
            || trimmed.range(of: #"^UC[0-9A-Za-z_-]{22}$"#, options: .regularExpression) != nil

        if isYouTube { return await addYouTube(trimmed) }

        // Everything else is treated as TikTok: "@handle", "handle", or a
        // tiktok.com URL (`normalizedHandle` rejects anything that isn't one).
        let handle = TikTokFeedResolver.normalizedHandle(trimmed)
        guard !handle.isEmpty else {
            return "That doesn't look like a TikTok @handle or a YouTube channel."
        }
        if items.contains(where: { $0.kind == .tiktok && $0.feedKey.lowercased() == handle.lowercased() }) {
            return "@\(handle) is already in your feeds."
        }
        guard let videos = try? await TikTokFeedResolver.latestVideos(of: handle), !videos.isEmpty else {
            return "Couldn't read @\(handle)'s public TikTok feed."
        }
        items.append(OfficialNewsSource(id: UUID(), kind: .tiktok, name: "@\(handle)", feedKey: handle))
        persist()
        return nil
    }

    @MainActor
    private func addYouTube(_ input: String) async -> String? {
        var channelID: String? = nil
        var name: String? = nil

        if input.range(of: #"^UC[0-9A-Za-z_-]{22}$"#, options: .regularExpression) != nil {
            channelID = input
        } else if let range = input.range(of: #"/channel/(UC[0-9A-Za-z_-]{22})"#, options: .regularExpression) {
            channelID = String(input[range].dropFirst("/channel/".count))
        } else {
            // Handle / custom URL — one page fetch resolves the canonical id
            // (and the channel title for the label).
            var urlString = input
            if !urlString.lowercased().hasPrefix("http") { urlString = "https://" + urlString }
            guard let url = URL(string: urlString) else { return "That URL doesn't parse." }
            var request = URLRequest(url: url)
            request.setValue(Self.browserUA, forHTTPHeaderField: "User-Agent")
            guard let (data, _) = try? await URLSession.shared.data(for: request),
                  let html = String(data: data, encoding: .utf8),
                  let idRange = html.range(of: #""channelId":"UC[0-9A-Za-z_-]{22}""#, options: .regularExpression)
            else { return "Couldn't find a channel id at that URL." }
            channelID = String(html[idRange].dropFirst("\"channelId\":\"".count).dropLast(1))
            if let titleRange = html.range(of: #"<meta property="og:title" content="([^"]+)""#, options: .regularExpression) {
                name = String(html[titleRange]
                    .dropFirst(#"<meta property="og:title" content=""#.count).dropLast(1))
            }
        }

        guard let id = channelID else { return "Couldn't find a channel id at that URL." }
        if items.contains(where: { $0.kind == .youtube && $0.feedKey == id }) {
            return "That channel is already in your feeds."
        }
        // The RSS feed is the source of truth — verify it exists and grab the
        // channel title when the page didn't give one.
        guard let feedURL = URL(string: "https://www.youtube.com/feeds/videos.xml?channel_id=\(id)"),
              let (data, response) = try? await URLSession.shared.data(from: feedURL),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let xml = String(data: data, encoding: .utf8)
        else { return "That channel has no public uploads feed." }
        if name == nil,
           let titleRange = xml.range(of: #"<title>([^<]+)</title>"#, options: .regularExpression) {
            name = String(xml[titleRange].dropFirst("<title>".count).dropLast("</title>".count))
        }

        items.append(OfficialNewsSource(id: UUID(), kind: .youtube, name: name ?? "YouTube channel", feedKey: id))
        persist()
        return nil
    }

    func remove(id: UUID) {
        items.removeAll { $0.id == id }
        persist()
    }

    private func persist() {
        UserDefaults.standard.set(try? JSONEncoder().encode(items), forKey: Self.key)
    }
}
