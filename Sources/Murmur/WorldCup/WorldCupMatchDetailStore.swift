import Foundation

struct WorldCupMatchDetail {
    struct Event: Identifiable {
        enum Kind { case goal, yellow, red, substitution, other }
        let id: String
        let minute: String      // "23'"
        let kind: Kind
        let text: String        // "R. Jiménez — Goal"
        let teamAbbrev: String  // attribution; empty when ESPN omits it
    }

    struct StatLine: Identifiable {
        let id: String
        let label: String       // "Possession"
        let home: String
        let away: String
    }

    struct Player: Identifiable {
        let id: String
        let jersey: String
        let position: String
        let name: String
    }

    struct FormGame: Identifiable {
        let id: String
        let result: String     // "W" | "D" | "L"
        let summary: String    // "vs SRB 5–1 · Friendly"
    }

    struct H2HLine: Identifiable {
        let id: String
        let text: String       // "2010 FIFA World Cup · @ RSA 1–1 (D)"
    }

    let events: [Event]
    let stats: [StatLine]
    let homeStarters: [Player]
    let awayStarters: [Player]
    let homeForm: [FormGame]
    let awayForm: [FormGame]
    let headToHead: [H2HLine]
    let fetchedAt: Date

    var isEmpty: Bool {
        events.isEmpty && stats.isEmpty && homeStarters.isEmpty
            && homeForm.isEmpty && headToHead.isEmpty
    }
}

/// Per-match deep data (goal/card timeline, match stats, lineups) from
/// ESPN's `summary` endpoint, fetched on demand when a row is expanded and
/// cached for 60s so an expanded live match keeps refreshing on the same
/// cadence as the scoreboard. Before kickoff ESPN returns empty sections —
/// `WorldCupMatchDetail.isEmpty` lets the UI say so instead of showing
/// blank space.
final class WorldCupMatchDetailStore: ObservableObject {
    static let shared = WorldCupMatchDetailStore()

    @Published private(set) var details: [String: WorldCupMatchDetail] = [:]
    @Published private(set) var loading: Set<String> = []

    private init() {}

    func detail(for matchID: String) -> WorldCupMatchDetail? { details[matchID] }

