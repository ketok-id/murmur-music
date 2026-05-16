# Pocket DJ Phase 6 — Recordings Library

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give the user an in-app way to see, play, and delete their bounced master recordings — closing the loop on Phase 1's master-record feature. Today recordings land in `~/Library/Application Support/Murmur/Recordings/` and the user has to dig through Finder to find them.

**Architecture:** A new `Recording` model represents one bounced WAV file (URL, timestamp, duration, file size). `RecordingsStore` scans the recordings directory and publishes a sorted list. `RecordingPlayer` is a tiny `AVAudioPlayer` wrapper for previewing one recording at a time. `RecordingsView` is a SwiftUI list with play/pause/delete per row. `RecordingsWindowController` hosts it in a standalone window opened from the booth.

**Tech Stack:** `AVAudioPlayer` (already available via AVFoundation), SwiftUI list, `FileManager` for directory scanning + deletion. No new dependencies.

**Testing:** `swift build -c release` + manual smoke in Task 7. No Co-Authored-By trailer in subagent commits.

**Prerequisites:** Phase 5 merged into `main`. The master REC button in the booth already writes WAVs to `~/Library/Application Support/Murmur/Recordings/<timestamp>.wav`.

---

## File Structure

**New files:**

```
Sources/Murmur/Recordings/
  Recording.swift                One Recording: url, date, duration, sizeBytes
  RecordingsStore.swift          Scans dir, publishes [Recording], delete()
  RecordingPlayer.swift          AVAudioPlayer wrapper with @Published playback state
Sources/Murmur/Booth/
  RecordingsView.swift           SwiftUI list of recordings with row controls
  RecordingsWindowController.swift   NSWindow hosting RecordingsView
```

**Modified files:**

- `Sources/Murmur/Booth/MasterControlsView.swift` — add a small "📁" button under the REC button that opens the recordings window.
- `Sources/Murmur/main.swift` — instantiate `RecordingsWindowController` in `AppDelegate`; expose it via a shared environment object (`RecordingsLauncher`) the same way `BoothLauncher` works.

---

### Task 1: Recording model

**Files:**
- Create: `Sources/Murmur/Recordings/Recording.swift`

- [ ] **Step 1: Implement**

```swift
import AVFoundation
import Foundation

/// One bounced master recording on disk.
struct Recording: Identifiable, Equatable {
    /// URL on disk.
    let url: URL
    /// Modification date of the file.
    let date: Date
    /// Duration in seconds (read from the WAV via AVAudioFile).
    let duration: Double
    /// File size in bytes.
    let sizeBytes: Int64

    /// `id` for SwiftUI list iteration.
    var id: URL { url }

    /// "23.4 MB" or "812 KB".
    var sizeLabel: String {
        ByteCountFormatter().string(fromByteCount: sizeBytes)
    }

    /// "2:34" formatted duration.
    var durationLabel: String {
        let s = Int(duration)
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    /// "May 16, 2026 — 11:42 AM"
    var dateLabel: String {
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .short
        return df.string(from: date)
    }
}
```

- [ ] **Step 2: Build and commit**

```bash
cd /Users/mm/Documents/youtube-audio-widget
swift build -c release 2>&1 | tail -5
git add Sources/Murmur/Recordings/Recording.swift
git commit -m "feat(recordings): add Recording model"
```

---

### Task 2: RecordingsStore

**Files:**
- Create: `Sources/Murmur/Recordings/RecordingsStore.swift`

- [ ] **Step 1: Implement**

```swift
import AVFoundation
import Combine
import Foundation

/// Lists and manages bounced recording files on disk.
///
/// Scans `MasterRecorder.recordingsDirectory` on init and on demand, publishes
/// the result as a sorted (newest-first) array of `Recording`s. Supports
/// delete via `FileManager.removeItem`.
final class RecordingsStore: ObservableObject {
    @Published private(set) var recordings: [Recording] = []

    init() {
        refresh()
    }

    /// Re-scan the recordings directory.
    func refresh() {
        let dir = MasterRecorder.recordingsDirectory
        let fm = FileManager.default
        guard let urls = try? fm.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            recordings = []
            return
        }

        var list: [Recording] = []
        for url in urls where url.pathExtension.lowercased() == "wav" {
            let attrs = (try? url.resourceValues(forKeys: [
                .contentModificationDateKey, .fileSizeKey,
            ])) ?? URLResourceValues()
            let date = attrs.contentModificationDate ?? Date.distantPast
            let size = Int64(attrs.fileSize ?? 0)
            let duration = (try? AVAudioFile(forReading: url)).map { f in
                Double(f.length) / f.processingFormat.sampleRate
            } ?? 0
            list.append(Recording(url: url, date: date, duration: duration, sizeBytes: size))
        }
        list.sort { $0.date > $1.date }
        recordings = list
    }

    /// Delete one recording from disk and refresh the list.
    func delete(_ recording: Recording) {
        try? FileManager.default.removeItem(at: recording.url)
        refresh()
    }
}
```

