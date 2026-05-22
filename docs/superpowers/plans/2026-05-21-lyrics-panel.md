# Lyrics Panel — Music-category time-synced lyrics via LRCLIB

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** When the currently playing video is classified as `VideoCategoryHint.music`, expose a "Lyrics" button in the panel that opens a side window showing time-synced lyrics, with the current line highlighted. The window updates as the song plays, scrubbing follows seeks.

**Why now:** The pieces already exist — `VideoCategoryHint.classify` gates music videos, `PlayerController` publishes `@Published var currentTime` on a Combine pipeline, and the auxiliary-sheet-as-Window pattern (queue, playlist, etc.) is well established. The only new thing is fetching + parsing LRC.

**Tradeoff acknowledged:** Title parsing is heuristic. "Artist - Song (Official Video)" works; non-Latin scripts and unconventional titles miss. We accept misses as a "no lyrics found" state rather than guessing wrong. LRCLIB is the only data source — no API key, no display licensing, but coverage is best on Western pop/rock and weaker elsewhere.

**Architecture:**
- `LyricsStore` (singleton, `Ambient/`) — fetches from `https://lrclib.net/api/get?artist_name=…&track_name=…&duration=…`, caches by `videoID`, publishes `@Published var current: LyricsResult?` (which is `.loading | .lines([LyricsLine]) | .plain(String) | .none(reason: String)`).
- `LyricsLine` is `{ start: Double, text: String }`. Parsed from LRC `[mm:ss.xx]` timestamps.
- A Combine sink in `AppDelegate` on `controller.$currentVideoID` triggers `LyricsStore.shared.fetch(for: id)` — but **only when `controller.categoryHint == .music`** (gate). When the category isn't music, the store is cleared and the lyrics button hides.
- New `LyricsWindow` (`Window` scene in `Murmur.swift`, id `lyrics`). Body is `LyricsView`, observes `LyricsStore.shared` and `controller.$currentTime`, computes the active line index via binary search, scrolls a `ScrollViewReader` to keep the active line centered.
- `ContentView` header gets a lyrics-button (next to queue button), visible only when `controller.categoryHint == .music`. Opens with `openWindow(id: "lyrics")`.

**Tech stack:** Same. No new dependencies. URLSession for the fetch.

**Out of scope:**
- Transcripts for non-music (talks/podcasts). YouTube `/captions` requires owner OAuth; `timedtext` is too brittle to ship behind a feature toggle.
- User-supplied lyrics overrides. Could come later, but not now.
- Saving favorite lyrics to disk beyond the URL/Memory cache. Cache is in-memory only — refetch on relaunch.
- Lyrics translation. LRCLIB sometimes returns translated tracks but selection logic adds complexity not yet warranted.

**Testing:** `swift build -c release` + manual smoke in Task 7. No test target exists per `CLAUDE.md`.

**Prerequisites:** Current `main` (post-MenuBarExtra migration, `Murmur.swift` entry point, `VideoCategoryHint.swift` present).

---

## File Structure

**New files:**

```
Sources/Murmur/Ambient/
  LyricsStore.swift         Singleton + LyricsResult + LyricsLine + LRCLIB client + in-memory cache
  TrackQuery.swift          Pure title-parsing helpers (split "Artist - Song (Official Video)" → artist/track)
Sources/Murmur/Booth/
  LyricsView.swift          The window body: scrolling list, active-line highlight, scrubs with currentTime
```

**Modified files:**

- `Sources/Murmur/PlayerController.swift`:
  - Add `@Published var categoryHint: VideoCategoryHint = .other`. Set inside the metadata-fetched code path (search for where title is set after a load — the same place that calls `VideoCategoryHint.classify` already in this file, if any; otherwise classify on-the-spot from category ID + title).
- `Sources/Murmur/AppDelegate.swift`:
  - New `lyricsCancellable` Combine sink on `controller.$currentVideoID` (drops first to avoid initial fetch, then filters on `controller.categoryHint == .music`, calls `LyricsStore.shared.fetch(...)`).
