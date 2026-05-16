# Pocket DJ Phase 2b — Performance Controls

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the performance ergonomics that turn beatmatched mixing into actual DJing: 8 hot-cue pads per deck (set/jump/delete, persisted per track), beat-quantized loops (in/out, halve/double, save), and a phase meter showing master-vs-slave alignment drift in real time.

**Architecture:** Hot cues are persisted in `LibraryIndex` per track path (extend `TrackMetadata`); `DeckController` gains `setHotCue`/`jumpHotCue`/`deleteHotCue` methods that read/write through to the file's metadata. Loops use `AVAudioPlayerNode.scheduleSegment` with beat-quantized boundaries, re-scheduled each loop pass via the completion handler so playback is seamless. The phase meter samples `currentTimeSeconds` from both decks at ~30Hz, derives each deck's phase position within its beat, and publishes a `phaseOffset` from `MixerEngine` that a small SwiftUI needle binds to.

**Tech Stack:** Same as Phase 2a — Swift 5.9+, AVFoundation, SwiftUI. No new dependencies.

**On testing:** Same as prior phases — `CLAUDE.md` rules out `swift test`. Verify with `swift build -c release` + the final manual smoke in Task 12.

**Prerequisites:** Phase 2a complete on the same branch parent. Booth window already shows BPM, waveform, beat grid, tempo slider, sync controls.

---

## File Structure

**New files:**

```
Sources/Murmur/Decks/
  HotCue.swift              Codable model: id (0-7), name, seconds, colorHex
  LoopState.swift           Codable + observable model: inSeconds, outSeconds, isActive
  LoopEngine.swift          Per-deck loop scheduling using AVAudioPlayerNode.scheduleSegment
  PhaseAnalyzer.swift       Computes master/slave phase offset; runs at ~30Hz
Sources/Murmur/Booth/
  HotCuePadsView.swift      8 colored pads in a 4x2 or 1x8 grid
  LoopControlsView.swift    IN, OUT, ½, ×2, ON/OFF buttons
  CueAndLoopOverlay.swift   Draws hot-cue flags + loop region on top of the waveform
  PhaseMeterView.swift      Horizontal needle drifting left/right of center
```

**Modified files:**

- `Sources/Murmur/Analysis/TrackMetadata.swift` — add `hotCues: [HotCue]` (default empty).
- `Sources/Murmur/Analysis/LibraryIndex.swift` — add `setHotCues(_:forPath:)`.
- `Sources/Murmur/Decks/DeckState.swift` — add `hotCues`, `loop` (LoopState observable).
- `Sources/Murmur/Decks/DeckController.swift` — `setHotCue`, `jumpHotCue`, `deleteHotCue`; integrate `LoopEngine`; wire loop scheduling on track load.
- `Sources/Murmur/Decks/MixerEngine.swift` — own `PhaseAnalyzer`; expose `@Published phaseOffset: Double` (seconds).
- `Sources/Murmur/Booth/DeckView.swift` — add `HotCuePadsView` + `LoopControlsView` rows; pass cue actions.
- `Sources/Murmur/Booth/BoothView.swift` — insert `PhaseMeterView` above the crossfader.

---

### Task 1: HotCue model + TrackMetadata extension

**Files:**
- Create: `Sources/Murmur/Decks/HotCue.swift`
- Modify: `Sources/Murmur/Analysis/TrackMetadata.swift`
- Modify: `Sources/Murmur/Analysis/LibraryIndex.swift`

- [ ] **Step 1: Create `Sources/Murmur/Decks/HotCue.swift`**

```swift
import Foundation

/// One hot-cue: a time offset on a track plus a color tag.
///
/// `colorHex` is a CSS-style 6-char hex string (e.g. "ff6b6b"). Stored as
/// hex rather than RGBA floats so the JSON cache stays human-readable.
struct HotCue: Codable, Equatable, Identifiable {
    /// Pad index 0…7.
    let id: Int
    /// Seconds offset into the track.
    var seconds: Double
    /// CSS-style hex (no leading #).
    var colorHex: String

    /// Default palette indexed by pad id.
    static let defaultPalette: [String] = [
        "ff6b6b", "fbbf77", "ffe066", "6ee7ff",
        "a78bfa", "ff7ab6", "5eead4", "f97316",
    ]

    static func defaultColor(for id: Int) -> String {
        defaultPalette[id % defaultPalette.count]
    }
}
```

- [ ] **Step 2: Modify `Sources/Murmur/Analysis/TrackMetadata.swift`**

Find the struct definition:

```swift
struct TrackMetadata: Codable, Equatable {
    let bpm: Double
    let duration: Double
    var firstBeat: Double
    let peaksPath: String
}
```

Replace with (adds `hotCues` with default empty array; default is required so existing cached JSON without the field still decodes):

```swift
struct TrackMetadata: Codable, Equatable {
    let bpm: Double
    let duration: Double
    var firstBeat: Double
    let peaksPath: String
    var hotCues: [HotCue] = []
}
```

- [ ] **Step 3: Modify `Sources/Murmur/Analysis/LibraryIndex.swift`**

Find the `setFirstBeat` method. Add this method immediately below it:

