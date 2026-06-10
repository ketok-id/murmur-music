import Foundation

struct CustomLiveSource: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    /// Channel URL as the user entered it, e.g. "https://www.youtube.com/@MotionGrade".
    var channelURL: String

    /// `/live` variant the resolver hits to find the current stream.
    var liveURL: URL? {
        let trimmed = channelURL.hasSuffix("/live")
            ? channelURL
            : channelURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/live"
        return URL(string: trimmed)
    }

    var fallbackURL: URL? { URL(string: channelURL) }
}

/// User-added "listen live" chips — any YouTube channel (a local commentary
/// channel, a favorite radio) resolved through the same `/live` scrape as
/// the built-ins. Persisted as JSON in UserDefaults.
final class WorldCupCustomSourcesStore: ObservableObject {
    static let shared = WorldCupCustomSourcesStore()
    private static let key = "youtube-audio-widget.worldcup.customSources"

    @Published private(set) var items: [CustomLiveSource]

    private init() {
        let data = UserDefaults.standard.data(forKey: Self.key) ?? Data()
        items = (try? JSONDecoder().decode([CustomLiveSource].self, from: data)) ?? []
    }

    /// Returns false (and adds nothing) unless the URL looks like a YouTube
    /// channel the `/live` scrape can work with.
    @discardableResult
    func add(name: String, channelURL: String) -> Bool {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        var url = channelURL.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty, !url.isEmpty else { return false }
        // Accept "youtube.com/@handle" without a scheme.
        if !url.lowercased().hasPrefix("http") { url = "https://" + url }
        guard url.lowercased().contains("youtube.com/") || url.lowercased().contains("youtu.be/"),
              URL(string: url) != nil
        else { return false }
        // Store the channel root; liveURL appends /live itself.
        if url.hasSuffix("/live") { url = String(url.dropLast(5)) }
        items.append(CustomLiveSource(id: UUID(), name: trimmedName, channelURL: url))
        persist()
        return true
    }

    func remove(id: UUID) {
        items.removeAll { $0.id == id }
        persist()
    }

    private func persist() {
        UserDefaults.standard.set(try? JSONEncoder().encode(items), forKey: Self.key)
    }
}
