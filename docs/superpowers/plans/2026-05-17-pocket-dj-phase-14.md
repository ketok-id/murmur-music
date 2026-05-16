# Pocket DJ Phase 14 — YouTube Channel Favorites & Browse

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add channel-level browsing to the YouTube search sheet. User flow: switch to "Channels" mode → search for a channel by name → ★ save the ones they want → tap a saved channel → see its recent videos → click a video → loads on the main player.

**Why this is quota-cheap:** A channel-name search costs 100 units (same as video search), but every subsequent browse is just 2 units (channel detail + playlist items). Save 10 channels once, then browse them ~5,000 times/day on the free tier.

**Architecture:**
- `ChannelFavorite` is a Codable model persisted in `UserDefaults` via a new `ChannelFavoritesStore` (mirrors the existing `FavoritesStore` pattern).
- `YouTubeSearchAPI` gains three methods: `searchChannels(query:apiKey:)`, `fetchChannelDetails(channelId:apiKey:)` (returns title, thumbnail, and uploadsPlaylistId), `listChannelUploads(uploadsPlaylistId:apiKey:pageToken:)` (returns video results, paginated).
- `YouTubeSearchSheet` gets a segmented control: **Videos | Channels**. In Channels mode, the search hits `type=channel`; results show the channel avatar + name with a ★ toggle. Below the results, a list of saved channels.
- Picking a channel (saved or search result) navigates into a new `ChannelBrowseView` showing the channel's recent uploads. Picking a video calls back to the sheet's parent.

**Tech Stack:** Same — SwiftUI, URLSession async, AsyncImage. No new dependencies.

**Testing:** `swift build -c release` + manual smoke in Task 8. Requires the API key from Phase 12.

**Prerequisites:** Phase 13 merged into `main`. `YouTubeSearchSheet`, `YouTubeResultsView`, `APIKeyStore` all exist.

---

## File Structure

**New files:**

```
Sources/Murmur/Ambient/
  ChannelFavorite.swift          Codable: channelId, title, thumbnailURL, uploadsPlaylistId?
  ChannelFavoritesStore.swift    UserDefaults-backed CRUD
  YTChannelResult.swift          Channel-shape search result (id, title, thumbnail)
Sources/Murmur/Booth/
  ChannelResultsView.swift       Search-results list for channels with ★ toggle
  ChannelBrowseView.swift        Lists a channel's recent uploads
```

**Modified files:**

- `Sources/Murmur/Ambient/YouTubeSearchAPI.swift` — add `searchChannels`, `fetchChannelDetails`, `listChannelUploads`.
- `Sources/Murmur/YouTubeSearchSheet.swift` — Videos/Channels segmented control + channel browse navigation.

---

### Task 1: ChannelFavorite + ChannelFavoritesStore

**Files:**
- Create: `Sources/Murmur/Ambient/ChannelFavorite.swift`
- Create: `Sources/Murmur/Ambient/ChannelFavoritesStore.swift`

- [ ] **Step 1: ChannelFavorite**

```swift
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
```

- [ ] **Step 2: ChannelFavoritesStore**

```swift
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
```

- [ ] **Step 3: Build + commit**

```bash
cd /Users/mm/Documents/youtube-audio-widget
swift build -c release 2>&1 | tail -5
git add Sources/Murmur/Ambient/ChannelFavorite.swift Sources/Murmur/Ambient/ChannelFavoritesStore.swift
git commit -m "feat(ambient): add ChannelFavorite + ChannelFavoritesStore"
```

---

### Task 2: YTChannelResult model

**Files:**
- Create: `Sources/Murmur/Ambient/YTChannelResult.swift`

- [ ] **Step 1: Implement**

```swift
import Foundation

/// One channel-shape result from a YouTube Data API v3 search.
struct YTChannelResult: Identifiable, Equatable {
    let channelId: String
    let title: String
    let thumbnailURL: URL?

    var id: String { channelId }
}
```

- [ ] **Step 2: Build + commit**

```bash
swift build -c release 2>&1 | tail -5
git add Sources/Murmur/Ambient/YTChannelResult.swift
git commit -m "feat(ambient): add YTChannelResult model"
```

---

### Task 3: YouTubeSearchAPI extensions

**Files:**
- Modify: `Sources/Murmur/Ambient/YouTubeSearchAPI.swift`

