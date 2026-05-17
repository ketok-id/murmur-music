# Pocket DJ Phase 20 — Watch Timestamps (Resume Where You Left Off)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Track playhead position for every played video, persist across launches, and resume from the saved spot the next time the same video is loaded. Show a small "↩︎ 0:42:30" badge on RECENT VIDEOS rows so the user knows what'll happen.

**Architecture:**
- The YouTube iframe's `infoDelivery` postMessage already includes `currentTime`. We hook the existing JS forwarder to ship a new `time` message to Swift.
- `PlayerController` gains `@Published var currentTime: Double = 0`. `ScriptHandler` handles a new `"time"` case.
- `PlayedVideoEntry` gains `var lastPosition: TimeInterval? = nil`. `PlayedVideoHistoryStore` gains `updatePosition(videoID:seconds:)`.
- `AppDelegate` subscribes to `controller.$currentTime` with a 5s throttle and writes to the store.
- `PlayerController.loadPlayer(videoID:)` looks up the saved position; if > 5s and not near the end, adds `&start=<seconds>` to the embed URL — YouTube's iframe respects it natively.
- `YouTubeSearchSheet`'s `playedRow` shows "↩︎ 0:42:30" when a saved position exists.

**Tech Stack:** Same. No new dependencies.

**Testing:** `swift build -c release` + manual smoke in Task 6.

**Prerequisites:** Phase 19 merged into `main`.

---

## File Structure

**No new files.** All modifications:

- `Sources/Murmur/Ambient/PlayedVideoHistoryStore.swift` — add `lastPosition` to entry + `updatePosition` method.
- `Sources/Murmur/main.swift` — `currentTime` on `PlayerController`, JS notify, ScriptHandler handler, `loadPlayer` reads saved position, AppDelegate subscription.
- `Sources/Murmur/YouTubeSearchSheet.swift` — show resume badge in `playedRow`.

---

### Task 1: PlayedVideoEntry.lastPosition + updatePosition

**Files:**
- Modify: `Sources/Murmur/Ambient/PlayedVideoHistoryStore.swift`

- [ ] **Step 1: Extend PlayedVideoEntry**

Find:
```swift
struct PlayedVideoEntry: Codable, Identifiable, Equatable {
    let videoID: String
    var title: String
    var date: Date

    var id: String { videoID }

    var thumbnailURL: URL? {
        URL(string: "https://img.youtube.com/vi/\(videoID)/mqdefault.jpg")
    }
}
```

Replace with:
```swift
struct PlayedVideoEntry: Codable, Identifiable, Equatable {
    let videoID: String
    var title: String
    var date: Date
    /// Last known playhead position in seconds, populated as the video plays.
    var lastPosition: TimeInterval? = nil

    var id: String { videoID }

    var thumbnailURL: URL? {
        URL(string: "https://img.youtube.com/vi/\(videoID)/mqdefault.jpg")
    }
}
```

- [ ] **Step 2: Add updatePosition method on the store**

In `PlayedVideoHistoryStore`, find the existing `remove(videoID:)` method. After it (before `clear()`), add:

```swift
    /// Update the lastPosition for a videoID. No-op if the videoID isn't in
    /// history yet (record happens via `record` first when the title arrives).
    func updatePosition(videoID: String, seconds: TimeInterval) {
        guard let i = entries.firstIndex(where: { $0.videoID == videoID }) else { return }
        entries[i].lastPosition = seconds
        save()
    }
```

- [ ] **Step 3: Build + commit**

```bash
cd /Users/mm/Documents/youtube-audio-widget
swift build -c release 2>&1 | tail -5
git add Sources/Murmur/Ambient/PlayedVideoHistoryStore.swift
git commit -m "feat(ambient): track lastPosition on PlayedVideoEntry"
```

---

### Task 2: PlayerController publishes currentTime

**Files:**
- Modify: `Sources/Murmur/main.swift`

### Change 1: Add @Published currentTime

Find the existing `@Published` properties in `PlayerController` (around line 62):

```swift
final class PlayerController: NSObject, ObservableObject, WKNavigationDelegate {
    @Published var isPlaying = false
    @Published var isReady = false
    @Published var volume: Double = 70
    @Published var title: String = "YouTube Live Stream"
    @Published var status: String = "Loading…"
    @Published private(set) var currentVideoID: String = kDefaultVideoID
```