```swift
    /// Update only the hotCues array for a track.
    func setHotCues(_ hotCues: [HotCue], forPath path: String) {
        queue.sync {
            guard var existing = tracks[path] else { return }
            existing.hotCues = hotCues
            tracks[path] = existing
            save()
        }
    }
```

- [ ] **Step 4: Verify build**

```bash
cd /Users/mm/Documents/youtube-audio-widget
swift build -c release 2>&1 | tail -5
```

- [ ] **Step 5: Commit**

```bash
git add Sources/Murmur/Decks/HotCue.swift Sources/Murmur/Analysis/TrackMetadata.swift Sources/Murmur/Analysis/LibraryIndex.swift
git commit -m "feat(analysis): add HotCue model + TrackMetadata.hotCues field"
```

---

### Task 2: LoopState model

**Files:**
- Create: `Sources/Murmur/Decks/LoopState.swift`

- [ ] **Step 1: Create `LoopState.swift`**

```swift
import Combine
import Foundation

/// Per-deck loop state. Observed by the UI; mutated by `DeckController`.
///
/// A loop is "armed" when both `inSeconds` and `outSeconds` are set.
/// `isActive` controls whether playback actually loops.
final class LoopState: ObservableObject {
    @Published var inSeconds: Double? = nil
    @Published var outSeconds: Double? = nil
    @Published var isActive: Bool = false

    /// True when both endpoints are set.
    var isArmed: Bool { inSeconds != nil && outSeconds != nil }

    /// Loop length in seconds, or nil if not fully set.
    var length: Double? {
        guard let i = inSeconds, let o = outSeconds, o > i else { return nil }
        return o - i
    }

    func clear() {
        inSeconds = nil
        outSeconds = nil
        isActive = false
    }
}
```

- [ ] **Step 2: Verify build**

```bash
swift build -c release 2>&1 | tail -5
```

- [ ] **Step 3: Commit**

```bash
git add Sources/Murmur/Decks/LoopState.swift
git commit -m "feat(decks): add observable LoopState"
```

---

### Task 3: LoopEngine — seamless looping via scheduleSegment

**Files:**
- Create: `Sources/Murmur/Decks/LoopEngine.swift`

This is the trickiest task. AVAudioPlayerNode loops via `scheduleSegment` with a completion callback that re-schedules the same segment. The completion runs on a background thread, so we marshal back to the player's own scheduling.

- [ ] **Step 1: Create `LoopEngine.swift`**

```swift
import AVFoundation
import Foundation

/// Drives seamless looping on an `AVAudioPlayerNode` by repeatedly scheduling
/// the same beat-quantized segment.
///
/// When `engage(player:file:inSeconds:outSeconds:)` is called, the engine stops
/// the player, reschedules a segment for the loop region, and registers a
/// completion callback that immediately re-queues the same segment so playback
/// continues into the next loop iteration with no audible gap.
///
/// Call `disengage()` to stop looping; the player will play out the current
/// loop iteration to completion (no clicks) and then schedule the rest of the
/// file from the loop's out-point onward.
final class LoopEngine {
    private weak var player: AVAudioPlayerNode?
    private var file: AVAudioFile?
    private var inFrame: AVAudioFramePosition = 0
    private var outFrame: AVAudioFramePosition = 0
    private var active: Bool = false

    /// True when looping is currently engaged.
    var isEngaged: Bool { active }

    /// Engage a loop on the given player. Stops current playback, schedules
    /// the loop segment, and arranges seamless re-scheduling.
    func engage(player: AVAudioPlayerNode, file: AVAudioFile, inSeconds: Double, outSeconds: Double) {
        let sr = file.processingFormat.sampleRate
        let inFrame = AVAudioFramePosition(max(0, inSeconds) * sr)
        let outFrame = AVAudioFramePosition(min(Double(file.length), outSeconds * sr))
        guard outFrame > inFrame else { return }

        self.player = player
        self.file = file
        self.inFrame = inFrame
        self.outFrame = outFrame
        self.active = true

        let wasPlaying = player.isPlaying
        player.stop()
        scheduleLoopSegment()
        if wasPlaying { player.play() }
    }

    /// Stop looping. Subsequent playback continues from the loop out-point
    /// to the end of the file.
    func disengage() {
        guard active, let player = player, let file = file else {
            active = false
            return
        }
        active = false
        // Schedule the rest of the file from outFrame onwards as the next
        // segment after the current loop completes naturally.
        let remaining = file.length - outFrame
        guard remaining > 0 else { return }
        player.scheduleSegment(file,
                               startingFrame: outFrame,
                               frameCount: AVAudioFrameCount(remaining),
                               at: nil,
                               completionHandler: nil)
    }

    private func scheduleLoopSegment() {
        guard let player = player, let file = file, active else { return }
        let frameCount = AVAudioFrameCount(outFrame - inFrame)
        player.scheduleSegment(file,
                               startingFrame: inFrame,
                               frameCount: frameCount,
                               at: nil) { [weak self] in
            // AVAudioPlayerNode runs completion on a background queue.
            // We only re-schedule if still active; otherwise disengage has
            // already queued the post-loop continuation.
            guard let self = self, self.active else { return }
            self.scheduleLoopSegment()
        }
    }
}
```

- [ ] **Step 2: Verify build**

```bash
swift build -c release 2>&1 | tail -5
```

- [ ] **Step 3: Commit**

