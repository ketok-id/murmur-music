# Pocket DJ Phase 18 — Result Badges + Channel URL in Popover

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Two features:
1. **Duration + category badges on search results.** After a search returns 10 video IDs, fire one extra `videos.list` call (1 quota unit) to fetch durations + category IDs. Duration displays as a YouTube-style overlay on the thumbnail bottom-right; category renders as a leading emoji on the title row (🎵 Music, 🎙️ Podcast — when detectable; otherwise no badge).
2. **Channel URL paste in main popover URL row.** Detect when the user pastes a channel URL or `@handle` and route to the existing search sheet in Channels mode with the query pre-filled and activated. Falls through to existing video URL handling for normal video URLs.

**Architecture:**
- `VideoCategoryHint` is a small enum + classifier that maps `(categoryId, title)` → `{music, podcast, talk, other}`. Title heuristic catches "podcast" / "episode #" / "ep 12" patterns regardless of categoryId.
- `YouTubeSearchAPI.fetchVideoDetails(ids:apiKey:)` returns `[videoID: (duration, categoryId)]`. Parses ISO 8601 duration strings (`PT1H32M45S`) → `TimeInterval`.
- `YTSearchResult` gains `var duration: TimeInterval? = nil` and `var categoryHint: VideoCategoryHint? = nil`. Backward-compatible — existing call sites don't pass them and they default to `nil`.
- `YouTubeResultsView.runSearch()` returns results immediately; in the background fetches details and replaces results with the enriched copies once details arrive.
- `YouTubeSearchSheet` gains `initialMode` and `initialQuery` parameters (default `.videos` / empty). When non-empty, the sheet opens with those values seeded.
- `ContentView.submitURL()` first runs `YouTubeChannelURL.parse`. If channel-shaped, opens the search sheet seeded with Channels mode + the input. Otherwise the existing video-URL path runs.

**Tech Stack:** Same. No new dependencies.

**Testing:** `swift build -c release` + manual smoke in Task 7.

**Prerequisites:** Phase 17 merged into `main`.

---

## File Structure

**New files:**

```
Sources/Murmur/Ambient/
  VideoCategoryHint.swift      Enum + classifier (categoryId + title → hint)
```

**Modified files:**

- `Sources/Murmur/Ambient/YouTubeSearchAPI.swift` — add `fetchVideoDetails(ids:apiKey:)` + ISO 8601 duration parser + response struct.
- `Sources/Murmur/Ambient/YouTubeSearchAPI.swift` — `YTSearchResult` extensions for `duration` + `categoryHint` (NOTE: this struct lives in `YTSearchResult` file from earlier phase — verify location).
- `Sources/Murmur/Booth/YouTubeResultsView.swift` — duration overlay + category emoji; fetch details after search.
- `Sources/Murmur/YouTubeSearchSheet.swift` — accept `initialMode` + `initialQuery` parameters.
- `Sources/Murmur/ContentView.swift` — channel URL detect in `submitURL`; pass initial seed to the search sheet.

---

### Task 1: VideoCategoryHint + classifier

**Files:**
- Create: `Sources/Murmur/Ambient/VideoCategoryHint.swift`

- [ ] **Step 1: Implement**

```swift
import Foundation

/// Coarse classification of a YouTube video — drives the small emoji badge
/// shown alongside titles in result rows.
enum VideoCategoryHint: String, Equatable {
    case music
    case podcast
    case talk
    case other

    var emoji: String {
        switch self {
        case .music:   return "🎵"
        case .podcast: return "🎙️"
        case .talk:    return "💬"
        case .other:   return ""
        }
    }

    /// Classify from YouTube's categoryId + a title heuristic.
    ///
    /// Category IDs (subset):
    ///   - 10 = Music
    ///   - 22 = People & Blogs
    ///   - 25 = News & Politics
    ///   - 27 = Education
    ///   - 28 = Science & Technology
    static func classify(categoryId: String, title: String) -> VideoCategoryHint {
        let lower = title.lowercased()
        // Title heuristic for podcasts beats the category, since many podcasts
        // are filed under People & Blogs / Education / Science / etc.
        if lower.contains("podcast")
            || lower.range(of: #"\bepisode\s+\d"#, options: .regularExpression) != nil
            || lower.range(of: #"\bep[\s.]?\d"#, options: .regularExpression) != nil
            || lower.range(of: #"#\d{1,3}"#, options: .regularExpression) != nil {
            return .podcast
        }
        switch categoryId {
        case "10": return .music
        case "25", "27", "28": return .talk
        default: return .other
        }
    }
}
```

