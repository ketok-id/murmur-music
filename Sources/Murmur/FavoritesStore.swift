import Combine
import Foundation

// MARK: - Favorites (persisted to UserDefaults)

struct Favorite: Codable, Identifiable, Hashable {
    var name: String
    var videoID: String
    var id: String { videoID }
}

/// Singleton store backing the user's saved-favorites menu. Pure
/// UserDefaults-backed with no constructor dependencies, so it follows
/// the same `.shared` pattern as the other data stores in `Ambient/`
/// (e.g. `ChannelFavoritesStore`, `PlayedVideoHistoryStore`,
/// `UserPlaylistsStore`). Reach for `FavoritesStore.shared` directly
/// inside views — no `@EnvironmentObject` plumbing needed.
final class FavoritesStore: ObservableObject {
    static let shared = FavoritesStore()

    @Published var items: [Favorite] = []
    private let key = "youtube-audio-widget.favorites.v1"

    private init() { load() }

    func load() {
        if let data = UserDefaults.standard.data(forKey: key),
           let list = try? JSONDecoder().decode([Favorite].self, from: data) {
            items = list
            return
        }
        // First-launch seed.
        items = [
            Favorite(name: "Lofi Girl", videoID: "jfKfPfyJRdk"),
        ]
        save()
    }

    func save() {
        if let data = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    func add(name: String, videoID: String) {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayName = cleanName.isEmpty ? videoID : cleanName
        // Replace if same ID already exists, otherwise append.
        if let i = items.firstIndex(where: { $0.videoID == videoID }) {
            items[i].name = displayName
        } else {
            items.append(Favorite(name: displayName, videoID: videoID))
        }
        save()
    }

    func remove(_ favorite: Favorite) {
        items.removeAll { $0.videoID == favorite.videoID }
        save()
    }
}