```bash
git add Sources/Murmur/Decks/LoopEngine.swift
git commit -m "feat(decks): add LoopEngine for seamless beat-quantized loops"
```

---

### Task 4: DeckState additions for hot cues + loop

**Files:**
- Modify: `Sources/Murmur/Decks/DeckState.swift`

- [ ] **Step 1: Add the new properties**

Open `Sources/Murmur/Decks/DeckState.swift`. After the Phase 2a `@Published var isMaster: Bool = false` line, add:

```swift

    // ── Phase 2b: performance controls ────────────────────────────────────

    /// Hot cues for the currently loaded track.
    @Published var hotCues: [HotCue] = []
    /// Observable loop state.
    let loop = LoopState()
```

- [ ] **Step 2: Verify build**

```bash
swift build -c release 2>&1 | tail -5
```

- [ ] **Step 3: Commit**

```bash
git add Sources/Murmur/Decks/DeckState.swift
git commit -m "feat(decks): add Phase 2b state — hotCues + loop"
```

---

### Task 5: DeckController — hot cue methods + loop integration

**Files:**
- Modify: `Sources/Murmur/Decks/DeckController.swift`
- Modify: `Sources/Murmur/Audio/LocalFilePlayer.swift` (small additions)

- [ ] **Step 1: Expose `file` and `player` on `LocalFilePlayer`**

`LoopEngine` needs the underlying `AVAudioPlayerNode` and `AVAudioFile`. Open `Sources/Murmur/Audio/LocalFilePlayer.swift`.

Find:

```swift
    private let engine: AVAudioEngine
    private let player = AVAudioPlayerNode()
    private var file: AVAudioFile?
    private(set) var loadedURL: URL?
```

Change `player` and `file` to `private(set)`:

```swift
    private let engine: AVAudioEngine
    private(set) var player = AVAudioPlayerNode()
    private(set) var file: AVAudioFile?
    private(set) var loadedURL: URL?
```

- [ ] **Step 2: Add hot-cue + loop methods to `DeckController`**

Open `Sources/Murmur/Decks/DeckController.swift`. Add a new property at the top of the class, after `let player: LocalFilePlayer`:

```swift
    let loopEngine = LoopEngine()
```

Then add these methods at the bottom of the class, before the closing `}`:

```swift
    // MARK: - Hot cues

    /// Set the hot cue at pad index `id` to the current playhead position.
    func setHotCue(id: Int) {
        guard state.isLoaded else { return }
        let seconds = state.currentTimeSeconds
        var cues = state.hotCues
        let cue = HotCue(id: id, seconds: seconds, colorHex: HotCue.defaultColor(for: id))
        if let idx = cues.firstIndex(where: { $0.id == id }) {
            cues[idx] = cue
        } else {
            cues.append(cue)
            cues.sort { $0.id < $1.id }
        }
        state.hotCues = cues
        if let url = player.loadedURL {
            LibraryIndex.shared.setHotCues(cues, forPath: url.path)
        }
    }

    /// Jump playback to the cue at pad index `id`. No-op if the cue isn't set.
    func jumpHotCue(id: Int) {
        guard let cue = state.hotCues.first(where: { $0.id == id }) else { return }
        // Disengage any active loop first — jump cues take priority.
        if loopEngine.isEngaged {
            state.loop.isActive = false
            loopEngine.disengage()
        }
        player.seek(toSeconds: cue.seconds)
    }

    /// Remove the cue at pad index `id`.
    func deleteHotCue(id: Int) {
        var cues = state.hotCues
        cues.removeAll { $0.id == id }
        state.hotCues = cues
        if let url = player.loadedURL {
            LibraryIndex.shared.setHotCues(cues, forPath: url.path)
        }
    }

    // MARK: - Loops

    /// Set the loop IN point at the current playhead, snapped to the nearest beat.
    func setLoopIn() {
        let t = beatSnap(state.currentTimeSeconds)
        state.loop.inSeconds = t
    }

    /// Set the loop OUT point at the current playhead, snapped to the nearest beat,
    /// and engage the loop.
    func setLoopOut() {
        let t = beatSnap(state.currentTimeSeconds)
        guard let inT = state.loop.inSeconds, t > inT else { return }
        state.loop.outSeconds = t
        engageLoopIfReady()
    }

    /// Halve the loop length (move OUT to half-distance from IN).
    func halveLoop() {
        guard let inT = state.loop.inSeconds, let outT = state.loop.outSeconds else { return }
        let length = outT - inT
        state.loop.outSeconds = inT + length / 2
        engageLoopIfReady()
    }

    /// Double the loop length (move OUT to twice-distance from IN).
    func doubleLoop() {
        guard let inT = state.loop.inSeconds, let outT = state.loop.outSeconds else { return }
        let length = outT - inT
        state.loop.outSeconds = inT + length * 2
        engageLoopIfReady()
    }

    /// Toggle loop on/off.
    func toggleLoop() {
        if state.loop.isActive {
            state.loop.isActive = false
            loopEngine.disengage()
        } else {
            engageLoopIfReady()
        }
    }

    private func engageLoopIfReady() {
        guard let inT = state.loop.inSeconds,
              let outT = state.loop.outSeconds,
              let file = player.file,
              outT > inT else { return }
        state.loop.isActive = true
        loopEngine.engage(player: player.player, file: file, inSeconds: inT, outSeconds: outT)
    }

    private func beatSnap(_ t: Double) -> Double {
        guard state.bpm > 0 else { return t }
        let beatInterval = 60.0 / state.bpm
        let firstBeat = state.firstBeat
        let offsetFromFirst = t - firstBeat
        let beatsFromFirst = (offsetFromFirst / beatInterval).rounded()
        return firstBeat + beatsFromFirst * beatInterval
    }
```

