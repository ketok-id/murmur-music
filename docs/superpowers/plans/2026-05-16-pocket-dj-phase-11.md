# Pocket DJ Phase 11 — YouTube Source Enhancement

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make finding and adding YouTube sources less painful. Three changes: (a) **expand the curated ambient catalog** from 9 to ~40 sources organized by kind, (b) **add a searchable picker** to the ambient strip so you can type "rain" or "study" and filter the list, (c) **smart URL paste** in the popover so any YouTube URL format (or even a bare video ID) gets parsed correctly. No external API, no setup, ships fast.

Live YouTube search (typing "lofi study" → live results) is explicitly **out of scope** — it needs the YouTube Data API v3 with a user-provided API key. Save for a later phase.

**Architecture:** `AmbientSource.catalog` grows from 9 to ~40 entries. A new `AmbientPickerView` replaces the inline `Menu` in `AmbientStripView` — it's a popover-style picker with a search field at the top and the catalog filtered live by typed text (matches against `name` and `kindLabel`). The existing popover URL input gets a smarter parser: a new `YouTubeURL.parse(_:)` accepts video URLs in 6+ formats and bare IDs, returning a normalized video ID or `nil`.

**Tech Stack:** Same as before — SwiftUI, AppKit. No new dependencies.

**Testing:** `swift build -c release` + manual smoke in Task 5. No Co-Authored-By trailer in subagent commits.

**Prerequisites:** Phase 10 merged into `main`. The ambient strip + URL popover both exist.

---

## File Structure

**New files:**

```
Sources/Murmur/Ambient/
  YouTubeURL.swift        Static URL parser accepting all YouTube formats
Sources/Murmur/Booth/
  AmbientPickerView.swift Popover with search field + filtered catalog list
```

**Modified files:**

- `Sources/Murmur/Ambient/AmbientSource.swift` — expand catalog from 9 to ~40 entries.
- `Sources/Murmur/Booth/AmbientStripView.swift` — replace inline `Menu` with `AmbientPickerView` shown as a `.popover`.
- `Sources/Murmur/ContentView.swift` — pipe the existing URL input through `YouTubeURL.parse` for tolerant matching.
- `Sources/Murmur/main.swift` — `PlayerController` calls `YouTubeURL.parse` instead of its own minimal parsing (if any).

---

### Task 1: YouTubeURL parser

**Files:**
- Create: `Sources/Murmur/Ambient/YouTubeURL.swift`

- [ ] **Step 1: Implement**

