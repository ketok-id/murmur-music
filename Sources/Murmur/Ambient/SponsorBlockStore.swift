import CryptoKit
import Foundation

struct SponsorSegment {
    let category: String
    let start: Double
    let end: Double
}

/// SponsorBlock settings + segment fetcher. The community API is key-less;
/// lookups use the privacy-preserving hash-prefix endpoint — we send only the
/// first 4 hex chars of SHA-256(videoID), the server returns every matching
/// video, and never learns which one is playing. Data is CC BY-NC-SA 4.0,
/// credited in the Settings sheet.
///
/// Segments are fetched for ALL categories and cached in-memory per videoID
/// (LyricsStore precedent — not worth disk); the category toggles filter at
/// skip time, so flipping a category never refetches. `SponsorSkipper` (owned
/// by AppDelegate) does the actual position-watch + seek.
final class SponsorBlockStore: ObservableObject {
    static let shared = SponsorBlockStore()

    private static let enabledKey = "youtube-audio-widget.sponsorblock.enabled"
    private static let categoriesKey = "youtube-audio-widget.sponsorblock.categories"

    /// (label, api id) — order is the Settings display order.
    static let allCategories: [(label: String, id: String)] = [
        ("Sponsors", "sponsor"),
        ("Self-promotion", "selfpromo"),
        ("Like/subscribe reminders", "interaction"),
        ("Intros", "intro"),
        ("Outros / endcards", "outro"),
        ("Non-music sections", "music_offtopic"),
    ]

    /// Off by default — opt-in keeps load off the community API until the
    /// user actually wants it.
    @Published var enabled: Bool {
        didSet { UserDefaults.standard.set(enabled, forKey: Self.enabledKey) }
    }

    /// Category ids the user wants skipped.
    @Published var categories: Set<String> {
        didSet { UserDefaults.standard.set(Array(categories).sorted(), forKey: Self.categoriesKey) }
    }

    private var cache: [String: [SponsorSegment]] = [:]

    private init() {
        enabled = UserDefaults.standard.bool(forKey: Self.enabledKey)
        if let saved = UserDefaults.standard.stringArray(forKey: Self.categoriesKey) {
            categories = Set(saved)
        } else {
            categories = ["sponsor", "selfpromo", "interaction"]
        }
    }

    func toggleCategory(_ id: String) {
        if categories.contains(id) { categories.remove(id) } else { categories.insert(id) }
    }

    /// All segments for a video (every category — callers filter). Returns
    /// [] on any failure; a 404 just means "no segments known".
    @MainActor
    func segments(for videoID: String) async -> [SponsorSegment] {
        if let cached = cache[videoID] { return cached }

        let digest = SHA256.hash(data: Data(videoID.utf8))
        let prefix = digest.map { String(format: "%02x", $0) }.joined().prefix(4)
        let ids = Self.allCategories.map { "\"\($0.id)\"" }.joined(separator: ",")
        let categoriesParam = "[\(ids)]".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        guard let url = URL(string:
            "https://sponsor.ajay.app/api/skipSegments/\(prefix)?categories=\(categoriesParam)")
        else { return [] }

        guard let (data, response) = try? await URLSession.shared.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let matches = try? JSONDecoder().decode([HashMatch].self, from: data)
        else {
            cache[videoID] = []
            return []
        }

        let segments = matches
            .first { $0.videoID == videoID }?
            .segments
            .compactMap { seg -> SponsorSegment? in
                guard seg.segment.count == 2, seg.segment[1] - seg.segment[0] >= 1 else { return nil }
                return SponsorSegment(category: seg.category, start: seg.segment[0], end: seg.segment[1])
            } ?? []
        cache[videoID] = segments
        return segments
    }
}

// Only the fields we read from the hash-prefix response.
private struct HashMatch: Decodable {
    let videoID: String
    let segments: [Seg]

    struct Seg: Decodable {
        let category: String
        let segment: [Double]
    }
}
