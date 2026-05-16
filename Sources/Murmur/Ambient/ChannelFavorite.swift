import Foundation

/// A saved YouTube channel that the user can revisit to browse videos.
struct ChannelFavorite: Codable, Identifiable, Equatable {
    let channelId: String
    var title: String
    /// Channel avatar URL (medium quality).
    var thumbnailURL: String
    /// Cached uploads playlist ID. Empty until first browse fills it in.
    var uploadsPlaylistId: String

    var id: String { channelId }
}
