import Foundation

/// Fetches an account's latest TikTok posts without any API key, by reading
/// TikTok's own creator-embed page (`tiktok.com/embed/@handle`) — the page
/// behind their official "creator embed" iframe product. Unlike the profile
/// page (whose feed loads through signed XHRs a plain URLSession can't
/// reproduce), the embed page server-renders a `"videoList":[…]` JSON array
/// with the ~12 newest posts: item id, caption, cover image, play count.
/// Same scrape-the-HTML-a-browser-gets approach as `YouTubeLiveResolver`.
///
/// Publish dates aren't in that payload but are encoded in the item ID:
/// TikTok IDs are snowflakes — the top 32 bits are unix seconds.
enum TikTokFeedResolver {
    struct Item {
        let id: String          // numeric item id, e.g. "7623673034259369238"
        let handle: String      // author handle, no "@"
        let caption: String
        let coverURL: URL?      // signed CDN URL with x-expires — never persist
        let playCount: Int
        let published: Date?

        /// Canonical watch URL — browser fallback when the embed can't play.
        var link: URL? { URL(string: "https://www.tiktok.com/@\(handle)/video/\(id)") }
    }

    enum FeedError: Error { case noVideoList }

    /// Browser UA avoids TikTok's bot interstitial, same as the YouTube scrape.
    private static let browserUA =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36"

    static func latestVideos(of handle: String) async throws -> [Item] {
        let clean = normalizedHandle(handle)
        guard !clean.isEmpty,
              let url = URL(string: "https://www.tiktok.com/embed/@\(clean)")
        else { throw FeedError.noVideoList }

        var request = URLRequest(url: url)
        request.setValue(browserUA, forHTTPHeaderField: "User-Agent")
        let (data, _) = try await URLSession.shared.data(for: request)

        guard let html = String(data: data, encoding: .utf8),
              let array = jsonArray(after: "\"videoList\":", in: html),
              let arrayData = array.data(using: .utf8)
        else { throw FeedError.noVideoList }

        let raw = try JSONDecoder().decode([RawItem].self, from: arrayData)
        return raw.compactMap { item in
            guard item.privateItem != true, let numeric = UInt64(item.id) else { return nil }
            return Item(
                id: item.id,
                handle: item.authorUniqueId ?? clean,
                caption: item.desc?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                coverURL: item.coverUrl.flatMap(URL.init(string:)),
                playCount: item.playCount ?? 0,
                published: Date(timeIntervalSince1970: TimeInterval(numeric >> 32))
            )
        }
    }

    /// Accepts "@handle", "handle", or any tiktok.com profile/video URL.
    static func normalizedHandle(_ input: String) -> String {
        var s = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.lowercased().contains("tiktok.com"),
           let range = s.range(of: #"@[A-Za-z0-9_.]+"#, options: .regularExpression) {
            s = String(s[range])
        }
        if s.hasPrefix("@") { s = String(s.dropFirst()) }
        // Handles are alphanumerics, underscores, and periods only.
        guard s.range(of: #"^[A-Za-z0-9_.]+$"#, options: .regularExpression) != nil else { return "" }
        return s
    }

    /// Extracts the balanced `[…]` JSON array that immediately follows
    /// `marker`, honoring string literals and escapes so brackets inside
    /// captions don't end the scan early.
    private static func jsonArray(after marker: String, in html: String) -> String? {
        guard let m = html.range(of: marker), html[m.upperBound...].first == "[" else { return nil }
        let start = m.upperBound
        var depth = 0, inString = false, escaped = false
        var i = start
        while i < html.endIndex {
            let c = html[i]
            if escaped {
                escaped = false
            } else if c == "\\" {
                escaped = inString
            } else if c == "\"" {
                inString.toggle()
            } else if !inString {
                if c == "[" { depth += 1 }
                if c == "]" {
                    depth -= 1
                    if depth == 0 { return String(html[start...i]) }
                }
            }
            i = html.index(after: i)
        }
        return nil
    }

    // Only the fields we read from a videoList element.
    private struct RawItem: Decodable {
        let id: String
        let desc: String?
        let coverUrl: String?
        let playCount: Int?
        let authorUniqueId: String?
        let privateItem: Bool?
    }
}
