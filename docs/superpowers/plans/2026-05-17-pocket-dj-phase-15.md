# Pocket DJ Phase 15 — Search History

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Save the user's recent YouTube searches and surface them as one-click "rerun" chips when the search field is empty. Persistence is `UserDefaults`. Tracks both Videos-mode and Channels-mode queries; clicking a chip restores the mode + query + activates it. Capped at the last 20 entries.

**Architecture:** `SearchHistoryEntry` is a `Codable` value (query + mode + date). `SearchHistoryStore` is a singleton `UserDefaults`-backed `ObservableObject` mirroring the existing favorites stores. The store offers `record(query:mode:)` which deduplicates (moves matching entry to top), and `clear()`. `YouTubeSearchSheet` calls `record` whenever `activate()` fires; the placeholder state in `content` now lists recent entries as chips/rows above a small "Clear history" link.

**Tech Stack:** Same. No new dependencies.

**Testing:** `swift build -c release` + manual smoke in Task 4.

**Prerequisites:** Phase 14 merged into `main`.

---

## File Structure

**New files:**

```
Sources/Murmur/Ambient/
  SearchHistoryStore.swift   Codable entry model + UserDefaults-backed store
```

**Modified files:**

- `Sources/Murmur/YouTubeSearchSheet.swift` — record on `activate()`; redesign `placeholderState` and add "Recent" section.

---

### Task 1: SearchHistoryStore

**Files:**
- Create: `Sources/Murmur/Ambient/SearchHistoryStore.swift`

- [ ] **Step 1: Implement**

```swift
import Combine
import Foundation

/// One saved search query, with the mode it ran in and when it was last used.
struct SearchHistoryEntry: Codable, Identifiable, Equatable {
    enum Mode: String, Codable {
        case videos, channels
    }
    let query: String
    let mode: Mode
    var date: Date

    /// id = "mode|query" so the same query in two modes is two entries.
    var id: String { "\(mode.rawValue)|\(query)" }
}

/// UserDefaults-backed history of recent YouTube searches. Capped at the most
/// recent 20 unique (query+mode) entries; submitting a duplicate moves it to
/// the top instead of adding a second row.
final class SearchHistoryStore: ObservableObject {
    static let shared = SearchHistoryStore()

    @Published private(set) var entries: [SearchHistoryEntry] = []

    private let key = "youtube-audio-widget.search-history.v1"
    private let cap = 20

    private init() { load() }

    /// Add (or refresh) a query in the history. Moves an existing match to
    /// the top with an updated timestamp; otherwise prepends a new entry.
    func record(query: String, mode: SearchHistoryEntry.Mode) {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let id = "\(mode.rawValue)|\(trimmed)"
        var list = entries
        list.removeAll { $0.id == id }
        list.insert(SearchHistoryEntry(query: trimmed, mode: mode, date: Date()), at: 0)
        if list.count > cap { list = Array(list.prefix(cap)) }
        entries = list
        save()
    }

    func remove(id: String) {
        entries.removeAll { $0.id == id }
        save()
    }

    func clear() {
        entries = []
        save()
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let list = try? JSONDecoder().decode([SearchHistoryEntry].self, from: data) else { return }
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
git add Sources/Murmur/Ambient/SearchHistoryStore.swift
git commit -m "feat(ambient): add SearchHistoryStore for recent queries"
```

---

### Task 2: Record submissions in YouTubeSearchSheet

**Files:**
- Modify: `Sources/Murmur/YouTubeSearchSheet.swift`

- [ ] **Step 1: Wire `record` into `activate()`**

Open `Sources/Murmur/YouTubeSearchSheet.swift`. Find the existing `activate()` method:

```swift
    private func activate() {
        guard canSearch else { return }
        activeQuery = draftQuery.trimmingCharacters(in: .whitespaces)
    }
```

Replace with:

```swift
    private func activate() {
        guard canSearch else { return }
        let trimmed = draftQuery.trimmingCharacters(in: .whitespaces)
        activeQuery = trimmed
        SearchHistoryStore.shared.record(
            query: trimmed,
            mode: mode == .videos ? .videos : .channels
        )
    }
```

- [ ] **Step 2: Build + commit**

```bash
swift build -c release 2>&1 | tail -5
git add Sources/Murmur/YouTubeSearchSheet.swift
git commit -m "feat(popover): record activated searches in history"
```

---

