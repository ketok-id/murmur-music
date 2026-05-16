import Combine
import Foundation

/// `UserDefaults`-backed store for the YouTube Data API v3 key.
final class APIKeyStore: ObservableObject {
    static let shared = APIKeyStore()

    @Published var youtubeKey: String

    private let defaultsKey = "youtube-audio-widget.yt-api-key.v1"

    private init() {
        self.youtubeKey = UserDefaults.standard.string(forKey: defaultsKey) ?? ""
    }

    var hasYouTubeKey: Bool {
        !youtubeKey.trimmingCharacters(in: .whitespaces).isEmpty
    }

    func setYouTubeKey(_ key: String) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        youtubeKey = trimmed
        if trimmed.isEmpty {
            UserDefaults.standard.removeObject(forKey: defaultsKey)
        } else {
            UserDefaults.standard.set(trimmed, forKey: defaultsKey)
        }
    }
}
