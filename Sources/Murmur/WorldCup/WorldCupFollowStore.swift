import Foundation

/// Teams the user follows (by ESPN abbreviation, e.g. "MEX"). Drives the
/// schedule filter, notification scoping, kickoff reminders, and the
/// next-match countdown chip. UserDefaults-backed singleton per the
/// project's store rule.
final class WorldCupFollowStore: ObservableObject {
    static let shared = WorldCupFollowStore()
    private static let key = "youtube-audio-widget.worldcup.followedTeams"

    @Published private(set) var followed: Set<String>

    private init() {
        followed = Set(UserDefaults.standard.stringArray(forKey: Self.key) ?? [])
    }

    func isFollowed(_ abbrev: String) -> Bool { followed.contains(abbrev) }

    func toggle(_ abbrev: String) {
        if followed.contains(abbrev) { followed.remove(abbrev) } else { followed.insert(abbrev) }
        UserDefaults.standard.set(Array(followed).sorted(), forKey: Self.key)
    }

    func involvesFollowedTeam(_ match: WorldCupMatch) -> Bool {
        followed.contains(match.home.abbrev) || followed.contains(match.away.abbrev)
    }
}
