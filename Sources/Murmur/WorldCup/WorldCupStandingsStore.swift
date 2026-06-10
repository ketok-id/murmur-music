import Foundation

struct WorldCupGroupEntry: Identifiable {
    let id: String          // team abbreviation
    let name: String
    let abbrev: String
    let logoURL: URL?
    let rank: Int
    let played: Int
    let won: Int
    let drawn: Int
    let lost: Int
    let goalDiff: Int
    let goalsFor: Int
    let points: Int
}

struct WorldCupGroup: Identifiable {
    let id: String
    let name: String        // "Group A"
    let entries: [WorldCupGroupEntry]
}

/// Group tables for all 12 first-round groups, from ESPN's standings
/// endpoint. Throttled like the news store; the Groups tab also forces a
/// refresh whenever a match flips to full-time so the table tracks results.
final class WorldCupStandingsStore: ObservableObject {
    static let shared = WorldCupStandingsStore()

    @Published private(set) var groups: [WorldCupGroup] = []
    @Published private(set) var lastUpdated: Date? = nil
    @Published private(set) var isLoading = false
    @Published private(set) var errorText: String? = nil

    static let standingsURL = URL(string:
        "https://site.api.espn.com/apis/v2/sports/soccer/fifa.world/standings?season=2026")!

    private init() {}

    func refresh(force: Bool = false) {
        if isLoading { return }
        if !force, let last = lastUpdated, Date().timeIntervalSince(last) < 300 { return }
        isLoading = true

        Task {
            do {
                let (data, _) = try await URLSession.shared.data(from: Self.standingsURL)
                let root = try JSONDecoder().decode(StandingsRoot.self, from: data)
                let parsed = (root.children ?? []).compactMap { child -> WorldCupGroup? in
                    guard let name = child.name else { return nil }
                    let entries = (child.standings?.entries ?? [])
                        .compactMap(Self.entry(from:))
                        .sorted { $0.rank < $1.rank }
                    guard !entries.isEmpty else { return nil }
                    return WorldCupGroup(id: child.id ?? name, name: name, entries: entries)
                }
                await MainActor.run {
                    self.groups = parsed
                    self.lastUpdated = Date()
                    self.errorText = nil
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.errorText = "Couldn't load group tables — check your connection."
                    self.isLoading = false
                }
            }
        }
    }

    private static func entry(from raw: StandingsEntry) -> WorldCupGroupEntry? {
        guard let team = raw.team else { return nil }
        func stat(_ name: String) -> Int {
            Int(raw.stats?.first { $0.name == name }?.displayValue ?? "") ?? 0
        }
        let abbrev = team.abbreviation ?? team.displayName ?? "—"
        return WorldCupGroupEntry(
            id: abbrev,
            name: team.displayName ?? abbrev,
            abbrev: abbrev,
            logoURL: team.logos?.first?.href.flatMap(URL.init(string:)),
            rank: stat("rank"),
            played: stat("gamesPlayed"),
            won: stat("wins"),
            drawn: stat("ties"),
            lost: stat("losses"),
            goalDiff: stat("pointDifferential"),
            goalsFor: stat("pointsFor"),
            points: stat("points")
        )
    }
}

// MARK: - ESPN standings JSON (only the fields we read)

private struct StandingsRoot: Decodable { let children: [StandingsGroup]? }
private struct StandingsGroup: Decodable {
    let id: String?
    let name: String?
    let standings: StandingsList?
}
private struct StandingsList: Decodable { let entries: [StandingsEntry]? }
private struct StandingsEntry: Decodable {
    let team: StandingsTeam?
    let stats: [StandingsStat]?
}
private struct StandingsTeam: Decodable {
    let displayName: String?
    let abbreviation: String?
    let logos: [StandingsLogo]?
}
private struct StandingsLogo: Decodable { let href: String? }
private struct StandingsStat: Decodable {
    let name: String?
    let displayValue: String?
}