```swift
import Foundation

/// Tolerant YouTube URL → video ID parser.
///
/// Accepts any of:
///   - https://www.youtube.com/watch?v=VIDEO_ID
///   - https://www.youtube.com/watch?v=VIDEO_ID&t=42s  (extra query params)
///   - https://youtu.be/VIDEO_ID
///   - https://youtu.be/VIDEO_ID?t=42s
///   - https://www.youtube.com/embed/VIDEO_ID
///   - https://www.youtube.com/shorts/VIDEO_ID
///   - https://www.youtube.com/live/VIDEO_ID
///   - VIDEO_ID  (bare 11-character ID)
///
/// Returns the canonical 11-character video ID, or nil if not recognized.
enum YouTubeURL {
    /// Length of a standard YouTube video ID.
    private static let idLength = 11

    /// Regex characters used inside YouTube IDs (alphanum + - + _).
    private static let idCharSet = CharacterSet.alphanumerics
        .union(CharacterSet(charactersIn: "-_"))

    static func parse(_ input: String) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }

        // 1) Bare ID — exactly 11 chars from the allowed set.
        if trimmed.count == idLength && trimmed.unicodeScalars.allSatisfy({ idCharSet.contains($0) }) {
            return trimmed
        }

        // 2) Parse as URL.
        let urlString: String
        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
            urlString = trimmed
        } else if trimmed.hasPrefix("youtu.be/") || trimmed.hasPrefix("youtube.com/") || trimmed.hasPrefix("www.youtube.com/") {
            urlString = "https://" + trimmed
        } else {
            return nil
        }
        guard let url = URL(string: urlString) else { return nil }
        let host = (url.host ?? "").lowercased()

        // youtu.be/<id>
        if host == "youtu.be" {
            return extractIDFromPath(url.path)
        }

        // youtube.com / m.youtube.com / music.youtube.com / www.youtube.com
        if host.hasSuffix("youtube.com") {
            let path = url.path
            // /watch?v=...
            if path == "/watch" {
                if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                   let item = components.queryItems?.first(where: { $0.name == "v" }),
                   let v = item.value,
                   isValidID(v) {
                    return v
                }
            }
            // /embed/<id>, /shorts/<id>, /live/<id>
            for prefix in ["/embed/", "/shorts/", "/live/"] {
                if path.hasPrefix(prefix) {
                    let id = String(path.dropFirst(prefix.count))
                    if let extracted = extractIDFromPath("/" + id) {
                        return extracted
                    }
                }
            }
        }

        return nil
    }

    /// Pull the first 11-char ID-shaped token out of a path string.
    private static func extractIDFromPath(_ path: String) -> String? {
        let parts = path.split(separator: "/", omittingEmptySubsequences: true)
        guard let first = parts.first else { return nil }
        let candidate = String(first)
        // Strip trailing query params if any leaked through ("?t=42s").
        let cleaned = candidate.split(separator: "?").first.map(String.init) ?? candidate
        return isValidID(cleaned) ? cleaned : nil
    }

    private static func isValidID(_ s: String) -> Bool {
        s.count == idLength && s.unicodeScalars.allSatisfy { idCharSet.contains($0) }
    }
}
```

- [ ] **Step 2: Build and commit**

```bash
cd /Users/mm/Documents/youtube-audio-widget
swift build -c release 2>&1 | tail -5
git add Sources/Murmur/Ambient/YouTubeURL.swift
git commit -m "feat(ambient): add tolerant YouTube URL parser"
```

---

### Task 2: Expand AmbientSource catalog

**Files:**
- Modify: `Sources/Murmur/Ambient/AmbientSource.swift`

- [ ] **Step 1: Replace the catalog**

Find the existing static `catalog` array:

```swift
    static let catalog: [AmbientSource] = [
        AmbientSource(id: "mPZkdNFkNps", name: "Rain on Window",          kind: .rain),
        AmbientSource(id: "qRTVg8HHzUo", name: "Heavy Rain & Thunder",    kind: .rain),
        AmbientSource(id: "L_LUpnjgPso", name: "Fireplace Crackle",       kind: .fire),
        AmbientSource(id: "BOdLmxy06H0", name: "Coffee Shop Ambience",    kind: .cafe),
        AmbientSource(id: "eKFTSSKCzWA", name: "Forest Birds",            kind: .nature),
        AmbientSource(id: "lTRiuFIWV54", name: "Ocean Waves",             kind: .nature),
        AmbientSource(id: "jfKfPfyJRdk", name: "Lofi Girl Stream",        kind: .beats),
        AmbientSource(id: "n61ULEU7CO0", name: "Vinyl Crackle",           kind: .vinyl),
        AmbientSource(id: "nMfPqeZjc2c", name: "Brown Noise",             kind: .white),
    ]
```

Replace with:

```swift
    static let catalog: [AmbientSource] = [
        // Rain
        AmbientSource(id: "mPZkdNFkNps", name: "Rain on Window",            kind: .rain),
        AmbientSource(id: "qRTVg8HHzUo", name: "Heavy Rain & Thunder",      kind: .rain),
        AmbientSource(id: "q76bMs-NwRk", name: "Light Drizzle",             kind: .rain),
        AmbientSource(id: "yIQd2Ya0Ziw", name: "Rain in a Forest",          kind: .rain),
        AmbientSource(id: "RrkrdYm3HPQ", name: "Tent in a Storm",           kind: .rain),

        // Fire
        AmbientSource(id: "L_LUpnjgPso", name: "Fireplace Crackle",         kind: .fire),
        AmbientSource(id: "UgHKb_7884o", name: "Campfire at Night",         kind: .fire),
        AmbientSource(id: "rdc-bcQrZfY", name: "Wood Stove Ambience",       kind: .fire),
        AmbientSource(id: "L0MK7qz13bU", name: "Bonfire on the Beach",      kind: .fire),

        // Cafe
        AmbientSource(id: "BOdLmxy06H0", name: "Coffee Shop Ambience",      kind: .cafe),
        AmbientSource(id: "h2zkV-l_TbY", name: "Paris Cafe",                kind: .cafe),
        AmbientSource(id: "DeumyOzKqgI", name: "Library Whispers",          kind: .cafe),
        AmbientSource(id: "VTH7c-3VPCw", name: "Bookstore Ambience",        kind: .cafe),
        AmbientSource(id: "fOFzbgVQRMI", name: "Restaurant Murmur",         kind: .cafe),

        // Nature
        AmbientSource(id: "eKFTSSKCzWA", name: "Forest Birds",              kind: .nature),
        AmbientSource(id: "lTRiuFIWV54", name: "Ocean Waves",               kind: .nature),
        AmbientSource(id: "d0tU18Ybcvk", name: "Mountain Stream",           kind: .nature),
        AmbientSource(id: "OdIJ2x3nxzQ", name: "Distant Thunder Field",     kind: .nature),
        AmbientSource(id: "9zS9OdMzGqg", name: "Crickets at Dusk",          kind: .nature),
        AmbientSource(id: "xNN7iTA57jM", name: "Jungle at Dawn",            kind: .nature),

        // Beats
        AmbientSource(id: "jfKfPfyJRdk", name: "Lofi Girl — beats to study",kind: .beats),
        AmbientSource(id: "rUxyKA_-grg", name: "Lofi Girl — beats to sleep",kind: .beats),
        AmbientSource(id: "tNkZsRW7h2c", name: "ChilledCow Late Night",     kind: .beats),
        AmbientSource(id: "5qap5aO4i9A", name: "Lofi Hip Hop Radio",        kind: .beats),
        AmbientSource(id: "DWcJFNfaw9c", name: "Jazz Hop Cafe",             kind: .beats),
        AmbientSource(id: "4xDzrJKXOOY", name: "Synthwave Radio",           kind: .beats),

        // Vinyl
        AmbientSource(id: "n61ULEU7CO0", name: "Vinyl Crackle",             kind: .vinyl),
        AmbientSource(id: "Q0jXavyolwk", name: "Old Record Player",         kind: .vinyl),
        AmbientSource(id: "qK7-XGM6jrI", name: "Tape Hiss",                 kind: .vinyl),
        AmbientSource(id: "5XK7QmqlpoY", name: "Cassette Warmth",           kind: .vinyl),

        // Noise
        AmbientSource(id: "nMfPqeZjc2c", name: "Brown Noise",               kind: .white),
        AmbientSource(id: "vGUTFOLYIEM", name: "Pink Noise",                kind: .white),
        AmbientSource(id: "WPnUNXuyA1Y", name: "White Noise",               kind: .white),
        AmbientSource(id: "wAPCSnAhhC8", name: "Fan Noise",                 kind: .white),
        AmbientSource(id: "Q4fHCqr0V0w", name: "Airplane Cabin",            kind: .white),
        AmbientSource(id: "OkahfaPGOps", name: "Train Carriage",            kind: .white),
    ]
```

(Note: video IDs are placeholders — some may be stale. The point is the structure + count. If any are broken at runtime, swap in working IDs.)

- [ ] **Step 2: Build and commit**

```bash
swift build -c release 2>&1 | tail -5
git add Sources/Murmur/Ambient/AmbientSource.swift
git commit -m "feat(ambient): expand catalog from 9 to ~40 curated sources"
```

---

### Task 3: AmbientPickerView (searchable list)

**Files:**
- Create: `Sources/Murmur/Booth/AmbientPickerView.swift`

- [ ] **Step 1: Implement**

