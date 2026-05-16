# Pocket DJ Phase 16 — Played-Video History + Channel URL Paste

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Two small features.
1. **Played-video history** — record videos as they load on the main player; show them as a "RECENT VIDEOS" section (with thumbnails) in the search sheet's empty state.
2. **Channel URL paste** — let users paste a YouTube channel URL or `@handle` into the Channels-mode search field. Instead of a 100-unit name search, resolve directly via `channels.list?forHandle=…` (1 unit).

**Architecture:**

- `PlayedVideoEntry` + `PlayedVideoHistoryStore` mirror the existing `SearchHistoryStore` pattern — `UserDefaults` JSON, capped at 50, dedup-and-promote.
- `PlayerController` records on `title` changes (title fires when the YouTube iframe reports it, which means the video actually loaded). We record `(videoID, title, date)`.
- `YouTubeSearchSheet`'s videos-mode placeholder gets a new "RECENT VIDEOS" section above the existing "RECENT SEARCHES" section. YouTube thumbnail URLs are built deterministically from videoID (`https://img.youtube.com/vi/<id>/mqdefault.jpg`) — no extra API calls needed.
- `YouTubeChannelURL.parse(_:)` handles `youtube.com/@handle`, `youtube.com/channel/UC…`, `@handle` bare, and `UC...` bare IDs.
- `YouTubeSearchAPI.fetchChannelByHandle(handle:apiKey:)` does a single `channels.list?forHandle=…` lookup (1 unit) and returns channelId + title + thumbnail + uploadsPlaylistId.
- `ChannelResultsView` detects URL/handle input and routes to direct-lookup instead of search — the resolved channel appears as a single result row with a ★ to favorite.

**Tech Stack:** Same. No new dependencies.

**Testing:** `swift build -c release` + manual smoke in Task 7.

**Prerequisites:** Phase 15 merged into `main`.

---

## File Structure

**New files:**

```
Sources/Murmur/Ambient/
  PlayedVideoHistoryStore.swift   Entry model + store, mirrors SearchHistoryStore
  YouTubeChannelURL.swift          Parse YouTube channel URLs / handles
```

**Modified files:**

- `Sources/Murmur/main.swift` — wire `PlayerController.title` updates into the history store.
- `Sources/Murmur/Ambient/YouTubeSearchAPI.swift` — add `fetchChannelByHandle`.
- `Sources/Murmur/YouTubeSearchSheet.swift` — RECENT VIDEOS section in videos placeholder.
- `Sources/Murmur/Booth/ChannelResultsView.swift` — URL/handle detect → direct-lookup fast path.

---

### Task 1: PlayedVideoHistoryStore

**Files:**
- Create: `Sources/Murmur/Ambient/PlayedVideoHistoryStore.swift`

- [ ] **Step 1: Implement**

```swift
import Combine
import Foundation

/// One video that was loaded on the main player.
struct PlayedVideoEntry: Codable, Identifiable, Equatable {
    let videoID: String
    var title: String
    var date: Date

    var id: String { videoID }

    /// Deterministic YouTube thumbnail URL — no API call needed.
    var thumbnailURL: URL? {
        URL(string: "https://img.youtube.com/vi/\(videoID)/mqdefault.jpg")
    }
}

/// UserDefaults-backed history of videos played on the main player.
/// Capped at 50; dedup-by-videoID; re-loading promotes to top.
final class PlayedVideoHistoryStore: ObservableObject {
    static let shared = PlayedVideoHistoryStore()

    @Published private(set) var entries: [PlayedVideoEntry] = []

    private let key = "youtube-audio-widget.played-history.v1"
    private let cap = 50

    private init() { load() }

    /// Record (or refresh) a played video. Empty title is fine; will be
    /// overwritten when the next `record` arrives with the real title.
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
```

- [ ] **Step 2: Build + commit**

```bash
cd /Users/mm/Documents/youtube-audio-widget
swift build -c release 2>&1 | tail -5
git add Sources/Murmur/Ambient/PlayedVideoHistoryStore.swift
git commit -m "feat(ambient): add PlayedVideoHistoryStore"
```

---

### Task 2: Wire PlayerController to record played videos

**Files:**
- Modify: `Sources/Murmur/main.swift`

The cleanest hook: PlayerController's `title` is `@Published`; we subscribe to its updates and record `(currentVideoID, title)` when a title arrives. Avoid recording on the initial empty title.

- [ ] **Step 1: Add a Combine subscription on AppDelegate init**

In `Sources/Murmur/main.swift`, find `AppDelegate`. The properties block currently includes `let controller = PlayerController()`. After the existing property declarations, add:

```swift
    private var historyCancellable: AnyCancellable?
```

