import Combine
import Foundation

/// One saved search query, with the mode it ran in and when it was last used.
struct SearchHistoryEntry: Codable, Identifiable, Equatable {
    enum Mode: String, Codable {
        case videos, channels
    }
    let query: String
    let mode: Mode
    var date: Date

    /// id = "mode|query" so the same query in two modes is two entries.
    var id: String { "\(mode.rawValue)|\(query)" }
}

/// UserDefaults-backed history of recent YouTube searches. Capped at 20 entries.
final class SearchHistoryStore: ObservableObject {
    static let shared = SearchHistoryStore()

    @Published private(set) var entries: [SearchHistoryEntry] = []

    private let key = "youtube-audio-widget.search-history.v1"
    private let cap = 20

    private init() { load() }

    /// Add or refresh a query. Existing match moves to top with new timestamp.
    func record(query: String, mode: SearchHistoryEntry.Mode) {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let id = "\(mode.rawValue)|\(trimmed)"
        var list = entries
        list.removeAll { $0.id == id }
        list.insert(SearchHistoryEntry(query: trimmed, mode: mode, date: Date()), at: 0)
        if list.count > cap { list = Array(list.prefix(cap)) }
        entries = list
        save()
    }

    func remove(id: String) {
        entries.removeAll { $0.id == id }
        save()
    }

    func clear() {
        entries = []
        save()
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let list = try? JSONDecoder().decode([SearchHistoryEntry].self, from: data) else { return }
        entries = list
    }

    private func save() {
        if let data = try? JSONEncoder().encode(entries) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