- `Sources/Murmur/Murmur.swift`:
  - New `Window("Lyrics", id: "lyrics") { LyricsView().environmentObject(delegate.controller) }.windowResizability(.contentSize)`.
- `Sources/Murmur/ContentView.swift`:
  - Lyrics button in the header row (visible when `controller.categoryHint == .music`), opens `openWindow(id: "lyrics")`.
- `Sources/Murmur/Ambient/CLAUDE.md`:
  - Append the new UserDefaults key (none — cache is in-memory) and `LyricsStore` to the singleton list.

---

### Task 1: TrackQuery helper

**Files:**
- Create: `Sources/Murmur/Ambient/TrackQuery.swift`

- [ ] **Step 1: Implement**

```swift
import Foundation

/// Pure title parsing. Heuristic. Returns nil when no reasonable split.
enum TrackQuery {
    /// Strip the noise YouTube uploaders add: "(Official Video)", "[HD]", "(Lyrics)", "| Lyric Video", "ft. X".
    /// Order matters — strip parens/brackets first, then trailing "feat./ft. X", then collapse whitespace.
    static func clean(_ raw: String) -> String {
        var s = raw
        let noise: [String] = [
            #"\([^)]*\b(official|lyrics?|audio|video|mv|hd|4k|hq|visualizer|remaster(ed)?)\b[^)]*\)"#,
            #"\[[^\]]*\b(official|lyrics?|audio|video|mv|hd|4k|hq|visualizer|remaster(ed)?)\b[^\]]*\]"#,
            #"\s+\|\s+.*$"#,                 // "Title | Lyric Video"
            #"\s+(feat\.?|ft\.?)\s+.+$"#,    // "Title feat. Someone"
        ]
        for pattern in noise {
            s = s.replacingOccurrences(of: pattern, with: "",
                                       options: [.regularExpression, .caseInsensitive])
        }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
               .replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
    }

    /// Try to split a cleaned title into (artist, track) on en-dash, em-dash, or hyphen-with-spaces.
    /// Returns nil when no separator is found.
    static func split(_ cleaned: String) -> (artist: String, track: String)? {
        let separators = [" – ", " — ", " - "]
        for sep in separators {
            if let range = cleaned.range(of: sep) {
                let artist = String(cleaned[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
                let track  = String(cleaned[range.upperBound...]).trimmingCharacters(in: .whitespaces)
                if !artist.isEmpty && !track.isEmpty { return (artist, track) }
            }
        }
        return nil
    }
}
```

- [ ] **Step 2: Build + commit**

```bash
swift build 2>&1 | tail -5
git add Sources/Murmur/Ambient/TrackQuery.swift
git commit -m "feat(ambient): add TrackQuery title-parsing helper"
```

---

### Task 2: LyricsStore + LRCLIB client

**Files:**
- Create: `Sources/Murmur/Ambient/LyricsStore.swift`

- [ ] **Step 1: Implement**

