import Combine
import Foundation

/// UserDefaults-backed store for saved channels.
final class ChannelFavoritesStore: ObservableObject {
    static let shared = ChannelFavoritesStore()

    @Published private(set) var channels: [ChannelFavorite] = []

    private let key = "youtube-audio-widget.channels.v1"

    private init() { load() }

    var isEmpty: Bool { channels.isEmpty }

    func contains(channelId: String) -> Bool {
        channels.contains(where: { $0.channelId == channelId })
    }

    func add(_ channel: ChannelFavorite) {
        if let i = channels.firstIndex(where: { $0.channelId == channel.channelId }) {
            channels[i] = channel
        } else {
            channels.append(channel)
        }
        save()
    }

    func remove(channelId: String) {
        channels.removeAll { $0.channelId == channelId }
        save()
    }

    /// Update only the cached uploadsPlaylistId for a channel.
    func setUploadsPlaylistId(_ playlistId: String, forChannelId channelId: String) {
        guard let i = channels.firstIndex(where: { $0.channelId == channelId }) else { return }
        channels[i].uploadsPlaylistId = playlistId
        save()
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let list = try? JSONDecoder().decode([ChannelFavorite].self, from: data) else { return }
        channels = list
    }

    private func save() {
        if let data = try? JSONEncoder().encode(channels) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
