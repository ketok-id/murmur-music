# Pocket DJ Phase 17 — Discover Topics

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a "DISCOVER" section to the search sheet's empty state — a curated grid of audio-focused topic chips. Click one (e.g. "🎙️ Tech Podcasts") and it pre-fills the search field and runs the query. Skips the typing step for the kinds of content users actually want in a background-audio app: music mixes, podcasts, ambient sounds, talks, lofi, classical, etc. Video as incidental.

**Architecture:** A `DiscoverTopic` model holds emoji + title + query string. A hardcoded catalog lives in the same file. `DiscoverPanel` renders a 2-column grid of chips. `YouTubeSearchSheet`'s videos-mode placeholder gets DISCOVER inserted above RECENT VIDEOS / RECENT SEARCHES. Click a chip → set `draftQuery` + `activeQuery` + record to history.

**Tech Stack:** Same. No new dependencies or API calls — clicking a topic just runs the existing search path.

**Testing:** `swift build -c release` + manual smoke in Task 4.

**Prerequisites:** Phase 16 merged into `main`.

---

## File Structure

**New files:**

```
Sources/Murmur/Ambient/
  DiscoverTopic.swift      Model + curated catalog
Sources/Murmur/Booth/
  DiscoverPanel.swift      Grid of topic chips
```

**Modified files:**

- `Sources/Murmur/YouTubeSearchSheet.swift` — insert DISCOVER section in videos-mode placeholder.

---

### Task 1: DiscoverTopic + catalog

**Files:**
- Create: `Sources/Murmur/Ambient/DiscoverTopic.swift`

- [ ] **Step 1: Implement**

```swift
import Foundation

/// One curated audio-focused topic. Click → run `query` as a YouTube search.
struct DiscoverTopic: Identifiable, Equatable {
    let emoji: String
    let title: String
    let query: String

    /// id = "emoji|title" so duplicates can't slip in by accident.
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
```

- [ ] **Step 2: Build + commit**

```bash
cd /Users/mm/Documents/youtube-audio-widget
swift build -c release 2>&1 | tail -5
git add Sources/Murmur/Ambient/DiscoverTopic.swift
git commit -m "feat(ambient): add DiscoverTopic catalog of curated audio-focused topics"
```

---

### Task 2: DiscoverPanel view

**Files:**
- Create: `Sources/Murmur/Booth/DiscoverPanel.swift`

- [ ] **Step 1: Implement**

```swift
import SwiftUI

/// Grid of audio-focused discovery topics. Clicking a chip fires `onPick`
/// with the topic's query string.
struct DiscoverPanel: View {
    var onPick: (DiscoverTopic) -> Void

    private let columns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(DiscoverTopic.catalog) { topic in
                Button(action: { onPick(topic) }) {
                    HStack(spacing: 8) {
                        Text(topic.emoji)
                            .font(.system(size: 16))
                        Text(topic.title)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.white.opacity(0.85))
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                    )
                    .cornerRadius(6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 10)
    }
}
```

- [ ] **Step 2: Build + commit**

```bash
swift build -c release 2>&1 | tail -5
git add Sources/Murmur/Booth/DiscoverPanel.swift
git commit -m "feat(booth): add DiscoverPanel (2-column topic chip grid)"
```

---

### Task 3: Insert DISCOVER section into YouTubeSearchSheet placeholder

**Files:**
- Modify: `Sources/Murmur/YouTubeSearchSheet.swift`

The current placeholder shows either an empty-state or a list with RECENT VIDEOS + RECENT SEARCHES. Add a DISCOVER section at the top in videos mode. Always visible in videos mode (even when history is empty).

- [ ] **Step 1: Add a `discoverSection` helper and rework placeholderState**

Find the existing `placeholderState` computed property. Replace it with:

```swift
    @ViewBuilder
    private var placeholderState: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if mode == .videos {
                    discoverSection
                }
                if !played.entries.isEmpty && mode == .videos {
                    Divider().background(Color.white.opacity(0.04))
                    recentVideosSection
                }
                if !history.entries.isEmpty {
                    Divider().background(Color.white.opacity(0.04))
                    recentSearchesSection
                }
                if mode == .channels && history.entries.isEmpty && played.entries.isEmpty {
                    // Channels mode with no history: show a small hint.
                    VStack(spacing: 6) {
                        Image(systemName: "person.crop.circle")
                            .font(.system(size: 22))
                            .foregroundColor(.white.opacity(0.25))
                        Text("Type a channel name, paste a URL, or @handle.")
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.45))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private var discoverSection: some View {
        HStack {
            Text("DISCOVER")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .tracking(1.5)
                .foregroundColor(.white.opacity(0.4))
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 6)

        DiscoverPanel { topic in
            mode = .videos
            draftQuery = topic.query
            activeQuery = topic.query
            SearchHistoryStore.shared.record(query: topic.query, mode: .videos)
        }
    }
```

- [ ] **Step 2: Build + commit**

```bash
swift build -c release 2>&1 | tail -10
git add Sources/Murmur/YouTubeSearchSheet.swift
git commit -m "feat(popover): show DISCOVER topic chips in search sheet placeholder"
```

---

### Task 4: Build bundle + smoke + tag + merge

- [ ] **Step 1: Build**

```bash
./build-app.sh --sign 2>&1 | tail -10
```

- [ ] **Step 2: Manual smoke**

Quit running Murmur. `open dist/Murmur.app`.

1. Open the menu-bar popover → 🔍 → search sheet opens.
2. **Videos mode (default):** at the top of the empty state, a **DISCOVER** section shows 16 topic chips in a 2-column grid: Lofi & Chill, Music Mixes, Jazz & Soul, Classical, Ambient, EDM, Indie, Piano, Tech Podcasts, Interviews, Audiobooks, Science Talks, Rain Sounds, Fireplace, Live Radio, Nature Sounds.
3. Click **🎧 Lofi & Chill** → search field fills with "lofi hip hop study", results appear immediately.
4. Click ← to clear → back to placeholder. DISCOVER still there.
5. Click **🎙️ Tech Podcasts** → search field fills with "tech podcast", results.
6. After clicking a few topics, the **RECENT SEARCHES** section shows them as recently-used queries below DISCOVER. They're recorded normally.
7. Switch to **Channels** mode → DISCOVER is gone (audio-focused topics don't make sense for channel search). Channels placeholder shows the small "Type a channel name, paste a URL, or @handle." hint.
8. Switch back to Videos → DISCOVER returns.

- [ ] **Step 3: Tag + merge**

```bash
git tag -a phase-17-discover -m "Pocket DJ Phase 17: Discover topics in search sheet"
git checkout main
git merge --no-ff pocket-dj-phase-17 -m "Merge phase 17: Discover topics"
./build-app.sh --sign 2>&1 | tail -5
```

---

## Out of scope for Phase 17

- **Duration + category badges on results** (extra `videos.list` call per search, 1 unit) — useful but adds complexity. Can be a separate phase.
- **User-customizable Discover catalog** — chips are hardcoded for now.
- **Discover for channels** (e.g., "Top podcast channels") — would need pre-curated channel IDs. Different shape.
- **Trending / popular endpoints** — Data API has `videos.list?chart=mostPopular` but not topic-filtered well.

---

## Self-Review

- **Discover panel always visible in videos mode** ✅ even when search/play history is empty.
- **Click a topic → instant search** without typing ✅
- **Records to history naturally** ✅ so frequently-clicked topics become a fast-loop via RECENT SEARCHES.
- **Channels mode gets its own placeholder hint** ✅ since DISCOVER doesn't apply there.
- **Curated topics span music + podcasts + atmospherics + talks** ✅