Add three methods to the existing enum:
- `searchChannels(query:apiKey:maxResults:)` → `[YTChannelResult]`
- `fetchChannelDetails(channelId:apiKey:)` → `(title: String, thumbnailURL: URL?, uploadsPlaylistId: String)`
- `listChannelUploads(uploadsPlaylistId:apiKey:pageToken:)` → `(videos: [YTSearchResult], nextPageToken: String?)`

- [ ] **Step 1: Add methods**

Open `Sources/Murmur/Ambient/YouTubeSearchAPI.swift`. After the existing `static func search(...)` method (still inside the `enum YouTubeSearchAPI`), add:

```swift
    /// Search YouTube for channels matching the query.
    static func searchChannels(query: String, apiKey: String, maxResults: Int = 10) async throws -> [YTChannelResult] {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedQuery = query.trimmingCharacters(in: .whitespaces)
        guard !trimmedKey.isEmpty else { throw SearchError.noAPIKey }
        guard !trimmedQuery.isEmpty else { return [] }

        var components = URLComponents(string: "https://www.googleapis.com/youtube/v3/search")!
        components.queryItems = [
            URLQueryItem(name: "part", value: "snippet"),
            URLQueryItem(name: "q", value: trimmedQuery),
            URLQueryItem(name: "type", value: "channel"),
            URLQueryItem(name: "maxResults", value: String(maxResults)),
            URLQueryItem(name: "key", value: trimmedKey),
        ]
        guard let url = components.url else { throw SearchError.network("Failed to build URL") }

        let (data, response) = try await safeGET(url: url)
        try checkHTTPStatus(response: response, data: data)

        do {
            let decoded = try JSONDecoder().decode(YouTubeChannelSearchResponse.self, from: data)
            return decoded.items.compactMap { item -> YTChannelResult? in
                guard let channelId = item.id.channelId else { return nil }
                let thumbURL = item.snippet.thumbnails.medium.flatMap { URL(string: $0.url) }
                return YTChannelResult(
                    channelId: channelId,
                    title: item.snippet.title,
                    thumbnailURL: thumbURL
                )
            }
        } catch {
            throw SearchError.decode(error.localizedDescription)
        }
    }

    /// Fetch a channel's title, thumbnail, and uploadsPlaylistId.
    static func fetchChannelDetails(channelId: String, apiKey: String) async throws -> (title: String, thumbnailURL: URL?, uploadsPlaylistId: String) {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else { throw SearchError.noAPIKey }

        var components = URLComponents(string: "https://www.googleapis.com/youtube/v3/channels")!
        components.queryItems = [
            URLQueryItem(name: "part", value: "snippet,contentDetails"),
            URLQueryItem(name: "id", value: channelId),
            URLQueryItem(name: "key", value: trimmedKey),
        ]
        guard let url = components.url else { throw SearchError.network("Failed to build URL") }

        let (data, response) = try await safeGET(url: url)
        try checkHTTPStatus(response: response, data: data)

        do {
            let decoded = try JSONDecoder().decode(YouTubeChannelsListResponse.self, from: data)
            guard let item = decoded.items.first else {
                throw SearchError.decode("Channel not found")
            }
            let thumb = item.snippet.thumbnails.medium.flatMap { URL(string: $0.url) }
            return (
                title: item.snippet.title,
                thumbnailURL: thumb,
                uploadsPlaylistId: item.contentDetails.relatedPlaylists.uploads
            )
        } catch let err as SearchError {
            throw err
        } catch {
            throw SearchError.decode(error.localizedDescription)
        }
    }

    /// List a channel's uploads, newest first. Returns a page of ~50 results +
    /// an optional nextPageToken for further pagination.
    static func listChannelUploads(uploadsPlaylistId: String, apiKey: String, pageToken: String? = nil) async throws -> (videos: [YTSearchResult], nextPageToken: String?) {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else { throw SearchError.noAPIKey }
        guard !uploadsPlaylistId.isEmpty else { return ([], nil) }

        var components = URLComponents(string: "https://www.googleapis.com/youtube/v3/playlistItems")!
        var items = [
            URLQueryItem(name: "part", value: "snippet"),
            URLQueryItem(name: "playlistId", value: uploadsPlaylistId),
            URLQueryItem(name: "maxResults", value: "50"),
            URLQueryItem(name: "key", value: trimmedKey),
        ]
        if let pageToken = pageToken, !pageToken.isEmpty {
            items.append(URLQueryItem(name: "pageToken", value: pageToken))
        }
        components.queryItems = items
        guard let url = components.url else { throw SearchError.network("Failed to build URL") }

        let (data, response) = try await safeGET(url: url)
        try checkHTTPStatus(response: response, data: data)

        do {
            let decoded = try JSONDecoder().decode(YouTubePlaylistItemsResponse.self, from: data)
            let videos = decoded.items.compactMap { item -> YTSearchResult? in
                guard let videoId = item.snippet.resourceId.videoId else { return nil }
                let thumb = item.snippet.thumbnails.medium.flatMap { URL(string: $0.url) }
                return YTSearchResult(
                    videoID: videoId,
                    title: item.snippet.title,
                    channelTitle: item.snippet.channelTitle,
                    thumbnailURL: thumb
                )
            }
            return (videos: videos, nextPageToken: decoded.nextPageToken)
        } catch {
            throw SearchError.decode(error.localizedDescription)
        }
    }

    // MARK: - Shared HTTP helpers (refactored from search)

    private static func safeGET(url: URL) async throws -> (Data, URLResponse) {
        do {
            return try await URLSession.shared.data(from: url)
        } catch {
            throw SearchError.network(error.localizedDescription)
        }
    }

    private static func checkHTTPStatus(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }
        switch http.statusCode {
        case 200: return
        case 400: throw SearchError.invalidKey
        case 403:
            let body = String(data: data, encoding: .utf8) ?? ""
            if body.contains("quotaExceeded") || body.contains("dailyLimitExceeded") {
                throw SearchError.quotaExceeded
            } else {
                throw SearchError.invalidKey
            }
        default:
            throw SearchError.network("HTTP \(http.statusCode)")
        }
    }
```

