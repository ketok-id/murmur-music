import AppKit
import Combine
import Foundation

// MARK: - Model

struct WorldCupTeam {
    let name: String
    let abbrev: String
    let score: String?
    let shootoutScore: Int?   // knockout penalty shootouts only
    let logoURL: URL?
    let winner: Bool
}

struct WorldCupMatch: Identifiable {
    enum State { case scheduled, live, finished }

    let id: String
    let date: Date
    let stage: String        // "Group Stage", "Round Of 16", …
    let venue: String        // "Estadio Banorte · Mexico City"
    let state: State
    let clock: String        // "45'+2" while live
    let detail: String       // ESPN shortDetail ("FT", "HT", "Scheduled")
    let home: WorldCupTeam
    let away: WorldCupTeam

    /// YouTube query for the trailing "find stream" action. Live/upcoming
    /// matches search for streams; finished ones search for highlights.
    var searchQuery: String {
        let base = "\(home.name) vs \(away.name) World Cup 2026"
        return state == .finished ? "\(base) highlights" : "\(base) live"
    }
}

// MARK: - Store

/// 2026 FIFA World Cup schedule + live scores, fetched from ESPN's public
/// scoreboard endpoint (no API key, same JSON espn.com renders from).
///
/// Polling is adaptive: 60s while the World Cup window is open or a match is
/// live / kicking off soon, 15 min otherwise, and nothing at all once the
/// tournament window (June 11 – July 19, 2026 + buffer) has passed. The full
/// date-range payload is ~750 KB, so the fast cadence only runs when someone
/// is actually watching scores.
///
/// Best-effort like `UpdateChecker` — network failures surface as a one-line
/// `errorText` in the sheet, never as alerts.
final class WorldCupStore: ObservableObject {
    static let shared = WorldCupStore()

    @Published private(set) var matches: [WorldCupMatch] = []
    @Published private(set) var lastUpdated: Date? = nil
    @Published private(set) var isLoading = false
    @Published private(set) var errorText: String? = nil

    var liveCount: Int { matches.filter { $0.state == .live }.count }

    /// ESPN soccer scoreboard for the whole tournament. The `dates` range is
    /// inclusive; knockout fixtures appear in the feed as they're drawn.
    static let scoreboardURL = URL(string:
        "https://site.api.espn.com/apis/site/v2/sports/soccer/fifa.world/scoreboard?dates=20260611-20260720")!

    /// Stop polling entirely after this date — the feed is static history then.
    private static let tournamentEnd = DateComponents(
        calendar: .current, timeZone: TimeZone(identifier: "UTC"),
        year: 2026, month: 8, day: 1).date ?? .distantFuture

    private var timer: Timer?
    private var fetchTask: Task<Void, Never>?
    private var sheetOpen = false
    private var lastFetchAttempt: Date? = nil

    private init() {
        refresh()
        rescheduleTimer()
    }

    // MARK: Sheet lifecycle (drives the fast polling cadence)

    func sheetDidOpen() {
        sheetOpen = true
        refresh(force: true)
        rescheduleTimer()
    }

    func sheetDidClose() {
        sheetOpen = false
        rescheduleTimer()
    }

    // MARK: Fetch

    func refresh(force: Bool = false) {
        if isLoading { return }
        // Throttle accidental double-triggers (onAppear + timer firing together).
        if !force, let last = lastFetchAttempt, Date().timeIntervalSince(last) < 20 { return }
        lastFetchAttempt = Date()
        isLoading = true

        fetchTask = Task {
            do {
                let (data, _) = try await URLSession.shared.data(from: Self.scoreboardURL)
                let root = try JSONDecoder().decode(SBRoot.self, from: data)
                let parsed = root.events
                    .compactMap(Self.match(from:))
                    .sorted { $0.date < $1.date }
                await MainActor.run {
                    self.matches = parsed
                    self.lastUpdated = Date()
                    self.errorText = nil
                    self.isLoading = false
                    self.rescheduleTimer()
                }
            } catch {
                await MainActor.run {
                    self.errorText = "Couldn't load scores — check your connection."
                    self.isLoading = false
                }
            }
        }
    }