- [ ] **Step 2: Build + commit**

```bash
cd /Users/mm/Documents/youtube-audio-widget
swift build -c release 2>&1 | tail -5
git add Sources/Murmur/Ambient/VideoCategoryHint.swift
git commit -m "feat(ambient): add VideoCategoryHint classifier"
```

---

### Task 2: Extend YTSearchResult + add fetchVideoDetails API

**Files:**
- Modify: `Sources/Murmur/Ambient/YouTubeSearchAPI.swift`

### Change 1: Extend YTSearchResult

Find the existing `YTSearchResult` struct at the top of `YouTubeSearchAPI.swift`:

```swift
struct YTSearchResult: Identifiable, Equatable {
    let videoID: String
    let title: String
    let channelTitle: String
    let thumbnailURL: URL?

    var id: String { videoID }
}
```

Replace with:

```swift
struct YTSearchResult: Identifiable, Equatable {
    let videoID: String
    let title: String
    let channelTitle: String
    let thumbnailURL: URL?
    /// Filled in by `YouTubeSearchAPI.fetchVideoDetails` after search.
    var duration: TimeInterval? = nil
    var categoryHint: VideoCategoryHint? = nil

    var id: String { videoID }
}
```

(The defaults keep existing call sites in `searchChannels`, `listChannelUploads`, etc. building unchanged — they just leave the new fields nil.)

### Change 2: Add fetchVideoDetails method

Inside `enum YouTubeSearchAPI`, find the `fetchChannelByHandle` method. Add this new method immediately after it (before the `MARK: - Shared HTTP helpers` block):

```swift

    /// Fetch duration + categoryId for up to 50 video IDs in one call.
    /// 1 quota unit total, regardless of the ID count.
    static func fetchVideoDetails(ids: [String], apiKey: String) async throws -> [String: (duration: TimeInterval, categoryId: String)] {
        guard !ids.isEmpty else { return [:] }
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else { throw SearchError.noAPIKey }

        var components = URLComponents(string: "https://www.googleapis.com/youtube/v3/videos")!
        components.queryItems = [
            URLQueryItem(name: "part", value: "contentDetails,snippet"),
            URLQueryItem(name: "id", value: ids.joined(separator: ",")),
            URLQueryItem(name: "key", value: trimmedKey),
        ]
        guard let url = components.url else { throw SearchError.network("Failed to build URL") }

        let (data, response) = try await safeGET(url: url)
        try checkHTTPStatus(response: response, data: data)

        let decoded = try JSONDecoder().decode(YouTubeVideoDetailsResponse.self, from: data)
        var dict: [String: (duration: TimeInterval, categoryId: String)] = [:]
        for item in decoded.items {
            let duration = parseISO8601Duration(item.contentDetails.duration) ?? 0
            dict[item.id] = (duration: duration, categoryId: item.snippet.categoryId)
        }
        return dict
    }

    /// Parse `PT1H32M45S` → TimeInterval. Returns nil on malformed input.
    static func parseISO8601Duration(_ s: String) -> TimeInterval? {
        guard s.hasPrefix("PT") else { return nil }
        var remaining = Substring(s.dropFirst(2))
        var total: TimeInterval = 0
        while !remaining.isEmpty {
            guard let unitIdx = remaining.firstIndex(where: { !$0.isNumber && $0 != "." }) else { return nil }
            let numStr = String(remaining[..<unitIdx])
            guard let num = Double(numStr) else { return nil }
            let unit = remaining[unitIdx]
            switch unit {
            case "H": total += num * 3600
            case "M": total += num * 60
            case "S": total += num
            default: return nil
            }
            remaining = remaining[remaining.index(after: unitIdx)...]
        }
        return total
    }
```