Then at the bottom of the file (after the existing `YouTubeSearchResponse` private struct), add the new response shapes:

```swift

private struct YouTubeChannelSearchResponse: Decodable {
    let items: [Item]

    struct Item: Decodable {
        let id: IdBlock
        let snippet: Snippet
    }
    struct IdBlock: Decodable {
        let channelId: String?
    }
    struct Snippet: Decodable {
        let title: String
        let thumbnails: Thumbnails
    }
    struct Thumbnails: Decodable {
        let medium: Thumb?
    }
    struct Thumb: Decodable {
        let url: String
    }
}

private struct YouTubeChannelsListResponse: Decodable {
    let items: [Item]

    struct Item: Decodable {
        let snippet: Snippet
        let contentDetails: ContentDetails
    }
    struct Snippet: Decodable {
        let title: String
        let thumbnails: Thumbnails
    }
    struct Thumbnails: Decodable {
        let medium: Thumb?
    }
    struct Thumb: Decodable {
        let url: String
    }
    struct ContentDetails: Decodable {
        let relatedPlaylists: RelatedPlaylists
    }
    struct RelatedPlaylists: Decodable {
        let uploads: String
    }
}

private struct YouTubePlaylistItemsResponse: Decodable {
    let items: [Item]
    let nextPageToken: String?

    struct Item: Decodable {
        let snippet: Snippet
    }
    struct Snippet: Decodable {
        let title: String
        let channelTitle: String
        let thumbnails: Thumbnails
        let resourceId: ResourceId
    }
    struct Thumbnails: Decodable {
        let medium: Thumb?
    }
    struct Thumb: Decodable {
        let url: String
    }
    struct ResourceId: Decodable {
        let videoId: String?
    }
}
```

Also: the existing `search(...)` method has inline HTTP error handling that duplicates `checkHTTPStatus`. Leave the existing method as-is for now — refactoring it isn't necessary, and the duplicated logic is small. Just add the new helpers alongside.

- [ ] **Step 2: Build + commit**

```bash
swift build -c release 2>&1 | tail -10
git add Sources/Murmur/Ambient/YouTubeSearchAPI.swift
git commit -m "feat(ambient): add channel search + browse to YouTubeSearchAPI"
```

---

### Task 4: ChannelResultsView (search results + saved channels)

**Files:**
- Create: `Sources/Murmur/Booth/ChannelResultsView.swift`

Shows channel-search results (with ★ favorite toggle) above a divider, and saved channels below. Picking any channel calls `onPick(channelId)`.

- [ ] **Step 1: Implement**

