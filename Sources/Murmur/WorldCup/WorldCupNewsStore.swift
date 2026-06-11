import Foundation

// MARK: - Model

struct WorldCupNewsItem: Identifiable {
    enum Kind { case article, video, tiktok }

    let id: String
    let kind: Kind
    let source: String        // "ESPN" / "FIFA" / "@fifaworldcup" / outlet name
    let headline: String
    let published: Date?
    let imageURL: URL?
    let link: URL?            // canonical web URL (browser open / fallback)
    let videoID: String?      // YouTube id — plays in Murmur via PlayerController
    let tiktokID: String?     // TikTok item id — plays in the TikTokWindow embed
}

// MARK: - Store

/// Multi-source World Cup news feed, all key-less:
///   - ESPN's World Cup news endpoint (articles — same host as the scoreboard)
///   - official YouTube channels via their public RSS feeds (FIFA built in,
///     plus user-added channels) — tapping these plays *inside* Murmur
///   - official TikTok accounts via the creator-embed scrape
///     (`TikTokFeedResolver`) — @fifaworldcup built in, plus user-added
///   - Google News RSS scoped to followed teams (one OR-query, ≤8 teams)
///
/// All sources fetch concurrently and fail independently — one outage never
/// blanks the tab, and `errorText` only fires when *everything* failed.
/// Fetched on first News-tab open, then throttled to one refresh per 5 min.
final class WorldCupNewsStore: ObservableObject {
    static let shared = WorldCupNewsStore()

    @Published private(set) var items: [WorldCupNewsItem] = []
    @Published private(set) var lastUpdated: Date? = nil
    @Published private(set) var isLoading = false
    @Published private(set) var errorText: String? = nil

    static let espnNewsURL = URL(string:
        "https://site.api.espn.com/apis/site/v2/sports/soccer/fifa.world/news")!

    /// FIFA's main channel — carries daily WC2026 pressers, highlights, shows.
    static let builtInYouTubeChannels: [(id: String, name: String)] =
        [("UCpcTrCXblq78GZrTUTLWeBw", "FIFA")]
    /// FIFA World Cup's verified TikTok (57M followers).
    static let builtInTikTokHandles = ["fifaworldcup"]

    private static let browserUA =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36"

    private init() {}

    func refresh(force: Bool = false) {
        if isLoading { return }
        if !force, let last = lastUpdated, Date().timeIntervalSince(last) < 300 { return }
        isLoading = true

        // Snapshot store-backed config on the main thread before going async.
        let userSources = WorldCupNewsSourcesStore.shared.items
        let teamNames = Self.followedTeamNames()

        Task {
            var collected: [[WorldCupNewsItem]] = []
            await withTaskGroup(of: [WorldCupNewsItem].self) { group in
                group.addTask { await Self.fetchESPN() }
                for channel in Self.builtInYouTubeChannels {
                    group.addTask { await Self.fetchYouTubeChannel(id: channel.id, fallbackName: channel.name) }
                }
                for handle in Self.builtInTikTokHandles {
                    group.addTask { await Self.fetchTikTok(handle: handle) }
                }
                for source in userSources {
                    switch source.kind {
                    case .youtube:
                        group.addTask { await Self.fetchYouTubeChannel(id: source.feedKey, fallbackName: source.name) }
                    case .tiktok:
                        group.addTask { await Self.fetchTikTok(handle: source.feedKey) }
                    }
                }
                if !teamNames.isEmpty {
                    group.addTask { await Self.fetchTeamNews(teamNames: teamNames) }
                }
                for await part in group { collected.append(part) }
            }

            var seen = Set<String>()
            let merged = collected
                .flatMap { $0 }
                .filter { seen.insert($0.id).inserted }
                .sorted { ($0.published ?? .distantPast) > ($1.published ?? .distantPast) }

            await MainActor.run {
                if merged.isEmpty {
                    // Total outage: keep whatever we had; only surface an error
                    // when there's nothing at all to show. lastUpdated stays
                    // unset so the next tab-open retries immediately.
                    if self.items.isEmpty {
                        self.errorText = "Couldn't load news — check your connection."
                    }
                } else {
                    self.items = merged
                    self.lastUpdated = Date()
                    self.errorText = nil
                }
                self.isLoading = false
            }
        }
    }