- [ ] **Step 3: Restore hot cues on track load**

Find the `load(url:)` method's `AnalysisService.shared.analyze` completion block:

```swift
            AnalysisService.shared.analyze(url: url) { [weak self] result in
                guard let self = self, let result = result else { return }
                guard self.player.isLoaded,
                      self.state.displayName == result.url.deletingPathExtension().lastPathComponent
                else { return }
                self.state.bpm = result.metadata.bpm
                self.state.firstBeat = result.metadata.firstBeat
                self.state.peaks = result.peaks
            }
```

Add hot-cue restoration to the body:

```swift
            AnalysisService.shared.analyze(url: url) { [weak self] result in
                guard let self = self, let result = result else { return }
                guard self.player.isLoaded,
                      self.state.displayName == result.url.deletingPathExtension().lastPathComponent
                else { return }
                self.state.bpm = result.metadata.bpm
                self.state.firstBeat = result.metadata.firstBeat
                self.state.peaks = result.peaks
                self.state.hotCues = result.metadata.hotCues
            }
```

And in the `catch` block of `load(url:)` add a hot-cues reset. Find:

```swift
            state.bpm = 0
            state.firstBeat = 0
            state.peaks = []
        }
    }
```

Replace with:

```swift
            state.bpm = 0
            state.firstBeat = 0
            state.peaks = []
            state.hotCues = []
            state.loop.clear()
            loopEngine.disengage()
        }
    }
```

Also at the top of `load(url:)` where the existing reset happens (after `try player.load(url: url)`), find:

```swift
            // Reset analysis-derived state until we have new results.
            state.bpm = 0
            state.firstBeat = 0
            state.peaks = []
```

Replace with:

```swift
            // Reset analysis-derived state until we have new results.
            state.bpm = 0
            state.firstBeat = 0
            state.peaks = []
            state.hotCues = []
            state.loop.clear()
            loopEngine.disengage()
```

- [ ] **Step 4: Verify build**

```bash
swift build -c release 2>&1 | tail -5
```

- [ ] **Step 5: Commit**

```bash
git add Sources/Murmur/Decks/DeckController.swift Sources/Murmur/Audio/LocalFilePlayer.swift
git commit -m "feat(decks): add hot cue + loop methods to DeckController"
```

---

### Task 6: PhaseAnalyzer + MixerEngine.phaseOffset

**Files:**
- Create: `Sources/Murmur/Decks/PhaseAnalyzer.swift`
- Modify: `Sources/Murmur/Decks/MixerEngine.swift`

- [ ] **Step 1: Create `PhaseAnalyzer.swift`**

```swift
import Combine
import Foundation

/// Computes the phase offset between two beat-locked decks at ~30Hz.
///
/// Phase offset is the difference between each deck's position within its beat,
/// modulo a beat interval. -0.5 to +0.5 beats. 0 = locked.
///
/// Publishes via `@Published var offsetBeats: Double` — UI binds to this.
final class PhaseAnalyzer: ObservableObject {
    /// Phase offset in beats, range -0.5…+0.5. 0 = master and slave beats aligned.
    /// Positive = slave is ahead of master.
    @Published var offsetBeats: Double = 0

    private var timer: Timer?
    private weak var deck1: DeckController?
    private weak var deck2: DeckController?
    private var getMasterId: () -> Int? = { nil }

    deinit {
        timer?.invalidate()
    }

    func attach(deck1: DeckController, deck2: DeckController, getMasterId: @escaping () -> Int?) {
        self.deck1 = deck1
        self.deck2 = deck2
        self.getMasterId = getMasterId
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    private func tick() {
        guard let d1 = deck1, let d2 = deck2 else { return }
        guard let masterId = getMasterId() else {
            if offsetBeats != 0 { offsetBeats = 0 }
            return
        }
        let master = (masterId == 1) ? d1 : d2
        let slave = (masterId == 1) ? d2 : d1

        guard master.state.bpm > 0, slave.state.bpm > 0,
              master.state.isPlaying, slave.state.isPlaying else {
            if offsetBeats != 0 { offsetBeats = 0 }
            return
        }

        let masterBeatInterval = 60.0 / (master.state.bpm * Double(master.state.tempoRate))
        let slaveBeatInterval = 60.0 / (slave.state.bpm * Double(slave.state.tempoRate))

        let masterPhase = phaseWithinBeat(time: master.state.currentTimeSeconds,
                                          firstBeat: master.state.firstBeat,
                                          beatInterval: masterBeatInterval)
        let slavePhase = phaseWithinBeat(time: slave.state.currentTimeSeconds,
                                         firstBeat: slave.state.firstBeat,
                                         beatInterval: slaveBeatInterval)

        // Offset in beats: difference in [0,1) normalized phase, wrapped to (-0.5, 0.5].
        var delta = slavePhase - masterPhase
        if delta > 0.5 { delta -= 1 }
        if delta < -0.5 { delta += 1 }
        offsetBeats = delta
    }

    /// Normalized phase 0..1 within the current beat.
    private func phaseWithinBeat(time: Double, firstBeat: Double, beatInterval: Double) -> Double {
        let offset = time - firstBeat
        let normalized = (offset / beatInterval).truncatingRemainder(dividingBy: 1)
        return normalized < 0 ? normalized + 1 : normalized
    }
}
```