```swift
import SwiftUI

/// Channels-mode results view. Shows live channel-search results plus saved
/// favorites. Picking a channel (search result or favorite) calls `onPick`.
struct ChannelResultsView: View {
    let query: String      // Empty = show only favorites; non-empty = run search
    var onPick: (ChannelFavorite) -> Void

    @ObservedObject private var apiKeyStore = APIKeyStore.shared
    @ObservedObject private var favorites = ChannelFavoritesStore.shared

    @State private var results: [YTChannelResult] = []
    @State private var loading: Bool = false
    @State private var errorMessage: String? = nil

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if !query.isEmpty {
                    searchSection
                }
                if !favorites.channels.isEmpty {
                    if !query.isEmpty {
                        Divider().background(Color.white.opacity(0.06)).padding(.vertical, 4)
                    }
                    savedSection
                }
                if query.isEmpty && favorites.channels.isEmpty {
                    emptyState
                }
            }
        }
        .task(id: query) {
            await runSearch()
        }
    }

    @ViewBuilder
    private var searchSection: some View {
        sectionHeader("Search results")
        if loading {
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Searching channels…")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.5))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
        } else if let err = errorMessage {
            Text(err)
                .font(.system(size: 11))
                .foregroundColor(.yellow.opacity(0.8))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
        } else if results.isEmpty {
            Text("No channels found.")
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.4))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
        } else {
            ForEach(results) { result in
                channelRow(
                    title: result.title,
                    thumbnailURL: result.thumbnailURL,
                    isFavorited: favorites.contains(channelId: result.channelId),
                    onTap: {
                        let fav = ChannelFavorite(
                            channelId: result.channelId,
                            title: result.title,
                            thumbnailURL: result.thumbnailURL?.absoluteString ?? "",
                            uploadsPlaylistId: ""
                        )
                        onPick(fav)
                    },
                    onToggleFavorite: {
                        if favorites.contains(channelId: result.channelId) {
                            favorites.remove(channelId: result.channelId)
                        } else {
                            let fav = ChannelFavorite(
                                channelId: result.channelId,
                                title: result.title,
                                thumbnailURL: result.thumbnailURL?.absoluteString ?? "",
                                uploadsPlaylistId: ""
                            )
                            favorites.add(fav)
                        }
                    }
                )
            }
        }
    }

    @ViewBuilder
    private var savedSection: some View {
        sectionHeader("Saved channels")
        ForEach(favorites.channels) { fav in
            channelRow(
                title: fav.title,
                thumbnailURL: URL(string: fav.thumbnailURL),
                isFavorited: true,
                onTap: { onPick(fav) },
                onToggleFavorite: {
                    favorites.remove(channelId: fav.channelId)
                }
            )
        }
    }

    private func sectionHeader(_ label: String) -> some View {
        Text(label.uppercased())
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .tracking(1.5)
            .foregroundColor(.white.opacity(0.4))
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 4)
    }

    private func channelRow(
        title: String,
        thumbnailURL: URL?,
        isFavorited: Bool,
        onTap: @escaping () -> Void,
        onToggleFavorite: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 12) {
            Button(action: onTap) {
                HStack(spacing: 12) {
                    AsyncImage(url: thumbnailURL) { phase in
                        switch phase {
                        case .empty: Rectangle().fill(Color.white.opacity(0.04))
                        case .success(let image): image.resizable().aspectRatio(contentMode: .fill)
                        case .failure:
                            ZStack {
                                Rectangle().fill(Color.white.opacity(0.04))
                                Image(systemName: "person.crop.circle")
                                    .foregroundColor(.white.opacity(0.3))
                            }
                        @unknown default: Color.clear
                        }
                    }
                    .frame(width: 40, height: 40)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color.white.opacity(0.08), lineWidth: 0.5))

                    Text(title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white.opacity(0.92))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button(action: onToggleFavorite) {
                Image(systemName: isFavorited ? "star.fill" : "star")
                    .font(.system(size: 13))
                    .foregroundColor(isFavorited ? .yellow : .white.opacity(0.4))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "person.crop.circle")
                .font(.system(size: 22))
                .foregroundColor(.white.opacity(0.25))
            Text("Search to find channels.")
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.45))
            Text("Saved channels appear here for quick access.")
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.35))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
    }

    private func runSearch() async {
        guard !query.isEmpty else {
            results = []
            errorMessage = nil
            loading = false
            return
        }
        loading = true
        errorMessage = nil
        do {
            results = try await YouTubeSearchAPI.searchChannels(
                query: query, apiKey: apiKeyStore.youtubeKey
            )
        } catch let err as YouTubeSearchAPI.SearchError {
            errorMessage = err.errorDescription
        } catch {
            errorMessage = error.localizedDescription
        }
        loading = false
    }
}
```