    private func rescheduleTimer() {
        timer?.invalidate()
        timer = nil
        guard Date() < Self.tournamentEnd else { return }

        let interval: TimeInterval = (sheetOpen || hasLiveOrImminent) ? 60 : 900
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        timer?.tolerance = interval * 0.1
    }

    /// True while any match is in play or kicks off within the next 20
    /// minutes — the window where scores actually move.
    private var hasLiveOrImminent: Bool {
        let soon = Date().addingTimeInterval(20 * 60)
        return matches.contains {
            $0.state == .live || ($0.state == .scheduled && $0.date <= soon && $0.date >= Date().addingTimeInterval(-3 * 3600))
        }
    }

    // MARK: ESPN JSON → model

    private static func match(from event: SBEvent) -> WorldCupMatch? {
        guard let comp = event.competitions?.first,
              let competitors = comp.competitors, competitors.count >= 2,
              let date = parseDate(event.date)
        else { return nil }

        let homeRaw = competitors.first { $0.homeAway == "home" } ?? competitors[0]
        let awayRaw = competitors.first { $0.homeAway == "away" } ?? competitors[1]

        let state: WorldCupMatch.State
        switch comp.status?.type?.state {
        case "in":   state = .live
        case "post": state = .finished
        default:     state = .scheduled
        }

        var venue = comp.venue?.fullName ?? ""
        if let city = comp.venue?.address?.city, !city.isEmpty {
            venue = venue.isEmpty ? city : "\(venue) · \(city)"
        }

        return WorldCupMatch(
            id: event.id,
            date: date,
            stage: prettyStage(event.season?.slug),
            venue: venue,
            state: state,
            clock: comp.status?.displayClock ?? "",
            detail: comp.status?.type?.shortDetail ?? "",
            home: team(from: homeRaw),
            away: team(from: awayRaw)
        )
    }

    private static func team(from raw: SBCompetitor) -> WorldCupTeam {
        WorldCupTeam(
            name: raw.team?.displayName ?? raw.team?.abbreviation ?? "TBD",
            abbrev: raw.team?.abbreviation ?? "—",
            score: raw.score,
            shootoutScore: raw.shootoutScore,
            logoURL: raw.team?.logo.flatMap(URL.init(string:)),
            winner: raw.winner ?? false
        )
    }

    private static func prettyStage(_ slug: String?) -> String {
        guard let slug, !slug.isEmpty else { return "" }
        return slug.split(separator: "-").map { $0.capitalized }.joined(separator: " ")
    }

    /// ESPN emits minute-precision dates without seconds ("2026-06-11T19:00Z").
    private static let apiDate: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd'T'HH:mm'Z'"
        f.timeZone = TimeZone(identifier: "UTC")
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    private static let apiDateWithSeconds: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
        f.timeZone = TimeZone(identifier: "UTC")
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    private static func parseDate(_ raw: String?) -> Date? {
        guard let raw else { return nil }
        return apiDate.date(from: raw) ?? apiDateWithSeconds.date(from: raw)
    }
}

// MARK: - ESPN scoreboard JSON (only the fields we read)

private struct SBRoot: Decodable { let events: [SBEvent] }

private struct SBEvent: Decodable {
    let id: String
    let date: String?
    let season: SBSeason?
    let competitions: [SBCompetition]?
}

private struct SBSeason: Decodable { let slug: String? }

private struct SBCompetition: Decodable {
    let status: SBStatus?
    let venue: SBVenue?
    let competitors: [SBCompetitor]?
}

private struct SBStatus: Decodable {
    let displayClock: String?
    let type: SBStatusType?
}

private struct SBStatusType: Decodable {
    let state: String?        // "pre" | "in" | "post"
    let shortDetail: String?
}

private struct SBVenue: Decodable {
    let fullName: String?
    let address: SBAddress?
}

private struct SBAddress: Decodable { let city: String? }

private struct SBCompetitor: Decodable {
    let homeAway: String?
    let score: String?
    let shootoutScore: Int?
    let winner: Bool?
    let team: SBTeam?
}

private struct SBTeam: Decodable {
    let displayName: String?
    let abbreviation: String?
    let logo: String?
}

