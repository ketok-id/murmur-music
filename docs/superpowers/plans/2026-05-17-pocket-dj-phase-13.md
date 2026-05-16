# Pocket DJ Phase 13 — YouTube Search in Main Popover

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a YouTube search affordance to the main menu-bar popover. Click a search icon → sheet opens with a search field + live YouTube results → click a result → loads in the main player (same flow as pasting a video ID; floating video window picks it up). No deck/audio-graph integration, no architectural surprises — the popover already plays YouTube.

**Architecture:** A new `YouTubeSearchSheet` composes a `TextField` for the query + the existing `YouTubeResultsView` (from Phase 12) below it. The sheet is presented from a magnifying-glass button next to the existing URL input in `ContentView`. On result selection: `controller.load(input: videoID)` (the same path the URL field uses).

**Tech Stack:** Reuses Phase 12 infrastructure — `APIKeyStore`, `YouTubeSearchAPI`, `YouTubeResultsView`. No new dependencies.

**Testing:** `swift build -c release` + final manual smoke in Task 3. Requires a configured API key (Phase 12).

**Prerequisites:** Phase 12 merged into `main`. `YouTubeResultsView` and `APIKeyStore` exist.

---

## File Structure

**New files:**

```
Sources/Murmur/YouTubeSearchSheet.swift   Sheet with TextField + YouTubeResultsView + onPick
```

**Modified files:**

- `Sources/Murmur/ContentView.swift` — add a search button next to/in the URL row that presents `YouTubeSearchSheet`.

---

### Task 1: YouTubeSearchSheet

**Files:**
- Create: `Sources/Murmur/YouTubeSearchSheet.swift`

- [ ] **Step 1: Implement**

```swift
import SwiftUI

/// Sheet presented from the main popover for searching YouTube and picking a
/// result to load on the main player.
///
/// Two-step UX: user types a query in the field; pressing Return (or clicking
/// "Search") triggers the live API call via `YouTubeResultsView`. Picking a
/// result fires `onPick(videoID)` and the parent dismisses the sheet.
struct YouTubeSearchSheet: View {
    /// Called with the chosen result's video ID. Parent should dismiss + load.
    var onPick: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var apiKeyStore = APIKeyStore.shared

    @State private var draftQuery: String = ""
    @State private var activeQuery: String = ""    // Set when user submits
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().background(Color.white.opacity(0.08))
            searchRow
            Divider().background(Color.white.opacity(0.06))
            content
        }
        .frame(width: 420, height: 480)
        .background(Color(white: 0.05))
        .onAppear { searchFocused = true }
    }

    private var header: some View {
        HStack {
            Text("Search YouTube")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white)
            Spacer()
            Button(action: { dismiss() }) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.white.opacity(0.4))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var searchRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.5))
            TextField("e.g. lofi study, synthwave radio, ocean waves…", text: $draftQuery)
                .textFieldStyle(.plain)
                .font(.system(size: 12, design: .monospaced))
                .focused($searchFocused)
                .onSubmit { activate() }
            if !draftQuery.isEmpty {
                Button(action: {
                    draftQuery = ""
                    activeQuery = ""
                }) {
                    Image(systemName: "xmark.circle")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.4))
                }
                .buttonStyle(.plain)
            }
            Button("Search") { activate() }
                .keyboardShortcut(.defaultAction)
                .disabled(!canSearch)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var content: some View {
        if !apiKeyStore.hasYouTubeKey {
            noKeyState
        } else if activeQuery.isEmpty {
            placeholderState
        } else {
            YouTubeResultsView(
                query: activeQuery,
                onPick: { result in
                    onPick(result.videoID)
                    dismiss()
                },
                onBack: {
                    activeQuery = ""
                }
            )
            .frame(maxWidth: .infinity)
        }
    }

    private var noKeyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "key.slash")
                .font(.system(size: 22))
                .foregroundColor(.white.opacity(0.3))
            Text("No YouTube API key configured.")
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.6))
            Text("Open the gear in the popover header to add one.")
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.45))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var placeholderState: some View {
        VStack(spacing: 6) {
            Image(systemName: "play.rectangle.on.rectangle")
                .font(.system(size: 22))
                .foregroundColor(.white.opacity(0.25))
            Text("Type a query and press Return.")
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.45))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var canSearch: Bool {
        apiKeyStore.hasYouTubeKey &&
        !draftQuery.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func activate() {
        guard canSearch else { return }
        activeQuery = draftQuery.trimmingCharacters(in: .whitespaces)
    }
}
```

- [ ] **Step 2: Build and commit**

```bash
cd /Users/mm/Documents/youtube-audio-widget
swift build -c release 2>&1 | tail -5
git add Sources/Murmur/YouTubeSearchSheet.swift
git commit -m "feat(popover): add YouTubeSearchSheet (search field + live results)"
```

