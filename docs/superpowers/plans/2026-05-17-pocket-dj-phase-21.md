# Pocket DJ Phase 21 — Queue + Auto-Advance + Playback Speed

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn the popover from "single-track player" into a "session listener." Three coordinated features:

1. **Playback queue** — line up tracks; persists across launches; reorder/remove.
2. **Auto-advance** — when the current video ends, pop the queue and play next.
3. **Playback speed** — 0.5× to 2× via YouTube's native `setPlaybackRate` (podcast staple: 1.25/1.5×).

**Architecture:**
- `PlaybackQueue` is a singleton `ObservableObject` with `[QueueItem]` persisted to `UserDefaults`. Items are uniquely IDed by `UUID` so duplicate videos can coexist.
- `PlayerController` gains: `var onEnded: (() -> Void)?` callback, `@Published var playbackRate: Double = 1.0` with `didSet` → `setPlaybackRate(rate)` (JS bridge already generic; just call `ytCmd('setPlaybackRate', [rate])`).
- `ScriptHandler`'s ended-state case (`playerState == 0`) calls `c.onEnded?()`.
- `AppDelegate` wires `controller.onEnded` to `PlaybackQueue.shared.popNext()` → `controller.load(input:)`.
- `QueueSheet` is the queue UI (similar pattern to `RecordingsView`): list, reorder, remove, clear.
- Result rows in `YouTubeResultsView`, `playedRow`, and `ChannelBrowseView` get a `.contextMenu` with "Play next" / "Add to queue".
- A new "queue" button in the popover header shows the queue count + opens the sheet.
- Playback speed picker is a small `Menu` next to the volume slider showing the current speed.

**Tech Stack:** Same. No new dependencies.

**Testing:** `swift build -c release` + manual smoke in Task 8.

**Prerequisites:** Phase 20 merged into `main`.

---

## File Structure

**New files:**

```
Sources/Murmur/Ambient/
  PlaybackQueue.swift       Singleton + QueueItem + UserDefaults persistence
Sources/Murmur/Booth/
  QueueSheet.swift          Sheet view listing the queue with reorder/remove
```

**Modified files:**

- `Sources/Murmur/main.swift`:
  - `PlayerController` gains `onEnded`, `playbackRate`, `setPlaybackRate(_:)`.
  - `ScriptHandler` invokes `c.onEnded?()` on ended state.
  - `AppDelegate` wires the queue advance + provides a `QueueLauncher` env object for the popover.
- `Sources/Murmur/ContentView.swift`:
  - Queue button in header (shows count when non-empty) + sheet.
  - Playback speed `Menu` in the controls row.
- `Sources/Murmur/Booth/YouTubeResultsView.swift` — `.contextMenu` on row.
- `Sources/Murmur/Booth/ChannelBrowseView.swift` — `.contextMenu` on row.
- `Sources/Murmur/YouTubeSearchSheet.swift` — `.contextMenu` on `playedRow`.

---

### Task 1: PlaybackQueue + QueueItem

**Files:**
- Create: `Sources/Murmur/Ambient/PlaybackQueue.swift`

- [ ] **Step 1: Implement**