// MARK: - Navigation seed

/// Carries "open the board focused on this match" across process boundaries
/// — set by the notifier (notification click) or the `murmur://worldcup?match=`
/// deep link before `.murmurOpenWorldCup` is posted; the sheet consumes it
/// (switch to Matches, expand, scroll) and clears it. Same pattern as
/// `YouTubeSearchState`.
final class WorldCupNavState: ObservableObject {
    static let shared = WorldCupNavState()
    @Published var targetMatchID: String? = nil
    private init() {}
}

// MARK: - Live stream resolver

/// Resolves live YouTube streams without the Data API, by scraping the same
/// HTML pages a browser gets. Two flavors:
///   - `currentLiveVideoID(of:)` — "what is this channel live-streaming
///     right now?" via the channel's `/live` URL. Used by the quick-listen
///     chips so they always land on the *current* stream instead of a
///     hardcoded ID that goes stale.
///   - `topLiveVideoID(matching:)` — "what's the top live stream for this
///     query?" via a live-filtered search-results page. Used by the
///     per-match play buttons to jump straight into a match stream.
enum YouTubeLiveResolver {
    enum ResolveError: Error { case notLive }

    /// Browser UA avoids YouTube's bot interstitial on the HTML pages.
    private static let browserUA =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36"

    static func currentLiveVideoID(of liveURL: URL) async throws -> String {
        var request = URLRequest(url: liveURL)
        request.setValue(browserUA, forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)

        // Live channels usually 302 straight to /watch?v=<id>.
        if let final = response.url,
           let comps = URLComponents(url: final, resolvingAgainstBaseURL: false),
           final.path == "/watch",
           let id = comps.queryItems?.first(where: { $0.name == "v" })?.value,
           id.count == 11 {
            return id
        }

        // Otherwise we landed on a channel page — only trust the embedded
        // videoId if the page says a live broadcast is actually running.
        guard let html = String(data: data, encoding: .utf8),
              html.contains("\"isLiveNow\":true"),
              let range = html.range(of: #""videoId":"([A-Za-z0-9_-]{11})""#,
                                     options: .regularExpression)
        else { throw ResolveError.notLive }

        let id = html[range]
            .replacingOccurrences(of: "\"videoId\":\"", with: "")
            .replacingOccurrences(of: "\"", with: "")
        guard id.count == 11 else { throw ResolveError.notLive }
        return id
    }

    /// Top live result for a search query, via the results page with
    /// YouTube's "Live" filter applied (`sp=EgJAAQ%3D%3D` is the
    /// protobuf-encoded filter, the same one the filter chip in the web UI
    /// produces).
    ///
    /// Guard against the no-results case: a live-filtered page with zero
    /// matches still embeds videoIds for suggested (non-live) videos, so an
    /// ID is only trusted when a LIVE_NOW badge follows it — the badge sits
    /// inside the same videoRenderer JSON as its videoId, so the last ID
    /// *before* the first badge is the first genuinely-live result.
    static func topLiveVideoID(matching query: String) async throws -> String {
        let escaped = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        guard let url = URL(string:
            "https://www.youtube.com/results?search_query=\(escaped)&sp=EgJAAQ%3D%3D")
        else { throw ResolveError.notLive }

        var request = URLRequest(url: url)
        request.setValue(browserUA, forHTTPHeaderField: "User-Agent")
        let (data, _) = try await URLSession.shared.data(for: request)

        guard let html = String(data: data, encoding: .utf8),
              let badge = html.range(of: "BADGE_STYLE_TYPE_LIVE_NOW")
        else { throw ResolveError.notLive }

        let head = html[html.startIndex..<badge.lowerBound]
        var lastID: Substring? = nil
        var searchFrom = head.startIndex
        while let r = head.range(of: #""videoId":"([A-Za-z0-9_-]{11})""#,
                                 options: .regularExpression,
                                 range: searchFrom..<head.endIndex) {
            lastID = head[r].dropFirst(11).dropLast(1)   // strip "videoId":" … "
            searchFrom = r.upperBound
        }
        guard let id = lastID, id.count == 11 else { throw ResolveError.notLive }
        return String(id)
    }
}
