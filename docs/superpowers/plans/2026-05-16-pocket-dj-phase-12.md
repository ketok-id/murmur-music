# Pocket DJ Phase 12 — Live YouTube Search

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Type a search query in the ambient picker → hit "Search YouTube" → live results from YouTube Data API v3 → click a result to load it as an ambient source. Requires a user-supplied API key (free; ~100 searches/day on Google's free tier). Keys are stored in `UserDefaults` and never transmitted anywhere except YouTube.

**Architecture:** `APIKeyStore` is a thin `UserDefaults` wrapper for the YouTube API key. `YouTubeSearchAPI.search(query:)` is an `async` function that calls `https://www.googleapis.com/youtube/v3/search?part=snippet&q=<q>&type=video&maxResults=10&key=<KEY>` and decodes results into `[YTSearchResult]`. A new `APIKeySetupSheet` (modal sheet) lets the user paste their key — opened from a gear icon in the popover header. `AmbientPickerView` gets a "Search YouTube" button under its filtered catalog list; clicking it triggers an async search and replaces the catalog list with a results list (titles + channel + thumbnails via `AsyncImage`). Clicking a result loads it as an ambient source, same path as catalog selection.

**Tech Stack:** Same — SwiftUI, async/await, `URLSession`. `AsyncImage` for thumbnails (macOS 12+, we're on 13+).

**Testing:** `swift build -c release` + final manual smoke in Task 8. Requires the user's actual API key for the smoke; the rest is verifiable via compilation. No Co-Authored-By trailer in subagent commits.

**Prerequisites:** Phase 11 merged into `main`. Ambient catalog + searchable picker already exist.

---

## File Structure

**New files:**

```
Sources/Murmur/Ambient/
  APIKeyStore.swift          UserDefaults wrapper for the YouTube API key
  YouTubeSearchAPI.swift     Async search() + YTSearchResult model
Sources/Murmur/Booth/
  APIKeySetupSheet.swift     Modal sheet for entering/clearing the key
  YouTubeResultsView.swift   Live results list with AsyncImage thumbnails
```

**Modified files:**

- `Sources/Murmur/Booth/AmbientPickerView.swift` — add "Search YouTube" button below catalog list; switch to results view when active.
- `Sources/Murmur/ContentView.swift` — add a gear button in the header that opens `APIKeySetupSheet`.

---

### Task 1: APIKeyStore

**Files:**
- Create: `Sources/Murmur/Ambient/APIKeyStore.swift`

- [ ] **Step 1: Implement**

```swift
import Combine
import Foundation

/// `UserDefaults`-backed store for the YouTube Data API v3 key.
///
/// Keys are stored in plain `UserDefaults`. Treat them as user-config, not
/// secrets — they grant the same access the user already has on their own
/// Google Cloud project, and they live only on this device.
final class APIKeyStore: ObservableObject {
    static let shared = APIKeyStore()

    @Published var youtubeKey: String

    private let defaultsKey = "youtube-audio-widget.yt-api-key.v1"

    private init() {
        self.youtubeKey = UserDefaults.standard.string(forKey: defaultsKey) ?? ""
    }

    /// True when a non-empty key is configured.
    var hasYouTubeKey: Bool {
        !youtubeKey.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// Persist a new key value. Empty string clears.
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
```

- [ ] **Step 2: Build and commit**

```bash
cd /Users/mm/Documents/youtube-audio-widget
swift build -c release 2>&1 | tail -5
git add Sources/Murmur/Ambient/APIKeyStore.swift
git commit -m "feat(ambient): add APIKeyStore for YouTube API key"
```

---

### Task 2: YouTubeSearchAPI

**Files:**
- Create: `Sources/Murmur/Ambient/YouTubeSearchAPI.swift`

- [ ] **Step 1: Implement**

```swift
import Foundation

/// One result from a YouTube Data API v3 search response.
struct YTSearchResult: Identifiable, Equatable {
    let videoID: String
    let title: String
    let channelTitle: String
    let thumbnailURL: URL?

    var id: String { videoID }
}

/// YouTube Data API v3 search client. Caller supplies the API key.
enum YouTubeSearchAPI {
    enum SearchError: Error, LocalizedError {
        case noAPIKey
        case quotaExceeded
        case invalidKey
        case network(String)
        case decode(String)

        var errorDescription: String? {
            switch self {
            case .noAPIKey:        return "No YouTube API key configured."
            case .quotaExceeded:   return "Daily search quota exceeded. Try again tomorrow."
            case .invalidKey:      return "API key rejected by YouTube. Check it in Settings."
            case .network(let m):  return "Network error: \(m)"
            case .decode(let m):   return "Couldn't read YouTube's response: \(m)"
            }
        }
    }

    /// Synchronously runs an async search and returns results or throws.
    static func search(query: String, apiKey: String, maxResults: Int = 10) async throws -> [YTSearchResult] {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedQuery = query.trimmingCharacters(in: .whitespaces)
        guard !trimmedKey.isEmpty else { throw SearchError.noAPIKey }
        guard !trimmedQuery.isEmpty else { return [] }

        var components = URLComponents(string: "https://www.googleapis.com/youtube/v3/search")!
        components.queryItems = [
            URLQueryItem(name: "part", value: "snippet"),
            URLQueryItem(name: "q", value: trimmedQuery),
            URLQueryItem(name: "type", value: "video"),
            URLQueryItem(name: "maxResults", value: String(maxResults)),
            URLQueryItem(name: "key", value: trimmedKey),
        ]
        guard let url = components.url else {
            throw SearchError.network("Failed to build URL")
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(from: url)
        } catch {
            throw SearchError.network(error.localizedDescription)
        }

        if let http = response as? HTTPURLResponse {
            switch http.statusCode {
            case 200: break
            case 400: throw SearchError.invalidKey
            case 403:
                // Could be quota or auth; sniff payload.
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

        do {
            let decoded = try JSONDecoder().decode(YouTubeSearchResponse.self, from: data)
            return decoded.items.compactMap { item -> YTSearchResult? in
                guard let videoID = item.id.videoId else { return nil }
                let thumbURL = item.snippet.thumbnails.medium.map { URL(string: $0.url) } ?? nil
                return YTSearchResult(
                    videoID: videoID,
                    title: item.snippet.title,
                    channelTitle: item.snippet.channelTitle,
                    thumbnailURL: thumbURL ?? nil
                )
            }
        } catch {
            throw SearchError.decode(error.localizedDescription)
        }
    }
}

// MARK: - JSON decoding shapes (internal)

private struct YouTubeSearchResponse: Decodable {
    let items: [Item]

    struct Item: Decodable {
        let id: IdBlock
        let snippet: Snippet
    }
    struct IdBlock: Decodable {
        let videoId: String?
    }
    struct Snippet: Decodable {
        let title: String
        let channelTitle: String
        let thumbnails: Thumbnails
    }
    struct Thumbnails: Decodable {
        let medium: Thumb?
    }
    struct Thumb: Decodable {
        let url: String
    }
}
```

- [ ] **Step 2: Build and commit**

```bash
swift build -c release 2>&1 | tail -5
git add Sources/Murmur/Ambient/YouTubeSearchAPI.swift
git commit -m "feat(ambient): add YouTubeSearchAPI client + YTSearchResult model"
```

---

### Task 3: APIKeySetupSheet

**Files:**
- Create: `Sources/Murmur/Booth/APIKeySetupSheet.swift`

- [ ] **Step 1: Implement**

```swift
import SwiftUI

/// Modal sheet for entering/clearing the YouTube Data API v3 key.
struct APIKeySetupSheet: View {
    @ObservedObject var store: APIKeyStore
    @Environment(\.dismiss) private var dismiss

    @State private var draftKey: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("YouTube API Key")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.white.opacity(0.4))
                }
                .buttonStyle(.plain)
            }

            Text("Required for live YouTube search. Free for up to ~100 searches/day on Google's free tier. Setup takes ~5 minutes — see the link below.")
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.6))
                .fixedSize(horizontal: false, vertical: true)

            Link(destination: URL(string: "https://console.cloud.google.com/apis/library/youtube.googleapis.com")!) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.up.right.square")
                    Text("Open Google Cloud Console")
                }
                .font(.system(size: 11))
                .foregroundColor(.cyan)
            }

            Divider().background(Color.white.opacity(0.1))

            VStack(alignment: .leading, spacing: 4) {
                Text("Paste your API key")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .tracking(0.5)
                    .foregroundColor(.white.opacity(0.5))
                SecureField("AIzaSy…", text: $draftKey)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, design: .monospaced))
                    .padding(8)
                    .background(Color.white.opacity(0.05))
                    .cornerRadius(4)
            }

            HStack(spacing: 8) {
                if store.hasYouTubeKey {
                    Button("Clear saved key") {
                        store.setYouTubeKey("")
                        draftKey = ""
                    }
                    .foregroundColor(.red.opacity(0.7))
                    .buttonStyle(.plain)
                }
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(.plain)
                Button("Save") {
                    store.setYouTubeKey(draftKey)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(draftKey.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(18)
        .frame(width: 380)
        .background(Color(white: 0.05))
        .onAppear { draftKey = store.youtubeKey }
    }
}
```

- [ ] **Step 2: Build and commit**

```bash
swift build -c release 2>&1 | tail -5
git add Sources/Murmur/Booth/APIKeySetupSheet.swift
git commit -m "feat(booth): add APIKeySetupSheet for YouTube key entry"
```

---

### Task 4: Add gear button to popover header

**Files:**
- Modify: `Sources/Murmur/ContentView.swift`

The popover already has a header. Add a small gear icon button beside or in the header that presents `APIKeySetupSheet`.

- [ ] **Step 1: Add the sheet state + button**

Open `Sources/Murmur/ContentView.swift`. Find the property block where other `@State` declarations live (near `@State private var urlInput: String = ""`). Add:

```swift
    @State private var showingAPIKeySheet: Bool = false
    @ObservedObject private var apiKeyStore = APIKeyStore.shared
```

Find the `header` computed property (or wherever the popover header is defined — search for "header" or "Murmur" title text). It currently has something like `Text("Murmur")` plus possibly a row layout. Replace the existing header block with one that includes a trailing gear button.

If the existing header looks like:

```swift
    private var header: some View {
        HStack {
            Text("MURMUR")
                ...
            Spacer()
        }
    }
```

Replace with:

```swift
    private var header: some View {
        HStack {
            Text("MURMUR")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .tracking(2)
                .foregroundColor(fgDim)
            Spacer()
            Button(action: { showingAPIKeySheet = true }) {
                Image(systemName: "gearshape")
                    .font(.system(size: 10))
                    .foregroundColor(apiKeyStore.hasYouTubeKey ? accent : fgDim)
            }
            .buttonStyle(.plain)
            .help(apiKeyStore.hasYouTubeKey ? "YouTube API key configured" : "Configure YouTube API key")
        }
        .sheet(isPresented: $showingAPIKeySheet) {
            APIKeySetupSheet(store: apiKeyStore)
        }
    }
```

(NOTE: read the existing `header` first to preserve other styling. The key additions are the gear `Button`, the `.sheet(...)` modifier, and the `.help(...)`.)

If the header is structured differently than the example, adapt: the goal is just to add a trailing gear button that toggles `showingAPIKeySheet`, and attach `.sheet(isPresented: $showingAPIKeySheet) { APIKeySetupSheet(store: apiKeyStore) }` to a stable parent view.

- [ ] **Step 2: Build and commit**

```bash
swift build -c release 2>&1 | tail -10
git add Sources/Murmur/ContentView.swift
git commit -m "feat(popover): add gear button + sheet for YouTube API key"
```

---

### Task 5: YouTubeResultsView

**Files:**
- Create: `Sources/Murmur/Booth/YouTubeResultsView.swift`

- [ ] **Step 1: Implement**

```swift
import SwiftUI

/// Live YouTube search results list with async-loaded thumbnails.
struct YouTubeResultsView: View {
    let query: String
    var onPick: (YTSearchResult) -> Void
    var onBack: () -> Void

    @State private var results: [YTSearchResult] = []
    @State private var loading: Bool = true
    @State private var errorMessage: String? = nil

    @ObservedObject private var apiKeyStore = APIKeyStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.6))
                }
                .buttonStyle(.plain)
                Text("YouTube · \"\(query)\"")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.white.opacity(0.8))
                    .lineLimit(1)
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color.white.opacity(0.04))
            Divider().background(Color.white.opacity(0.06))

            content
        }
        .frame(width: 280)
        .background(Color(white: 0.06))
        .task(id: query) {
            await runSearch()
        }
    }

    @ViewBuilder
    private var content: some View {
        if loading {
            VStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Searching YouTube…")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.5))
            }
            .frame(maxWidth: .infinity, maxHeight: 200)
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
            .frame(maxWidth: .infinity, maxHeight: 200)
        } else if results.isEmpty {
            Text("No results.")
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.4))
                .frame(maxWidth: .infinity, maxHeight: 200, alignment: .center)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(results) { result in
                        row(result)
                    }
                }
            }
            .frame(maxHeight: 320)
        }
    }

    private func row(_ result: YTSearchResult) -> some View {
        Button(action: { onPick(result) }) {
            HStack(spacing: 10) {
                AsyncImage(url: result.thumbnailURL) { phase in
                    switch phase {
                    case .empty:
                        Rectangle().fill(Color.white.opacity(0.04))
                    case .success(let image):
                        image.resizable().aspectRatio(contentMode: .fill)
                    case .failure:
                        Image(systemName: "play.rectangle")
                            .foregroundColor(.white.opacity(0.3))
                    @unknown default:
                        Color.clear
                    }
                }
                .frame(width: 56, height: 32)
                .clipShape(RoundedRectangle(cornerRadius: 3))
                .overlay(RoundedRectangle(cornerRadius: 3).stroke(Color.white.opacity(0.08), lineWidth: 1))

                VStack(alignment: .leading, spacing: 2) {
                    Text(decodeHTMLEntities(result.title))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.white.opacity(0.9))
                        .lineLimit(2)
                    Text(result.channelTitle)
                        .font(.system(size: 9))
                        .foregroundColor(.cyan.opacity(0.7))
                        .lineLimit(1)
                }
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

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

    /// YouTube returns titles with HTML entities (e.g., "&amp;"). Decode for display.
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

- [ ] **Step 2: Build and commit**

```bash
swift build -c release 2>&1 | tail -10
git add Sources/Murmur/Booth/YouTubeResultsView.swift
git commit -m "feat(booth): add YouTubeResultsView with AsyncImage thumbnails"
```

---

### Task 6: Wire YouTube search into AmbientPickerView

**Files:**
- Modify: `Sources/Murmur/Booth/AmbientPickerView.swift`

Add a "Search YouTube" button at the bottom of the catalog list. When clicked, swap the view contents to `YouTubeResultsView`. Provide a back action.

- [ ] **Step 1: Wrap body in a state machine + add "Search YouTube" button**

Replace the ENTIRE contents of `Sources/Murmur/Booth/AmbientPickerView.swift` with:

```swift
import SwiftUI

/// Searchable picker for ambient sources. Filters the curated catalog locally,
/// and offers a "Search YouTube" path that hits the live API when the user
/// wants results beyond the curated list.
struct AmbientPickerView: View {
    /// Receives the user's choice (nil = clear / off).
    var onPick: (AmbientSource?) -> Void

    @State private var query: String = ""
    @State private var showingYouTube: Bool = false
    @FocusState private var searchFocused: Bool

    @ObservedObject private var apiKeyStore = APIKeyStore.shared

    private var filtered: [AmbientSource] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        if q.isEmpty { return AmbientSource.catalog }
        return AmbientSource.catalog.filter { src in
            src.name.lowercased().contains(q) ||
            src.kindLabel.lowercased().contains(q)
        }
    }

    var body: some View {
        if showingYouTube {
            YouTubeResultsView(
                query: query,
                onPick: { result in
                    let source = AmbientSource(id: result.videoID, name: result.title, kind: .beats)
                    onPick(source)
                },
                onBack: { showingYouTube = false }
            )
        } else {
            catalogView
        }
    }

    private var catalogView: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.5))
                TextField("Search ambient…", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, design: .monospaced))
                    .focused($searchFocused)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color.white.opacity(0.04))
            Divider().background(Color.white.opacity(0.06))

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    row(label: "— Off —", kindLabel: "", isOff: true) {
                        onPick(nil)
                    }
                    Divider().background(Color.white.opacity(0.04))
                    if filtered.isEmpty {
                        Text("No matches in catalog.")
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.4))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 12)
                            .frame(maxWidth: .infinity, alignment: .center)
                    } else {
                        ForEach(filtered) { src in
                            row(label: src.name, kindLabel: src.kindLabel, isOff: false) {
                                onPick(src)
                            }
                        }
                    }
                }
            }
            .frame(maxHeight: 280)

            Divider().background(Color.white.opacity(0.08))
            ytSearchButton
        }
        .frame(width: 280)
        .background(Color(white: 0.06))
        .onAppear { searchFocused = true }
    }

    @ViewBuilder
    private var ytSearchButton: some View {
        let q = query.trimmingCharacters(in: .whitespaces)
        let canSearch = !q.isEmpty && apiKeyStore.hasYouTubeKey
        let label: String
        let foreground: Color
        let disabled: Bool

        if q.isEmpty {
            label = "Type to search YouTube"
            foreground = .white.opacity(0.35)
            disabled = true
        } else if !apiKeyStore.hasYouTubeKey {
            label = "Set API key to search YouTube →"
            foreground = .white.opacity(0.45)
            disabled = true
        } else {
            label = "Search YouTube for \"\(q)\""
            foreground = .cyan
            disabled = false
        }

        Button(action: {
            if canSearch { showingYouTube = true }
        }) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass.circle")
                Text(label).lineLimit(1)
            }
            .font(.system(size: 11, design: .monospaced))
            .foregroundColor(foreground)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }

    private func row(label: String, kindLabel: String, isOff: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if !kindLabel.isEmpty {
                    Text(kindLabel)
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .tracking(0.5)
                        .foregroundColor(.cyan.opacity(0.75))
                        .frame(width: 50, alignment: .leading)
                } else {
                    Color.clear.frame(width: 50)
                }
                Text(label)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(isOff ? .white.opacity(0.45) : .white.opacity(0.9))
                    .lineLimit(1)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(Color.clear)
    }
}
```

- [ ] **Step 2: Build and commit**

```bash
swift build -c release 2>&1 | tail -10
git add Sources/Murmur/Booth/AmbientPickerView.swift
git commit -m "feat(booth): add Search YouTube path in AmbientPickerView"
```

---

### Task 7: Build bundle + smoke + tag + merge

- [ ] **Step 1: Build the bundle**

```bash
./build-app.sh --sign 2>&1 | tail -10
```

- [ ] **Step 2: Manual smoke**

Quit any running Murmur instance. `open dist/Murmur.app`.

**First-time setup:**

1. Click the menu-bar Murmur icon to open the popover.
2. In the header, there's now a **gear icon** (top-right). It's dim because no key is set.
3. Click the gear → **"YouTube API Key" sheet opens** with paste field, link to Google Cloud Console, Cancel/Save buttons.
4. Paste your API key (starts with `AIza…`) → Save.
5. Sheet closes. Gear icon turns accent-colored, indicating a key is configured.

**Live search from booth:**

6. Open the booth. Click an ambient channel's "Pick a bed…" → picker opens.
7. Type "lofi study" in the search field. Catalog filters live (probably shows the 6 "BEATS" entries).
8. At the bottom of the picker: **"Search YouTube for \"lofi study\""** button in cyan. Click it.
9. View switches to results — spinner "Searching YouTube…" for ~1s, then **10 results** with thumbnails (medium quality), titles (HTML entities decoded), and channel names in cyan.
10. Back arrow (top-left) → returns to the catalog view.
11. Click a result → it loads as that ambient channel's source, popover closes, audio starts playing the new source.

**Error states:**

12. Clear the key (gear → Clear saved key → Cancel out of sheet). Open ambient picker, type, try the search button → button now says "Set API key to search YouTube →" and is disabled.
13. With a deliberately wrong key (paste `AIzaXXXXX`), search → error message "API key rejected by YouTube. Check it in Settings."
14. With network off, search → error message "Network error: …"

- [ ] **Step 3: Tag**

```bash
git tag -a phase-12-yt-live-search -m "Pocket DJ Phase 12: live YouTube search via Data API v3"
```

- [ ] **Step 4: Merge to main**

```bash
git checkout main
git merge --no-ff pocket-dj-phase-12 -m "Merge phase 12: live YouTube search"
./build-app.sh --sign 2>&1 | tail -5
```

---

## Out of Scope for Phase 12

- **Caching results** to reduce repeat API calls — could be added later.
- **Pagination** (loading more than 10 results per search).
- **Filtering by duration / live status** in search params.
- **Recently used YouTube sources** persistence — would add as a "Recent" section in the picker. Useful later.
- **Channel/playlist search** — `type=video` only for now.

---

## Self-Review

- **API key storage**: ✅ `UserDefaults` with explicit clear path; never logged or transmitted except to YouTube.
- **Quota awareness**: ✅ Error message specifically calls out daily quota.
- **Error UX**: ✅ Three distinct error states (no key, quota, invalid key) with clear messages.
- **No payment**: ✅ Stays within free tier — only blocked by quota, never billed.
- **Thumbnails**: ✅ `AsyncImage` (macOS 12+, we're on 13+).
- **HTML entity decoding**: ✅ YouTube returns `&amp;` etc.; `decodeHTMLEntities` cleans them.

No spec gaps. Type signatures consistent: `YouTubeSearchAPI.search/SearchError`, `YTSearchResult.id/videoID/title/channelTitle/thumbnailURL`, `APIKeyStore.youtubeKey/hasYouTubeKey/setYouTubeKey`.