### Change 3: Add response struct at bottom of file

At the END of the file (after `YouTubeChannelsListWithIdResponse`), add:

```swift

private struct YouTubeVideoDetailsResponse: Decodable {
    let items: [Item]

    struct Item: Decodable {
        let id: String
        let snippet: Snippet
        let contentDetails: ContentDetails
    }
    struct Snippet: Decodable {
        let categoryId: String
    }
    struct ContentDetails: Decodable {
        let duration: String
    }
}
```

Build + commit:
```bash
swift build -c release 2>&1 | tail -10
git add Sources/Murmur/Ambient/YouTubeSearchAPI.swift
git commit -m "feat(ambient): add fetchVideoDetails for duration + category"
```

---

### Task 3: Backfill details + display in YouTubeResultsView

**Files:**
- Modify: `Sources/Murmur/Booth/YouTubeResultsView.swift`

### Change 1: Update runSearch to fetch details after the search

Find the existing `runSearch` method:

```swift
    private func runSearch() async {
        loading = true
        errorMessage = nil
        do {
            let res = try await YouTubeSearchAPI.search(
                query: query,
                apiKey: apiKeyStore.youtubeKey
            )
            results = res
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
        loading = true
        errorMessage = nil
        do {
            let res = try await YouTubeSearchAPI.search(
                query: query,
                apiKey: apiKeyStore.youtubeKey
            )
            results = res
            loading = false

            // Background-enrich with duration + category. Failure is silent —
            // results still render without the badges.
            guard !res.isEmpty else { return }
            let ids = res.map { $0.videoID }
            if let details = try? await YouTubeSearchAPI.fetchVideoDetails(
                ids: ids, apiKey: apiKeyStore.youtubeKey
            ) {
                results = res.map { result in
                    var copy = result
                    if let d = details[result.videoID] {
                        copy.duration = d.duration
                        copy.categoryHint = VideoCategoryHint.classify(
                            categoryId: d.categoryId, title: result.title
                        )
                    }
                    return copy
                }
            }
        } catch let err as YouTubeSearchAPI.SearchError {
            errorMessage = err.errorDescription
            loading = false
        } catch {
            errorMessage = error.localizedDescription
            loading = false
        }
    }
```

### Change 2: Update the row to show duration + category emoji

Find the existing `row(_:)` method. Replace the ENTIRE body of `row(_:)` with:

```swift
    private func row(_ result: YTSearchResult) -> some View {
        Button(action: { onPick(result) }) {
            HStack(alignment: .top, spacing: 12) {
                ZStack(alignment: .bottomTrailing) {
                    AsyncImage(url: result.thumbnailURL) { phase in
                        switch phase {
                        case .empty:
                            Rectangle().fill(Color.white.opacity(0.05))
                        case .success(let image):
                            image.resizable().aspectRatio(contentMode: .fill)
                        case .failure:
                            ZStack {
                                Rectangle().fill(Color.white.opacity(0.04))
                                Image(systemName: "play.rectangle")
                                    .foregroundColor(.white.opacity(0.3))
                            }
                        @unknown default:
                            Color.clear
                        }
                    }
                    if let duration = result.duration, duration > 0 {
                        Text(formatDuration(duration))
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .foregroundColor(.white)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.black.opacity(0.75))
                            .cornerRadius(2)
                            .padding(3)
                    }
                }
                .frame(width: 80, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.white.opacity(0.06), lineWidth: 0.5))

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 4) {
                        if let hint = result.categoryHint, hint != .other, !hint.emoji.isEmpty {
                            Text(hint.emoji)
                                .font(.system(size: 11))
                        }
                        Text(decodeHTMLEntities(result.title))
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.white.opacity(0.92))
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Text(result.channelTitle)
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.5))
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// "1:32:45" or "5:42" formatted duration.
    private func formatDuration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        } else {
            return String(format: "%d:%02d", m, s)
        }
    }
```