- [ ] **Step 2: Build + commit**

```bash
swift build -c release 2>&1 | tail -10
git add Sources/Murmur/Booth/ChannelResultsView.swift
git commit -m "feat(booth): add ChannelResultsView (search + saved channels)"
```

---

### Task 5: ChannelBrowseView (videos of a channel)

**Files:**
- Create: `Sources/Murmur/Booth/ChannelBrowseView.swift`

- [ ] **Step 1: Implement**

```swift
import SwiftUI

/// Browses one channel's recent uploads. Fetches uploadsPlaylistId on first
/// load (if not already cached on the channel favorite), then lists videos.
struct ChannelBrowseView: View {
    let channel: ChannelFavorite
    var onPickVideo: (YTSearchResult) -> Void
    var onBack: () -> Void

    @ObservedObject private var apiKeyStore = APIKeyStore.shared
    @ObservedObject private var favorites = ChannelFavoritesStore.shared

    @State private var videos: [YTSearchResult] = []
    @State private var nextPageToken: String? = nil
    @State private var loading: Bool = true
    @State private var loadingMore: Bool = false
    @State private var errorMessage: String? = nil
    @State private var uploadsPlaylistId: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.6))
                }
                .buttonStyle(.plain)
                AsyncImage(url: URL(string: channel.thumbnailURL)) { phase in
                    switch phase {
                    case .success(let image): image.resizable().aspectRatio(contentMode: .fill)
                    default: Rectangle().fill(Color.white.opacity(0.05))
                    }
                }
                .frame(width: 22, height: 22)
                .clipShape(Circle())
                Text(channel.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white.opacity(0.92))
                    .lineLimit(1)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color.white.opacity(0.03))
            Divider().background(Color.white.opacity(0.06))

            content
        }
        .task {
            await initialLoad()
        }
    }

    @ViewBuilder
    private var content: some View {
        if loading {
            VStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Loading channel uploads…")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.5))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let err = errorMessage {
            VStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 18))
                    .foregroundColor(.yellow.opacity(0.7))
                Text(err)
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if videos.isEmpty {
            Text("No uploads found.")
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.4))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(videos) { video in
                        videoRow(video)
                        if video.id != videos.last?.id {
                            Divider().background(Color.white.opacity(0.04)).padding(.leading, 104)
                        }
                    }
                    if nextPageToken != nil {
                        loadMoreButton
                    }
                }
            }
        }
    }

    private func videoRow(_ video: YTSearchResult) -> some View {
        Button(action: { onPickVideo(video) }) {
            HStack(alignment: .top, spacing: 12) {
                AsyncImage(url: video.thumbnailURL) { phase in
                    switch phase {
                    case .empty: Rectangle().fill(Color.white.opacity(0.05))
                    case .success(let image): image.resizable().aspectRatio(contentMode: .fill)
                    case .failure:
                        ZStack {
                            Rectangle().fill(Color.white.opacity(0.04))
                            Image(systemName: "play.rectangle").foregroundColor(.white.opacity(0.3))
                        }
                    @unknown default: Color.clear
                    }
                }
                .frame(width: 80, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.white.opacity(0.06), lineWidth: 0.5))

                Text(decodeHTMLEntities(video.title))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white.opacity(0.92))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var loadMoreButton: some View {
        Button(action: { Task { await loadMore() } }) {
            HStack(spacing: 6) {
                if loadingMore {
                    ProgressView().controlSize(.small)
                }
                Text(loadingMore ? "Loading…" : "Load more")
                    .font(.system(size: 11, weight: .medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .foregroundColor(.cyan.opacity(0.8))
        }
        .buttonStyle(.plain)
        .disabled(loadingMore)
    }

    private func initialLoad() async {
        loading = true
        errorMessage = nil

        // Resolve uploadsPlaylistId — use cached if available, else fetch.
        var playlistId = channel.uploadsPlaylistId
        if playlistId.isEmpty {
            do {
                let details = try await YouTubeSearchAPI.fetchChannelDetails(
                    channelId: channel.channelId, apiKey: apiKeyStore.youtubeKey
                )
                playlistId = details.uploadsPlaylistId
                // Persist the discovered id back to the favorite so future
                // browses skip this lookup.
                if favorites.contains(channelId: channel.channelId) {
                    favorites.setUploadsPlaylistId(playlistId, forChannelId: channel.channelId)
                }
            } catch let err as YouTubeSearchAPI.SearchError {
                errorMessage = err.errorDescription
                loading = false
                return
            } catch {
                errorMessage = error.localizedDescription
                loading = false
                return
            }
        }
        uploadsPlaylistId = playlistId

        // Fetch first page of uploads.
        do {
            let page = try await YouTubeSearchAPI.listChannelUploads(
                uploadsPlaylistId: playlistId, apiKey: apiKeyStore.youtubeKey
            )
            videos = page.videos
            nextPageToken = page.nextPageToken
        } catch let err as YouTubeSearchAPI.SearchError {
            errorMessage = err.errorDescription
        } catch {
            errorMessage = error.localizedDescription
        }
        loading = false
    }

    private func loadMore() async {
        guard let token = nextPageToken, !loadingMore else { return }
        loadingMore = true
        do {
            let page = try await YouTubeSearchAPI.listChannelUploads(
                uploadsPlaylistId: uploadsPlaylistId,
                apiKey: apiKeyStore.youtubeKey,
                pageToken: token
            )
            videos.append(contentsOf: page.videos)
            nextPageToken = page.nextPageToken
        } catch {
            // Silently fail on pagination — keep existing results.
        }
        loadingMore = false
    }

    private func decodeHTMLEntities(_ s: String) -> String {
        guard let data = s.data(using: .utf8) else { return s }
        if let attributed = try? NSAttributedString(
            data: data,
            options: [.documentType: NSAttributedString.DocumentType.html,
                      .characterEncoding: String.Encoding.utf8.rawValue],
            documentAttributes: nil
        ) {
            return attributed.string
        }
        return s
    }
}
```

