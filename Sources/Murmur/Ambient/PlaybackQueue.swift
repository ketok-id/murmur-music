import Combine
import Foundation

/// One queued track. UUID-IDed so multiple of the same video can coexist.
struct QueueItem: Codable, Identifiable, Equatable {
    let id: UUID
    let videoID: String
    var title: String
    var thumbnailURL: String
    let addedAt: Date

    var thumb: URL? {
        URL(string: thumbnailURL.isEmpty
            ? "https://img.youtube.com/vi/\(videoID)/mqdefault.jpg"
            : thumbnailURL)
    }
}

/// UserDefaults-backed playback queue. FIFO by default; supports
/// reorder and "play next" insertion at index 0.
final class PlaybackQueue: ObservableObject {
    static let shared = PlaybackQueue()

    @Published private(set) var items: [QueueItem] = []

    private let key = "youtube-audio-widget.playback-queue.v1"

    private init() { load() }

    var count: Int { items.count }
    var isEmpty: Bool { items.isEmpty }

    /// Append to the end.
    func enqueue(videoID: String, title: String, thumbnailURL: String = "") {
        items.append(QueueItem(
            id: UUID(),
            videoID: videoID,
            title: title,
            thumbnailURL: thumbnailURL,
            addedAt: Date()
        ))
        save()
    }

    /// Insert at index 0 — plays after the current track ends.
    func enqueueNext(videoID: String, title: String, thumbnailURL: String = "") {
        items.insert(QueueItem(
            id: UUID(),
            videoID: videoID,
            title: title,
            thumbnailURL: thumbnailURL,
            addedAt: Date()
        ), at: 0)
        save()
    }

    func remove(itemID: UUID) {
        items.removeAll { $0.id == itemID }
        save()
    }

    func move(from source: IndexSet, to destination: Int) {
        items.move(fromOffsets: source, toOffset: destination)
        save()
    }

    func clear() {
        items = []
        save()
    }

    /// Pop the next item (FIFO). Returns nil if queue is empty.
    @discardableResult
    func popNext() -> QueueItem? {
        guard !items.isEmpty else { return nil }
        let item = items.removeFirst()
        save()
        return item
    }

    /// Refill the queue from the YouTube "most popular" chart, respecting the
    /// user's selected region + category. Skips the just-finished video and
    /// anything already present in the queue. Silent no-op if no API key is set
    /// or the network call fails — auto-advance is best-effort.
    @MainActor
    func refillFromTrending(excluding excludeVideoID: String = "", maxItems: Int = 5) async {
        let key = APIKeyStore.shared.youtubeKey
        guard !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let store = TrendingRegionStore.shared
        let existing = Set(items.map { $0.videoID })
        do {
            let results = try await YouTubeSearchAPI.fetchTrending(
                regionCode: store.regionCode,
                apiKey: key,
                categoryId: store.categoryId,
                maxResults: 25
            )
            let fresh = results.filter {
                $0.videoID != excludeVideoID && !existing.contains($0.videoID)
            }
            for result in fresh.prefix(maxItems) {
                enqueue(
                    videoID: result.videoID,
                    title: result.title,
                    thumbnailURL: result.thumbnailURL?.absoluteString ?? ""
                )
            }
        } catch {
            return
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let list = try? JSONDecoder().decode([QueueItem].self, from: data) else { return }
        items = list
    }

    private func save() {
        if let data = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