### Task 3: Show recent-searches list in the placeholder state

**Files:**
- Modify: `Sources/Murmur/YouTubeSearchSheet.swift`

The current `placeholderState` shows a single "Type a query and press Return." Replace it with a richer placeholder that includes a "Recent" section when history has entries.

- [ ] **Step 1: Add history store reference**

Near the existing `@ObservedObject private var apiKeyStore = APIKeyStore.shared`, add:

```swift
    @ObservedObject private var history = SearchHistoryStore.shared
```

- [ ] **Step 2: Replace `placeholderState`**

Find the existing computed property:

```swift
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
```

Replace with:

```swift
    @ViewBuilder
    private var placeholderState: some View {
        if history.entries.isEmpty {
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
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("RECENT")
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

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(history.entries) { entry in
                            historyRow(entry)
                            if entry.id != history.entries.last?.id {
                                Divider()
                                    .background(Color.white.opacity(0.04))
                                    .padding(.leading, 38)
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private func historyRow(_ entry: SearchHistoryEntry) -> some View {
        HStack(spacing: 10) {
            Button(action: { reenter(entry) }) {
                HStack(spacing: 10) {
                    Image(systemName: entry.mode == .videos ? "play.rectangle" : "person.crop.circle")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.5))
                        .frame(width: 18)
                    Text(entry.query)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.white.opacity(0.85))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button(action: { history.remove(id: entry.id) }) {
                Image(systemName: "xmark.circle")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.3))
            }
            .buttonStyle(.plain)
            .help("Remove from history")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
    }

    /// Restore a history entry: switches mode, fills the field, and activates.
    private func reenter(_ entry: SearchHistoryEntry) {
        mode = (entry.mode == .videos) ? .videos : .channels
        draftQuery = entry.query
        // Bypass `activate()` — record is unnecessary since it's already at top.
        activeQuery = entry.query
        // Bump its timestamp so it stays at the top.
        history.record(query: entry.query, mode: entry.mode)
    }
```

- [ ] **Step 3: Build + commit**

```bash
swift build -c release 2>&1 | tail -10
git add Sources/Murmur/YouTubeSearchSheet.swift
git commit -m "feat(popover): show recent searches when sheet is empty"
```

---

### Task 4: Build bundle + smoke + tag + merge

- [ ] **Step 1: Build**

```bash
./build-app.sh --sign 2>&1 | tail -10
```

- [ ] **Step 2: Manual smoke**

Quit running Murmur. `open dist/Murmur.app`.

1. Menu-bar icon → 🔍 → search sheet opens.
2. **Fresh install / empty history:** shows "Type a query and press Return." (Same as before.)
3. Type "lofi study" → Return → results appear. Pick → sheet dismisses.
4. Open the sheet again → empty search field → **"RECENT" section appears with "lofi study"** as a row with a small ▶ icon (videos mode).
5. Switch to **Channels** mode → search "lofi girl" → Return → results. Pick the channel → ★ it → browse → pick a video → dismiss.
6. Reopen sheet → both "lofi study" (with ▶ icon) and "lofi girl" (with person icon) appear, newest first. Channels icon indicates channels-mode entry.
7. Click "lofi study" row → sheet switches to Videos mode, fills "lofi study" in the field, activates the search, results appear.
8. Back to empty state → click the **X** on a history row → that entry removed.
9. **Clear** at the top → all history wiped.
10. Quit + relaunch → history persists.

- [ ] **Step 3: Tag + merge**

```bash
git tag -a phase-15-search-history -m "Pocket DJ Phase 15: persistent search history"
git checkout main
git merge --no-ff pocket-dj-phase-15 -m "Merge phase 15: search history"
./build-app.sh --sign 2>&1 | tail -5
```

---

## Out of scope for Phase 15

- **Play history** (which videos got loaded onto the main player) — separate feature, could be next.
- **Cross-device sync** — UserDefaults only.
- **Time-based grouping** ("Today", "Yesterday", …) — flat list for v1.
- **Search history in the ambient picker's YouTube tab** — only the main sheet for v1.

---

## Self-Review

- **Recent queries persist via UserDefaults** ✅
- **Deduplication moves repeated queries to top** ✅
- **Mode-aware (videos vs channels)** ✅ — small icon distinguishes
- **Click to rerun** ✅ switches mode + fills field + activates
- **Per-row remove + global clear** ✅
- **Cap at 20** ✅