- [ ] **Step 2: Build + commit**

```bash
swift build -c release 2>&1 | tail -10
git add Sources/Murmur/Booth/ChannelBrowseView.swift
git commit -m "feat(booth): add ChannelBrowseView (channel uploads list + pagination)"
```

---

### Task 6: Wire mode switcher + channel browse navigation into YouTubeSearchSheet

**Files:**
- Modify: `Sources/Murmur/YouTubeSearchSheet.swift`

Add a segmented Picker at the top for Videos / Channels. In Channels mode, render `ChannelResultsView`. Picking a channel pushes into `ChannelBrowseView`. Picking a video from the browse calls `onPick(videoID)` and dismisses.

- [ ] **Step 1: Replace YouTubeSearchSheet body**

Open `Sources/Murmur/YouTubeSearchSheet.swift`. Replace the existing `body` and `content` blocks with this expanded version. Keep the existing `header`, `noKeyState`, `placeholderState`, `canSearch`, `activate()` private members as-is.

Find the `body` and `content` blocks and replace with:

```swift
    enum Mode: String, CaseIterable, Identifiable {
        case videos, channels
        var id: String { rawValue }
        var label: String {
            switch self {
            case .videos: return "Videos"
            case .channels: return "Channels"
            }
        }
    }

    @State private var mode: Mode = .videos
    @State private var browsing: ChannelFavorite? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().background(Color.white.opacity(0.08))
            modePicker
            searchRow
            Divider().background(Color.white.opacity(0.06))
            content
        }
        .frame(width: 420, height: 540)
        .background(Color(white: 0.05))
        .onAppear { searchFocused = true }
    }

    private var modePicker: some View {
        Picker("", selection: $mode) {
            ForEach(Mode.allCases) { mode in
                Text(mode.label).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .padding(.horizontal, 14)
        .padding(.top, 8)
        .padding(.bottom, 2)
        .onChange(of: mode) { _ in
            // Switching mode clears the in-progress query so the new mode
            // starts fresh.
            activeQuery = ""
            browsing = nil
        }
    }

    @ViewBuilder
    private var content: some View {
        if !apiKeyStore.hasYouTubeKey {
            noKeyState
        } else if let channel = browsing {
            ChannelBrowseView(
                channel: channel,
                onPickVideo: { video in
                    onPick(video.videoID)
                    dismiss()
                },
                onBack: { browsing = nil }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            switch mode {
            case .videos:
                if activeQuery.isEmpty {
                    placeholderState
                } else {
                    YouTubeResultsView(
                        query: activeQuery,
                        onPick: { result in
                            onPick(result.videoID)
                            dismiss()
                        },
                        onBack: { activeQuery = "" },
                        showHeader: false
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            case .channels:
                ChannelResultsView(
                    query: activeQuery,
                    onPick: { channel in
                        browsing = channel
                    }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
```

