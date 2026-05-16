import Foundation

/// One curated audio-focused topic. Click → run `query` as a YouTube search.
struct DiscoverTopic: Identifiable, Equatable {
    let emoji: String
    let title: String
    let query: String

    var id: String { "\(emoji)|\(title)" }

    static let catalog: [DiscoverTopic] = [
        // Music
        DiscoverTopic(emoji: "🎧", title: "Lofi & Chill",     query: "lofi hip hop study"),
        DiscoverTopic(emoji: "🎵", title: "Music Mixes",      query: "music mix 1 hour"),
        DiscoverTopic(emoji: "🎷", title: "Jazz & Soul",      query: "jazz cafe mix"),
        DiscoverTopic(emoji: "🎼", title: "Classical",        query: "classical music for studying"),
        DiscoverTopic(emoji: "🌌", title: "Ambient",          query: "ambient music long"),
        DiscoverTopic(emoji: "🎶", title: "EDM",              query: "edm mix 2024"),
        DiscoverTopic(emoji: "🎸", title: "Indie",            query: "indie playlist"),
        DiscoverTopic(emoji: "🎹", title: "Piano",            query: "piano music for focus"),

        // Podcasts / talks
        DiscoverTopic(emoji: "🎙️", title: "Tech Podcasts",    query: "tech podcast"),
        DiscoverTopic(emoji: "🎤", title: "Interviews",       query: "interview podcast"),
        DiscoverTopic(emoji: "📚", title: "Audiobooks",       query: "audiobook full"),
        DiscoverTopic(emoji: "🧠", title: "Science Talks",    query: "science talk"),

        // Atmosphere / focus
        DiscoverTopic(emoji: "☔", title: "Rain Sounds",      query: "rain sounds 10 hours"),
        DiscoverTopic(emoji: "🔥", title: "Fireplace",        query: "fireplace ambience"),
        DiscoverTopic(emoji: "📻", title: "Live Radio",       query: "live radio"),
        DiscoverTopic(emoji: "🌊", title: "Nature Sounds",    query: "nature sounds for sleep"),
    ]
}
