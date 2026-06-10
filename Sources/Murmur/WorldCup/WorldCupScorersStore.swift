import Combine
import Foundation

struct WorldCupScorer: Identifiable {
    let id: String          // "name|team"
    let name: String
    let teamAbbrev: String
    let goals: Int
}

/// Golden Boot race, computed locally: ESPN exposes no tournament player
/// stats until matches are played (their leaders endpoints 404 pre-stats and
/// the schema is unverifiable), so instead we tally goal events out of each
/// finished match's summary exactly once and persist the running counts.
/// Deterministic, schema-known, and survives restarts.
///
/// Caveats: own goals are excluded (Golden Boot rules) and shootout
/// penalties are skipped by requiring a clock value on the event.
final class WorldCupScorersStore: ObservableObject {
    static let shared = WorldCupScorersStore()

    @Published private(set) var scorers: [WorldCupScorer] = []

    private static let kCounts = "youtube-audio-widget.worldcup.scorerCounts"
    private static let kIngested = "youtube-audio-widget.worldcup.ingestedMatches"

    private var counts: [String: Int]      // "name|team" → goals
    private var ingested: Set<String>      // match IDs already tallied
    private var inFlight = Set<String>()
    private var cancellable: AnyCancellable?

    private init() {
        let d = UserDefaults.standard
        counts = (try? JSONDecoder().decode([String: Int].self,
                                            from: d.data(forKey: Self.kCounts) ?? Data())) ?? [:]
        ingested = Set(d.stringArray(forKey: Self.kIngested) ?? [])
        publish()
        cancellable = WorldCupStore.shared.$matches
            .receive(on: DispatchQueue.main)
            .sink { [weak self] matches in self?.ingestFinished(matches) }
    }

    private func ingestFinished(_ matches: [WorldCupMatch]) {
        for match in matches where match.state == .finished
            && !ingested.contains(match.id)
            && !inFlight.contains(match.id) {
            inFlight.insert(match.id)
            tally(match)
        }
    }

    private func tally(_ match: WorldCupMatch) {
        Task {
            defer { Task { @MainActor in self.inFlight.remove(match.id) } }
            guard let url = URL(string:
                "https://site.api.espn.com/apis/site/v2/sports/soccer/fifa.world/summary?event=\(match.id)")
            else { return }
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                let root = try JSONDecoder().decode(ScorerSummaryRoot.self, from: data)
                let goals: [(name: String, team: String)] = (root.keyEvents ?? []).compactMap { ev in
                    let type = ev.type?.text ?? ""
                    guard type.localizedCaseInsensitiveContains("goal")
                            || type.localizedCaseInsensitiveContains("penalty - scored")
                    else { return nil }
                    guard !type.localizedCaseInsensitiveContains("own goal") else { return nil }
                    // Shootout penalties carry no running clock — skip them.
                    guard let minute = ev.clock?.displayValue, !minute.isEmpty else { return nil }
                    guard let name = ev.participants?.first?.athlete?.displayName else { return nil }
                    let team = ev.team?.abbreviation ?? ev.team?.displayName ?? ""
                    return (name, team)
                }
                await MainActor.run {
                    for goal in goals {
                        self.counts["\(goal.name)|\(goal.team)", default: 0] += 1
                    }
                    self.ingested.insert(match.id)
                    self.persist()
                    self.publish()
                }
            } catch {
                // Not ingested — retried on the next matches publish.
            }
        }
    }

    private func publish() {
        scorers = counts
            .map { key, goals -> WorldCupScorer in
                let parts = key.split(separator: "|", maxSplits: 1).map(String.init)
                return WorldCupScorer(id: key,
                                      name: parts.first ?? key,
                                      teamAbbrev: parts.count > 1 ? parts[1] : "",
                                      goals: goals)
            }
            .sorted { ($0.goals, $1.name) > ($1.goals, $0.name) }
    }

    private func persist() {
        let d = UserDefaults.standard
        d.set(try? JSONEncoder().encode(counts), forKey: Self.kCounts)
        d.set(Array(ingested), forKey: Self.kIngested)
    }
}

// Minimal slice of the summary JSON for goal tallying.
private struct ScorerSummaryRoot: Decodable { let keyEvents: [ScorerEvent]? }
private struct ScorerEvent: Decodable {
    let clock: ScorerClock?
    let type: ScorerType?
    let team: ScorerTeam?
    let participants: [ScorerParticipant]?
}
private struct ScorerClock: Decodable { let displayValue: String? }
private struct ScorerType: Decodable { let text: String? }
private struct ScorerTeam: Decodable {
    let abbreviation: String?
    let displayName: String?
}
private struct ScorerParticipant: Decodable { let athlete: ScorerAthlete? }
private struct ScorerAthlete: Decodable { let displayName: String? }