    /// Followed-team display names (ESPN abbrevs → names via the schedule
    /// already in memory). Capped at 8 to keep the Google News query sane;
    /// empty when nothing is followed or the schedule hasn't loaded yet.
    private static func followedTeamNames() -> [String] {
        let followed = WorldCupFollowStore.shared.followed
        guard !followed.isEmpty else { return [] }
        var names: [String: String] = [:]
        for match in WorldCupStore.shared.matches {
            names[match.home.abbrev] = match.home.name
            names[match.away.abbrev] = match.away.name
        }
        return Array(followed.compactMap { names[$0] }.sorted().prefix(8))
    }

    // MARK: - ESPN (articles)

    private static func fetchESPN() async -> [WorldCupNewsItem] {
        var request = URLRequest(url: espnNewsURL)
        request.setValue(browserUA, forHTTPHeaderField: "User-Agent")
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let root = try? JSONDecoder().decode(NewsRoot.self, from: data)
        else { return [] }
        return root.articles.compactMap { a -> WorldCupNewsItem? in
            guard let headline = a.headline, !headline.isEmpty else { return nil }
            return WorldCupNewsItem(
                id: (a.links?.web?.href ?? headline),
                kind: .article,
                source: "ESPN",
                headline: headline,
                published: a.published.flatMap(parseISODate),
                imageURL: a.images?.first?.url.flatMap(URL.init(string:)),
                link: (a.links?.web?.href).flatMap(URL.init(string:)),
                videoID: nil,
                tiktokID: nil
            )
        }
    }

    // MARK: - YouTube channel RSS (official video)