```swift
import Combine
import Foundation

struct LyricsLine: Equatable {
    let start: Double  // seconds from track start
    let text: String
}

enum LyricsResult: Equatable {
    case idle
    case loading
    case synced([LyricsLine])
    case plain(String)
    case missing(reason: String)
}

@MainActor
final class LyricsStore: ObservableObject {
    static let shared = LyricsStore()

    @Published private(set) var current: LyricsResult = .idle

    private var cache: [String: LyricsResult] = [:]   // keyed by videoID
    private var inflight: Task<Void, Never>?
    private var activeVideoID: String = ""

    private init() {}

    func clear() {
        inflight?.cancel(); inflight = nil
        activeVideoID = ""
        current = .idle
    }

    /// Drive a fetch for a videoID. Idempotent — duplicate calls for the same id are no-ops.
    func fetch(videoID: String, title: String, duration: Double) {
        guard !videoID.isEmpty else { clear(); return }
        guard videoID != activeVideoID else { return }
        activeVideoID = videoID

        if let cached = cache[videoID] {
            current = cached
            return
        }

        inflight?.cancel()
        current = .loading

        guard let (artist, track) = TrackQuery.split(TrackQuery.clean(title)) else {
            let result = LyricsResult.missing(reason: "Couldn't parse artist/track from title")
            cache[videoID] = result
            current = result
            return
        }

        inflight = Task { [weak self] in
            let result = await Self.fetchLRCLIB(artist: artist, track: track, duration: duration)
            guard let self = self else { return }
            guard !Task.isCancelled, self.activeVideoID == videoID else { return }
            self.cache[videoID] = result
            self.current = result
        }
    }

    // MARK: - LRCLIB client

    private struct LRCLIBResponse: Decodable {
        let syncedLyrics: String?
        let plainLyrics: String?
    }

    private static func fetchLRCLIB(artist: String, track: String, duration: Double) async -> LyricsResult {
        var comps = URLComponents(string: "https://lrclib.net/api/get")!
        comps.queryItems = [
            URLQueryItem(name: "artist_name", value: artist),
            URLQueryItem(name: "track_name", value: track),
            URLQueryItem(name: "duration", value: String(Int(duration.rounded()))),
        ]
        guard let url = comps.url else {
            return .missing(reason: "Bad URL")
        }
        var req = URLRequest(url: url)
        req.setValue("Murmur/macOS (https://github.com/ketok-id/murmur-music)", forHTTPHeaderField: "User-Agent")
        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            if let http = response as? HTTPURLResponse, http.statusCode == 404 {
                return .missing(reason: "Not found on LRCLIB")
            }
            let decoded = try JSONDecoder().decode(LRCLIBResponse.self, from: data)
            if let synced = decoded.syncedLyrics, !synced.isEmpty,
               let lines = parseLRC(synced), !lines.isEmpty {
                return .synced(lines)
            }
            if let plain = decoded.plainLyrics, !plain.isEmpty {
                return .plain(plain)
            }
            return .missing(reason: "No lyrics in LRCLIB response")
        } catch is CancellationError {
            return .missing(reason: "Cancelled")
        } catch {
            return .missing(reason: "Network error: \(error.localizedDescription)")
        }
    }

    /// Parse LRC `[mm:ss.xx]text` (one or many timestamps per line) into LyricsLine.
    /// Lines without timestamps are skipped. Returns nil if zero usable lines.
    static func parseLRC(_ source: String) -> [LyricsLine]? {
        var out: [LyricsLine] = []
        let stampPattern = try? NSRegularExpression(pattern: #"\[(\d{1,2}):(\d{2})(?:\.(\d{1,3}))?\]"#)
        for raw in source.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(raw)
            guard let regex = stampPattern else { continue }
            let nsLine = line as NSString
            let matches = regex.matches(in: line, range: NSRange(location: 0, length: nsLine.length))
            guard !matches.isEmpty else { continue }
            // Text is whatever follows the last timestamp.
            let lastEnd = matches.last!.range.upperBound
            let text = nsLine
                .substring(from: lastEnd)
                .trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty else { continue }
            for m in matches {
                let mm = Int(nsLine.substring(with: m.range(at: 1))) ?? 0
                let ss = Int(nsLine.substring(with: m.range(at: 2))) ?? 0
                let frac: Double = {
                    let r = m.range(at: 3)
                    guard r.location != NSNotFound else { return 0 }
                    let raw = nsLine.substring(with: r)
                    let n = Double(raw) ?? 0
                    let divisor = pow(10.0, Double(raw.count))
                    return n / divisor
                }()
                let t = Double(mm * 60 + ss) + frac
                out.append(LyricsLine(start: t, text: text))
            }
        }
        out.sort { $0.start < $1.start }
        return out.isEmpty ? nil : out
    }
}
```

- [ ] **Step 2: Build + commit**

```bash
swift build 2>&1 | tail -5
git add Sources/Murmur/Ambient/LyricsStore.swift
git commit -m "feat(ambient): add LyricsStore + LRCLIB client"
```

---

### Task 3: PlayerController exposes categoryHint

**Files:**
- Modify: `Sources/Murmur/PlayerController.swift`

- [ ] **Step 1: Add the published property + set on metadata load**

Add near the other `@Published` declarations:

```swift
@Published var categoryHint: VideoCategoryHint = .other
```

Find the code path where title/categoryId arrive from YouTube metadata (search the file for where `title` is reassigned post-load). When that happens, also set:

```swift
self.categoryHint = VideoCategoryHint.classify(categoryId: categoryId, title: title)
```

If the metadata path doesn't have `categoryId` plumbed yet, classify on title only:

```swift
self.categoryHint = VideoCategoryHint.classify(categoryId: "", title: title)
```

- [ ] **Step 2: Build + commit**

```bash
swift build 2>&1 | tail -5
git add Sources/Murmur/PlayerController.swift
git commit -m "feat(player): publish categoryHint for downstream observers"
```

---

### Task 4: AppDelegate wires LyricsStore to currentVideoID

**Files:**
- Modify: `Sources/Murmur/AppDelegate.swift`

- [ ] **Step 1: Add the Combine sink**

Near the other `*Cancellable` properties:

```swift
private var lyricsCancellable: AnyCancellable?
```

Inside `applicationDidFinishLaunching`, after the existing `historyCancellable` / `lastSessionCancellable` setup:

```swift
lyricsCancellable = controller.$currentVideoID
    .dropFirst()
    .removeDuplicates()
    .sink { [weak self] videoID in
        guard let self = self else { return }
        if self.controller.categoryHint == .music {
            LyricsStore.shared.fetch(
                videoID: videoID,
                title: self.controller.title,
                duration: self.controller.duration
            )
        } else {
            LyricsStore.shared.clear()
        }
    }
```

Also observe `controller.$categoryHint` so that a late category classification (metadata arrives after videoID) still triggers a fetch:

```swift
controller.$categoryHint
    .dropFirst()
    .removeDuplicates()
    .sink { [weak self] hint in
        guard let self = self else { return }
        if hint == .music {
            LyricsStore.shared.fetch(
                videoID: self.controller.currentVideoID,
                title: self.controller.title,
                duration: self.controller.duration
            )
        } else {
            LyricsStore.shared.clear()
        }
    }
    .store(in: &cancellables) // or hold in a dedicated property
```

- [ ] **Step 2: Build + commit**

```bash
swift build 2>&1 | tail -5
git add Sources/Murmur/AppDelegate.swift
git commit -m "feat(app): wire LyricsStore to player video + category changes"
```

---

### Task 5: LyricsView

**Files:**
- Create: `Sources/Murmur/Booth/LyricsView.swift`

- [ ] **Step 1: Implement**

```swift
import SwiftUI

struct LyricsView: View {
    @EnvironmentObject var controller: PlayerController
    @ObservedObject private var store = LyricsStore.shared

    var body: some View {
        Group {
            switch store.current {
            case .idle, .missing:
                emptyState
            case .loading:
                ProgressView("Looking up lyrics…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .plain(let text):
                ScrollView { Text(text).padding() }
            case .synced(let lines):
                synced(lines: lines)
            }
        }
        .frame(width: 360, height: 540)
        .background(Color(red: 13/255, green: 13/255, blue: 18/255))
    }

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 8) {
            Text("No lyrics").font(.headline)
            if case .missing(let reason) = store.current {
                Text(reason).font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func synced(lines: [LyricsLine]) -> some View {
        let activeIdx = activeIndex(in: lines, at: controller.currentTime)
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { idx, line in
                        Text(line.text)
                            .font(.body)
                            .opacity(idx == activeIdx ? 1.0 : 0.45)
                            .fontWeight(idx == activeIdx ? .semibold : .regular)
                            .id(idx)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(16)
            }
            .onChange(of: activeIdx) { newIdx in
                guard let i = newIdx else { return }
                withAnimation(.easeOut(duration: 0.25)) {
                    proxy.scrollTo(i, anchor: .center)
                }
            }
        }
    }

    /// Binary search for the largest index whose start ≤ t. Returns nil when t precedes the first line.
    private func activeIndex(in lines: [LyricsLine], at t: Double) -> Int? {
        guard !lines.isEmpty, t >= lines[0].start else { return nil }
        var lo = 0, hi = lines.count - 1
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            if lines[mid].start <= t { lo = mid } else { hi = mid - 1 }
        }
        return lo
    }
}
```