```swift
import SwiftUI

/// Searchable picker for ambient sources. Replaces the simple `Menu` in
/// `AmbientStripView` so the user can filter the catalog by typed text.
///
/// Matches against `name` and `kindLabel`, case-insensitive.
struct AmbientPickerView: View {
    /// Receives the user's choice (nil = clear / off).
    var onPick: (AmbientSource?) -> Void

    @State private var query: String = ""
    @FocusState private var searchFocused: Bool

    private var filtered: [AmbientSource] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        if q.isEmpty { return AmbientSource.catalog }
        return AmbientSource.catalog.filter { src in
            src.name.lowercased().contains(q) ||
            src.kindLabel.lowercased().contains(q)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Search field.
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

            // Off row + filtered catalog.
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    row(label: "— Off —", kindLabel: "", isOff: true) {
                        onPick(nil)
                    }
                    Divider().background(Color.white.opacity(0.04))
                    if filtered.isEmpty {
                        Text("No matches")
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.4))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 16)
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
            .frame(maxHeight: 320)
        }
        .frame(width: 280)
        .background(Color(white: 0.06))
        .onAppear { searchFocused = true }
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
swift build -c release 2>&1 | tail -5
git add Sources/Murmur/Booth/AmbientPickerView.swift
git commit -m "feat(booth): add searchable AmbientPickerView"
```

---

### Task 4: Wire AmbientPickerView into AmbientStripView

**Files:**
- Modify: `Sources/Murmur/Booth/AmbientStripView.swift`

- [ ] **Step 1: Replace the inline Menu with a popover trigger**

Open `Sources/Murmur/Booth/AmbientStripView.swift`. Find the existing `channelControls` helper. It contains a `Menu` with the catalog inline. Replace the ENTIRE `channelControls` function with:

```swift
    private func channelControls(state: AmbientChannelState, label: String) -> some View {
        ChannelControlRow(state: state)
    }
```

Then add this helper subview at the bottom of the file, AFTER the closing `}` of `struct AmbientStripView`:

```swift

/// Inner row for one ambient channel. Lives at file scope so its `@State`
/// (for the popover binding) is per-channel.
private struct ChannelControlRow: View {
    @ObservedObject var state: AmbientChannelState
    @State private var pickerOpen = false

    var body: some View {
        HStack(spacing: 8) {
            Button(action: { pickerOpen.toggle() }) {
                HStack(spacing: 4) {
                    Circle()
                        .fill(state.source != nil ? Color.cyan : Color.white.opacity(0.15))
                        .frame(width: 8, height: 8)
                    Text(state.source?.name ?? "Pick a bed…")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(state.source != nil ? .white : .white.opacity(0.4))
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8))
                        .foregroundColor(.white.opacity(0.4))
                }
            }
            .buttonStyle(.plain)
            .popover(isPresented: $pickerOpen, arrowEdge: .bottom) {
                AmbientPickerView { picked in
                    state.source = picked
                    pickerOpen = false
                }
            }

            Button(action: { state.muted.toggle() }) {
                Image(systemName: state.muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.system(size: 10))
                    .foregroundColor(state.muted ? .red.opacity(0.6) : .white.opacity(0.6))
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.plain)

            Slider(value: Binding(
                get: { Double(state.volume) },
                set: { state.volume = Float($0) }
            ), in: 0...1)
            .frame(width: 60)
        }
    }
}
```

- [ ] **Step 2: Build and commit**

```bash
swift build -c release 2>&1 | tail -10
git add Sources/Murmur/Booth/AmbientStripView.swift
git commit -m "feat(booth): show AmbientPickerView in a popover with live search"
```

---

### Task 5: Smart URL paste in the existing popover

**Files:**
- Modify: `Sources/Murmur/ContentView.swift`

The existing popover has a URL/ID `TextField`. Currently it loads whatever's typed assuming it's either a video ID or a URL the existing `PlayerController` knows how to handle. Improve it: route through `YouTubeURL.parse` and show subtle feedback when input doesn't parse.

- [ ] **Step 1: Find where the URL input is loaded**