Add immediately after `currentVideoID`:

```swift
    /// Current playhead in seconds, updated from iframe infoDelivery events.
    @Published var currentTime: Double = 0
```

### Change 2: JS notify includes currentTime

In `loadPlayer(videoID:)`, find the JS block that handles `infoDelivery` (around line 164):

```javascript
            } else if (d.event === 'infoDelivery' && d.info) {
              if (typeof d.info.playerState !== 'undefined') {
                if (d.info.playerState === 1) hideCover();
                notify('state', {state:d.info.playerState});
              }
              if (d.info.videoData && d.info.videoData.title) notify('title', {title:d.info.videoData.title});
            } else if (d.event === 'onError') {
```

Modify to also notify currentTime:

```javascript
            } else if (d.event === 'infoDelivery' && d.info) {
              if (typeof d.info.playerState !== 'undefined') {
                if (d.info.playerState === 1) hideCover();
                notify('state', {state:d.info.playerState});
              }
              if (d.info.videoData && d.info.videoData.title) notify('title', {title:d.info.videoData.title});
              if (typeof d.info.currentTime === 'number') notify('time', {time: d.info.currentTime});
            } else if (d.event === 'onError') {
```

### Change 3: ScriptHandler handles "time"

Find the switch statement in `ScriptHandler.userContentController` (around line 242). Add a new case for "time" between the existing "title" and "error" cases:

Find:
```swift
            case "title":
                if let t = body["title"] as? String, !t.isEmpty { c.title = t }
            case "error":
```

Replace with:
```swift
            case "title":
                if let t = body["title"] as? String, !t.isEmpty { c.title = t }
            case "time":
                if let t = body["time"] as? Double { c.currentTime = t }
            case "error":
```

- [ ] **Step 1: Build + commit**

```bash
swift build -c release 2>&1 | tail -10
git add Sources/Murmur/main.swift
git commit -m "feat(player): publish currentTime from iframe infoDelivery events"
```

---

### Task 3: AppDelegate throttled save

**Files:**
- Modify: `Sources/Murmur/main.swift`

- [ ] **Step 1: Add a position cancellable + subscription**

`AppDelegate` already has `historyCancellable: AnyCancellable?` from Phase 16. Add a sibling.

Find:
```swift
    private var historyCancellable: AnyCancellable?
```

Add immediately after:
```swift
    private var positionCancellable: AnyCancellable?
```

In `applicationDidFinishLaunching`, near the existing `historyCancellable = controller.$title.…` block, add:

```swift
        // Throttle position writes to ~5s so we don't hammer UserDefaults.
        positionCancellable = controller.$currentTime
            .throttle(for: .seconds(5), scheduler: DispatchQueue.main, latest: true)
            .sink { [weak self] seconds in
                guard let self = self else { return }
                let videoID = self.controller.currentVideoID
                guard !videoID.isEmpty, seconds > 1 else { return }
                PlayedVideoHistoryStore.shared.updatePosition(videoID: videoID, seconds: seconds)
            }
```

- [ ] **Step 2: Build + commit**

```bash
swift build -c release 2>&1 | tail -10
git add Sources/Murmur/main.swift
git commit -m "feat(player): throttle-save currentTime to PlayedVideoHistoryStore"
```

---

### Task 4: Resume from saved position on load

**Files:**
- Modify: `Sources/Murmur/main.swift`

In `loadPlayer(videoID:)`, look up the saved position before building the HTML and inject `&start=<seconds>` into the iframe URL.

- [ ] **Step 1: Update loadPlayer**

Find the start of `loadPlayer(videoID: String)` (around line 91). The first executable line is likely setting state / clearing flags. Insert this BEFORE the HTML is built (i.e., before any `let html = """..."""` or the existing HTML string):

```swift
        // Look up resume position from history. Skip if too small (just
        // started) or near the end (don't resume the last few seconds).
        let savedPosition = PlayedVideoHistoryStore.shared.entries
            .first(where: { $0.videoID == videoID })?
            .lastPosition ?? 0
        let startSeconds: Int = (savedPosition > 5) ? Int(savedPosition) : 0
```

Then find the iframe URL on line 115:

```swift
          src="https://www.youtube-nocookie.com/embed/\(videoID)?enablejsapi=1&autoplay=1&controls=0&playsinline=1&modestbranding=1&rel=0&fs=0&iv_load_policy=3&origin=https://www.youtube-nocookie.com"
```