    func fetch(matchID: String, force: Bool = false) {
        if loading.contains(matchID) { return }
        if !force, let cached = details[matchID],
           Date().timeIntervalSince(cached.fetchedAt) < 60 { return }
        loading.insert(matchID)

        Task {
            defer { Task { @MainActor in self.loading.remove(matchID) } }
            guard let url = URL(string:
                "https://site.api.espn.com/apis/site/v2/sports/soccer/fifa.world/summary?event=\(matchID)")
            else { return }
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                let root = try JSONDecoder().decode(SummaryRoot.self, from: data)
                let parsed = Self.parse(root)
                await MainActor.run { self.details[matchID] = parsed }
            } catch {
                // Leave any stale cache in place; the row shows what it has.
            }
        }
    }

    // MARK: Summary JSON → model

    private static func parse(_ root: SummaryRoot) -> WorldCupMatchDetail {
        // Timeline — goals, cards, subs in match order.
        let events: [WorldCupMatchDetail.Event] = (root.keyEvents ?? []).enumerated().compactMap { idx, raw in
            let typeText = raw.type?.text ?? ""
            let kind: WorldCupMatchDetail.Event.Kind
            switch true {
            case typeText.localizedCaseInsensitiveContains("goal"),
                 typeText.localizedCaseInsensitiveContains("penalty - scored"):
                kind = .goal
            case typeText.localizedCaseInsensitiveContains("yellow"): kind = .yellow
            case typeText.localizedCaseInsensitiveContains("red"):    kind = .red
            case typeText.localizedCaseInsensitiveContains("substitution"): kind = .substitution
            default: kind = .other
            }
            // Skip filler events (kickoff, halftime whistles…) that have no
            // participant and aren't goals/cards.
            let who = raw.participants?.first?.athlete?.displayName
            if kind == .other && who == nil { return nil }
            let label = [who, typeText.isEmpty ? nil : typeText]
                .compactMap { $0 }.joined(separator: " — ")
            return WorldCupMatchDetail.Event(
                id: "\(idx)-\(raw.clock?.displayValue ?? "")",
                minute: raw.clock?.displayValue ?? "",
                kind: kind,
                text: label.isEmpty ? (raw.text ?? "Event") : label,
                teamAbbrev: raw.team?.abbreviation ?? raw.team?.displayName ?? ""
            )
        }

        // Stats — join the two teams' statistics arrays by stat name,
        // keeping a curated subset in a fixed order.
        let teams = root.boxscore?.teams ?? []
        func statMap(_ t: SummaryBoxTeam?) -> [String: (label: String, value: String)] {
            Dictionary(uniqueKeysWithValues: (t?.statistics ?? []).compactMap { s in
                guard let name = s.name, let v = s.displayValue else { return nil }
                return (name, (s.label ?? name, v))
            })
        }
        let home = statMap(teams.first)
        let away = statMap(teams.count > 1 ? teams[1] : nil)
        let wanted = ["possessionPct", "totalShots", "shotsOnTarget",
                      "wonCorners", "foulsCommitted", "offsides", "saves"]
        let stats: [WorldCupMatchDetail.StatLine] = wanted.compactMap { name in
            guard let h = home[name], let a = away[name] else { return nil }
            return WorldCupMatchDetail.StatLine(id: name, label: h.label, home: h.value, away: a.value)
        }

        // Starting XIs (posted ~1h before kickoff).
        func starters(_ homeAway: String) -> [WorldCupMatchDetail.Player] {
            let side = (root.rosters ?? []).first { $0.homeAway == homeAway }
            return (side?.roster ?? [])
                .filter { $0.starter == true }
                .enumerated()
                .compactMap { idx, p in
                    guard let name = p.athlete?.displayName else { return nil }
                    return WorldCupMatchDetail.Player(
                        id: "\(homeAway)-\(idx)-\(name)",
                        jersey: p.jersey ?? "",
                        position: p.position?.abbreviation ?? "",
                        name: name
                    )
                }
        }

        // Recent form, one side per team in boxscore order (home first).
        func form(_ idx: Int) -> [WorldCupMatchDetail.FormGame] {
            let sides = root.boxscore?.form ?? []
            guard sides.count > idx else { return [] }
            return (sides[idx].events ?? []).prefix(5).enumerated().map { i, game in
                WorldCupMatchDetail.FormGame(
                    id: "\(idx)-\(i)",
                    result: game.gameResult ?? "—",
                    summary: gameSummary(game)
                )
            }
        }

        // Past meetings between the two sides, newest first.
        let h2h: [WorldCupMatchDetail.H2HLine] = (root.headToHeadGames ?? [])
            .flatMap { $0.events ?? [] }
            .prefix(4)
            .enumerated()
            .map { i, game in
                let year = (game.gameDate ?? "").prefix(4)
                return WorldCupMatchDetail.H2HLine(
                    id: "h2h-\(i)",
                    text: "\(year) · \(gameSummary(game)) (\(game.gameResult ?? "—"))"
                )
            }

        return WorldCupMatchDetail(
            events: events,
            stats: stats,
            homeStarters: starters("home"),
            awayStarters: starters("away"),
            homeForm: form(0),
            awayForm: form(1),
            headToHead: h2h,
            fetchedAt: Date()
        )
    }

    /// "vs SRB 5–1 · Friendly" — relative to the team whose form/h2h list
    /// the game came from (`atVs` is theirs, scores are home–away as played).
    private static func gameSummary(_ game: SummaryFormGame) -> String {
        let opp = game.opponent?.abbreviation ?? game.opponent?.displayName ?? "?"
        let score = [game.homeTeamScore, game.awayTeamScore]
            .compactMap { $0 }.joined(separator: "–")
        let league = game.leagueName.map { $0 == "FIFA World Cup" ? "" : " · \($0)" } ?? ""
        return "\(game.atVs ?? "vs") \(opp) \(score)\(league)"
    }
}

// MARK: - ESPN summary JSON (only the fields we read)

private struct SummaryRoot: Decodable {
    let keyEvents: [SummaryEvent]?
    let boxscore: SummaryBoxscore?
    let rosters: [SummaryRoster]?
    let headToHeadGames: [SummaryH2HSide]?
}

private struct SummaryH2HSide: Decodable { let events: [SummaryFormGame]? }

private struct SummaryFormGame: Decodable {
    let gameResult: String?
    let gameDate: String?
    let atVs: String?
    let homeTeamScore: String?
    let awayTeamScore: String?
    let leagueName: String?
    let competitionName: String?
    let opponent: SummaryTeamRef?
}

private struct SummaryEvent: Decodable {
    let clock: SummaryClock?
    let type: SummaryEventType?
    let text: String?
    let team: SummaryTeamRef?
    let participants: [SummaryParticipant]?
}
private struct SummaryClock: Decodable { let displayValue: String? }
private struct SummaryEventType: Decodable { let text: String? }
private struct SummaryTeamRef: Decodable {
    let abbreviation: String?
    let displayName: String?
}
private struct SummaryParticipant: Decodable { let athlete: SummaryAthlete? }
private struct SummaryAthlete: Decodable { let displayName: String? }

private struct SummaryBoxscore: Decodable {
    let teams: [SummaryBoxTeam]?
    let form: [SummaryFormSide]?
}
private struct SummaryFormSide: Decodable { let events: [SummaryFormGame]? }
private struct SummaryBoxTeam: Decodable { let statistics: [SummaryStat]? }
private struct SummaryStat: Decodable {
    let name: String?
    let label: String?
    let displayValue: String?
}

private struct SummaryRoster: Decodable {
    let homeAway: String?
    let roster: [SummaryPlayer]?
}
private struct SummaryPlayer: Decodable {
    let starter: Bool?
    let jersey: String?
    let position: SummaryPosition?
    let athlete: SummaryAthlete?
}
private struct SummaryPosition: Decodable { let abbreviation: String? }
