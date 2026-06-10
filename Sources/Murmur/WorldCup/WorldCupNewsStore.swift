import Foundation

struct WorldCupArticle: Identifiable {
    let id: String
    let headline: String
    let published: Date?
    let imageURL: URL?
    let link: URL?
}

/// ESPN's World Cup news feed (same key-less host as the scoreboard).
/// Fetched on first News-tab open, then throttled to one refresh per 5 min.
final class WorldCupNewsStore: ObservableObject {
    static let shared = WorldCupNewsStore()

    @Published private(set) var articles: [WorldCupArticle] = []
    @Published private(set) var lastUpdated: Date? = nil
    @Published private(set) var isLoading = false
    @Published private(set) var errorText: String? = nil

    static let newsURL = URL(string:
        "https://site.api.espn.com/apis/site/v2/sports/soccer/fifa.world/news")!

    private init() {}

    func refresh(force: Bool = false) {
        if isLoading { return }
        if !force, let last = lastUpdated, Date().timeIntervalSince(last) < 300 { return }
        isLoading = true

        Task {
            do {
                let (data, _) = try await URLSession.shared.data(from: Self.newsURL)
                let root = try JSONDecoder().decode(NewsRoot.self, from: data)
                let parsed = root.articles.compactMap { a -> WorldCupArticle? in
                    guard let headline = a.headline, !headline.isEmpty else { return nil }
                    return WorldCupArticle(
                        id: (a.links?.web?.href ?? headline),
                        headline: headline,
                        published: a.published.flatMap(Self.parseDate),
                        imageURL: a.images?.first?.url.flatMap(URL.init(string:)),
                        link: (a.links?.web?.href).flatMap(URL.init(string:))
                    )
                }
                await MainActor.run {
                    self.articles = parsed
                    self.lastUpdated = Date()
                    self.errorText = nil
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.errorText = "Couldn't load news — check your connection."
                    self.isLoading = false
                }
            }
        }
    }

    private static let iso: ISO8601DateFormatter = ISO8601DateFormatter()
    private static func parseDate(_ raw: String) -> Date? { iso.date(from: raw) }
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