```swift
import Combine
import Foundation

/// One queued track. UUID-IDed so multiple of the same video can coexist.
struct QueueItem: Codable, Identifiable, Equatable {
    let id: UUID
    let videoID: String
    var title: String
    var thumbnailURL: String
    let addedAt: Date

    var thumb: URL? {
        URL(string: thumbnailURL.isEmpty
            ? "https://img.youtube.com/vi/\(videoID)/mqdefault.jpg"
            : thumbnailURL)
    }
}

/// UserDefaults-backed playback queue. FIFO by default; supports
/// reorder and "play next" insertion at index 0.
final class PlaybackQueue: ObservableObject {
    static let shared = PlaybackQueue()

    @Published private(set) var items: [QueueItem] = []

    private let key = "youtube-audio-widget.playback-queue.v1"

    private init() { load() }

    var count: Int { items.count }
    var isEmpty: Bool { items.isEmpty }

    /// Append to the end.
    func enqueue(videoID: String, title: String, thumbnailURL: String = "") {
        items.append(QueueItem(
            id: UUID(),
            videoID: videoID,
            title: title,
            thumbnailURL: thumbnailURL,
            addedAt: Date()
        ))
        save()
    }

    /// Insert at index 0 — plays after the current track ends.
    func enqueueNext(videoID: String, title: String, thumbnailURL: String = "") {
        items.insert(QueueItem(
            id: UUID(),
            videoID: videoID,
            title: title,
            thumbnailURL: thumbnailURL,
            addedAt: Date()
        ), at: 0)
        save()
    }

    func remove(itemID: UUID) {
        items.removeAll { $0.id == itemID }
        save()
    }

    func move(from source: IndexSet, to destination: Int) {
        items.move(fromOffsets: source, toOffset: destination)
        save()
    }

    func clear() {
        items = []
        save()
    }

    /// Pop the next item (FIFO). Returns nil if queue is empty.
    @discardableResult
    func popNext() -> QueueItem? {
        guard !items.isEmpty else { return nil }
        let item = items.removeFirst()
        save()
        return item
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let list = try? JSONDecoder().decode([QueueItem].self, from: data) else { return }
        items = list
    }

    private func save() {
        if let data = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
```

- [ ] **Step 2: Build + commit**

```bash
cd /Users/mm/Documents/youtube-audio-widget
swift build -c release 2>&1 | tail -5
git add Sources/Murmur/Ambient/PlaybackQueue.swift
git commit -m "feat(ambient): add PlaybackQueue + QueueItem"
```

---

### Task 2: PlayerController gains onEnded + playbackRate

**Files:**
- Modify: `Sources/Murmur/main.swift`

### Change 1: Add onEnded callback + playbackRate

In `PlayerController`, find the existing `@Published` properties (around line 62). Add immediately after `@Published var currentTime: Double = 0`:

```swift
    /// Speed multiplier; 1.0 = normal. YouTube supports 0.25 – 2.0.
    @Published var playbackRate: Double = 1.0 {
        didSet { applyPlaybackRate() }
    }
    /// Called when the YouTube playerState transitions to ended (state 0).
    var onEnded: (() -> Void)?
```

Find the existing `play()` / `pause()` / `setVolume(...)` / `unmute()` methods (around line 224-228). Add immediately after `unmute()`:

```swift
    func setPlaybackRate(_ rate: Double) {
        playbackRate = rate
    }

    private func applyPlaybackRate() {
        let rate = max(0.25, min(2.0, playbackRate))
        webView.evaluateJavaScript("window.ytCmd && ytCmd('setPlaybackRate', [\(rate)]);",
                                   completionHandler: nil)
    }
```

### Change 2: ScriptHandler fires onEnded

Find the existing switch case for state 0 (around line 258):
```swift
                    case 0: c.isPlaying = false; c.status = "Ended"
```

Replace with:
```swift
                    case 0:
                        c.isPlaying = false
                        c.status = "Ended"
                        c.onEnded?()
```

### Change 3: Re-apply rate after onReady

The iframe forgets the rate when reloaded. Find the `case "ready":` block in ScriptHandler (around line 246):
```swift
            case "ready":
                c.isReady = true
                c.status = "Ready"
                c.unmute()
                c.setVolume(Int(c.volume))
                c.play()
```

Replace with:
```swift
            case "ready":
                c.isReady = true
                c.status = "Ready"
                c.unmute()
                c.setVolume(Int(c.volume))
                c.play()
                if c.playbackRate != 1.0 {
                    c.setPlaybackRate(c.playbackRate)
                }
```

- [ ] **Step 1: Build + commit**

```bash
swift build -c release 2>&1 | tail -10
git add Sources/Murmur/main.swift
git commit -m "feat(player): add onEnded callback + playbackRate"
```

---

### Task 3: AppDelegate wires queue auto-advance + popover env object