- [ ] **Step 2: Build and commit**

```bash
swift build -c release 2>&1 | tail -5
git add Sources/Murmur/Recordings/RecordingsStore.swift
git commit -m "feat(recordings): add RecordingsStore (scan + delete)"
```

---

### Task 3: RecordingPlayer

**Files:**
- Create: `Sources/Murmur/Recordings/RecordingPlayer.swift`

- [ ] **Step 1: Implement**

```swift
import AVFoundation
import Combine
import Foundation

/// Single-source playback of one Recording. Used by `RecordingsView` to
/// audition a bounced WAV without going through the deck pipeline.
///
/// Uses `AVAudioPlayer` (high-level, single-file) rather than the deck's
/// `AVAudioEngine` graph — this is preview audio, not mix audio.
final class RecordingPlayer: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published private(set) var nowPlayingURL: URL? = nil
    @Published private(set) var currentTime: Double = 0
    @Published private(set) var duration: Double = 0

    private var player: AVAudioPlayer?
    private var timer: Timer?

    /// True if a recording is currently playing.
    var isPlaying: Bool { player?.isPlaying ?? false }

    deinit {
        timer?.invalidate()
    }

    /// Play (or resume) the given recording. If a different recording is
    /// currently playing, it's stopped first.
    func play(_ recording: Recording) {
        if nowPlayingURL == recording.url, let p = player {
            if p.isPlaying { p.pause() } else { p.play() }
            // No-op state mutation triggers Published change for buttons.
            nowPlayingURL = nowPlayingURL
            return
        }
        stop()
        do {
            let p = try AVAudioPlayer(contentsOf: recording.url)
            p.delegate = self
            p.prepareToPlay()
            p.play()
            self.player = p
            self.nowPlayingURL = recording.url
            self.duration = p.duration
            startTimer()
        } catch {
            NSLog("[RecordingPlayer] failed to play \(recording.url.lastPathComponent): \(error)")
        }
    }

    /// Stop and release the player.
    func stop() {
        player?.stop()
        player = nil
        nowPlayingURL = nil
        currentTime = 0
        duration = 0
        timer?.invalidate()
        timer = nil
    }

    /// True if `recording` is the one currently loaded (whether playing or paused).
    func isLoaded(_ recording: Recording) -> Bool {
        nowPlayingURL == recording.url
    }

    /// True if `recording` is currently audible (loaded + playing).
    func isPlaying(_ recording: Recording) -> Bool {
        nowPlayingURL == recording.url && (player?.isPlaying ?? false)
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self = self, let p = self.player else { return }
            self.currentTime = p.currentTime
        }
    }

    // MARK: - AVAudioPlayerDelegate

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        stop()
    }
}
```

- [ ] **Step 2: Build and commit**

```bash
swift build -c release 2>&1 | tail -5
git add Sources/Murmur/Recordings/RecordingPlayer.swift
git commit -m "feat(recordings): add RecordingPlayer for in-app preview"
```

---

### Task 4: RecordingsView

**Files:**
- Create: `Sources/Murmur/Booth/RecordingsView.swift`

- [ ] **Step 1: Implement**