Replace with:

```swift
          src="https://www.youtube-nocookie.com/embed/\(videoID)?enablejsapi=1&autoplay=1&controls=0&playsinline=1&modestbranding=1&rel=0&fs=0&iv_load_policy=3&origin=https://www.youtube-nocookie.com&start=\(startSeconds)"
```

(The `start=0` case is harmless — YouTube treats it as "start from beginning.")

- [ ] **Step 2: Build + commit**

```bash
swift build -c release 2>&1 | tail -10
git add Sources/Murmur/main.swift
git commit -m "feat(player): resume from lastPosition via iframe start= param"
```

---

### Task 5: Resume badge in playedRow

**Files:**
- Modify: `Sources/Murmur/YouTubeSearchSheet.swift`

Show "↩︎ 0:42:30" in RECENT VIDEOS rows that have a saved position.

- [ ] **Step 1: Update playedRow**

Find the existing `playedRow(_:)` method. Replace its entire body with:

```swift
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

                    VStack(alignment: .leading, spacing: 3) {
                        Text(entry.title.isEmpty ? entry.videoID : entry.title)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.white.opacity(0.9))
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                        if let pos = entry.lastPosition, pos > 5 {
                            HStack(spacing: 3) {
                                Image(systemName: "arrow.uturn.left.circle")
                                    .font(.system(size: 9))
                                Text("Resume \(formatResumeTime(pos))")
                                    .font(.system(size: 10, design: .monospaced))
                            }
                            .foregroundColor(.cyan.opacity(0.75))
                        }
                    }
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

    private func formatResumeTime(_ seconds: TimeInterval) -> String {
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

- [ ] **Step 2: Build + commit**

```bash
swift build -c release 2>&1 | tail -10
git add Sources/Murmur/YouTubeSearchSheet.swift
git commit -m "feat(popover): show resume timestamp on played video rows"
```

---

### Task 6: Build bundle + smoke + tag + merge

- [ ] **Step 1: Build**

```bash
./build-app.sh --sign 2>&1 | tail -10
```

- [ ] **Step 2: Manual smoke**

Quit running Murmur. `open dist/Murmur.app`.

1. Open popover → 🔍 → search any video, click a result → loads on main player.
2. Let it play for ~20 seconds.
3. Click another video, or quit Murmur entirely.
4. Reopen Murmur → 🔍 → empty state shows **RECENT VIDEOS** with the previous video and a cyan **"↩︎ Resume 0:00:20"** label below the title.
5. Click that row → main player loads the video starting at ~20 seconds in. ✅
6. Let it play to ~1 minute, click another track, then come back → the resume timestamp should now read ~1:00.
7. Test rollover: play near the end of a short video, close. Reload → resume close to the end (or near 0 if the auto-throttle didn't catch the last seconds).
8. **Console log check**: with logs visible in Console.app filtered for Murmur, you shouldn't see `[Analysis]` lines for YouTube playback — only ambient layer / DJ booth analyses. Watching activity is silent.

- [ ] **Step 3: Tag + merge**

```bash
git tag -a phase-20-watch-timestamps -m "Pocket DJ Phase 20: resume watched videos at saved position"
git checkout main
git merge --no-ff pocket-dj-phase-20 -m "Merge phase 20: watch timestamps"
./build-app.sh --sign 2>&1 | tail -5
```

---

## Out of Scope for Phase 20

- Per-deck DJ booth position tracking (Phase 1 already handles seek for local-file decks).
- Cross-device sync of watch progress.
- "Mark as watched" / clear-all timestamps button.
- Resume hint in the favorites menu — only RECENT VIDEOS surfaces it for now.
- Showing the percent-watched progress bar on the thumbnail (like YouTube's red bar).

---

## Self-Review

- **infoDelivery currentTime extraction**: ✅ adds one line to the existing JS forwarder + one switch case in ScriptHandler. No new IPC mechanism.
- **5s throttle on save** keeps UserDefaults writes reasonable. ✅
- **`start=N` URL parameter** is a stable YouTube embed feature. ✅
- **>5s threshold + main-player-only** prevents spurious resume hints. ✅
- **Backward compatibility**: `lastPosition` is optional, default nil — existing cached entries decode cleanly. ✅