You'll need `import Combine` at the top of the file (likely already imported via UIKit/SwiftUI; verify by checking the imports — if `import Combine` is missing, add it under the existing imports).

Then in `applicationDidFinishLaunching`, near the existing engine startup block, add:

```swift
        // Record videos to history as their titles arrive.
        historyCancellable = controller.$title
            .removeDuplicates()
            .sink { [weak self] title in
                guard let self = self else { return }
                let trimmedTitle = title.trimmingCharacters(in: .whitespaces)
                // Skip empty + the boilerplate "Loading…" / "YouTube Live Stream" defaults.
                let videoID = self.controller.currentVideoID
                guard !trimmedTitle.isEmpty,
                      trimmedTitle != "Loading…",
                      trimmedTitle != "YouTube Live Stream",
                      !videoID.isEmpty else { return }
                PlayedVideoHistoryStore.shared.record(videoID: videoID, title: trimmedTitle)
            }
```

Place that block after `do { try mixer.start() ... }` or anywhere convenient in `applicationDidFinishLaunching`. The exact line position doesn't matter — just needs to execute once during launch.

- [ ] **Step 2: Build + commit**

```bash
swift build -c release 2>&1 | tail -10
git add Sources/Murmur/main.swift
git commit -m "feat(player): record played videos to history on title updates"
```

---

### Task 3: RECENT VIDEOS section in YouTubeSearchSheet

**Files:**
- Modify: `Sources/Murmur/YouTubeSearchSheet.swift`

Add the played-history store; rebuild `placeholderState` to include RECENT VIDEOS at the top (videos mode only) followed by RECENT SEARCHES below.

- [ ] **Step 1: Add store observation**

Find the existing line `@ObservedObject private var history = SearchHistoryStore.shared` (added in Phase 15). Immediately after it, add:

```swift
    @ObservedObject private var played = PlayedVideoHistoryStore.shared
```

- [ ] **Step 2: Restructure `placeholderState`**

Find the existing `placeholderState` computed property. Replace it ENTIRELY with:

```swift
    @ViewBuilder
    private var placeholderState: some View {
        if history.entries.isEmpty && played.entries.isEmpty {
            VStack(spacing: 6) {
                Image(systemName: "play.rectangle.on.rectangle")
                    .font(.system(size: 22))
                    .foregroundColor(.white.opacity(0.25))
                Text("Type a query and press Return.")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.45))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if !played.entries.isEmpty && mode == .videos {
                        recentVideosSection
                    }
                    if !history.entries.isEmpty {
                        if !played.entries.isEmpty && mode == .videos {
                            Divider().background(Color.white.opacity(0.04))
                        }
                        recentSearchesSection
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    @ViewBuilder
    private var recentVideosSection: some View {
        HStack {
            Text("RECENT VIDEOS")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .tracking(1.5)
                .foregroundColor(.white.opacity(0.4))
            Spacer()
            Button("Clear") { played.clear() }
                .buttonStyle(.plain)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.white.opacity(0.4))
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 6)

        ForEach(played.entries.prefix(10)) { entry in
            playedRow(entry)
            if entry.id != played.entries.prefix(10).last?.id {
                Divider().background(Color.white.opacity(0.04)).padding(.leading, 104)
            }
        }
    }

    @ViewBuilder
    private var recentSearchesSection: some View {
        HStack {
            Text("RECENT SEARCHES")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .tracking(1.5)
                .foregroundColor(.white.opacity(0.4))
            Spacer()
            Button("Clear") { history.clear() }
                .buttonStyle(.plain)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.white.opacity(0.4))
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 6)

        ForEach(history.entries) { entry in
            historyRow(entry)
            if entry.id != history.entries.last?.id {
                Divider().background(Color.white.opacity(0.04)).padding(.leading, 38)
            }
        }
    }

    private func playedRow(_ entry: PlayedVideoEntry) -> some View {
        HStack(spacing: 10) {
            Button(action: { onPick(entry.videoID); dismiss() }) {
                HStack(spacing: 12) {
                    AsyncImage(url: entry.thumbnailURL) { phase in
                        switch phase {
                        case .success(let image): image.resizable().aspectRatio(contentMode: .fill)
                        default: Rectangle().fill(Color.white.opacity(0.05))
                        }
                    }
                    .frame(width: 80, height: 48)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.white.opacity(0.06), lineWidth: 0.5))

                    Text(entry.title.isEmpty ? entry.videoID : entry.title)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.9))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button(action: { played.remove(videoID: entry.videoID) }) {
                Image(systemName: "xmark.circle")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.3))
            }
            .buttonStyle(.plain)
            .help("Remove from history")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
```

- [ ] **Step 3: Build + commit**

