import Foundation
import SwiftUI

/// Persisted preferences for the YouTube "most popular" chart:
/// region code, optional category filter, and auto-fill-on-queue-empty toggle.
/// Region falls back to `Locale.current.region` on first launch, then "US".
final class TrendingRegionStore: ObservableObject {
    static let shared = TrendingRegionStore()
    private static let regionKey = "youtube-audio-widget.trending.region.v1"
    private static let categoryKey = "youtube-audio-widget.trending.category.v1"
    private static let autoFillKey = "youtube-audio-widget.trending.autofill.v1"

    @Published var regionCode: String {
        didSet { UserDefaults.standard.set(regionCode, forKey: Self.regionKey) }
    }

    /// Empty string = "All" (no category filter). Otherwise a YouTube
    /// videoCategoryId like "10" (Music) or "20" (Gaming).
    @Published var categoryId: String {
        didSet { UserDefaults.standard.set(categoryId, forKey: Self.categoryKey) }
    }

    /// When true and the playback queue empties at end-of-track, the player
    /// fetches trending and refills the queue automatically. Off by default
    /// to avoid surprising users with unexpected network activity.
    @Published var autoFillFromTrending: Bool {
        didSet { UserDefaults.standard.set(autoFillFromTrending, forKey: Self.autoFillKey) }
    }

    private init() {
        if let stored = UserDefaults.standard.string(forKey: Self.regionKey), !stored.isEmpty {
            self.regionCode = stored.uppercased()
        } else {
            self.regionCode = Self.localeRegion() ?? "US"
        }
        self.categoryId = UserDefaults.standard.string(forKey: Self.categoryKey) ?? ""
        self.autoFillFromTrending = UserDefaults.standard.bool(forKey: Self.autoFillKey)
    }

    private static func localeRegion() -> String? {
        if #available(macOS 13.0, *) {
            if let r = Locale.current.region?.identifier, !r.isEmpty {
                return r.uppercased()
            }
        }
        return nil
    }

    /// Curated subset of YouTube-supported ISO 3166-1 alpha-2 region codes.
    /// Not exhaustive — picked to cover the biggest YouTube markets without
    /// dumping ~110 options into a menu.
    static let supported: [Region] = [
        Region(code: "US", name: "United States"),
        Region(code: "GB", name: "United Kingdom"),
        Region(code: "CA", name: "Canada"),
        Region(code: "AU", name: "Australia"),
        Region(code: "NZ", name: "New Zealand"),
        Region(code: "IE", name: "Ireland"),
        Region(code: "DE", name: "Germany"),
        Region(code: "FR", name: "France"),
        Region(code: "ES", name: "Spain"),
        Region(code: "IT", name: "Italy"),
        Region(code: "NL", name: "Netherlands"),
        Region(code: "SE", name: "Sweden"),
        Region(code: "NO", name: "Norway"),
        Region(code: "DK", name: "Denmark"),
        Region(code: "FI", name: "Finland"),
        Region(code: "PL", name: "Poland"),
        Region(code: "TR", name: "Turkey"),
        Region(code: "RU", name: "Russia"),
        Region(code: "BR", name: "Brazil"),
        Region(code: "MX", name: "Mexico"),
        Region(code: "AR", name: "Argentina"),
        Region(code: "CL", name: "Chile"),
        Region(code: "CO", name: "Colombia"),
        Region(code: "JP", name: "Japan"),
        Region(code: "KR", name: "South Korea"),
        Region(code: "CN", name: "China"),
        Region(code: "HK", name: "Hong Kong"),
        Region(code: "TW", name: "Taiwan"),
        Region(code: "IN", name: "India"),
        Region(code: "ID", name: "Indonesia"),
        Region(code: "MY", name: "Malaysia"),
        Region(code: "SG", name: "Singapore"),
        Region(code: "PH", name: "Philippines"),
        Region(code: "TH", name: "Thailand"),
        Region(code: "VN", name: "Vietnam"),
        Region(code: "AE", name: "United Arab Emirates"),
        Region(code: "SA", name: "Saudi Arabia"),
        Region(code: "IL", name: "Israel"),
        Region(code: "EG", name: "Egypt"),
        Region(code: "ZA", name: "South Africa"),
        Region(code: "NG", name: "Nigeria"),
        Region(code: "KE", name: "Kenya"),
    ]

    struct Region: Identifiable, Hashable {
        let code: String
        let name: String
        var id: String { code }
    }

    func displayName(for code: String) -> String {
        Self.supported.first(where: { $0.code == code })?.name ?? code
    }

    /// YouTube video category IDs that work with `chart=mostPopular`. Not all
    /// of YouTube's ~30 categories are eligible — these are the ones that
    /// consistently return a chart across major regions. Empty `id` = "All".
    static let categories: [Category] = [
        Category(id: "",   label: "All",            emoji: "✨"),
        Category(id: "10", label: "Music",          emoji: "🎵"),
        Category(id: "20", label: "Gaming",         emoji: "🎮"),
        Category(id: "24", label: "Entertainment",  emoji: "🎬"),
        Category(id: "25", label: "News",           emoji: "📰"),
        Category(id: "17", label: "Sports",         emoji: "⚽"),
        Category(id: "23", label: "Comedy",         emoji: "😂"),
        Category(id: "28", label: "Science & Tech", emoji: "🔬"),
    ]

    struct Category: Identifiable, Hashable {
        let id: String
        let label: String
        let emoji: String
    }

    func categoryLabel(for id: String) -> String {
        Self.categories.first(where: { $0.id == id })?.label ?? "All"
    }
}