**Files:**
- Modify: `Sources/Murmur/main.swift`

### Change 1: Add QueueLauncher shim

The popover needs a way to open the queue sheet. Following the same pattern as `BoothLauncher`/`RecordingsLauncher`, add at the bottom of the file BEFORE the `// MARK: - Boot` line:

```swift
// MARK: - Queue launcher (SwiftUI bridge)
final class QueueLauncher: ObservableObject {
    @Published var isShowing = false
    func show() { isShowing = true }
}
```

### Change 2: Add queue launcher + advance hook in AppDelegate

In `AppDelegate`, find the existing `var booth: BoothWindowController!` and `var recordings: RecordingsWindowController!` properties. Add:

```swift
    let queueLauncher = QueueLauncher()
```

In `applicationDidFinishLaunching`, find the existing `historyCancellable = controller.$title.…` block. After the `positionCancellable = …` block, add:

```swift
        // Queue auto-advance.
        controller.onEnded = { [weak self] in
            guard let self = self else { return }
            if let next = PlaybackQueue.shared.popNext() {
                _ = self.controller.load(input: next.videoID)
            }
        }
```

### Change 3: Inject queueLauncher into popover environment

Find the `popover.contentViewController = NSHostingController(rootView: ContentView() ...)` block. The current chain looks like:

```swift
        popover.contentViewController = NSHostingController(
            rootView: ContentView()
                .environmentObject(controller)
                .environmentObject(favorites)
                .environmentObject(videoWindow)
                .environmentObject(mixer)
                .environmentObject(BoothLauncher(booth: booth))
                .environmentObject(RecordingsLauncher(controller: recordings))
        )
```

Add `.environmentObject(queueLauncher)` to the chain. So it becomes:

```swift
        popover.contentViewController = NSHostingController(
            rootView: ContentView()
                .environmentObject(controller)
                .environmentObject(favorites)
                .environmentObject(videoWindow)
                .environmentObject(mixer)
                .environmentObject(BoothLauncher(booth: booth))
                .environmentObject(RecordingsLauncher(controller: recordings))
                .environmentObject(queueLauncher)
        )
```

- [ ] **Step 1: Build + commit**

```bash
swift build -c release 2>&1 | tail -10
git add Sources/Murmur/main.swift
git commit -m "feat(player): wire onEnded to PlaybackQueue + QueueLauncher env"
```

---

### Task 4: QueueSheet UI

**Files:**
- Create: `Sources/Murmur/Booth/QueueSheet.swift`

- [ ] **Step 1: Implement**

```swift
import SwiftUI

/// Modal sheet showing the playback queue with reorder/remove/play-now.
struct QueueSheet: View {
    var onPlayNow: (QueueItem) -> Void

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var queue = PlaybackQueue.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().background(Color.white.opacity(0.08))
            content
        }
        .frame(width: 420, height: 500)
        .background(Color(white: 0.05))
    }

    private var header: some View {
        HStack {
            Text("Up Next")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white)
            Text("(\(queue.count))")
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.white.opacity(0.4))
            Spacer()
            if !queue.isEmpty {
                Button("Clear all") { queue.clear() }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.red.opacity(0.7))
            }
            Button(action: { dismiss() }) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.white.opacity(0.4))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var content: some View {
        if queue.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "list.bullet")
                    .font(.system(size: 24))
                    .foregroundColor(.white.opacity(0.25))
                Text("Queue is empty.")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.45))
                Text("Right-click a search result → \"Add to queue\".")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.35))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List {
                ForEach(queue.items) { item in
                    row(item)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
                .onMove { src, dest in queue.move(from: src, to: dest) }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }

    private func row(_ item: QueueItem) -> some View {
        HStack(spacing: 10) {
            Button(action: { onPlayNow(item); dismiss() }) {
                HStack(spacing: 10) {
                    AsyncImage(url: item.thumb) { phase in
                        switch phase {
                        case .success(let image): image.resizable().aspectRatio(contentMode: .fill)
                        default: Rectangle().fill(Color.white.opacity(0.05))
                        }
                    }
                    .frame(width: 64, height: 36)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                    .overlay(RoundedRectangle(cornerRadius: 3).stroke(Color.white.opacity(0.06), lineWidth: 0.5))

                    Text(item.title.isEmpty ? item.videoID : item.title)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.9))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button(action: { queue.remove(itemID: item.id) }) {
                Image(systemName: "xmark.circle")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.35))
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 3)
    }
}
```

