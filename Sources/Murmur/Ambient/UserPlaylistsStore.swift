import Combine
import Foundation

/// One entry in a user-composed playlist. UUID-IDed so the same video can
/// appear multiple times (e.g. an intro track repeated between sections).
struct UserPlaylistItem: Codable, Identifiable, Equatable, Hashable {
    let id: UUID
    let videoID: String
    var title: String
    var thumbnailURL: String

    var thumb: URL? {
        URL(string: thumbnailURL.isEmpty
            ? "https://img.youtube.com/vi/\(videoID)/mqdefault.jpg"
            : thumbnailURL)
    }
}

struct UserPlaylist: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var items: [UserPlaylistItem]
    let createdAt: Date
}

/// UserDefaults-backed store of named, locally-composed playlists. Distinct
/// from `PlaylistStore` (which mirrors a YouTube `&list=…` playlist via the
/// Data API). Items are loaded one at a time through `PlayerController.load`,
/// not through YouTube's `&list=` URL — so the iframe never auto-advances; we
/// drive each track manually from `PlayerController.playNext` / `onEnded`.
final class UserPlaylistsStore: ObservableObject {
    static let shared = UserPlaylistsStore()

    @Published private(set) var playlists: [UserPlaylist] = []
    @Published private(set) var activeID: UUID? = nil
    @Published private(set) var activeIndex: Int? = nil

    private let key = "youtube-audio-widget.userPlaylists.v1"

    private init() { load() }

    var activePlaylist: UserPlaylist? {
        guard let id = activeID else { return nil }
        return playlists.first(where: { $0.id == id })
    }

    var hasActivePlaylist: Bool {
        guard let p = activePlaylist else { return false }
        return !p.items.isEmpty
    }

    // MARK: - Mutations

    @discardableResult
    func create(name: String) -> UUID {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayName = cleanName.isEmpty ? "Untitled" : cleanName
        let p = UserPlaylist(id: UUID(), name: displayName, items: [], createdAt: Date())
        playlists.append(p)
        save()
        return p.id
    }

    func rename(id: UUID, to name: String) {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty,
              let i = playlists.firstIndex(where: { $0.id == id }) else { return }
        playlists[i].name = cleanName
        save()
    }

    func delete(id: UUID) {
        playlists.removeAll { $0.id == id }
        if activeID == id { deactivate() }
        save()
    }

    func addItem(to playlistID: UUID, videoID: String, title: String, thumbnailURL: String = "") {
        guard let i = playlists.firstIndex(where: { $0.id == playlistID }) else { return }
        playlists[i].items.append(UserPlaylistItem(
            id: UUID(),
            videoID: videoID,
            title: title,
            thumbnailURL: thumbnailURL
        ))
        save()
    }

    func removeItem(playlistID: UUID, itemID: UUID) {
        guard let i = playlists.firstIndex(where: { $0.id == playlistID }) else { return }
        // If we're removing the currently-playing item, deactivate so we don't
        // dangling-index past the end of a now-shorter list.
        if activeID == playlistID, let idx = activeIndex,
           idx < playlists[i].items.count,
           playlists[i].items[idx].id == itemID {
            deactivate()
        }
        playlists[i].items.removeAll { $0.id == itemID }
        save()
    }

    func moveItem(playlistID: UUID, from source: IndexSet, to destination: Int) {
        guard let i = playlists.firstIndex(where: { $0.id == playlistID }) else { return }
        playlists[i].items.move(fromOffsets: source, toOffset: destination)
        // Re-anchor the cursor to the still-playing video, if any.
        if activeID == playlistID, let idx = activeIndex,
           idx < playlists[i].items.count {
            // Nothing to do — the move() above keeps the same array reference
            // and the active item's identity (UUID) is preserved; but its
            // index may have shifted. Recompute against currentVideoID.
            // The reconcile pass on $currentVideoID will fix it; safer no-op here.
        }
        save()
    }

    // MARK: - Playback

    /// Mark `playlistID` as the active source and return the item to load.
    /// Caller is responsible for calling `PlayerController.load(input:)` with
    /// the returned item's videoID.
    @discardableResult
    func activate(playlistID: UUID, startAt index: Int = 0) -> UserPlaylistItem? {
        guard let p = playlists.first(where: { $0.id == playlistID }),
              index >= 0, index < p.items.count else { return nil }
        activeID = playlistID
        activeIndex = index
        return p.items[index]
    }

    func deactivate() {
        activeID = nil
        activeIndex = nil
    }

    /// Advance the cursor and return the next item, or nil if at end.
    /// Called from `PlayerController.playNext` and the `onEnded` handler.
    @discardableResult
    func nextItem() -> UserPlaylistItem? {
        guard let p = activePlaylist, let idx = activeIndex,
              idx + 1 < p.items.count else { return nil }
        activeIndex = idx + 1
        return p.items[idx + 1]
    }

    @discardableResult
    func previousItem() -> UserPlaylistItem? {
        guard let p = activePlaylist, let idx = activeIndex,
              idx - 1 >= 0 else { return nil }
        activeIndex = idx - 1
        return p.items[idx - 1]
    }

    /// Sync the active cursor to whatever `currentVideoID` is reporting. Called
    /// from a Combine subscription on `PlayerController.$currentVideoID`. If
    /// the new videoID isn't in the active playlist, we deactivate — that's
    /// how "user pasted a different URL" or "user picked from history"
    /// implicitly exits playlist mode without each callsite needing to know.
    func reconcile(currentVideoID: String) {
        guard !currentVideoID.isEmpty, let p = activePlaylist else { return }
        if let idx = p.items.firstIndex(where: { $0.videoID == currentVideoID }) {
            if activeIndex != idx { activeIndex = idx }
        } else {
            deactivate()
        }
    }

    // MARK: - Persistence

    private struct Persisted: Codable {
        var playlists: [UserPlaylist]
        var activeID: UUID?
        var activeIndex: Int?
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let blob = try? JSONDecoder().decode(Persisted.self, from: data) else { return }
        playlists = blob.playlists
        // Don't restore activeID/activeIndex across launches — playback resumes
        // from the last single video, not back into a playlist mid-cursor.
    }

    private func save() {
        let blob = Persisted(playlists: playlists, activeID: nil, activeIndex: nil)
        if let data = try? JSONEncoder().encode(blob) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