- [ ] **Step 2: Modify `MixerEngine.swift`**

Find the property block. After `@Published private(set) var masterDeckId: Int? = nil`, add:

```swift
    let phaseAnalyzer = PhaseAnalyzer()
```

Find the `init()` method. At the end of `init()` (after the existing `deck1.connect(...)` and `deck2.connect(...)` lines), add:

```swift
        phaseAnalyzer.attach(deck1: deck1, deck2: deck2) { [weak self] in
            self?.masterDeckId
        }
```

- [ ] **Step 3: Verify build**

```bash
swift build -c release 2>&1 | tail -5
```

- [ ] **Step 4: Commit**

```bash
git add Sources/Murmur/Decks/PhaseAnalyzer.swift Sources/Murmur/Decks/MixerEngine.swift
git commit -m "feat(mixer): add PhaseAnalyzer publishing master/slave phase offset"
```

---

### Task 7: HotCuePadsView

**Files:**
- Create: `Sources/Murmur/Booth/HotCuePadsView.swift`

- [ ] **Step 1: Implement `HotCuePadsView`**

```swift
import SwiftUI

/// 8 hot-cue pads in a 4x2 grid. Click sets-or-jumps; right-click deletes.
///
/// A pad shows colored when its cue is set, dim outline when empty.
struct HotCuePadsView: View {
    let hotCues: [HotCue]
    var onSetOrJump: (Int) -> Void
    var onDelete: (Int) -> Void

    var body: some View {
        let columns = [GridItem(.flexible(), spacing: 4),
                       GridItem(.flexible(), spacing: 4),
                       GridItem(.flexible(), spacing: 4),
                       GridItem(.flexible(), spacing: 4)]
        LazyVGrid(columns: columns, spacing: 4) {
            ForEach(0..<8, id: \.self) { id in
                pad(id: id)
            }
        }
    }

    private func pad(id: Int) -> some View {
        let cue = hotCues.first(where: { $0.id == id })
        let color = cue.flatMap { Color(hex: $0.colorHex) } ?? Color.white.opacity(0.06)
        return Button(action: { onSetOrJump(id) }) {
            Text("\(id + 1)")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(cue == nil ? .white.opacity(0.5) : .black)
                .frame(maxWidth: .infinity)
                .frame(height: 22)
                .background(color)
                .overlay(RoundedRectangle(cornerRadius: 3).stroke(Color.white.opacity(0.1), lineWidth: 1))
                .cornerRadius(3)
        }
        .buttonStyle(.plain)
        .contextMenu {
            if cue != nil {
                Button("Delete cue \(id + 1)", role: .destructive) { onDelete(id) }
            }
        }
    }
}

extension Color {
    /// Construct a `Color` from a 6-character hex string (no #). Returns nil on bad input.
    init?(hex: String) {
        var s = hex
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        let r = Double((v >> 16) & 0xff) / 255
        let g = Double((v >> 8) & 0xff) / 255
        let b = Double(v & 0xff) / 255
        self = Color(red: r, green: g, blue: b)
    }
}
```

- [ ] **Step 2: Verify build**

```bash
swift build -c release 2>&1 | tail -5
```

- [ ] **Step 3: Commit**

```bash
git add Sources/Murmur/Booth/HotCuePadsView.swift
git commit -m "feat(booth): add HotCuePadsView with 8 cue pads + delete via context menu"
```

---

### Task 8: LoopControlsView

**Files:**
- Create: `Sources/Murmur/Booth/LoopControlsView.swift`

- [ ] **Step 1: Implement `LoopControlsView`**

```swift
import SwiftUI

/// Loop controls strip: IN, OUT, ½, ×2, ON/OFF.
struct LoopControlsView: View {
    @ObservedObject var loop: LoopState
    var tint: Color
    var onSetIn: () -> Void
    var onSetOut: () -> Void
    var onHalve: () -> Void
    var onDouble: () -> Void
    var onToggle: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            button("IN", active: loop.inSeconds != nil, action: onSetIn)
            button("OUT", active: loop.outSeconds != nil, action: onSetOut)
            button("½", active: false, action: onHalve)
                .disabled(!loop.isArmed)
                .opacity(loop.isArmed ? 1 : 0.4)
            button("×2", active: false, action: onDouble)
                .disabled(!loop.isArmed)
                .opacity(loop.isArmed ? 1 : 0.4)
            button(loop.isActive ? "LOOP" : "LOOP", active: loop.isActive, action: onToggle)
                .disabled(!loop.isArmed)
                .opacity(loop.isArmed ? 1 : 0.4)
            Spacer()
        }
    }

    private func button(_ label: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .tracking(0.5)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .foregroundColor(active ? tint : .white.opacity(0.55))
                .background(active ? tint.opacity(0.15) : Color.white.opacity(0.03))
                .overlay(RoundedRectangle(cornerRadius: 3).stroke(active ? tint.opacity(0.5) : Color.white.opacity(0.08), lineWidth: 1))
                .cornerRadius(3)
        }
        .buttonStyle(.plain)
    }
}
```

