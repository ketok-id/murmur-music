import Foundation
import SwiftUI

struct PlaylistEntry: Identifiable, Equatable {
    let videoID: String
    let title: String
    let channelTitle: String
    let thumbnailURL: URL?

    var id: String { videoID }
}

/// Holds the currently-loaded YouTube playlist's enumerated items and tracks
/// which video is playing. Driven by:
///   - `load(playlistID:apiKey:)` when the user opens a `PL…` link
///   - `updateCurrent(videoID:)` whenever the iframe reports a new active video
///     (initial load and YouTube's auto-advance through the playlist)
///
/// Mixes (`RD…`) are not enumerable through the Data API, so the store is
/// cleared whenever an unsupported playlist is loaded.
final class PlaylistStore: ObservableObject {
    static let shared = PlaylistStore()

    @Published private(set) var playlistID: String = ""
    @Published private(set) var items: [PlaylistEntry] = []
    @Published private(set) var currentIndex: Int? = nil
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var errorMessage: String? = nil

    private var loadTask: Task<Void, Never>?

    private init() {}

    var isEmpty: Bool { items.isEmpty }
    var hasActivePlaylist: Bool { !playlistID.isEmpty && !items.isEmpty }

    /// Load the enumerated items for a `PL…` playlist. Cancels any in-flight
    /// load. No-ops for empty IDs or `RD…` mixes.
    func load(playlistID: String, apiKey: String) {
        let trimmedID = playlistID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedID.isEmpty, !trimmedID.hasPrefix("RD") else {
            clear()
            return
        }
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else {
            clear()
            return
        }
        loadTask?.cancel()
        self.playlistID = trimmedID
        self.items = []
        self.currentIndex = nil
        self.isLoading = true
        self.errorMessage = nil

        loadTask = Task { [weak self] in
            await self?.runLoad(playlistID: trimmedID, apiKey: trimmedKey)
        }
    }

    private func runLoad(playlistID: String, apiKey: String) async {
        var collected: [PlaylistEntry] = []
        var pageToken: String? = nil
        do {
            repeat {
                if Task.isCancelled { return }
                let page = try await YouTubeSearchAPI.fetchPlaylistItems(
                    playlistId: playlistID,
                    apiKey: apiKey,
                    pageToken: pageToken
                )
                collected.append(contentsOf: page.videos.map {
                    PlaylistEntry(
                        videoID: $0.videoID,
                        title: $0.title,
                        channelTitle: $0.channelTitle,
                        thumbnailURL: $0.thumbnailURL
                    )
                })
                pageToken = page.nextPageToken
                // Cap at 200 items so a 5000-track playlist doesn't burn 100 quota.
                if collected.count >= 200 { break }
            } while pageToken != nil && !pageToken!.isEmpty

            let final = collected
            await MainActor.run {
                self.items = final
                self.isLoading = false
                self.errorMessage = nil
            }
        } catch let err as YouTubeSearchAPI.SearchError {
            await MainActor.run {
                self.isLoading = false
                self.errorMessage = err.errorDescription
            }
        } catch {
            let msg = error.localizedDescription
            await MainActor.run {
                self.isLoading = false
                self.errorMessage = msg
            }
        }
    }

    /// Update which entry is active based on the currently-playing videoID.
    /// Called from the iframe bridge — both on initial load and every time
    /// YouTube auto-advances through the playlist.
    func updateCurrent(videoID: String) {
        guard !items.isEmpty else { return }
        if let idx = items.firstIndex(where: { $0.videoID == videoID }) {
            currentIndex = idx
        }
    }

    func clear() {
        loadTask?.cancel()
        loadTask = nil
        playlistID = ""
        items = []
        currentIndex = nil
        isLoading = false
        errorMessage = nil
    }
}
