import Combine
import Foundation

struct PlayedVideoEntry: Codable, Identifiable, Equatable {
    let videoID: String
    var title: String
    var date: Date

    var id: String { videoID }

    var thumbnailURL: URL? {
        URL(string: "https://img.youtube.com/vi/\(videoID)/mqdefault.jpg")
    }
}

final class PlayedVideoHistoryStore: ObservableObject {
    static let shared = PlayedVideoHistoryStore()

    @Published private(set) var entries: [PlayedVideoEntry] = []

    private let key = "youtube-audio-widget.played-history.v1"
    private let cap = 50

    private init() { load() }

    func record(videoID: String, title: String) {
        let trimmedID = videoID.trimmingCharacters(in: .whitespaces)
        guard !trimmedID.isEmpty else { return }
        let cleanedTitle = title.trimmingCharacters(in: .whitespaces)
        var list = entries
        list.removeAll { $0.videoID == trimmedID }
        list.insert(PlayedVideoEntry(videoID: trimmedID, title: cleanedTitle, date: Date()), at: 0)
        if list.count > cap { list = Array(list.prefix(cap)) }
        entries = list
        save()
    }

    func remove(videoID: String) {
        entries.removeAll { $0.videoID == videoID }
        save()
    }

    func clear() {
        entries = []
        save()
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let list = try? JSONDecoder().decode([PlayedVideoEntry].self, from: data) else { return }
        entries = list
    }

    private func save() {
        if let data = try? JSONEncoder().encode(entries) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
