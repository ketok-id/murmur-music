import Combine
import Foundation

/// UserDefaults-backed snapshot of "what was playing when the app last quit"
/// so a relaunch resumes the same video / playlist context instead of
/// dropping back to `kDefaultVideoID`. The in-track playhead is restored
/// separately via `PlayedVideoHistoryStore.lastPosition`. Active user
/// playlist state lives in `UserPlaylistsStore` (it persists its own
/// `activeID` / `activeIndex` for the same reason).
final class LastSessionStore: ObservableObject {
    static let shared = LastSessionStore()

    @Published private(set) var videoID: String = ""
    /// The YouTube `list=…` playlist (PL/RD…) the video was playing inside,
    /// or empty for a standalone video. Restored so YouTube's iframe keeps
    /// auto-advancing the list after relaunch.
    @Published private(set) var ytPlaylistID: String = ""

    private let key = "youtube-audio-widget.lastSession.v1"

    private init() { load() }

    func update(videoID: String, ytPlaylistID: String) {
        let trimmed = videoID.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        if self.videoID == trimmed && self.ytPlaylistID == ytPlaylistID { return }
        self.videoID = trimmed
        self.ytPlaylistID = ytPlaylistID
        save()
    }

    private struct Persisted: Codable {
        var videoID: String
        var ytPlaylistID: String
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let blob = try? JSONDecoder().decode(Persisted.self, from: data) else { return }
        videoID = blob.videoID
        ytPlaylistID = blob.ytPlaylistID
    }

    private func save() {
        let blob = Persisted(videoID: videoID, ytPlaylistID: ytPlaylistID)
        if let data = try? JSONEncoder().encode(blob) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
