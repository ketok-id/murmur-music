import Foundation
import SwiftUI

/// Persisted region code used for the YouTube "most popular" chart.
/// Falls back to `Locale.current.region` on first launch, then "US".
final class TrendingRegionStore: ObservableObject {
    static let shared = TrendingRegionStore()
    private static let key = "youtube-audio-widget.trending.region.v1"

    @Published var regionCode: String {
        didSet {
            UserDefaults.standard.set(regionCode, forKey: Self.key)
        }
    }

    private init() {
        if let stored = UserDefaults.standard.string(forKey: Self.key), !stored.isEmpty {
            self.regionCode = stored.uppercased()
        } else {
            self.regionCode = Self.localeRegion() ?? "US"
        }
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
}