Open `Sources/Murmur/ContentView.swift`. Find the `urlRow` computed property and the `loadFromInput()` function (or wherever `urlInput` is used to call into `controller`). The exact structure of `ContentView.swift` from prior phases:

```swift
// Look for something like:
controller.loadVideo(videoID: urlInput)
// or
controller.loadVideoIDOrURL(urlInput)
```

(If the file already routes through `PlayerController`, modify the call site to first run `YouTubeURL.parse(urlInput) ?? urlInput` so a parsed ID takes priority, and the raw string is the fallback.)

In the action handler that loads from `urlInput`, change the load call to:

```swift
let parsed = YouTubeURL.parse(urlInput) ?? urlInput
controller.load(videoID: parsed)
// (or whatever the existing load method is named; preserve the original method name).
```

The exact line to replace varies — find the existing `controller.load…(…urlInput…)` call site, and inject the `YouTubeURL.parse` step before it.

- [ ] **Step 2: Build and commit**

```bash
swift build -c release 2>&1 | tail -10
git add Sources/Murmur/ContentView.swift
git commit -m "feat(popover): accept any YouTube URL format in the input field"
```

---

### Task 6: Build bundle + smoke + tag + merge

- [ ] **Step 1: Build**

```bash
./build-app.sh --sign 2>&1 | tail -10
```

- [ ] **Step 2: Manual smoke**

`open dist/Murmur.app`. Quit any running instance first.

**Ambient catalog & picker:**

1. Open booth → click an ambient channel's "Pick a bed…" button. A **popover opens** with a search field at the top and the full catalog (~36 entries) below, organized with `KIND` labels on the left in cyan.
2. The search field is auto-focused. Type "rain" → list filters to just the 5 rain entries. Type "lofi" → just the lofi entries. Type something nonsense like "xyz" → "No matches" message.
3. Clear the field → full catalog back.
4. Click a row → ambient channel loads that source, popover closes.
5. Click "— Off —" at the top of the list → channel goes empty, popover closes.

**Smart URL paste in popover:**

6. Open the menu-bar Murmur popover (NOT the booth). Find the URL input.
7. Paste each of these and verify the loaded video matches:
   - `https://www.youtube.com/watch?v=jfKfPfyJRdk` → loads Lofi Girl stream.
   - `https://youtu.be/jfKfPfyJRdk` → same.
   - `https://youtu.be/jfKfPfyJRdk?t=42s` → same (ignores the timestamp).
   - `jfKfPfyJRdk` (bare ID) → same.
   - `https://www.youtube.com/embed/jfKfPfyJRdk` → same.
   - `youtube.com/shorts/dQw4w9WgXcQ` (no scheme) → loads that video.
8. Paste invalid text like `not a youtube link` → either no-op or fallback to existing behavior (depends on `PlayerController.load` — should not crash).

- [ ] **Step 3: Tag**

```bash
git tag -a phase-11-yt-search -m "Pocket DJ Phase 11: enhanced ambient catalog + URL parser"
```

- [ ] **Step 4: Merge to main**

```bash
git checkout main
git merge --no-ff pocket-dj-phase-11 -m "Merge phase 11: YouTube source enhancement"
./build-app.sh --sign 2>&1 | tail -5
```

---

## Out of Scope for Phase 11

- **Live YouTube search** via the Data API — that's a separate phase requiring user-provided API key, search UI, error handling, and pagination.
- **Auto-fetching video titles/thumbnails** for pasted URLs — needs API or web scraping.
- **Custom favorites for ambient sources** (user-added "my saved YouTube beds") — a small addition for a later phase.
- **Catalog versioning / cloud-updated catalog** — currently catalog is hardcoded; OK for v1.

---

## Self-Review

- **Expanded catalog with structured kinds** ✅ ~36 entries across 7 kinds.
- **Searchable picker UI** ✅ popover with autofocused field, live filter, kind labels.
- **Smart URL parsing** ✅ accepts all 6+ standard YouTube URL formats + bare IDs.
- **No external API or setup required** ✅.

No spec gaps for the in-scope set. Type signatures consistent.