    /// `youtube.com/feeds/videos.xml?channel_id=UC…` — official, key-less,
    /// stable XML with the channel's 15 newest uploads.
    private static func fetchYouTubeChannel(id: String, fallbackName: String) async -> [WorldCupNewsItem] {
        guard let url = URL(string: "https://www.youtube.com/feeds/videos.xml?channel_id=\(id)"),
              let xml = await fetchString(url)
        else { return [] }

        // Feed-level <title> (the channel name) sits before the first <entry>.
        let head = xml.range(of: "<entry>").map { String(xml[..<$0.lowerBound]) } ?? xml
        let channelName = firstMatch(in: head, pattern: "<title>([^<]*)</title>")
            .map(unescapeXML) ?? fallbackName

        var items: [WorldCupNewsItem] = []
        var searchFrom = xml.startIndex
        while let entryStart = xml.range(of: "<entry>", range: searchFrom..<xml.endIndex),
              let entryEnd = xml.range(of: "</entry>", range: entryStart.upperBound..<xml.endIndex) {
            let entry = String(xml[entryStart.upperBound..<entryEnd.lowerBound])
            searchFrom = entryEnd.upperBound

            guard let videoID = firstMatch(in: entry, pattern: "<yt:videoId>([^<]+)</yt:videoId>"),
                  let title = firstMatch(in: entry, pattern: "<title>([^<]*)</title>").map(unescapeXML),
                  !title.isEmpty
            else { continue }
            items.append(WorldCupNewsItem(
                id: "yt:\(videoID)",
                kind: .video,
                source: channelName,
                headline: title,
                published: firstMatch(in: entry, pattern: "<published>([^<]+)</published>")
                    .flatMap(parseISODate),
                imageURL: firstMatch(in: entry, pattern: #"<media:thumbnail url="([^"]+)""#)
                    .flatMap(URL.init(string:)),
                link: URL(string: "https://www.youtube.com/watch?v=\(videoID)"),
                videoID: videoID,
                tiktokID: nil
            ))
        }
        return items
    }

    // MARK: - TikTok (official accounts)

    private static func fetchTikTok(handle: String) async -> [WorldCupNewsItem] {
        guard let videos = try? await TikTokFeedResolver.latestVideos(of: handle) else { return [] }
        return videos.map { v in
            WorldCupNewsItem(
                id: "tt:\(v.id)",
                kind: .tiktok,
                source: "@\(v.handle)",
                headline: v.caption.isEmpty ? "New post from @\(v.handle)" : v.caption,
                published: v.published,
                imageURL: v.coverURL,
                link: v.link,
                videoID: nil,
                tiktokID: v.id
            )
        }
    }

    // MARK: - Google News RSS (followed-team press)

    private static func fetchTeamNews(teamNames: [String]) async -> [WorldCupNewsItem] {
        let quoted = teamNames.map { "\"\($0)\"" }.joined(separator: " OR ")
        let query = "(\(quoted)) World Cup when:7d"
        guard let escaped = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://news.google.com/rss/search?q=\(escaped)&hl=en-US&gl=US&ceid=US:en"),
              let xml = await fetchString(url)
        else { return [] }

        var items: [WorldCupNewsItem] = []
        var searchFrom = xml.startIndex
        while items.count < 15,
              let itemStart = xml.range(of: "<item>", range: searchFrom..<xml.endIndex),
              let itemEnd = xml.range(of: "</item>", range: itemStart.upperBound..<xml.endIndex) {
            let item = String(xml[itemStart.upperBound..<itemEnd.lowerBound])
            searchFrom = itemEnd.upperBound

            guard var title = firstMatch(in: item, pattern: "<title>([^<]*)</title>").map(unescapeXML),
                  let link = firstMatch(in: item, pattern: "<link>([^<]+)</link>")
            else { continue }
            let outlet = firstMatch(in: item, pattern: "<source[^>]*>([^<]+)</source>")
                .map(unescapeXML) ?? "Google News"
            // Google appends " - Outlet" to every headline; we show the outlet
            // separately, so strip the suffix.
            if title.hasSuffix(" - \(outlet)") { title = String(title.dropLast(outlet.count + 3)) }
            guard !title.isEmpty else { continue }

            items.append(WorldCupNewsItem(
                id: link,
                kind: .article,
                source: outlet,
                headline: title,
                published: firstMatch(in: item, pattern: "<pubDate>([^<]+)</pubDate>")
                    .flatMap { rfc1123.date(from: $0) },
                imageURL: nil,
                link: URL(string: link),
                videoID: nil,
                tiktokID: nil
            ))
        }
        return items
    }

    // MARK: - Shared helpers

    private static func fetchString(_ url: URL) async -> String? {
        var request = URLRequest(url: url)
        request.setValue(browserUA, forHTTPHeaderField: "User-Agent")
        guard let (data, _) = try? await URLSession.shared.data(for: request) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// First capture group of `pattern` in `text`.
    private static func firstMatch(in text: String, pattern: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let m = re.firstMatch(in: text, range: range), m.numberOfRanges > 1,
              let r = Range(m.range(at: 1), in: text)
        else { return nil }
        return String(text[r])
    }

    /// Feed titles arrive XML-escaped ("Czechia &amp; Korea", "&#8217;").
    /// Numeric entities first, then named — `&amp;` last so "&amp;lt;" can't
    /// double-unescape into "<".
    private static func unescapeXML(_ s: String) -> String {
        var out = s
        if let re = try? NSRegularExpression(pattern: "&#(x?)([0-9a-fA-F]+);") {
            let matches = re.matches(in: out, range: NSRange(out.startIndex..., in: out)).reversed()
            for m in matches {
                guard let whole = Range(m.range, in: out),
                      let hexFlag = Range(m.range(at: 1), in: out),
                      let digits = Range(m.range(at: 2), in: out),
                      let code = UInt32(out[digits], radix: out[hexFlag].isEmpty ? 10 : 16),
                      let scalar = Unicode.Scalar(code)
                else { continue }
                out.replaceSubrange(whole, with: String(Character(scalar)))
            }
        }
        for (entity, char) in [("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&apos;", "'"), ("&amp;", "&")] {
            out = out.replacingOccurrences(of: entity, with: char)
        }
        return out
    }

    private static let iso = ISO8601DateFormatter()
    private static func parseISODate(_ raw: String) -> Date? { iso.date(from: raw) }

    /// Google News pubDate: "Wed, 11 Jun 2026 07:30:00 GMT".
    private static let rfc1123: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return f
    }()
}

// MARK: - ESPN news JSON (only the fields we read)

private struct NewsRoot: Decodable { let articles: [NewsArticle] }
private struct NewsArticle: Decodable {
    let headline: String?
    let published: String?
    let images: [NewsImage]?
    let links: NewsLinks?
}
private struct NewsImage: Decodable { let url: String? }
private struct NewsLinks: Decodable { let web: NewsWeb? }
private struct NewsWeb: Decodable { let href: String? }