- [ ] **Step 2: Verify build**

```bash
swift build -c release 2>&1 | tail -5
```

- [ ] **Step 3: Commit**

```bash
git add Sources/Murmur/Booth/LoopControlsView.swift
git commit -m "feat(booth): add LoopControlsView (IN/OUT/½/×2/LOOP)"
```

---

### Task 9: CueAndLoopOverlay — cue flags + loop region on the waveform

**Files:**
- Create: `Sources/Murmur/Booth/CueAndLoopOverlay.swift`

- [ ] **Step 1: Implement `CueAndLoopOverlay`**

```swift
import SwiftUI

/// Overlays hot-cue flags and the active loop region on top of the waveform.
///
/// Cue flags render as thin vertical lines in each cue's color, with a small
/// triangle "flag" at the top. The loop region is a tinted band between the
/// IN and OUT seconds.
struct CueAndLoopOverlay: View {
    let hotCues: [HotCue]
    @ObservedObject var loop: LoopState
    let duration: Double
    var loopTint: Color = .cyan

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                // Loop region band (drawn first so cues sit on top).
                if let inT = loop.inSeconds, let outT = loop.outSeconds, duration > 0 {
                    let x1 = CGFloat(inT / duration) * geo.size.width
                    let x2 = CGFloat(outT / duration) * geo.size.width
                    Rectangle()
                        .fill(loopTint.opacity(loop.isActive ? 0.28 : 0.15))
                        .frame(width: max(2, x2 - x1), height: geo.size.height)
                        .offset(x: x1, y: 0)
                }

                // Hot cue flags.
                ForEach(hotCues) { cue in
                    if duration > 0 {
                        let x = CGFloat(cue.seconds / duration) * geo.size.width
                        let color = Color(hex: cue.colorHex) ?? .white
                        ZStack(alignment: .top) {
                            // Vertical line.
                            Rectangle()
                                .fill(color)
                                .frame(width: 2, height: geo.size.height)
                            // Flag at top.
                            Text("\(cue.id + 1)")
                                .font(.system(size: 8, weight: .bold, design: .monospaced))
                                .foregroundColor(.black)
                                .frame(width: 14, height: 12)
                                .background(color)
                        }
                        .offset(x: x - 1, y: 0)
                    }
                }
            }
            .allowsHitTesting(false)
        }
    }
}
```

- [ ] **Step 2: Verify build**

```bash
swift build -c release 2>&1 | tail -5
```

- [ ] **Step 3: Commit**

```bash
git add Sources/Murmur/Booth/CueAndLoopOverlay.swift
git commit -m "feat(booth): add CueAndLoopOverlay with hot cue flags + loop region"
```

---

### Task 10: PhaseMeterView

**Files:**
- Create: `Sources/Murmur/Booth/PhaseMeterView.swift`

- [ ] **Step 1: Implement `PhaseMeterView`**

```swift
import SwiftUI

/// Horizontal phase meter — needle drifts left/right of center as the slave
/// deck's beats lead/trail the master's. Goes green near zero (within ±0.05 beat).
struct PhaseMeterView: View {
    /// Phase offset in beats, -0.5…+0.5.
    let offsetBeats: Double

    private var locked: Bool { abs(offsetBeats) < 0.05 }

    var body: some View {
        VStack(spacing: 4) {
            Text("PHASE")
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .tracking(1.5)
                .foregroundColor(.white.opacity(0.5))

            GeometryReader { geo in
                ZStack {
                    // Track background.
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.white.opacity(0.06))
                    // Center mark.
                    Rectangle()
                        .fill(Color.white.opacity(0.25))
                        .frame(width: 1)
                    // Needle.
                    Rectangle()
                        .fill(locked ? Color.green : Color.cyan)
                        .frame(width: 4, height: geo.size.height + 6)
                        .shadow(color: (locked ? Color.green : Color.cyan).opacity(0.7), radius: 4)
                        // Map offsetBeats (-0.5..+0.5) to ±half-width.
                        .offset(x: CGFloat(max(-0.5, min(0.5, offsetBeats))) * geo.size.width)
                }
            }
            .frame(height: 10)
        }
    }
}
```

- [ ] **Step 2: Verify build**

```bash
swift build -c release 2>&1 | tail -5
```

- [ ] **Step 3: Commit**

```bash
git add Sources/Murmur/Booth/PhaseMeterView.swift
git commit -m "feat(booth): add PhaseMeterView with locked-green needle"
```

---

### Task 11: Wire Phase 2b views into DeckView + BoothView

**Files:**
- Modify: `Sources/Murmur/Booth/DeckView.swift`
- Modify: `Sources/Murmur/Booth/BoothView.swift`

- [ ] **Step 1: Add new DeckView properties**

Open `Sources/Murmur/Booth/DeckView.swift`. Find the property block:

```swift
struct DeckView: View {
    @ObservedObject var state: DeckState
    var deckNumber: Int
    var tint: Color
    var onLoad: (URL) -> Void
    var onTogglePlay: () -> Void
    var hasMaster: Bool
    var onSync: () -> Void
    var onToggleMaster: () -> Void
```

Add these properties immediately after `onToggleMaster`:

```swift
    var onSetOrJumpCue: (Int) -> Void
    var onDeleteCue: (Int) -> Void
    var onSetLoopIn: () -> Void
    var onSetLoopOut: () -> Void
    var onHalveLoop: () -> Void
    var onDoubleLoop: () -> Void
    var onToggleLoop: () -> Void
```

- [ ] **Step 2: Add overlay to waveform ZStack and insert new control rows**

Find the existing waveform `ZStack`:

```swift
            ZStack {
                WaveformView(
                    peaks: state.peaks,
                    progress: state.durationSeconds > 0 ? state.currentTimeSeconds / state.durationSeconds : 0,
                    tint: tint
                )
                BeatGridOverlay(
                    bpm: state.bpm,
                    duration: state.durationSeconds,
                    firstBeat: $state.firstBeat,
                    tint: tint
                )
            }
            .frame(height: 50)
```

Replace with:

```swift
            ZStack {
                WaveformView(
                    peaks: state.peaks,
                    progress: state.durationSeconds > 0 ? state.currentTimeSeconds / state.durationSeconds : 0,
                    tint: tint
                )
                BeatGridOverlay(
                    bpm: state.bpm,
                    duration: state.durationSeconds,
                    firstBeat: $state.firstBeat,
                    tint: tint
                )
                CueAndLoopOverlay(
                    hotCues: state.hotCues,
                    loop: state.loop,
                    duration: state.durationSeconds,
                    loopTint: tint
                )
            }
            .frame(height: 50)
```

Then find `SyncControlsView(...)` and insert AFTER it (and before the existing folder/play HStack):

```swift
            HotCuePadsView(
                hotCues: state.hotCues,
                onSetOrJump: onSetOrJumpCue,
                onDelete: onDeleteCue
            )

            LoopControlsView(
                loop: state.loop,
                tint: tint,
                onSetIn: onSetLoopIn,
                onSetOut: onSetLoopOut,
                onHalve: onHalveLoop,
                onDouble: onDoubleLoop,
                onToggle: onToggleLoop
            )
```

- [ ] **Step 3: Update BoothView**

Open `Sources/Murmur/Booth/BoothView.swift`. Replace the ENTIRE `body` content (inside `var body: some View { ... }`) with:

```swift
        VStack(spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                DeckView(
                    state: deck1State,
                    deckNumber: 1,
                    tint: .cyan,
                    onLoad: { mixer.deck1.load(url: $0) },
                    onTogglePlay: { mixer.deck1.togglePlay() },
                    hasMaster: mixer.masterDeckId != nil,
                    onSync: { mixer.sync(slave: mixer.deck1) },
                    onToggleMaster: {
                        mixer.setMaster(deck1State.isMaster ? nil : 1)
                    },
                    onSetOrJumpCue: { id in
                        if deck1State.hotCues.contains(where: { $0.id == id }) {
                            mixer.deck1.jumpHotCue(id: id)
                        } else {
                            mixer.deck1.setHotCue(id: id)
                        }
                    },
                    onDeleteCue: { mixer.deck1.deleteHotCue(id: $0) },
                    onSetLoopIn: { mixer.deck1.setLoopIn() },
                    onSetLoopOut: { mixer.deck1.setLoopOut() },
                    onHalveLoop: { mixer.deck1.halveLoop() },
                    onDoubleLoop: { mixer.deck1.doubleLoop() },
                    onToggleLoop: { mixer.deck1.toggleLoop() }
                )
                VStack(spacing: 8) {
                    MasterControlsView(mixer: mixer)
                    PhaseMeterView(offsetBeats: mixer.phaseAnalyzer.offsetBeats)
                        .frame(height: 30)
                }
                .frame(width: 110)
                DeckView(
                    state: deck2State,
                    deckNumber: 2,
                    tint: .orange,
                    onLoad: { mixer.deck2.load(url: $0) },
                    onTogglePlay: { mixer.deck2.togglePlay() },
                    hasMaster: mixer.masterDeckId != nil,
                    onSync: { mixer.sync(slave: mixer.deck2) },
                    onToggleMaster: {
                        mixer.setMaster(deck2State.isMaster ? nil : 2)
                    },
                    onSetOrJumpCue: { id in
                        if deck2State.hotCues.contains(where: { $0.id == id }) {
                            mixer.deck2.jumpHotCue(id: id)
                        } else {
                            mixer.deck2.setHotCue(id: id)
                        }
                    },
                    onDeleteCue: { mixer.deck2.deleteHotCue(id: $0) },
                    onSetLoopIn: { mixer.deck2.setLoopIn() },
                    onSetLoopOut: { mixer.deck2.setLoopOut() },
                    onHalveLoop: { mixer.deck2.halveLoop() },
                    onDoubleLoop: { mixer.deck2.doubleLoop() },
                    onToggleLoop: { mixer.deck2.toggleLoop() }
                )
            }

            CrossfaderView(position: $mixer.crossfadePosition)
                .frame(height: 36)
                .background(Color(white: 0.04))
                .cornerRadius(8)
        }
        .padding(14)
        .frame(minWidth: 1000, minHeight: 600)
        .background(Color(white: 0.02))
```

