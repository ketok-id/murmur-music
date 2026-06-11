import Foundation

struct TrackStat: Codable, Identifiable {
    let videoID: String
    var title: String
    var seconds: Double
    var lastPlayed: Date

    var id: String { videoID }
}

/// Local listening totals — per-track and per-day accumulated seconds, fed by
/// `ListeningRecorder`'s playhead deltas. Zero network; powers the Stats
/// window. UserDefaults-backed singleton per the store rule.
///
/// Writes are throttled (one persist per ~20s of listening) so the per-tick
/// `add` calls don't hammer the defaults plist; `flush()` runs from
/// `applicationWillTerminate` to catch the tail.
final class ListeningStatsStore: ObservableObject {
    static let shared = ListeningStatsStore()

    private static let tracksKey = "youtube-audio-widget.listeningStats.tracks.v1"
    private static let dailyKey = "youtube-audio-widget.listeningStats.daily.v1"
    /// Keep the plist bounded: top tracks by listened time, ~13 months of days.
    private static let maxTracks = 300
    private static let maxDays = 400

    @Published private(set) var tracks: [String: TrackStat]
    /// "yyyy-MM-dd" (local calendar) → seconds listened that day.
    @Published private(set) var daily: [String: Double]

    private var unsavedSeconds: Double = 0

    private init() {
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: Self.tracksKey),
           let list = try? JSONDecoder().decode([TrackStat].self, from: data) {
            tracks = Dictionary(uniqueKeysWithValues: list.map { ($0.videoID, $0) })
        } else {
            tracks = [:]
        }
        if let data = defaults.data(forKey: Self.dailyKey),
           let map = try? JSONDecoder().decode([String: Double].self, from: data) {
            daily = map
        } else {
            daily = [:]
        }
    }

    func add(seconds: Double, videoID: String, title: String) {
        guard seconds > 0, !videoID.isEmpty else { return }
        var stat = tracks[videoID] ?? TrackStat(videoID: videoID, title: title, seconds: 0, lastPlayed: Date())
        stat.seconds += seconds
        stat.lastPlayed = Date()
        if !title.isEmpty { stat.title = title }
        tracks[videoID] = stat
        daily[Self.dayKey(Date()), default: 0] += seconds

        unsavedSeconds += seconds
        if unsavedSeconds >= 20 { flush() }
    }

    func flush() {
        unsavedSeconds = 0
        // Trim before persisting so the stored blobs stay small.
        if tracks.count > Self.maxTracks {
            let keep = tracks.values.sorted { $0.seconds > $1.seconds }.prefix(Self.maxTracks)
            tracks = Dictionary(uniqueKeysWithValues: keep.map { ($0.videoID, $0) })
        }
        if daily.count > Self.maxDays {
            let keep = daily.keys.sorted(by: >).prefix(Self.maxDays)
            daily = daily.filter { keep.contains($0.key) }
        }
        let defaults = UserDefaults.standard
        defaults.set(try? JSONEncoder().encode(Array(tracks.values)), forKey: Self.tracksKey)
        defaults.set(try? JSONEncoder().encode(daily), forKey: Self.dailyKey)
    }

    // MARK: - Derived (for the Stats window)

    var totalAllTime: Double { daily.values.reduce(0, +) }

    var totalToday: Double { daily[Self.dayKey(Date())] ?? 0 }

    var totalLast7Days: Double {
        lastDays(7).reduce(0) { $0 + $1.seconds }
    }

    /// Oldest → newest, including zero days, for the bar chart.
    func lastDays(_ count: Int) -> [(day: Date, seconds: Double)] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return (0..<count).reversed().compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            return (day: day, seconds: daily[Self.dayKey(day)] ?? 0)
        }
    }

    func topTracks(limit: Int = 10) -> [TrackStat] {
        tracks.values.sorted { $0.seconds > $1.seconds }.prefix(limit).map { $0 }
    }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static func dayKey(_ date: Date) -> String { dayFormatter.string(from: date) }
}