- [ ] **Step 2: Build + commit**

```bash
swift build -c release 2>&1 | tail -10
git add Sources/Murmur/Booth/QueueSheet.swift
git commit -m "feat(booth): add QueueSheet for playback queue management"
```

---

### Task 5: Queue button + sheet + playback speed in popover

**Files:**
- Modify: `Sources/Murmur/ContentView.swift`

### Change 1: Add @EnvironmentObject for queueLauncher + queue observation

Find the existing `@EnvironmentObject` declarations at the top of `ContentView`. Add:

```swift
    @EnvironmentObject var queueLauncher: QueueLauncher
    @ObservedObject private var playbackQueue = PlaybackQueue.shared
```

### Change 2: Queue button in header

Find the existing header `HStack` (line ~54-87). The gear button is at the trailing end. Add a queue button before the gear (so order is: Video, Reload, Queue, Gear):

Find:
```swift
            Button(action: { controller.reload() }) {
                Text("Reload").foregroundColor(fgDim)
            }
            .buttonStyle(.plain)
            .help("Reload current stream")
            Button(action: { showingAPIKeySheet = true }) {
```

Insert a queue button between them:

```swift
            Button(action: { controller.reload() }) {
                Text("Reload").foregroundColor(fgDim)
            }
            .buttonStyle(.plain)
            .help("Reload current stream")
            Button(action: { queueLauncher.show() }) {
                if playbackQueue.isEmpty {
                    Image(systemName: "list.bullet")
                        .foregroundColor(fgDim)
                } else {
                    HStack(spacing: 2) {
                        Image(systemName: "list.bullet")
                        Text("\(playbackQueue.count)")
                    }
                    .foregroundColor(accent)
                }
            }
            .buttonStyle(.plain)
            .help("Playback queue")
            Button(action: { showingAPIKeySheet = true }) {
```

### Change 3: Wire QueueSheet to the launcher

The existing `.sheet(isPresented: $showingAPIKeySheet)` is on the header. Add a sibling `.sheet` to the same parent. Find:

```swift
        .font(.system(size: 11, weight: .medium, design: .monospaced))
        .sheet(isPresented: $showingAPIKeySheet) {
            APIKeySetupSheet(store: apiKeyStore)
        }
    }
```

Replace with:
```swift
        .font(.system(size: 11, weight: .medium, design: .monospaced))
        .sheet(isPresented: $showingAPIKeySheet) {
            APIKeySetupSheet(store: apiKeyStore)
        }
        .sheet(isPresented: $queueLauncher.isShowing) {
            QueueSheet { item in
                _ = controller.load(input: item.videoID)
            }
        }
    }
```

### Change 4: Playback speed Menu in controlsRow

Find the existing `controlsRow`:
```swift
    private var controlsRow: some View {
        HStack(spacing: 8) {
            Text("vol")
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundColor(fgDim)
            Slider(value: $controller.volume, in: 0...100)
                .tint(accent)
                .controlSize(.mini)
                .onChange(of: controller.volume) { newVal in
                    controller.setVolume(Int(newVal))
                }
            Text(String(format: "%03d", Int(controller.volume)))
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundColor(fg)
        }
    }
```