```bash
swift build -c release 2>&1 | tail -10
git add Sources/Murmur/YouTubeSearchSheet.swift
git commit -m "feat(popover): add RECENT VIDEOS section to search sheet placeholder"
```

---

### Task 4: YouTubeChannelURL parser

**Files:**
- Create: `Sources/Murmur/Ambient/YouTubeChannelURL.swift`

- [ ] **Step 1: Implement**

```swift
import Foundation

/// Parser for YouTube channel references: URLs (modern + legacy paths),
/// `@handle`, or raw channel IDs (`UC…`, 24 chars).
enum YouTubeChannelURL {
    /// Either a direct channel ID or a YouTube handle (with @).
    enum Result: Equatable {
        case channelId(String)
        case handle(String)        // includes leading "@"
    }

    /// Returns a Result if the input looks like a channel reference; nil if not.
    static func parse(_ input: String) -> Result? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }

        // Bare channel ID (UC + 22 chars, total 24).
        if isChannelId(trimmed) { return .channelId(trimmed) }

        // Bare handle "@something" (3+ chars after @).
        if trimmed.hasPrefix("@"), trimmed.count >= 4 { return .handle(trimmed) }

        // URL forms.
        let urlString: String
        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
            urlString = trimmed
        } else if trimmed.hasPrefix("youtube.com/") || trimmed.hasPrefix("www.youtube.com/") || trimmed.hasPrefix("m.youtube.com/") {
            urlString = "https://" + trimmed
        } else {
            return nil
        }

        guard let url = URL(string: urlString) else { return nil }
        guard let host = url.host?.lowercased(), host.hasSuffix("youtube.com") else { return nil }

        let path = url.path
        // /@handle  → handle
        if path.hasPrefix("/@") {
            let handle = String(path.dropFirst())  // drops the leading '/'
            return handle.count >= 4 ? .handle(handle) : nil
        }
        // /channel/UC...  → channel ID
        if path.hasPrefix("/channel/") {
            let id = String(path.dropFirst("/channel/".count))
                .split(separator: "/").first.map(String.init) ?? ""
            return isChannelId(id) ? .channelId(id) : nil
        }
        return nil
    }

    private static func isChannelId(_ s: String) -> Bool {
        guard s.hasPrefix("UC"), s.count == 24 else { return false }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        return s.unicodeScalars.allSatisfy { allowed.contains($0) }
    }
}
```

- [ ] **Step 2: Build + commit**

```bash
swift build -c release 2>&1 | tail -5
git add Sources/Murmur/Ambient/YouTubeChannelURL.swift
git commit -m "feat(ambient): add YouTubeChannelURL parser"
```

---

### Task 5: YouTubeSearchAPI.fetchChannelByHandle

**Files:**
- Modify: `Sources/Murmur/Ambient/YouTubeSearchAPI.swift`

- [ ] **Step 1: Add new method**

Find the existing `fetchChannelDetails(channelId:apiKey:)` method inside `enum YouTubeSearchAPI`. Immediately after it, add:

```swift
    /// Resolve a YouTube handle (e.g. "@lofigirl") to channel info via
    /// `channels.list?forHandle=…`. Costs 1 quota unit (same as fetchChannelDetails).
    static func fetchChannelByHandle(handle: String, apiKey: String) async throws -> (channelId: String, title: String, thumbnailURL: URL?, uploadsPlaylistId: String) {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else { throw SearchError.noAPIKey }
        let cleanHandle = handle.hasPrefix("@") ? handle : "@" + handle

        var components = URLComponents(string: "https://www.googleapis.com/youtube/v3/channels")!
        components.queryItems = [
            URLQueryItem(name: "part", value: "snippet,contentDetails"),
            URLQueryItem(name: "forHandle", value: cleanHandle),
            URLQueryItem(name: "key", value: trimmedKey),
        ]
        guard let url = components.url else { throw SearchError.network("Failed to build URL") }

        let (data, response) = try await safeGET(url: url)
        try checkHTTPStatus(response: response, data: data)

        do {
            let decoded = try JSONDecoder().decode(YouTubeChannelsListWithIdResponse.self, from: data)
            guard let item = decoded.items.first else {
                throw SearchError.decode("Channel not found for \(cleanHandle)")
            }
            let thumb = item.snippet.thumbnails.medium.flatMap { URL(string: $0.url) }
            return (
                channelId: item.id,
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
```

Then at the bottom of the file (after the existing `YouTubeChannelsListResponse` private struct), add a new response struct (with an `id` field, since `forHandle` returns the channel id):

```swift

private struct YouTubeChannelsListWithIdResponse: Decodable {
    let items: [Item]

    struct Item: Decodable {
        let id: String
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
```

- [ ] **Step 2: Build + commit**