Build + commit:
```bash
swift build -c release 2>&1 | tail -10
git add Sources/Murmur/Booth/YouTubeResultsView.swift
git commit -m "feat(booth): show duration overlay + category badge on result rows"
```

---

### Task 4: Initial seed parameters on YouTubeSearchSheet

**Files:**
- Modify: `Sources/Murmur/YouTubeSearchSheet.swift`

- [ ] **Step 1: Add initialMode + initialQuery properties**

Find the existing property declarations near the top of `YouTubeSearchSheet`:

```swift
struct YouTubeSearchSheet: View {
    /// Called with the chosen result's video ID. Parent should dismiss + load.
    var onPick: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var apiKeyStore = APIKeyStore.shared
```

Add two new properties RIGHT ABOVE `var onPick:`:

```swift
    /// Seed mode when the sheet opens. Default: videos.
    var initialMode: Mode = .videos
    /// Seed query when the sheet opens. If non-empty, the sheet activates
    /// the search immediately on appear.
    var initialQuery: String = ""

```

So the block becomes:

```swift
struct YouTubeSearchSheet: View {
    var initialMode: Mode = .videos
    var initialQuery: String = ""
    var onPick: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var apiKeyStore = APIKeyStore.shared
```

- [ ] **Step 2: Apply seed in onAppear**

Find the existing `.onAppear { searchFocused = true }` (at the bottom of `body`). Replace with:

```swift
        .onAppear {
            searchFocused = true
            if !initialQuery.isEmpty {
                mode = initialMode
                draftQuery = initialQuery
                activeQuery = initialQuery
                SearchHistoryStore.shared.record(
                    query: initialQuery,
                    mode: initialMode == .videos ? .videos : .channels
                )
            }
        }
```

Build + commit:
```bash
swift build -c release 2>&1 | tail -10
git add Sources/Murmur/YouTubeSearchSheet.swift
git commit -m "feat(popover): accept initialMode + initialQuery on YouTubeSearchSheet"
```

---

### Task 5: Channel URL detect in ContentView.submitURL

**Files:**
- Modify: `Sources/Murmur/ContentView.swift`

- [ ] **Step 1: Add seed state**

Find the existing `@State private var showingYouTubeSearch: Bool = false`. Add immediately after it:

```swift
    @State private var ytInitialMode: YouTubeSearchSheet.Mode = .videos
    @State private var ytInitialQuery: String = ""
```

- [ ] **Step 2: Update sheet binding**

Find the existing `.sheet(isPresented: $showingYouTubeSearch)` modifier. Replace with:

```swift
        .sheet(isPresented: $showingYouTubeSearch) {
            YouTubeSearchSheet(
                initialMode: ytInitialMode,
                initialQuery: ytInitialQuery
            ) { videoID in
                _ = controller.load(input: videoID)
            }
        }
```

(The closure is the trailing `onPick`. If the existing sheet uses different syntax, adapt — the key is to pass `initialMode` + `initialQuery`.)

- [ ] **Step 3: Reset seed when opening via the magnifying-glass button**

Find the existing magnifying-glass Button action `{ showingYouTubeSearch = true }`. Replace with:

```swift
            Button(action: {
                ytInitialMode = .videos
                ytInitialQuery = ""
                showingYouTubeSearch = true
            }) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(fgDim)
            }
            .buttonStyle(.plain)
            .help("Search YouTube")
```

- [ ] **Step 4: Update submitURL to detect channel refs**

Find the existing `submitURL()`:

```swift
    private func submitURL() {
        let trimmed = urlInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let input = YouTubeURL.parse(trimmed) ?? trimmed
        if controller.load(input: input) {
            urlInput = ""
        }
    }
```