Also, update the `searchRow` placeholder text to be mode-aware. Find:

```swift
            TextField("e.g. lofi study, synthwave radio, ocean waves…", text: $draftQuery)
```

Replace with:

```swift
            TextField(mode == .videos
                      ? "e.g. lofi study, synthwave radio, ocean waves…"
                      : "Channel name (e.g. lofi girl)", text: $draftQuery)
```

- [ ] **Step 2: Build + commit**

```bash
swift build -c release 2>&1 | tail -10
git add Sources/Murmur/YouTubeSearchSheet.swift
git commit -m "feat(popover): add Channels mode + browse to YouTubeSearchSheet"
```

---

### Task 7: Build bundle + smoke + tag + merge

- [ ] **Step 1: Build**

```bash
./build-app.sh --sign 2>&1 | tail -10
```

- [ ] **Step 2: Manual smoke**

Quit any running Murmur instance. `open dist/Murmur.app`. Ensure your API key from Phase 12 is still configured (gear icon should be cyan).

1. Click menu-bar Murmur → popover → search icon (🔍). Sheet opens, now with a **Videos | Channels** segmented control at the top.
2. **Videos mode** (default): same as Phase 13 — type "lofi study", press Return → results, pick → load.
3. Switch to **Channels** mode. Search field placeholder changes to "Channel name…". If you have no saved channels yet, you see "Search to find channels."
4. Type "Lofi Girl" → press Return. Spinner → list of channel results with **round avatars** + channel name + **★ star button** on the right.
5. Click the ★ next to "Lofi Girl" → star fills yellow. Channel persists in `UserDefaults`. Switch off the mode and back — saved channel appears in the "Saved channels" section below.
6. Click on the channel row itself (not the star) → view switches to **ChannelBrowseView**: header has back arrow + small channel avatar + channel name; below it lists ~50 recent uploads with the same row design as search results.
7. Click a video → sheet dismisses, main player loads it.
8. Re-open search sheet → still in Channels mode (you may have to switch back). Click the saved channel → instantly opens browse (this time with cached `uploadsPlaylistId`, no extra channel-details call).
9. Scroll to bottom of browse list, click **Load more** → next 50 uploads append. Cost: 1 quota unit.
10. Star-toggle an unwanted channel off → it disappears from saved list immediately.
11. Quit + relaunch the app → saved channels persist.

- [ ] **Step 3: Tag**

```bash
git tag -a phase-14-channel-favorites -m "Pocket DJ Phase 14: YouTube channel favorites + browse"
```

- [ ] **Step 4: Merge to main**

```bash
git checkout main
git merge --no-ff pocket-dj-phase-14 -m "Merge phase 14: YouTube channel favorites + browse"
./build-app.sh --sign 2>&1 | tail -5
```

---

## Out of scope for Phase 14

- **Channel URL paste** (e.g., pasting `https://youtube.com/@lofigirl` to directly browse): could be a small follow-up using `forHandle=` in `channels.list`.
- **Subscriber/video counts** on channel rows: extra `part=statistics` fields, slight quota bump.
- **Drag-reorder of saved channels.**
- **Search by both videos AND channels at once.**
- **Caching playlist items between sessions** (currently each session re-fetches).

---

## Self-Review

- **Quota costs accurate**: search-channels 100u; channel-details 1u (cached after first browse); playlist-items 1u per page of 50. ✅
- **Cache `uploadsPlaylistId` to skip the channel-details call** on repeat browses: ✅ via `ChannelFavoritesStore.setUploadsPlaylistId`.
- **Persistent saved channels** via UserDefaults under `youtube-audio-widget.channels.v1`: ✅
- **Mode switch clears in-progress query** to avoid stale results: ✅
- **Picked video loads on main player** via same `controller.load(input:)` path as existing flow: ✅
- **Pagination** with Load More button: ✅, silent error handling for paginated fetches.

No spec gaps for the in-scope set. Type signatures consistent: `ChannelFavorite.channelId/title/thumbnailURL/uploadsPlaylistId`, `YTChannelResult.channelId/title/thumbnailURL`, `YouTubeSearchAPI.searchChannels/fetchChannelDetails/listChannelUploads`.
