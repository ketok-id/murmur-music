import Foundation

/// One channel-shape result from a YouTube Data API v3 search.
struct YTChannelResult: Identifiable, Equatable {
    let channelId: String
    let title: String
    let thumbnailURL: URL?

    var id: String { channelId }
}