Replace with:
```swift
    private var controlsRow: some View {
        HStack(spacing: 8) {
            Text("vol")
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundColor(fgDim)
            Slider(value: $controller.volume, in: 0...100)
                .tint(accent)
                .controlSize(.mini)
                .onChange(of: controller.volume) { newVal in
                    controller.setVolume(Int(newVal))
                }
            Text(String(format: "%03d", Int(controller.volume)))
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundColor(fg)
            Menu {
                ForEach([0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0], id: \.self) { rate in
                    Button(action: { controller.setPlaybackRate(rate) }) {
                        if controller.playbackRate == rate {
                            Label(String(format: "%.2fx", rate), systemImage: "checkmark")
                        } else {
                            Text(String(format: "%.2fx", rate))
                        }
                    }
                }
            } label: {
                Text(String(format: "%.2gx", controller.playbackRate))
                    .foregroundColor(controller.playbackRate == 1.0 ? fgDim : accent)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .font(.system(size: 9, weight: .medium, design: .monospaced))
            .help("Playback speed")
        }
    }
```

- [ ] **Step 1: Build + commit**

```bash
swift build -c release 2>&1 | tail -10
git add Sources/Murmur/ContentView.swift
git commit -m "feat(popover): queue button + sheet + playback-speed menu"
```

---

### Task 6: Context menus on result rows

**Files:**
- Modify: `Sources/Murmur/Booth/YouTubeResultsView.swift`
- Modify: `Sources/Murmur/Booth/ChannelBrowseView.swift`
- Modify: `Sources/Murmur/YouTubeSearchSheet.swift`

Each video-row Button gets a `.contextMenu` with "Play next" and "Add to queue".

### Change 1: YouTubeResultsView.row

In `Sources/Murmur/Booth/YouTubeResultsView.swift`, find the `row(_:)` method. After the closing `}` of `.buttonStyle(.plain)` (i.e., on the outer Button), add `.contextMenu` modifier:

Find:
```swift
        .buttonStyle(.plain)
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
```

Replace with:
```swift
        .buttonStyle(.plain)
        .contextMenu {
            Button("Play next") {
                PlaybackQueue.shared.enqueueNext(
                    videoID: result.videoID,
                    title: result.title,
                    thumbnailURL: result.thumbnailURL?.absoluteString ?? ""
                )
            }
            Button("Add to queue") {
                PlaybackQueue.shared.enqueue(
                    videoID: result.videoID,
                    title: result.title,
                    thumbnailURL: result.thumbnailURL?.absoluteString ?? ""
                )
            }
        }
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
```

### Change 2: ChannelBrowseView.videoRow

In `Sources/Murmur/Booth/ChannelBrowseView.swift`, find the `videoRow(_:)` method's closing `}.buttonStyle(.plain)`. Add a `.contextMenu` right after it:

Find:
```swift
        .buttonStyle(.plain)
    }

    private var loadMoreButton: some View {
```

Replace with:
```swift
        .buttonStyle(.plain)
        .contextMenu {
            Button("Play next") {
                PlaybackQueue.shared.enqueueNext(
                    videoID: video.videoID,
                    title: video.title,
                    thumbnailURL: video.thumbnailURL?.absoluteString ?? ""
                )
            }
            Button("Add to queue") {
                PlaybackQueue.shared.enqueue(
                    videoID: video.videoID,
                    title: video.title,
                    thumbnailURL: video.thumbnailURL?.absoluteString ?? ""
                )
            }
        }
    }

    private var loadMoreButton: some View {
```

### Change 3: YouTubeSearchSheet.playedRow

In `Sources/Murmur/YouTubeSearchSheet.swift`, find the `playedRow(_:)` method. After the outer Button's `.buttonStyle(.plain)` (the one that triggers `onPick(entry.videoID)`), add `.contextMenu`:

Find the inside of `playedRow` — specifically the outer HStack's first Button block. After its `}.buttonStyle(.plain)`, the next element is the trash Button. Add a `.contextMenu` to the FIRST Button (the title/thumbnail tap target) by adding the modifier RIGHT BEFORE the trash button block.

Look for this structure in playedRow:
```swift
            Button(action: { onPick(entry.videoID); dismiss() }) {
                HStack(spacing: 12) {
                    ...
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button(action: { played.remove(videoID: entry.videoID) }) {
```