---

### Task 2: Wire search button into popover URL row

**Files:**
- Modify: `Sources/Murmur/ContentView.swift`

Add a magnifying glass button next to the existing URL TextField. Clicking it opens the sheet. Picking a result calls `controller.load(input: videoID)`.

- [ ] **Step 1: Add sheet state**

Find the existing `@State` block in `ContentView` (around line 9, near `urlInput`). Add immediately after the Phase 12 state:

```swift
    @State private var showingYouTubeSearch: Bool = false
```

(If `showingYouTubeSearch` already exists from any reason, skip this — but it shouldn't.)

- [ ] **Step 2: Add the search button to `urlRow`**

Find the `urlRow` computed property — look for the existing line `TextField("paste url or video id", text: $urlInput, onCommit: submitURL)` (around line 84 in pre-Phase-13 code).

The current row likely looks something like:

```swift
    private var urlRow: some View {
        HStack {
            TextField("paste url or video id", text: $urlInput, onCommit: submitURL)
                ...
            Button(...) { submitURL() }
        }
    }
```

You need to insert a search button INSIDE that HStack, just before the existing TextField (or just after, whichever reads cleaner). Read the file to see the exact structure. The button to add:

```swift
            Button(action: { showingYouTubeSearch = true }) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(fgDim)
            }
            .buttonStyle(.plain)
            .help("Search YouTube")
```

Then add a `.sheet(...)` modifier to the urlRow's outer HStack (or to the parent view in `body` — anywhere stable). Add at the end of `urlRow`'s body:

```swift
        .sheet(isPresented: $showingYouTubeSearch) {
            YouTubeSearchSheet { videoID in
                _ = controller.load(input: videoID)
            }
        }
```

If the sheet syntax conflicts (modifier already on the HStack), attach to the parent body instead — search for the existing `.sheet(isPresented: $showingAPIKeySheet)` modifier on the `header` and add the new sheet right next to it. Both work; pick whichever is cleanest given the file's current layout.

- [ ] **Step 3: Build and commit**

```bash
swift build -c release 2>&1 | tail -10
git add Sources/Murmur/ContentView.swift
git commit -m "feat(popover): add YouTube search button + sheet to URL row"
```

---

### Task 3: Build bundle + smoke + tag + merge

- [ ] **Step 1: Build**

```bash
./build-app.sh --sign 2>&1 | tail -10
```

- [ ] **Step 2: Manual smoke**

Quit any running Murmur instance. `open dist/Murmur.app`.

1. Click the menu-bar icon → popover opens. The URL row now has a **magnifying-glass icon** next to (or before) the existing URL input.
2. Click the magnifying glass → **YouTubeSearchSheet** opens (420 × 480), modal over the popover.
3. The sheet shows: "Search YouTube" title, an autofocused search field, and a placeholder state ("Type a query and press Return.").
4. Type "synthwave radio" → press Return (or click **Search**). The view swaps to `YouTubeResultsView`: spinner → 10 results with thumbnails, titles, channel names.
5. Click a result → **sheet dismisses**, the player loads the YouTube video, and the floating video window picks it up (or audio plays via the menu-bar player if no video window is visible).
6. Reopen the search sheet → it's empty again. Type a new query → new results.
7. Click the X button in the search field → clears the field.
8. Test the no-key state: gear → Clear saved key → open search sheet → see "No YouTube API key configured. Open the gear in the popover header to add one."

- [ ] **Step 3: Tag**

```bash
git tag -a phase-13-popover-yt-search -m "Pocket DJ Phase 13: YouTube search in main popover"
```

- [ ] **Step 4: Merge to main**

```bash
git checkout main
git merge --no-ff pocket-dj-phase-13 -m "Merge phase 13: YouTube search in main popover"
./build-app.sh --sign 2>&1 | tail -5
```

---

## Out of Scope for Phase 13

- **Search history / recent queries** — could be added as a small follow-up.
- **Click result to add to favorites** — current flow loads the video; user can save via the existing favorites button afterward.
- **YouTube search in the ambient picker** — already shipped in Phase 12.
- **YouTube as DJ deck source** — fundamentally limited; deferred.

---

## Self-Review

- **Reuses Phase 12 infrastructure** ✅ `APIKeyStore`, `YouTubeSearchAPI`, `YouTubeResultsView`.
- **Uses existing player load path** ✅ `controller.load(input: videoID)`.
- **No-key state handled** ✅ Clear message + direction to gear.
- **Sheet auto-focus** ✅ `searchFocused = true` on `.onAppear`.
- **Return-key + Search button** ✅ Both trigger via `activate()`.

No spec gaps. Type signatures consistent.