```swift
import SwiftUI

/// Lists recorded WAV files with per-row play/pause + delete.
struct RecordingsView: View {
    @ObservedObject var store: RecordingsStore
    @ObservedObject var player: RecordingPlayer

    @State private var deleteCandidate: Recording? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().background(Color.white.opacity(0.06))
            if store.recordings.isEmpty {
                emptyState
            } else {
                List {
                    ForEach(store.recordings) { rec in
                        row(rec)
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .frame(minWidth: 460, minHeight: 360)
        .background(Color(white: 0.04))
        .alert(item: $deleteCandidate) { rec in
            Alert(
                title: Text("Delete recording?"),
                message: Text("\(rec.url.lastPathComponent) — \(rec.sizeLabel)"),
                primaryButton: .destructive(Text("Delete")) {
                    if player.isLoaded(rec) { player.stop() }
                    store.delete(rec)
                },
                secondaryButton: .cancel()
            )
        }
    }

    private var header: some View {
        HStack {
            Text("Recordings")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)
            Spacer()
            Text("\(store.recordings.count) bounce\(store.recordings.count == 1 ? "" : "s")")
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.white.opacity(0.5))
            Button(action: { store.refresh() }) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.55))
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "waveform")
                .font(.system(size: 32))
                .foregroundColor(.white.opacity(0.2))
            Text("No recordings yet")
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(.white.opacity(0.4))
            Text("Hit REC in the booth to bounce a mix.")
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.3))
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func row(_ rec: Recording) -> some View {
        HStack(spacing: 10) {
            Button(action: { player.play(rec) }) {
                Image(systemName: player.isPlaying(rec) ? "pause.fill" : "play.fill")
                    .font(.system(size: 13))
                    .foregroundColor(player.isLoaded(rec) ? .cyan : .white.opacity(0.65))
                    .frame(width: 28, height: 28)
                    .background(player.isLoaded(rec) ? Color.cyan.opacity(0.12) : Color.white.opacity(0.04))
                    .cornerRadius(4)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                Text(rec.url.deletingPathExtension().lastPathComponent)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.white.opacity(0.9))
                    .lineLimit(1)
                HStack(spacing: 8) {
                    Text(rec.dateLabel)
                    Text("·")
                    Text(rec.durationLabel)
                    Text("·")
                    Text(rec.sizeLabel)
                }
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.white.opacity(0.45))
            }
            Spacer()
            Button(action: { deleteCandidate = rec }) {
                Image(systemName: "trash")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.4))
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
    }
}
```

- [ ] **Step 2: Build and commit**

```bash
swift build -c release 2>&1 | tail -5
git add Sources/Murmur/Booth/RecordingsView.swift
git commit -m "feat(booth): add RecordingsView (list + per-row controls)"
```

---

### Task 5: RecordingsWindowController

**Files:**
- Create: `Sources/Murmur/Booth/RecordingsWindowController.swift`

- [ ] **Step 1: Implement**

```swift
import AppKit
import SwiftUI

/// Standalone NSWindow hosting `RecordingsView`. Kept alive for the life of
/// the app — close button hides it rather than terminating.
final class RecordingsWindowController: NSObject, NSWindowDelegate {
    private let window: NSWindow
    let store: RecordingsStore
    let player: RecordingPlayer

    init() {
        self.store = RecordingsStore()
        self.player = RecordingPlayer()
        let host = NSHostingController(
            rootView: RecordingsView(store: store, player: player)
        )
        let win = NSWindow(contentViewController: host)
        win.title = "Murmur Recordings"
        win.styleMask = [.titled, .closable, .resizable, .miniaturizable]
        win.setContentSize(NSSize(width: 540, height: 440))
        win.center()
        win.isReleasedWhenClosed = false
        self.window = win
        super.init()
        self.window.delegate = self
    }

    func show() {
        store.refresh()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func hide() {
        player.stop()
        window.orderOut(nil)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        hide()
        return false
    }
}
```

- [ ] **Step 2: Build and commit**

```bash
swift build -c release 2>&1 | tail -5
git add Sources/Murmur/Booth/RecordingsWindowController.swift
git commit -m "feat(booth): add RecordingsWindowController"
```

---

### Task 6: Wire into AppDelegate + Master Controls

**Files:**
- Modify: `Sources/Murmur/main.swift`
- Modify: `Sources/Murmur/Booth/MasterControlsView.swift`

- [ ] **Step 1: Instantiate RecordingsWindowController in AppDelegate**

Open `Sources/Murmur/main.swift`. Find the `AppDelegate` property block:

```swift
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    var statusItem: NSStatusItem!
    var popover: NSPopover!
    let controller = PlayerController()
    let favorites = FavoritesStore()
    var videoWindow: VideoWindowController!
    let mixer = MixerEngine()
    var booth: BoothWindowController!
```

Add after `var booth:`:

```swift
    var recordings: RecordingsWindowController!
```

Find this block in `applicationDidFinishLaunching`:

```swift
        // Booth window — kept alive for the life of the app; hidden by default.
        booth = BoothWindowController(mixer: mixer)
```

Add immediately after it:

```swift
        recordings = RecordingsWindowController()
```

Find this block where the popover content view is set:

```swift
        popover.contentViewController = NSHostingController(
            rootView: ContentView()
                .environmentObject(controller)
                .environmentObject(favorites)
                .environmentObject(videoWindow)
                .environmentObject(mixer)
                .environmentObject(BoothLauncher(booth: booth))
        )
```

Replace with:

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

Then at the bottom of `main.swift`, where `BoothLauncher` is defined, add this immediately above the `// MARK: - Boot` line:

```swift
// MARK: - Recordings launcher (SwiftUI bridge)
final class RecordingsLauncher: ObservableObject {
    let controller: RecordingsWindowController
    init(controller: RecordingsWindowController) { self.controller = controller }
    func show() { controller.show() }
}

```

- [ ] **Step 2: Add Recordings button to MasterControlsView**

Open `Sources/Murmur/Booth/MasterControlsView.swift`. The existing structure has a vstack with MASTER label, master vol knob, REC button. Add an `@EnvironmentObject` near the top of the struct:

Find:
```swift
struct MasterControlsView: View {
    @ObservedObject var mixer: MixerEngine
```

Add immediately below:
```swift
    @EnvironmentObject var recordingsLauncher: RecordingsLauncher
```

Then find the REC button's enclosing `VStack`. After the REC `Button { ... }.buttonStyle(.plain)` block, add an additional button — the LIST button:

```swift

            Button(action: { recordingsLauncher.show() }) {
                HStack(spacing: 4) {
                    Image(systemName: "list.bullet")
                        .font(.system(size: 9))
                    Text("LIST")
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .tracking(1)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
                .foregroundColor(.white.opacity(0.55))
                .background(Color.white.opacity(0.04))
                .cornerRadius(4)
            }
            .buttonStyle(.plain)
```

- [ ] **Step 3: Build and commit**

```bash
swift build -c release 2>&1 | tail -10
git add Sources/Murmur/main.swift Sources/Murmur/Booth/MasterControlsView.swift
git commit -m "feat(booth): wire recordings window into AppDelegate + master strip"
```

---

### Task 7: Build bundle + smoke + tag + merge

- [ ] **Step 1: Build the .app bundle**

```bash
./build-app.sh --sign 2>&1 | tail -10
```

- [ ] **Step 2: Manual smoke**

`open dist/Murmur.app`. Open the booth.

1. **First open with no recordings:** click the small **LIST** button under the REC button. A new "Murmur Recordings" window opens with an empty state ("No recordings yet" + waveform icon).
2. Close the recordings window. Back in the booth, click **REC** on a track that's playing. Let it record 10 seconds. Click **REC** again to stop.
3. Click **LIST** again — the new recording shows up at the top of the list with its filename, date, duration ("0:10"), and file size.
4. Click the play icon on the row. The recording plays back in the recordings window (separate from the booth audio — uses `AVAudioPlayer` not `AVAudioEngine`). Pause icon appears on the row. Click pause → playback pauses. Click play → resumes.
5. Click the **trash** icon → confirmation alert. Confirm → recording disappears AND the WAV is deleted from disk:
   ```bash
   ls "$HOME/Library/Application Support/Murmur/Recordings/"
   ```
   The file should be gone.
6. Bounce 2–3 more recordings. They appear newest-first.
7. **Click the refresh button** (top right of recordings window) — re-scans the directory. If you add a WAV via Finder while the window is open, refresh shows it.
8. Quit + re-open the app, open recordings window → all recordings still there. Persistence is just the filesystem; no UserDefaults needed.
9. Close the recordings window via its red close button → window hides (doesn't terminate the app). Any playing recording stops. Re-open via LIST → state intact.

- [ ] **Step 3: Tag**

```bash
git tag -a phase-6-recordings -m "Pocket DJ Phase 6: in-app recordings library"
```

- [ ] **Step 4: Merge to main**

```bash
git checkout main
git merge --no-ff pocket-dj-phase-6 -m "Merge phase 6: recordings library"
./build-app.sh --sign 2>&1 | tail -5
```

---

## Out of Scope for Phase 6

- Reveal-in-Finder button (handy but trivial to add later)
- Rename recordings inline
- Export to other formats (M4A, MP3)
- Multi-select + bulk delete
- Sort options other than newest-first

---

## Self-Review

- **§5.7 Recording the master:** Phase 1 implemented the bounce; Phase 6 closes the loop with a library UI. ✅
- **Empty state:** explicitly handled. ✅
- **File persistence:** filesystem-only, no UserDefaults — consistent with Phase 1's design choice. ✅
- **Hide-on-close pattern:** same as `BoothWindowController` and `VideoWindowController`. ✅
- **No new dependencies:** `AVAudioPlayer` is part of AVFoundation. ✅

No spec gaps for the in-scope set. Type signatures consistent: `Recording.url/date/duration/sizeBytes`, `RecordingsStore.recordings/refresh/delete`, `RecordingPlayer.play/stop/isLoaded/isPlaying`, `RecordingsLauncher.show`.