Replace with:

```swift
    private func submitURL() {
        let trimmed = urlInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        // Channel URL or @handle → open the search sheet in Channels mode
        // with the input pre-filled. ChannelResultsView's URL-fast-path
        // resolves to a single channel result (1 quota unit).
        if YouTubeChannelURL.parse(trimmed) != nil {
            ytInitialMode = .channels
            ytInitialQuery = trimmed
            showingYouTubeSearch = true
            urlInput = ""
            return
        }

        // Video URL or ID — existing path.
        let input = YouTubeURL.parse(trimmed) ?? trimmed
        if controller.load(input: input) {
            urlInput = ""
        }
    }
```

Build + commit:
```bash
swift build -c release 2>&1 | tail -10
git add Sources/Murmur/ContentView.swift
git commit -m "feat(popover): channel URL paste opens search sheet in Channels mode"
```

---

### Task 6: Build bundle + smoke + tag + merge

- [ ] **Step 1: Build**

```bash
./build-app.sh --sign 2>&1 | tail -10
```

- [ ] **Step 2: Manual smoke**

Quit running Murmur. `open dist/Murmur.app`. Ensure API key configured.

**Duration + category badges:**

1. Open popover → 🔍 → search sheet. Click any DISCOVER chip (e.g. 🎙️ Tech Podcasts).
2. Results appear without durations first.
3. After ~0.5–1s, **white "0:45:32" overlays** appear at the bottom-right of each thumbnail. Long-form mixes show "1:00:00+", short clips "2:14".
4. **🎙️ emoji** appears before titles for entries that match the podcast heuristic ("podcast" / "episode 12" / "ep #" / "#42" in the title).
5. Click 🎵 Music Mixes → many results get a **🎵 emoji** prefix (categoryId 10 = Music).
6. Search "lofi mix" → expect a mix of music + plain results (categoryId varies). Music tracks tagged.

**Channel URL in popover:**

7. Close the sheet. In the popover URL row, paste `@lofigirl` (or `https://www.youtube.com/@lofigirl`). Click **Go**.
8. The URL field clears, and the **search sheet opens in Channels mode** with "@lofigirl" already typed in. The ChannelResultsView fast-path resolves to a single channel result.
9. ★ to favorite → click to browse → pick a video → loads on main player.
10. Paste a regular video URL (`https://youtu.be/xxx`) → loads normally on the main player (no sheet, same as before).
11. Paste random text → falls through to existing video-input path (no crash).

- [ ] **Step 3: Tag + merge**

```bash
git tag -a phase-18-badges-and-popover-channel -m "Pocket DJ Phase 18: duration/category badges + popover channel paste"
git checkout main
git merge --no-ff pocket-dj-phase-18 -m "Merge phase 18: result badges + popover channel paste"
./build-app.sh --sign 2>&1 | tail -5
```

---

## Out of scope for Phase 18

- Badges on `ChannelBrowseView` rows — uses the same `YTSearchResult` model, but ChannelBrowseView's `listChannelUploads` doesn't currently fetch details. Could add later.
- Filter results by category ("show only music").
- More precise podcast detection via `topicDetails` (Wikipedia URLs).
- Duration filter ("only long-form" / "only short").

---

## Self-Review

- **Background-enrich pattern**: search returns immediately, details async-backfill. Failure is silent — results still render. ✅
- **ISO 8601 parsing**: handles `PT1H32M45S`, `PT45M`, `PT30S`, mixed. ✅
- **Quota impact**: +1 unit per search (so ~100 → ~101 per call). Negligible. ✅
- **Category classifier**: title heuristic catches podcasts hiding in non-Music categories. ✅ Music category captured cleanly via id "10".
- **Channel URL in popover**: routes to existing sheet path; doesn't add a new state machine. ✅ Seed gets reset by the magnifying-glass button so the manual search experience is unchanged.
- **Falls through gracefully**: random text → existing load path; video URL → existing parse; channel URL → sheet. No clobbering. ✅