```bash
swift build -c release 2>&1 | tail -10
git add Sources/Murmur/Ambient/YouTubeSearchAPI.swift
git commit -m "feat(ambient): add fetchChannelByHandle to YouTubeSearchAPI"
```

---

### Task 6: ChannelResultsView — URL/handle fast path

**Files:**
- Modify: `Sources/Murmur/Booth/ChannelResultsView.swift`

When the query parses as a YouTube channel URL/handle, do a direct lookup (1 unit) instead of `searchChannels` (100 units). Result is a single channel; same `YTChannelResult` shape.

- [ ] **Step 1: Update `runSearch`**

Find the existing `runSearch` method:

```swift
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
```

Replace with:

```swift
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
            // URL/handle fast path — 1 unit instead of 100.
            if let parsed = YouTubeChannelURL.parse(query) {
                let channelId: String
                let title: String
                let thumb: URL?
                switch parsed {
                case .channelId(let id):
                    let details = try await YouTubeSearchAPI.fetchChannelDetails(
                        channelId: id, apiKey: apiKeyStore.youtubeKey
                    )
                    channelId = id
                    title = details.title
                    thumb = details.thumbnailURL
                case .handle(let handle):
                    let resolved = try await YouTubeSearchAPI.fetchChannelByHandle(
                        handle: handle, apiKey: apiKeyStore.youtubeKey
                    )
                    channelId = resolved.channelId
                    title = resolved.title
                    thumb = resolved.thumbnailURL
                }
                results = [YTChannelResult(channelId: channelId, title: title, thumbnailURL: thumb)]
            } else {
                results = try await YouTubeSearchAPI.searchChannels(
                    query: query, apiKey: apiKeyStore.youtubeKey
                )
            }
        } catch let err as YouTubeSearchAPI.SearchError {
            errorMessage = err.errorDescription
        } catch {
            errorMessage = error.localizedDescription
        }
        loading = false
    }
```

- [ ] **Step 2: Build + commit**

```bash
swift build -c release 2>&1 | tail -10
git add Sources/Murmur/Booth/ChannelResultsView.swift
git commit -m "feat(booth): direct-lookup fast path for channel URL/handle paste"
```

---

### Task 7: Build bundle + smoke + tag + merge

- [ ] **Step 1: Build**

```bash
./build-app.sh --sign 2>&1 | tail -10
```

- [ ] **Step 2: Manual smoke**

Quit running Murmur. `open dist/Murmur.app`.

**Played-video history:**

1. Open the menu-bar popover. Paste a YouTube video URL (or pick from Favorites/Discover) → main player loads it. Wait for the title to appear in the header.
2. Click 🔍 → search sheet opens. Empty query → **RECENT VIDEOS** section appears at the top of the placeholder, with the just-played video's thumbnail + title + a × to remove.
3. Click the video row → sheet dismisses, main player reloads that video.
4. Play 2–3 more videos. Reopen sheet → newest at top.
5. Same video twice → only one entry (deduped).
6. **Clear** at the section header → wipes all played history.

**Channel URL paste:**

7. Switch to **Channels** mode. Paste `https://www.youtube.com/@lofigirl` (or `@lofigirl`, or `https://youtube.com/channel/UCSJ4gkVC6NrvII8umztf0Ow` — any modern format).
8. Press Return → resolves directly via `forHandle` or `id` lookup (1 unit). Single result row shows up with the channel avatar + name + ★ toggle.
9. Click the row → opens browse view for that channel (same as before).
10. Click ★ → saves the channel.
11. Compare quota: name-search costs 100 units; URL paste costs 1. Same end result.
12. Pasting an invalid URL (e.g. random YouTube video URL) → falls back to channel name search.

- [ ] **Step 3: Tag + merge**

```bash
git tag -a phase-16-history-and-channel-url -m "Pocket DJ Phase 16: played video history + channel URL paste"
git checkout main
git merge --no-ff pocket-dj-phase-16 -m "Merge phase 16: played history + channel URL paste"
./build-app.sh --sign 2>&1 | tail -5
```

---

## Out of scope for Phase 16

- Channel URL paste in the **main popover URL row** (only in the channel-search field for now). Easy follow-up.
- Recording when an ambient layer YouTube source is loaded (only the main player counts toward "played video history").
- Recording video duration in the entry.

---

## Self-Review

- **Played history persists** via UserDefaults, capped at 50, deduped. ✅
- **Thumbnails for free** — built from videoID, no API call. ✅
- **RECENT VIDEOS only in videos mode** so it doesn't clutter Channels mode. ✅
- **Channel URL parser handles 4+ formats** + bare handles + bare channel IDs. ✅
- **URL fast path uses 1 unit instead of 100** — order of magnitude savings. ✅
- **Falls back to search for unrecognized input** so behaviour is additive. ✅