Insert a `.contextMenu` modifier on the first Button:

```swift
            Button(action: { onPick(entry.videoID); dismiss() }) {
                HStack(spacing: 12) {
                    ...
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .contextMenu {
                Button("Play next") {
                    PlaybackQueue.shared.enqueueNext(
                        videoID: entry.videoID,
                        title: entry.title,
                        thumbnailURL: entry.thumbnailURL?.absoluteString ?? ""
                    )
                }
                Button("Add to queue") {
                    PlaybackQueue.shared.enqueue(
                        videoID: entry.videoID,
                        title: entry.title,
                        thumbnailURL: entry.thumbnailURL?.absoluteString ?? ""
                    )
                }
            }

            Button(action: { played.remove(videoID: entry.videoID) }) {
```

- [ ] **Step 1: Build + commit**

```bash
swift build -c release 2>&1 | tail -10
git add Sources/Murmur/Booth/YouTubeResultsView.swift Sources/Murmur/Booth/ChannelBrowseView.swift Sources/Murmur/YouTubeSearchSheet.swift
git commit -m "feat(booth): right-click context menu for queue actions on video rows"
```

---

### Task 7: Build bundle + smoke + tag + merge

- [ ] **Step 1: Build**

```bash
./build-app.sh --sign 2>&1 | tail -10
```

- [ ] **Step 2: Manual smoke**

Quit running Murmur. `open dist/Murmur.app`.

**Queue + auto-advance:**

1. Open popover → 🔍 → search any music → results.
2. **Right-click** a result → context menu with "Play next" and "Add to queue".
3. Click "Add to queue" — sheet stays open. Right-click another → "Add to queue". Repeat 3 times.
4. Open the popover → header has a new **list-bullet icon with count** (e.g., `3`) in accent color.
5. Click it → **QueueSheet** opens listing the 3 items with thumbnails.
6. Reorder via drag (List supports `.onMove`). Remove one via the X. Click another row's main area → it plays now, sheet dismisses.
7. Let that video play to its end (or skip ahead near the end). When it ends, **the next queued item auto-loads**. ✅
8. After all queue items play through, the queue is empty.

**Playback speed:**

9. In the popover, controls row has the volume slider + a small "1.0x" menu trigger to the right.
10. Click → menu with 0.5x / 0.75x / 1.0x / 1.25x / 1.5x / 1.75x / 2.0x. Current is checkmarked.
11. Click 1.5x → audio speeds up (1.5×). The label shows "1.5x" in accent color (vs `fgDim` at 1.0x).
12. Reload a track / load a new one → speed is preserved across reloads (the `onReady` hook re-applies it).
13. Set back to 1.0x → label returns to dim.

**Persistence:**

14. Queue 2 items, quit Murmur, relaunch. Queue is still there.

- [ ] **Step 3: Tag + merge**

```bash
git tag -a phase-21-queue-and-speed -m "Pocket DJ Phase 21: queue + auto-advance + playback speed"
git checkout main
git merge --no-ff pocket-dj-phase-21 -m "Merge phase 21: session listening"
./build-app.sh --sign 2>&1 | tail -5
```

---

## Out of scope for Phase 21

- **Shuffle / repeat** — could be a small follow-up. For now, queue is strict FIFO.
- **Queue from main popover favorites / Discover** — context menu only on search/history/channel-browse rows.
- **Auto-fill queue with "next suggested" on ended** — needs a separate recommendation source.
- **Cross-fade between queue items** — would need audio routing through AVAudioEngine.

---

## Self-Review

- **Queue persistence via UserDefaults** ✅
- **Auto-advance via PlayerController.onEnded** — minimal callback hook ✅
- **Playback rate preserved across reloads** via onReady re-apply ✅
- **Queue count visible in popover header** so user always knows what's stacked up ✅
- **Right-click "Play next" / "Add to queue"** on all video-row surfaces (search, history, channel browse) ✅
- **List reorder** via SwiftUI `.onMove` ✅