Note: `minHeight` bumped from 500 to 600 to fit the new cue pads + loop controls rows.

- [ ] **Step 4: PhaseAnalyzer needs to participate in @ObservedObject updates**

Since `mixer.phaseAnalyzer.offsetBeats` is a `@Published` property but `phaseAnalyzer` itself isn't observed by the SwiftUI tree, the meter won't auto-update. There are two fixes; the simpler one is to wrap the `PhaseMeterView` call in an `@ObservedObject`-aware subview. Replace this line in step 3:

```swift
                    PhaseMeterView(offsetBeats: mixer.phaseAnalyzer.offsetBeats)
                        .frame(height: 30)
```

with:

```swift
                    LivePhaseMeter(analyzer: mixer.phaseAnalyzer)
                        .frame(height: 30)
```

Then add this helper view at the bottom of `BoothView.swift`, AFTER the closing `}` of `struct BoothView`:

```swift
/// Tiny wrapper so SwiftUI observes `PhaseAnalyzer.@Published`.
private struct LivePhaseMeter: View {
    @ObservedObject var analyzer: PhaseAnalyzer
    var body: some View { PhaseMeterView(offsetBeats: analyzer.offsetBeats) }
}
```

- [ ] **Step 5: Update window minimum height**

Open `Sources/Murmur/Booth/BoothWindowController.swift`. Find:

```swift
        win.setContentSize(NSSize(width: 1100, height: 560))
        win.contentMinSize = NSSize(width: 1000, height: 500)
```

Replace with:

```swift
        win.setContentSize(NSSize(width: 1100, height: 660))
        win.contentMinSize = NSSize(width: 1000, height: 600)
```

- [ ] **Step 6: Verify build**

```bash
swift build -c release 2>&1 | tail -10
```

- [ ] **Step 7: Commit**

```bash
git add Sources/Murmur/Booth/DeckView.swift Sources/Murmur/Booth/BoothView.swift Sources/Murmur/Booth/BoothWindowController.swift
git commit -m "feat(booth): wire hot cues + loops + phase meter into the booth"
```

---

### Task 12: Build bundle + manual smoke + tag

- [ ] **Step 1: Build the .app bundle**

```bash
./build-app.sh --sign 2>&1 | tail -10
```

- [ ] **Step 2: Run the smoke**

`open dist/Murmur.app`. With a track loaded on Deck 1:

1. Play. Click pad **1** — it lights up red (default color). Continue playing past the cue point.
2. Click pad **1** again — playback jumps back to where you set the cue.
3. Set cues on pads 2, 3, 4 at different points. They appear as colored vertical flags on the waveform with small numbered tags at the top.
4. Right-click pad 2 → "Delete cue 2" — pad goes back to dim, flag disappears from waveform.
5. Click **IN** during playback — IN button lights up.
6. Wait a beat or two, click **OUT** — OUT button lights, LOOP turns on, the section between IN and OUT shows as a cyan band on the waveform, playback loops cleanly with no clicks at the loop boundary.
7. Click **½** — the OUT marker (cyan band) shrinks to half the previous length. Loop length halves audibly.
8. Click **×2** — back to original.
9. Click **LOOP** — loop disengages, playback continues out of the loop region into the rest of the file.
10. Quit and re-open the app, load the same track — pads 1, 3, 4 are still colored (from step 3 minus deleted 2). Console shows analysis was a cache hit.
11. With both decks playing in SYNC, watch the **PHASE** meter between the master controls. Needle should hover near center; if Deck 2's BPM detection is slightly off, you'll see it drift slowly.

- [ ] **Step 3: Tag the milestone**

```bash
git tag -a phase-2b-performance -m "Pocket DJ Phase 2b: hot cues + loops + phase meter"
```

---

## Out of scope for Phase 2b

- Saved loops (long-press a hot-cue pad to save current loop region as a re-callable cue) — Phase 3
- Continuous-sync / "sync hold" that re-corrects phase drift — Phase 3
- Effects rack — Phase 4
- Library panel / crates / prep crate — Phase 6

---

## Self-Review

- **§5.4 Cue points and hot cues:** 8 pads, color-coded, click set-or-jump, right-click delete, persisted per track. ✅ Tasks 1, 5, 7.
- **§5.4 Loops:** beat-quantized in/out, halve/double, on-screen region. ✅ Tasks 2, 3, 5, 8, 9.
- **§5.2 Phase meter:** visual showing alignment drift, locked-green threshold. ✅ Tasks 6, 10.
- **Saved loops as 9th-16th pads:** explicit out-of-scope.
- **§5.4 hot cue colors / palette:** 8-color default palette in `HotCue.defaultPalette`. ✅
- **§7.3 Beat-quantized loops use lastRenderTime:** the spec mentions sample-accurate quantization via `lastRenderTime`. Phase 2b uses `currentTimeSeconds` (frame-accurate but rounded to beat). This is acceptable for v1; sample-accurate quantization is a future refinement.

No spec gaps for the in-scope set. No placeholders. Type signatures consistent across tasks (`HotCue.id`, `LoopState.inSeconds/outSeconds/isActive`, `PhaseAnalyzer.offsetBeats`).