- [ ] **Step 2: Build + commit**

```bash
swift build 2>&1 | tail -5
git add Sources/Murmur/Booth/LyricsView.swift
git commit -m "feat(booth): add LyricsView with synced-line highlight"
```

---

### Task 6: Register Window scene + header button

**Files:**
- Modify: `Sources/Murmur/Murmur.swift`
- Modify: `Sources/Murmur/ContentView.swift`

- [ ] **Step 1: Add the Window scene**

In `MurmurApp.body`, alongside the other auxiliary `Window` scenes (queue / playlist / etc.):

```swift
Window("Lyrics", id: "lyrics") {
    LyricsView()
        .environmentObject(delegate.controller)
}
.windowResizability(.contentSize)
```

- [ ] **Step 2: Add the header button in ContentView**

Find the existing queue button in the header row. Add adjacent:

```swift
if controller.categoryHint == .music {
    Button {
        openWindow(id: "lyrics")
    } label: {
        Image(systemName: "text.quote")
    }
    .help("Lyrics")
    .buttonStyle(.plain)
}
```

(Match the surrounding styling — the existing buttons already encode the right `.buttonStyle` / padding.)

- [ ] **Step 3: Build + commit**

```bash
swift build 2>&1 | tail -5
git add Sources/Murmur/Murmur.swift Sources/Murmur/ContentView.swift
git commit -m "feat(ui): expose Lyrics window for music-category videos"
```

---

### Task 7: Manual smoke test

Not automatable — there is no test target. Run through these by hand.

- [ ] `swift run -c release`
- [ ] Play "Featured → Claude FM" — it's a lofi music stream, `VideoCategoryHint.music`. Confirm the Lyrics button **does not** appear if the category resolves to `.other` (lofi streams often have weird category IDs); if it does, confirm the panel opens and reports "No lyrics" gracefully (LRCLIB won't have a match).
- [ ] Paste a YouTube URL for a well-known song with the title format "Artist - Song (Official Audio)". Confirm the Lyrics button appears, the panel opens, and the active line follows playback.
- [ ] Scrub backward and forward — the highlight should follow `currentTime`.
- [ ] Switch to a podcast/talk video — Lyrics button disappears, store clears.
- [ ] Close the lyrics window. Open it again via the button. Should reopen with the same content (cache).
- [ ] Quit and relaunch. Cache is in-memory only — a fresh fetch should happen on the next play.

---

### Task 8: Update CLAUDE docs

**Files:**
- Modify: `Sources/Murmur/Ambient/CLAUDE.md`

- [ ] **Step 1: Append `LyricsStore` to the singleton list in `Ambient/CLAUDE.md`**

Add a one-line note: in-memory only, no UserDefaults key (intentional — lyrics aren't worth persisting; LRCLIB is fast).

- [ ] **Step 2: Mention the lyrics window briefly in the root `CLAUDE.md` "Auxiliary sheets are `Window` scenes" bullet** (add `lyrics` to the window-IDs list).

- [ ] **Step 3: Commit**

```bash
git add Sources/Murmur/Ambient/CLAUDE.md CLAUDE.md
git commit -m "docs: note LyricsStore + lyrics window scene"
```

---

## Notes for the implementer

- **Don't add a LyricsStore.v1 UserDefaults key.** Lyrics text isn't worth the disk pressure; LRCLIB usually responds in <300ms and the in-memory cache covers the same-session case.
- **Don't expand TrackQuery to handle every edge case in this PR.** First-pass coverage on the common "Artist - Song" patterns is enough. The "missing" state is informative enough for users to know it didn't match.
- **Don't fetch on every `currentTime` tick.** Fetches are gated on `currentVideoID` and `categoryHint` only.
- **Don't pull lyrics from Genius/Musixmatch** without revisiting the licensing question — both restrict display in third-party clients. LRCLIB's data is community-contributed and CC0-licensed.
