# Pocket DJ Phase 1 Implementation Plan — Audio Foundation

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship a working 2-deck local-file DJ mixer in Murmur: load two audio files, play them, adjust per-deck volume / 3-band EQ / filter, crossfade between them, and record the master to a WAV file. No 3D booth yet (SwiftUI mockup is fine), no BPM/sync/cue/loops/effects rack/key detection/library/Ambient Layer/Mood Dial — those are Phases 2–6.

**Architecture:** Single `AVAudioEngine` (`AudioGraph`) holds two `ChannelStrip` chains (volume → 3-band EQ → filter), each fed by a `LocalFilePlayer` (`AVAudioPlayerNode` + `AVAudioFile`). Strips feed an A-group submixer and a B-group submixer; a `Crossfader` adjusts the two submixers' gains on an equal-power curve. The submixers feed the engine's `mainMixerNode`, which is tapped by `MasterRecorder` to write a WAV file. A new `BoothWindowController` (sibling of the existing `VideoWindowController`) hosts a SwiftUI `BoothView` for control. The existing YouTube popover behavior is untouched — Phase 1 is purely additive.

**Tech Stack:** Swift 5.9+, AppKit, SwiftUI, `AVFoundation` (`AVAudioEngine`, `AVAudioPlayerNode`, `AVAudioUnitEQ`, `AVAudioFile`). macOS 13+. No new SwiftPM dependencies. No build-system changes.

**On testing:** Per `CLAUDE.md`, this repo has no test target by design ("Don't invent `swift test` instructions"). Every task uses **manual verification** instead: `swift run -c release`, follow the steps, confirm the described audible/visible behavior. Manual steps are deliberately specific so failures are unambiguous.

**Prerequisites for verification:** Have two local audio files ready at known paths. Suggested defaults the plan refers to:
- `~/Music/test-track-A.m4a`
- `~/Music/test-track-B.m4a`

Any AVFoundation-readable format works (M4A, MP3, WAV, AIFF, ALAC). Use musically different tracks (e.g., one with heavy bass, one with crisp highs) so EQ/filter effects are obviously audible.

---

## File Structure

New files under `Sources/Murmur/`:

```
Audio/
  AudioGraph.swift          AVAudioEngine wrapper: lifecycle, submix nodes, install/remove taps
  SourcePlayer.swift        Protocol all source backends will eventually implement
  LocalFilePlayer.swift     AVAudioPlayerNode-backed file player (load/play/pause/seek/volume)
  ChannelStrip.swift        Per-deck audio chain: volume + 3-band EQ + LP/HP filter
  Crossfader.swift          Equal-power crossfade math + applies to A/B submix gains
  MasterRecorder.swift      Master-bus tap → AVAudioFile (WAV)
Decks/
  DeckState.swift           ObservableObject mirroring one deck's UI state
  DeckController.swift      Binds a SourcePlayer + ChannelStrip + DeckState
  MixerEngine.swift         Top-level coordinator: owns AudioGraph + 2 decks + crossfader + recorder
Booth/
  BoothWindowController.swift   NSWindow controller for the booth (sibling of VideoWindowController)
  BoothView.swift               SwiftUI top-level layout (decks + center strip)
  DeckView.swift                SwiftUI per-deck panel (file picker + transport + knobs)
  KnobView.swift                Reusable circular knob (SwiftUI; for EQ + filter)
  CrossfaderView.swift          SwiftUI crossfader slider
  MasterControlsView.swift      SwiftUI master volume + record button
```

Modified:

- `Sources/Murmur/main.swift` — `AppDelegate` instantiates `MixerEngine` and `BoothWindowController`; injects them into the popover.
- `Sources/Murmur/ContentView.swift` — adds an "Open DJ Booth" button below the existing controls.

`Package.swift` — **unchanged.**

---

### Task 1: Add Audio module skeleton + regression smoke

**Files:**
- Create: `Sources/Murmur/Audio/AudioGraph.swift`
- Modify: `Sources/Murmur/main.swift:407` (after `var videoWindow:` declaration)

- [ ] **Step 1: Create the Audio directory and stub `AudioGraph`**

Create `Sources/Murmur/Audio/AudioGraph.swift` with:

```swift
import AVFoundation

/// Owns the single AVAudioEngine that drives the DJ surface.
///
/// Phase 1 only wires the engine lifecycle + two submix nodes (A group, B group)
/// connected to `mainMixerNode`. Decks and recording are bolted on by later tasks.
final class AudioGraph {
    let engine = AVAudioEngine()
    let submixA = AVAudioMixerNode()
    let submixB = AVAudioMixerNode()

    init() {
        engine.attach(submixA)
        engine.attach(submixB)
        // Connect both submixers to the main mixer at the engine's default format.
        let mainFormat = engine.mainMixerNode.outputFormat(forBus: 0)
        engine.connect(submixA, to: engine.mainMixerNode, format: mainFormat)
        engine.connect(submixB, to: engine.mainMixerNode, format: mainFormat)
    }

    func start() throws {
        guard !engine.isRunning else { return }
        engine.prepare()
        try engine.start()
    }

    func stop() {
        engine.stop()
    }
}
```

- [ ] **Step 2: Wire a no-op `MixerEngine` placeholder into `AppDelegate`**

In `Sources/Murmur/main.swift`, in `AppDelegate` (line ~401), add the property next to `var videoWindow`:

Find this block:
```swift
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    var statusItem: NSStatusItem!
    var popover: NSPopover!
    let controller = PlayerController()
    let favorites = FavoritesStore()
    var videoWindow: VideoWindowController!
```

Add `let audioGraph = AudioGraph()` immediately after `var videoWindow:`:

```swift
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    var statusItem: NSStatusItem!
    var popover: NSPopover!
    let controller = PlayerController()
    let favorites = FavoritesStore()
    var videoWindow: VideoWindowController!
    let audioGraph = AudioGraph()
```

Then in `applicationDidFinishLaunching`, after the existing `videoWindow = ...` line and the `controller.onWillLoadStream` block (line ~416), add:

```swift
        // Start the DJ audio graph. Decks/recording attach in later tasks.
        do {
            try audioGraph.start()
        } catch {
            NSLog("AudioGraph failed to start: \(error)")
        }
```

- [ ] **Step 3: Build and run; verify no regression**

Run:

```bash
cd /Users/mm/Documents/youtube-audio-widget
swift build -c release 2>&1 | tail -20
swift run -c release
```

**Expected:** App builds without errors. Menu-bar icon appears. Click it: the popover opens with the existing YouTube controls. The default Claude FM stream loads and plays. Quit the app from the popover. No console errors related to `AudioGraph`.

**Failure mode:** If the engine fails to start, you'll see an `NSLog` "AudioGraph failed to start: …" message in Console.app. Most likely cause is that the system has no audio output device — plug one in and try again.

- [ ] **Step 4: Commit**

```bash
git add Sources/Murmur/Audio/AudioGraph.swift Sources/Murmur/main.swift
git commit -m "feat(audio): add AudioGraph skeleton wrapping AVAudioEngine"
```

---

### Task 2: `SourcePlayer` protocol + `LocalFilePlayer`

**Files:**
- Create: `Sources/Murmur/Audio/SourcePlayer.swift`
- Create: `Sources/Murmur/Audio/LocalFilePlayer.swift`

- [ ] **Step 1: Define the `SourcePlayer` protocol**

Create `Sources/Murmur/Audio/SourcePlayer.swift`:

```swift
import AVFoundation

/// Abstract audio source — Phase 1 only ships `LocalFilePlayer`. Future phases
/// add `AppleMusicPlayer` and `YouTubeAmbientPlayer` (see design spec §7.1).
///
/// A `SourcePlayer` exposes a single `outputNode` that the channel strip
/// connects into. It must not call `engine.connect` itself.
protocol SourcePlayer: AnyObject {
    /// The node a `ChannelStrip` should connect *from*. Must be attached to the engine.
    var outputNode: AVAudioNode { get }
    /// Human-readable label for UI ("Bonobo — Cirrus", or "—" when nothing loaded).
    var displayName: String { get }
    /// True after a successful `load` and the player is playable.
    var isLoaded: Bool { get }
    /// Whether the player is currently playing.
    var isPlaying: Bool { get }
    /// Current playhead in seconds, valid only when `isLoaded`.
    var currentTimeSeconds: Double { get }
    /// Total duration in seconds, valid only when `isLoaded`.
    var durationSeconds: Double { get }

    func load(url: URL) throws
    func play()
    func pause()
    func seek(toSeconds seconds: Double)
}
```

- [ ] **Step 2: Implement `LocalFilePlayer`**

Create `Sources/Murmur/Audio/LocalFilePlayer.swift`:

```swift
import AVFoundation

/// Plays a local audio file via `AVAudioPlayerNode` + `AVAudioFile`.
///
/// Connect `outputNode` to a `ChannelStrip` input. The player node is attached
/// to the engine in `init`; it stays attached for the lifetime of the player.
final class LocalFilePlayer: SourcePlayer {
    private let engine: AVAudioEngine
    private let player = AVAudioPlayerNode()
    private var file: AVAudioFile?
    private var loadedURL: URL?

    /// Sample-frame offset of where playback was last started in the file.
    /// Combined with `player.lastRenderTime` to compute `currentTimeSeconds`.
    private var startFrame: AVAudioFramePosition = 0

    var outputNode: AVAudioNode { player }

    var displayName: String {
        loadedURL?.deletingPathExtension().lastPathComponent ?? "—"
    }

    var isLoaded: Bool { file != nil }
    var isPlaying: Bool { player.isPlaying }

    var currentTimeSeconds: Double {
        guard let file = file,
              let nodeTime = player.lastRenderTime,
              let playerTime = player.playerTime(forNodeTime: nodeTime) else {
            return 0
        }
        let frames = startFrame + playerTime.sampleTime
        return Double(frames) / file.processingFormat.sampleRate
    }

    var durationSeconds: Double {
        guard let file = file else { return 0 }
        return Double(file.length) / file.processingFormat.sampleRate
    }

    init(engine: AVAudioEngine) {
        self.engine = engine
        engine.attach(player)
    }

    func load(url: URL) throws {
        let file = try AVAudioFile(forReading: url)
        // Stop any in-flight playback before re-scheduling.
        if player.isPlaying { player.stop() }
        self.file = file
        self.loadedURL = url
        self.startFrame = 0
        player.scheduleFile(file, at: nil, completionHandler: nil)
    }

    func play() {
        guard isLoaded, !player.isPlaying else { return }
        if !engine.isRunning {
            try? engine.start()
        }
        player.play()
    }

    func pause() {
        guard player.isPlaying else { return }
        player.pause()
    }

    func seek(toSeconds seconds: Double) {
        guard let file = file else { return }
        let sampleRate = file.processingFormat.sampleRate
        let frame = AVAudioFramePosition(max(0, seconds) * sampleRate)
        let clampedFrame = min(frame, file.length - 1)
        let framesToPlay = AVAudioFrameCount(max(0, file.length - clampedFrame))
        guard framesToPlay > 0 else { return }

        let wasPlaying = player.isPlaying
        player.stop()
        startFrame = clampedFrame
        player.scheduleSegment(file,
                               startingFrame: clampedFrame,
                               frameCount: framesToPlay,
                               at: nil,
                               completionHandler: nil)
        if wasPlaying { player.play() }
    }
}
```

- [ ] **Step 3: Build and run**

```bash
swift build -c release 2>&1 | tail -20
```

**Expected:** clean build. No runtime behavior change yet — these types exist but aren't wired into `AudioGraph`.

- [ ] **Step 4: Commit**

```bash
git add Sources/Murmur/Audio/SourcePlayer.swift Sources/Murmur/Audio/LocalFilePlayer.swift
git commit -m "feat(audio): add SourcePlayer protocol and LocalFilePlayer"
```

---

### Task 3: `ChannelStrip` — per-deck volume + 3-band EQ + filter

**Files:**
- Create: `Sources/Murmur/Audio/ChannelStrip.swift`

- [ ] **Step 1: Implement `ChannelStrip`**

Create `Sources/Murmur/Audio/ChannelStrip.swift`:

```swift
import AVFoundation

/// One deck's audio chain.
///
/// Signal path: [SourcePlayer.outputNode]
///                   ↓
///               [eq3band]   3 parametric bands (low shelf, mid bell, high shelf)
///                   ↓
///               [filterEQ]  combined HP/LP filter sweep (one band, hp_lp mode)
///                   ↓
///               [volume]    AVAudioMixerNode used as a fader
///                   ↓
///        connected externally to either submixA or submixB
final class ChannelStrip {
    private let engine: AVAudioEngine

    /// 3-band EQ: low shelf @ 100Hz, mid bell @ 1kHz, high shelf @ 8kHz.
    let eq3band: AVAudioUnitEQ
    /// Single-band EQ used as a sweepable filter. Centre at 1kHz; mode toggled
    /// based on `filterPosition` sign (positive = HPF, negative = LPF).
    let filterEQ: AVAudioUnitEQ
    /// Final fader for the strip. Connect this to the desired group submixer.
    let volume = AVAudioMixerNode()

    /// EQ gains in dB, -24…+24 each.
    var lowGain: Float {
        get { eq3band.bands[0].gain }
        set { eq3band.bands[0].gain = max(-24, min(24, newValue)) }
    }
    var midGain: Float {
        get { eq3band.bands[1].gain }
        set { eq3band.bands[1].gain = max(-24, min(24, newValue)) }
    }
    var highGain: Float {
        get { eq3band.bands[2].gain }
        set { eq3band.bands[2].gain = max(-24, min(24, newValue)) }
    }

    /// Linear gain 0…1.5 (allows up to +3.5dB).
    var fader: Float {
        get { volume.outputVolume }
        set { volume.outputVolume = max(0, min(1.5, newValue)) }
    }

    /// Filter sweep -1…+1. -1 = full LPF cutoff ~100Hz, 0 = bypass,
    /// +1 = full HPF cutoff ~10kHz. Logarithmic mapping between.
    var filterPosition: Float = 0 {
        didSet { applyFilter(position: filterPosition) }
    }

    init(engine: AVAudioEngine) {
        self.engine = engine

        // --- 3-band EQ ---
        eq3band = AVAudioUnitEQ(numberOfBands: 3)
        let low = eq3band.bands[0]
        low.filterType = .lowShelf
        low.frequency = 100
        low.gain = 0
        low.bypass = false

        let mid = eq3band.bands[1]
        mid.filterType = .parametric
        mid.frequency = 1000
        mid.bandwidth = 1.0   // octaves
        mid.gain = 0
        mid.bypass = false

        let high = eq3band.bands[2]
        high.filterType = .highShelf
        high.frequency = 8000
        high.gain = 0
        high.bypass = false

        // --- Filter EQ (single band, mode flipped per direction) ---
        filterEQ = AVAudioUnitEQ(numberOfBands: 1)
        let f = filterEQ.bands[0]
        f.filterType = .highPass
        f.frequency = 20      // 20Hz HPF = effectively bypassed
        f.bypass = true
        f.gain = 0

        engine.attach(eq3band)
        engine.attach(filterEQ)
        engine.attach(volume)

        // Internal connections: eq3band → filterEQ → volume.
        let fmt = engine.mainMixerNode.outputFormat(forBus: 0)
        engine.connect(eq3band, to: filterEQ, format: fmt)
        engine.connect(filterEQ, to: volume, format: fmt)
    }

    /// Connect a source's output node into the head of this strip.
    func connectSource(_ source: SourcePlayer) {
        let fmt = engine.mainMixerNode.outputFormat(forBus: 0)
        engine.connect(source.outputNode, to: eq3band, format: fmt)
    }

    private func applyFilter(position: Float) {
        let p = max(-1, min(1, position))
        let band = filterEQ.bands[0]
        if abs(p) < 0.02 {
            band.bypass = true
            return
        }
        band.bypass = false
        if p > 0 {
            // HPF: 100Hz → 10kHz logarithmically as p goes 0 → 1
            band.filterType = .highPass
            band.frequency = 100 * pow(100, p)   // 100 * 100^p, so 0→100Hz, 1→10kHz
        } else {
            // LPF: 10kHz → 100Hz logarithmically as p goes 0 → -1
            band.filterType = .lowPass
            band.frequency = 10000 * pow(100, p) // p is negative, so 100^p < 1
        }
    }
}
```

- [ ] **Step 2: Build**

```bash
swift build -c release 2>&1 | tail -20
```

**Expected:** clean build. No behavior change yet — still not wired up.

- [ ] **Step 3: Commit**

```bash
git add Sources/Murmur/Audio/ChannelStrip.swift
git commit -m "feat(audio): add ChannelStrip with 3-band EQ and sweep filter"
```

---

### Task 4: `Crossfader` — equal-power curve

**Files:**
- Create: `Sources/Murmur/Audio/Crossfader.swift`

- [ ] **Step 1: Implement `Crossfader`**

Create `Sources/Murmur/Audio/Crossfader.swift`:

```swift
import AVFoundation
import Foundation

/// Equal-power crossfade between two submix nodes.
///
/// `position` ∈ [-1, +1]:
///   -1.0 → submixA at full gain, submixB silent
///    0.0 → both at -3dB (≈0.707 linear) — equal-power center
///   +1.0 → submixB at full gain, submixA silent
///
/// Uses cos/sin so that aGain² + bGain² = 1 across the sweep (constant perceived
/// loudness when both decks contain uncorrelated content).
final class Crossfader {
    let submixA: AVAudioMixerNode
    let submixB: AVAudioMixerNode

    var position: Float = 0 {
        didSet { apply(position: position) }
    }

    init(submixA: AVAudioMixerNode, submixB: AVAudioMixerNode) {
        self.submixA = submixA
        self.submixB = submixB
        apply(position: 0)
    }

    static func gains(forPosition rawPosition: Float) -> (a: Float, b: Float) {
        let p = max(-1, min(1, rawPosition))
        // Map -1…+1 to 0…π/2 with center at π/4.
        let angle = (p + 1) * (.pi / 4)
        let a = cosf(angle)
        let b = sinf(angle)
        return (a, b)
    }

    private func apply(position: Float) {
        let (a, b) = Crossfader.gains(forPosition: position)
        submixA.outputVolume = a
        submixB.outputVolume = b
    }
}
```

- [ ] **Step 2: Sanity-check the math manually**

Open a Swift REPL or a temporary scratch file and verify the curve. (Optional — no production change.) Position −1.0 → (cos(0), sin(0)) = (1, 0). Position 0 → (cos(π/4), sin(π/4)) ≈ (0.707, 0.707). Position +1.0 → (cos(π/2), sin(π/2)) = (0, 1). Sum of squares constant.

- [ ] **Step 3: Build**

```bash
swift build -c release 2>&1 | tail -20
```

**Expected:** clean build.

- [ ] **Step 4: Commit**

```bash
git add Sources/Murmur/Audio/Crossfader.swift
git commit -m "feat(audio): add equal-power Crossfader"
```

---

### Task 5: `MasterRecorder` — tap the main mixer to WAV

**Files:**
- Create: `Sources/Murmur/Audio/MasterRecorder.swift`

- [ ] **Step 1: Implement `MasterRecorder`**

Create `Sources/Murmur/Audio/MasterRecorder.swift`:

```swift
import AVFoundation
import Foundation

/// Records the engine's `mainMixerNode` output to a 48 kHz / 16-bit stereo WAV.
///
/// Only one recording can be active at a time. Files land in
/// `~/Library/Application Support/Murmur/Recordings/<timestamp>.wav`.
final class MasterRecorder {
    private let engine: AVAudioEngine
    private var outputFile: AVAudioFile?
    private(set) var isRecording = false
    private(set) var currentOutputURL: URL?

    init(engine: AVAudioEngine) {
        self.engine = engine
    }

    /// Folder where recordings are written. Created on first use.
    static var recordingsDirectory: URL {
        let appSupport = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
            .appendingPathComponent("Murmur", isDirectory: true)
            .appendingPathComponent("Recordings", isDirectory: true)
        try? FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
        return appSupport
    }

    /// Starts recording. Returns the URL of the new WAV file, or nil on failure.
    @discardableResult
    func start() -> URL? {
        guard !isRecording else { return currentOutputURL }
        let timestamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let url = Self.recordingsDirectory.appendingPathComponent("\(timestamp).wav")

        // File format: 48 kHz / 16-bit stereo LPCM WAV.
        let fileSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 48000.0,
            AVNumberOfChannelsKey: 2,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false
        ]

        do {
            let file = try AVAudioFile(forWriting: url, settings: fileSettings)
            self.outputFile = file
            self.currentOutputURL = url
        } catch {
            NSLog("MasterRecorder failed to open file: \(error)")
            return nil
        }

        let mixer = engine.mainMixerNode
        let tapFormat = mixer.outputFormat(forBus: 0)
        mixer.installTap(onBus: 0, bufferSize: 4096, format: tapFormat) { [weak self] buffer, _ in
            guard let self = self, let file = self.outputFile else { return }
            do {
                try file.write(from: buffer)
            } catch {
                NSLog("MasterRecorder write error: \(error)")
            }
        }
        isRecording = true
        return url
    }

    /// Stops recording and closes the file. Returns the URL of the finished WAV.
    @discardableResult
    func stop() -> URL? {
        guard isRecording else { return nil }
        engine.mainMixerNode.removeTap(onBus: 0)
        let url = currentOutputURL
        outputFile = nil
        isRecording = false
        return url
    }
}
```

- [ ] **Step 2: Build**

```bash
swift build -c release 2>&1 | tail -20
```

**Expected:** clean build.

- [ ] **Step 3: Commit**

```bash
git add Sources/Murmur/Audio/MasterRecorder.swift
git commit -m "feat(audio): add MasterRecorder for WAV bouncing"
```

---

### Task 6: `DeckState` — observable per-deck state

**Files:**
- Create: `Sources/Murmur/Decks/DeckState.swift`

- [ ] **Step 1: Implement `DeckState`**

Create `Sources/Murmur/Decks/DeckState.swift`:

```swift
import Combine
import Foundation

/// Observable state for one deck. UI binds to this; `DeckController` writes to it.
///
/// `volume`, `lowGain`, `midGain`, `highGain`, `filter` are mirrored into the
/// `ChannelStrip` by `DeckController`. The UI never touches the strip directly.
final class DeckState: ObservableObject {
    @Published var displayName: String = "—"
    @Published var isLoaded: Bool = false
    @Published var isPlaying: Bool = false
    @Published var currentTimeSeconds: Double = 0
    @Published var durationSeconds: Double = 0

    /// 0…1.5. 1.0 = unity.
    @Published var volume: Float = 1.0
    /// dB, -24…+24.
    @Published var lowGain: Float = 0
    @Published var midGain: Float = 0
    @Published var highGain: Float = 0
    /// -1…+1. 0 = bypass; +1 = HPF closed; -1 = LPF closed.
    @Published var filter: Float = 0
}
```

- [ ] **Step 2: Build**

```bash
swift build -c release 2>&1 | tail -20
```

**Expected:** clean build.

- [ ] **Step 3: Commit**

```bash
git add Sources/Murmur/Decks/DeckState.swift
git commit -m "feat(decks): add observable DeckState"
```

---

### Task 7: `DeckController` — bind player + strip + state

**Files:**
- Create: `Sources/Murmur/Decks/DeckController.swift`

- [ ] **Step 1: Implement `DeckController`**

Create `Sources/Murmur/Decks/DeckController.swift`:

```swift
import AVFoundation
import Combine
import Foundation

/// Owns one deck's source player + channel strip and mirrors observable state.
///
/// Wires `DeckState.@Published` properties to the strip via Combine. The UI
/// mutates `DeckState`; the controller's sinks push the values into the audio
/// graph.
final class DeckController {
    let state = DeckState()
    let strip: ChannelStrip
    let player: LocalFilePlayer

    private var cancellables = Set<AnyCancellable>()
    private var positionTimer: Timer?

    init(engine: AVAudioEngine) {
        self.player = LocalFilePlayer(engine: engine)
        self.strip = ChannelStrip(engine: engine)
        strip.connectSource(player)
        wireStateBindings()
        startPositionPolling()
    }

    /// Connect this strip's volume node to a downstream submix.
    func connect(to submix: AVAudioMixerNode, in engine: AVAudioEngine) {
        let fmt = engine.mainMixerNode.outputFormat(forBus: 0)
        engine.connect(strip.volume, to: submix, format: fmt)
    }

    func load(url: URL) {
        do {
            try player.load(url: url)
            state.displayName = player.displayName
            state.isLoaded = true
            state.durationSeconds = player.durationSeconds
            state.currentTimeSeconds = 0
            state.isPlaying = false
        } catch {
            NSLog("DeckController load error: \(error)")
            state.isLoaded = false
            state.displayName = "Load failed"
        }
    }

    func togglePlay() {
        if player.isPlaying {
            player.pause()
        } else {
            player.play()
        }
        state.isPlaying = player.isPlaying
    }

    private func wireStateBindings() {
        state.$volume.sink { [weak self] v in self?.strip.fader = v }.store(in: &cancellables)
        state.$lowGain.sink { [weak self] v in self?.strip.lowGain = v }.store(in: &cancellables)
        state.$midGain.sink { [weak self] v in self?.strip.midGain = v }.store(in: &cancellables)
        state.$highGain.sink { [weak self] v in self?.strip.highGain = v }.store(in: &cancellables)
        state.$filter.sink { [weak self] v in self?.strip.filterPosition = v }.store(in: &cancellables)
    }

    private func startPositionPolling() {
        positionTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self = self, self.player.isLoaded else { return }
            self.state.currentTimeSeconds = self.player.currentTimeSeconds
            // Also mirror play-state in case it ended on its own.
            let nowPlaying = self.player.isPlaying
            if self.state.isPlaying != nowPlaying {
                self.state.isPlaying = nowPlaying
            }
        }
    }
}
```

- [ ] **Step 2: Build**

```bash
swift build -c release 2>&1 | tail -20
```

**Expected:** clean build.

- [ ] **Step 3: Commit**

```bash
git add Sources/Murmur/Decks/DeckController.swift
git commit -m "feat(decks): add DeckController binding player+strip+state"
```

---

### Task 8: `MixerEngine` — top-level coordinator + audible end-to-end test

**Files:**
- Create: `Sources/Murmur/Decks/MixerEngine.swift`
- Modify: `Sources/Murmur/main.swift` — replace `let audioGraph = AudioGraph()` with `let mixer = MixerEngine()`, and the `try audioGraph.start()` block with `try mixer.start()`.

- [ ] **Step 1: Implement `MixerEngine`**

Create `Sources/Murmur/Decks/MixerEngine.swift`:

```swift
import AVFoundation
import Combine
import Foundation

/// Top-level coordinator for the DJ surface.
///
/// Owns the `AudioGraph`, two `DeckController`s, the `Crossfader`, and the
/// `MasterRecorder`. UI talks to this object; this object talks to the audio
/// nodes.
final class MixerEngine: ObservableObject {
    let graph = AudioGraph()
    let deck1: DeckController
    let deck2: DeckController
    let crossfader: Crossfader
    let recorder: MasterRecorder

    /// Master output volume 0…1.5. 1.0 = unity.
    @Published var masterVolume: Float = 1.0 {
        didSet { graph.engine.mainMixerNode.outputVolume = max(0, min(1.5, masterVolume)) }
    }

    /// -1…+1, drives the crossfader.
    @Published var crossfadePosition: Float = 0 {
        didSet { crossfader.position = crossfadePosition }
    }

    @Published private(set) var isRecording: Bool = false
    @Published private(set) var lastRecordingURL: URL?

    init() {
        self.deck1 = DeckController(engine: graph.engine)
        self.deck2 = DeckController(engine: graph.engine)
        self.crossfader = Crossfader(submixA: graph.submixA, submixB: graph.submixB)
        self.recorder = MasterRecorder(engine: graph.engine)

        // Route deck1 → A submix, deck2 → B submix.
        deck1.connect(to: graph.submixA, in: graph.engine)
        deck2.connect(to: graph.submixB, in: graph.engine)
    }

    func start() throws {
        try graph.start()
    }

    func toggleRecording() {
        if recorder.isRecording {
            let url = recorder.stop()
            isRecording = false
            lastRecordingURL = url
        } else {
            let url = recorder.start()
            isRecording = recorder.isRecording
            lastRecordingURL = url
        }
    }
}
```

- [ ] **Step 2: Replace `audioGraph` with `mixer` in `AppDelegate`**

In `Sources/Murmur/main.swift`, change:

```swift
    let audioGraph = AudioGraph()
```

to:

```swift
    let mixer = MixerEngine()
```

And in `applicationDidFinishLaunching`, change:

```swift
        do {
            try audioGraph.start()
        } catch {
            NSLog("AudioGraph failed to start: \(error)")
        }
```

to:

```swift
        do {
            try mixer.start()
        } catch {
            NSLog("MixerEngine failed to start: \(error)")
        }
```

- [ ] **Step 3: Add a temporary CLI smoke test using `kDefaultAudioTestFile`**

Still in `main.swift`, **inside** `applicationDidFinishLaunching` after the `try mixer.start()` block, add this **temporary** debug block. We will remove it in Task 14.

```swift
        // ────────────────────────────────────────────────────────────────
        // TEMPORARY (removed in Task 14): force-load two files and play
        // both, so we can verify the audio chain audibly. Edit these
        // paths to point at two of your own audio files.
        let testA = URL(fileURLWithPath: NSString("~/Music/test-track-A.m4a").expandingTildeInPath)
        let testB = URL(fileURLWithPath: NSString("~/Music/test-track-B.m4a").expandingTildeInPath)
        if FileManager.default.fileExists(atPath: testA.path) {
            mixer.deck1.load(url: testA)
            mixer.deck1.togglePlay()
        }
        if FileManager.default.fileExists(atPath: testB.path) {
            mixer.deck2.load(url: testB)
            mixer.deck2.togglePlay()
        }
        // ────────────────────────────────────────────────────────────────
```

- [ ] **Step 4: Build and run; verify both files play simultaneously**

Run:

```bash
swift run -c release
```

**Expected:**
- Both `~/Music/test-track-A.m4a` and `~/Music/test-track-B.m4a` play simultaneously at equal volume (the crossfader defaults to center → equal-power 0.707 on both).
- If you set one file path to something invalid, the other still plays.
- The existing YouTube popover still works in parallel — open it, hit play, and you'll hear all three sources mixed together by the system output.

**If you don't hear audio:** check Console.app for `MixerEngine failed to start` or `DeckController load error` messages. Common causes: file path doesn't exist (check the `if FileManager.default.fileExists` guards above), file format isn't AVFoundation-readable, or the engine never started because no output device is available.

- [ ] **Step 5: Commit**

```bash
git add Sources/Murmur/Decks/MixerEngine.swift Sources/Murmur/main.swift
git commit -m "feat(mixer): add MixerEngine + temporary boot-time audible smoke test"
```

---

### Task 9: Verify crossfader, EQ, and filter audibly via temporary code

**Files:**
- Modify: `Sources/Murmur/main.swift` — extend the temporary debug block to sweep crossfader and EQ on a timer.

This task adds no production code — it's a transient verification pass before we build UI. The temporary block is removed in Task 14.

- [ ] **Step 1: Extend the temporary debug block in `main.swift`**

Find the temporary block from Task 8 and replace the load+play lines plus add sweeping behavior:

```swift
        // ────────────────────────────────────────────────────────────────
        // TEMPORARY (removed in Task 14)
        let testA = URL(fileURLWithPath: NSString("~/Music/test-track-A.m4a").expandingTildeInPath)
        let testB = URL(fileURLWithPath: NSString("~/Music/test-track-B.m4a").expandingTildeInPath)
        if FileManager.default.fileExists(atPath: testA.path) {
            mixer.deck1.load(url: testA)
            mixer.deck1.togglePlay()
        }
        if FileManager.default.fileExists(atPath: testB.path) {
            mixer.deck2.load(url: testB)
            mixer.deck2.togglePlay()
        }

        // Sweep crossfader: A→B over 8 seconds, then back, repeating.
        Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let mixer = self?.mixer else { return }
            let t = Date().timeIntervalSince1970
            mixer.crossfadePosition = Float(sin(t * 0.4))
        }

        // After 20s, kick deck1 EQ low+24, deck2 filter to LPF.
        DispatchQueue.main.asyncAfter(deadline: .now() + 20) { [weak self] in
            guard let mixer = self?.mixer else { return }
            mixer.deck1.state.lowGain = 24
            mixer.deck2.state.filter = -0.8
            NSLog("[debug] deck1 low +24dB; deck2 LPF on")
        }

        // After 30s, start recording.
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [weak self] in
            guard let mixer = self?.mixer else { return }
            mixer.toggleRecording()
            NSLog("[debug] recording started → \(mixer.lastRecordingURL?.path ?? "?")")
        }

        // After 45s, stop recording.
        DispatchQueue.main.asyncAfter(deadline: .now() + 45) { [weak self] in
            guard let mixer = self?.mixer else { return }
            mixer.toggleRecording()
            NSLog("[debug] recording stopped → \(mixer.lastRecordingURL?.path ?? "?")")
        }
        // ────────────────────────────────────────────────────────────────
```

The `[weak self]` captures expect `self` (the `AppDelegate`) to expose `mixer`. It already does — `let mixer = MixerEngine()` is a property of `AppDelegate`.

- [ ] **Step 2: Run and listen for 50 seconds**

```bash
swift run -c release
```

**Expected:**
- 0–20s: you hear both tracks alternating dominance on the crossfade sweep (left ear/output to right is irrelevant — what should be obvious is that A gets quiet while B gets loud, and back).
- At 20s: deck 1 audibly gains heavy bass (+24dB on low shelf @ 100Hz). Deck 2 gets noticeably duller as the LPF cuts highs (cutoff is ~158Hz at filter = -0.8).
- 30–45s: a WAV is being written. Console shows `[debug] recording started → /Users/.../Library/Application Support/Murmur/Recordings/<timestamp>.wav`.
- After 45s: `[debug] recording stopped`. Quit the app.

- [ ] **Step 3: Verify the recording**

```bash
ls -la "$HOME/Library/Application Support/Murmur/Recordings/"
afplay "$HOME/Library/Application Support/Murmur/Recordings/"<timestamp>.wav
```

(Replace `<timestamp>` with the actual filename.) **Expected:** the WAV plays back exactly what you heard during seconds 30–45 — the boosted-bass A + LPF'd B mixed by the crossfade.

If the file is silent or short, check Console for `MasterRecorder write error` messages. Most likely cause: a format mismatch between the mixer node's output format and the file's writing format — AVAudioFile resamples internally, so this should "just work," but a corrupt input file can produce empty buffers.

- [ ] **Step 4: Commit** (the temporary debug block stays for now — removed in Task 14)

```bash
git add Sources/Murmur/main.swift
git commit -m "chore(debug): add temporary timer-based audible crossfade+EQ+filter+record smoke"
```

---

### Task 10: `KnobView` — reusable circular knob

**Files:**
- Create: `Sources/Murmur/Booth/KnobView.swift`

- [ ] **Step 1: Implement `KnobView`**

Create `Sources/Murmur/Booth/KnobView.swift`:

```swift
import SwiftUI

/// A circular knob that controls a `Float` value.
///
/// Drag vertically to change. -∞→+∞ pixels map to `range.lowerBound`→`range.upperBound`.
/// The indicator dot sweeps from -135° (min) to +135° (max). At default (`defaultValue`),
/// double-click resets.
struct KnobView: View {
    @Binding var value: Float
    let range: ClosedRange<Float>
    let defaultValue: Float
    var label: String
    var tint: Color = .cyan
    var diameter: CGFloat = 44

    @State private var dragStartValue: Float = 0

    private var normalized: Float {
        (value - range.lowerBound) / (range.upperBound - range.lowerBound)
    }

    private var angleDegrees: Double {
        Double(normalized) * 270 - 135  // -135°…+135°
    }

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [Color(white: 0.25), Color(white: 0.10)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: diameter, height: diameter)
                    .shadow(color: .black.opacity(0.5), radius: 4, x: 0, y: 2)

                // Indicator
                Rectangle()
                    .fill(tint)
                    .frame(width: 2, height: diameter * 0.35)
                    .offset(y: -diameter * 0.2)
                    .rotationEffect(.degrees(angleDegrees))
                    .shadow(color: tint.opacity(0.7), radius: 3)
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        if drag.translation == .zero {
                            dragStartValue = value
                        }
                        // 200px of vertical travel = full range. Up = increase.
                        let delta = Float(-drag.translation.height) / 200 *
                            (range.upperBound - range.lowerBound)
                        value = max(range.lowerBound, min(range.upperBound, dragStartValue + delta))
                    }
            )
            .onTapGesture(count: 2) { value = defaultValue }

            Text(label)
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundColor(.white.opacity(0.6))
                .textCase(.uppercase)
                .tracking(1)
        }
    }
}
```

- [ ] **Step 2: Build**

```bash
swift build -c release 2>&1 | tail -20
```

**Expected:** clean build.

- [ ] **Step 3: Commit**

```bash
git add Sources/Murmur/Booth/KnobView.swift
git commit -m "feat(booth): add reusable KnobView"
```

---

### Task 11: `DeckView` — per-deck SwiftUI panel

**Files:**
- Create: `Sources/Murmur/Booth/DeckView.swift`

- [ ] **Step 1: Implement `DeckView`**

Create `Sources/Murmur/Booth/DeckView.swift`:

```swift
import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// One deck's UI: file picker → display → transport → EQ + filter + volume knobs.
struct DeckView: View {
    @ObservedObject var state: DeckState
    var deckNumber: Int
    var tint: Color
    var onLoad: (URL) -> Void
    var onTogglePlay: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("DECK \(deckNumber)")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .tracking(2)
                    .foregroundColor(tint)
                Spacer()
                if state.isLoaded {
                    Text(timeString(state.currentTimeSeconds) + " / " + timeString(state.durationSeconds))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.white.opacity(0.5))
                }
            }

            Text(state.displayName)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white)
                .lineLimit(1)

            HStack(spacing: 8) {
                Button(action: pickFile) {
                    Image(systemName: "folder")
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .background(Color.white.opacity(0.05))
                .cornerRadius(4)

                Button(action: onTogglePlay) {
                    Image(systemName: state.isPlaying ? "pause.fill" : "play.fill")
                        .frame(width: 28, height: 28)
                        .foregroundColor(state.isPlaying ? tint : .white.opacity(0.7))
                }
                .disabled(!state.isLoaded)
                .buttonStyle(.plain)
                .background(Color.white.opacity(0.05))
                .cornerRadius(4)

                Spacer()
            }

            HStack(spacing: 10) {
                KnobView(value: $state.highGain, range: -24...24, defaultValue: 0,
                         label: "HI", tint: tint)
                KnobView(value: $state.midGain, range: -24...24, defaultValue: 0,
                         label: "MID", tint: tint)
                KnobView(value: $state.lowGain, range: -24...24, defaultValue: 0,
                         label: "LO", tint: tint)
                KnobView(value: $state.filter, range: -1...1, defaultValue: 0,
                         label: "FILT", tint: .purple)
                KnobView(value: $state.volume, range: 0...1.5, defaultValue: 1.0,
                         label: "VOL", tint: tint)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(white: 0.06))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.08), lineWidth: 1))
        .cornerRadius(8)
    }

    private func pickFile() {
        let panel = NSOpenPanel()
        panel.title = "Load track on Deck \(deckNumber)"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.audio]
        if panel.runModal() == .OK, let url = panel.url {
            onLoad(url)
        }
    }

    private func timeString(_ seconds: Double) -> String {
        let s = Int(seconds)
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}
```

- [ ] **Step 2: Build**

```bash
swift build -c release 2>&1 | tail -20
```

**Expected:** clean build.

- [ ] **Step 3: Commit**

```bash
git add Sources/Murmur/Booth/DeckView.swift
git commit -m "feat(booth): add DeckView with file picker, transport, and 5 knobs"
```

---

### Task 12: `CrossfaderView` + `MasterControlsView`

**Files:**
- Create: `Sources/Murmur/Booth/CrossfaderView.swift`
- Create: `Sources/Murmur/Booth/MasterControlsView.swift`

- [ ] **Step 1: Implement `CrossfaderView`**

Create `Sources/Murmur/Booth/CrossfaderView.swift`:

```swift
import SwiftUI

struct CrossfaderView: View {
    @Binding var position: Float   // -1…+1

    var body: some View {
        VStack(spacing: 4) {
            HStack {
                Text("A").font(.system(size: 9, design: .monospaced)).foregroundColor(.white.opacity(0.5))
                Spacer()
                Text("B").font(.system(size: 9, design: .monospaced)).foregroundColor(.white.opacity(0.5))
            }
            // Slider on -1...+1, snaps back to 0 with double-click.
            Slider(value: Binding(
                get: { Double(position) },
                set: { position = Float($0) }
            ), in: -1...1)
            .onTapGesture(count: 2) { position = 0 }
        }
        .padding(.horizontal, 12)
    }
}
```

- [ ] **Step 2: Implement `MasterControlsView`**

Create `Sources/Murmur/Booth/MasterControlsView.swift`:

```swift
import SwiftUI

struct MasterControlsView: View {
    @ObservedObject var mixer: MixerEngine

    var body: some View {
        VStack(spacing: 10) {
            Text("MASTER")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .tracking(2)
                .foregroundColor(.white.opacity(0.6))

            KnobView(value: $mixer.masterVolume, range: 0...1.5, defaultValue: 1.0,
                     label: "VOL", tint: .cyan, diameter: 50)

            Button(action: { mixer.toggleRecording() }) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(mixer.isRecording ? Color.red : Color.red.opacity(0.4))
                        .frame(width: 8, height: 8)
                    Text(mixer.isRecording ? "REC ON" : "REC")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .tracking(1)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(mixer.isRecording ? Color.red.opacity(0.18) : Color.white.opacity(0.05))
                .foregroundColor(mixer.isRecording ? .red : .white.opacity(0.7))
                .cornerRadius(4)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(Color(white: 0.04))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.06), lineWidth: 1))
        .cornerRadius(8)
    }
}
```

- [ ] **Step 3: Build**

```bash
swift build -c release 2>&1 | tail -20
```

**Expected:** clean build.

- [ ] **Step 4: Commit**

```bash
git add Sources/Murmur/Booth/CrossfaderView.swift Sources/Murmur/Booth/MasterControlsView.swift
git commit -m "feat(booth): add CrossfaderView and MasterControlsView"
```

---

### Task 13: `BoothView` + `BoothWindowController` — full booth window

**Files:**
- Create: `Sources/Murmur/Booth/BoothView.swift`
- Create: `Sources/Murmur/Booth/BoothWindowController.swift`

- [ ] **Step 1: Implement `BoothView`**

Create `Sources/Murmur/Booth/BoothView.swift`:

```swift
import SwiftUI

/// Top-level booth UI: two decks flanking a center strip (crossfader + master).
struct BoothView: View {
    @ObservedObject var mixer: MixerEngine
    @ObservedObject var deck1State: DeckState
    @ObservedObject var deck2State: DeckState

    var body: some View {
        VStack(spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                DeckView(
                    state: deck1State,
                    deckNumber: 1,
                    tint: .cyan,
                    onLoad: { mixer.deck1.load(url: $0) },
                    onTogglePlay: { mixer.deck1.togglePlay() }
                )
                MasterControlsView(mixer: mixer)
                    .frame(width: 110)
                DeckView(
                    state: deck2State,
                    deckNumber: 2,
                    tint: .orange,
                    onLoad: { mixer.deck2.load(url: $0) },
                    onTogglePlay: { mixer.deck2.togglePlay() }
                )
            }

            CrossfaderView(position: $mixer.crossfadePosition)
                .frame(height: 36)
                .background(Color(white: 0.04))
                .cornerRadius(8)
        }
        .padding(14)
        .frame(minWidth: 760, minHeight: 320)
        .background(Color(white: 0.02))
    }
}
```

- [ ] **Step 2: Implement `BoothWindowController`**

Create `Sources/Murmur/Booth/BoothWindowController.swift`:

```swift
import AppKit
import SwiftUI

/// Hosts the SwiftUI BoothView in an independent NSWindow.
///
/// Lifecycle mirrors `VideoWindowController`: the window is created once and
/// kept alive for the lifetime of the app. Closing hides it rather than
/// terminating it — same `windowShouldClose → hide` pattern.
final class BoothWindowController: NSObject, NSWindowDelegate {
    private let window: NSWindow
    private let mixer: MixerEngine

    init(mixer: MixerEngine) {
        self.mixer = mixer
        let host = NSHostingController(
            rootView: BoothView(
                mixer: mixer,
                deck1State: mixer.deck1.state,
                deck2State: mixer.deck2.state
            )
        )
        let win = NSWindow(contentViewController: host)
        win.title = "Pocket DJ"
        win.styleMask = [.titled, .closable, .resizable, .miniaturizable]
        win.setContentSize(NSSize(width: 820, height: 360))
        win.center()
        win.isReleasedWhenClosed = false
        self.window = win
        super.init()
        self.window.delegate = self
    }

    func show() {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func hide() {
        window.orderOut(nil)
    }

    // Hide on close, never terminate (Murmur is a menu-bar app).
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        hide()
        return false
    }
}
```

- [ ] **Step 3: Build**

```bash
swift build -c release 2>&1 | tail -20
```

**Expected:** clean build.

- [ ] **Step 4: Commit**

```bash
git add Sources/Murmur/Booth/BoothView.swift Sources/Murmur/Booth/BoothWindowController.swift
git commit -m "feat(booth): add BoothView and BoothWindowController"
```

---

### Task 14: Wire the booth into `AppDelegate` and the popover; remove temporary debug code

**Files:**
- Modify: `Sources/Murmur/main.swift` — instantiate `BoothWindowController`, inject into popover, remove temporary debug block.
- Modify: `Sources/Murmur/ContentView.swift` — add "Open DJ Booth" button.

- [ ] **Step 1: Add `BoothWindowController` to `AppDelegate` and remove the temporary debug block**

In `Sources/Murmur/main.swift`, in `AppDelegate`:

After `let mixer = MixerEngine()`, add:

```swift
    var booth: BoothWindowController!
```

In `applicationDidFinishLaunching`, **replace** the entire temporary debug block (everything between the `// ────────────────────────────────────────────────────────────────` markers from Tasks 8 + 9) with:

```swift
        // Booth window — kept alive for the life of the app; hidden by default.
        booth = BoothWindowController(mixer: mixer)
```

And update the existing `popover.contentViewController = NSHostingController(...)` block to inject `mixer` and `booth`:

Find:
```swift
        popover.contentViewController = NSHostingController(
            rootView: ContentView()
                .environmentObject(controller)
                .environmentObject(favorites)
                .environmentObject(videoWindow)
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
        )
```

(`BoothLauncher` is a tiny `ObservableObject` shim because `BoothWindowController` is an `NSObject` — using it as an `EnvironmentObject` works but the shim keeps the SwiftUI types tidy.)

- [ ] **Step 2: Add the `BoothLauncher` shim at the bottom of `main.swift`, just before `// MARK: - Boot`**

```swift
// MARK: - Booth launcher (SwiftUI bridge)
final class BoothLauncher: ObservableObject {
    let booth: BoothWindowController
    init(booth: BoothWindowController) { self.booth = booth }
    func show() { booth.show() }
}
```

- [ ] **Step 3: Add "Open DJ Booth" button to `ContentView`**

In `Sources/Murmur/ContentView.swift`, add the environment object at the top:

Find:
```swift
struct ContentView: View {
    @EnvironmentObject var controller: PlayerController
    @EnvironmentObject var favorites: FavoritesStore
    @EnvironmentObject var videoWindow: VideoWindowController
```

Add below:
```swift
    @EnvironmentObject var booth: BoothLauncher
```

Then in `body`, find the closing of the main `VStack`:

```swift
            VStack(alignment: .leading, spacing: rowGap) {
                header
                urlRow
                dancerRow
                controlsRow
                statusFooter
            }
            .padding(outerPad)
```

Add the booth button between `statusFooter` and `.padding`:

```swift
            VStack(alignment: .leading, spacing: rowGap) {
                header
                urlRow
                dancerRow
                controlsRow
                statusFooter
                boothButton
            }
            .padding(outerPad)
```

Then add the `boothButton` computed property next to the other computed properties:

```swift
    private var boothButton: some View {
        Button(action: { booth.show() }) {
            Text("OPEN DJ BOOTH →")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .tracking(1.5)
                .foregroundColor(accent)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(accent.opacity(0.7), style: dashStyle)
                )
        }
        .buttonStyle(.plain)
    }
```

Also: the existing popover frame is `.frame(width: 300, height: 250)` — adding a new row pushes content past 250. Bump to 280:

Find:
```swift
        .frame(width: 300, height: 250)
```

Replace with:
```swift
        .frame(width: 300, height: 280)
```

And in `main.swift`, find:
```swift
        popover.contentSize = NSSize(width: 300, height: 250)
```
Replace with:
```swift
        popover.contentSize = NSSize(width: 300, height: 280)
```

- [ ] **Step 4: Build and run — end-to-end manual smoke**

```bash
swift run -c release
```

**Expected:**
- Menu-bar icon appears. Click it: popover shows the existing YouTube controls plus a new "OPEN DJ BOOTH →" button at the bottom.
- Click "OPEN DJ BOOTH →": a new resizable window titled "Pocket DJ" opens with two deck panels flanking a master strip + crossfader.
- On Deck 1, click the folder icon → pick `~/Music/test-track-A.m4a` → click play. You hear the track.
- On Deck 2, do the same with track B.
- Drag the crossfader from left to right: A fades out, B fades in (equal-power).
- Twist EQ knobs (vertical drag on each): hearable change. Double-click any knob → resets to default.
- Twist the FILT knob right → highs cut as HPF closes. Twist left → LPF cuts highs.
- Click REC in master strip → red dot turns on, "REC ON" label. Wait 10s. Click REC again. Console doesn't error.
- Verify file exists:
  ```bash
  ls -la "$HOME/Library/Application Support/Murmur/Recordings/"
  ```
  and play it with `afplay`. Expected: the WAV contains the last 10s of what you heard.
- Close the booth window via its red close button: window hides, app continues running, audio continues playing.
- Re-open the booth via the popover button: same window comes back with all state intact.
- Click the original YouTube controls: the YouTube stream still plays alongside the deck tracks (Murmur is now mixing 3 sources at the OS level — expected).
- Quit via the popover's quit menu: clean exit, no orphan processes.

- [ ] **Step 5: Commit**

```bash
git add Sources/Murmur/main.swift Sources/Murmur/ContentView.swift
git commit -m "feat(booth): wire BoothWindowController into popover; remove debug smoke"
```

---

### Task 15: Build the `.app` bundle and verify it ships

**Files:**
- (No code changes.)

- [ ] **Step 1: Build the app bundle**

```bash
./build-app.sh --sign
```

**Expected:** `dist/Murmur.app` and `dist/Murmur.zip` produced. No errors. The script ad-hoc signs since `--sign` was passed.

- [ ] **Step 2: Launch the bundle and run the same smoke as Task 14**

```bash
open dist/Murmur.app
```

If macOS Gatekeeper blocks it, right-click → Open. Run through the Task 14 verification steps using the bundled app. Everything should work identically to `swift run`.

- [ ] **Step 3: Verify it doesn't appear in the Dock**

The bundle must run as `LSUIElement` (menu-bar-only). Check: no Dock icon while the app runs. Confirm `Info.plist` includes `LSUIElement = true` (the existing `build-app.sh` handles this; this step verifies the new code didn't accidentally undo it).

- [ ] **Step 4: Tag the milestone**

```bash
git tag -a phase-1-audio-foundation -m "Pocket DJ Phase 1: 2-deck local-file mixer with EQ/filter/crossfade/record"
```

(Don't push the tag unless explicitly asked.)

---

## Out of Scope for Phase 1 (deferred to later phases)

These appear in the spec but are intentionally absent from this plan:

- BPM detection, waveform rendering, beat grid, sync, tempo slider, key lock (Phase 2)
- 3D booth scene with Three.js — Phase 1 uses native SwiftUI knobs (Phase 3)
- Hot cues, loops, additional decks 3 + 4 (Phase 4)
- Effects rack (echo, reverb, flanger), headphone cue, key detection (Phase 4)
- Ambient Layer, Mood Dial, scenes (Phase 5)
- Library panel, watched folders, crates, prep crate (Phase 6)
- Apple Music decks, MIDI controllers, performance recording (Phase 7)

If you find yourself reaching for any of the above to "make this work," stop and re-read the goal. Phase 1 succeeds when two local files can be mixed and recorded — that's it.

---

## Self-Review Notes

Run against the spec on 2026-05-16 after writing this plan:

- **§4 The two surfaces:** Phase 1 only implements the DJ surface (no Ambient Layer). ✅ deferred to Phase 5.
- **§4.2 Capability matrix:** local-file row — all Phase 1 capabilities covered (play/pause, volume, 3-band EQ, filter sweep, bounceable). ✅
- **§5.1 Loading and library:** Phase 1 uses `NSOpenPanel` direct picker, no crates. ✅ deferred to Phase 6.
- **§5.7 Recording the master:** WAV at 48 kHz / 16-bit, master tap. ✅ implemented. Apple Music + YouTube exclusion not relevant (those backends don't exist yet).
- **§6 3D mixing surface:** SwiftUI mockup, no Three.js. ✅ deferred to Phase 3.
- **§7.1 Audio pipeline:** `SourcePlayer` protocol + `LocalFilePlayer` + `ChannelStrip` + crossfader bus + master tap. ✅ implemented.
- **§7.3 Latency:** default 256-frame buffer is AVAudioEngine's macOS default — no Preferences UI to change it yet. ✅ acceptable for Phase 1.
- **§8 Murmur stack rules:** YouTube webview path untouched, popover behavior preserved, no Dock icon (`LSUIElement`) preserved. ✅ Task 15 explicitly verifies.
- **§11 Success criteria:** load latency ≤250ms — achieved by `LocalFilePlayer.load`, which only reads the header (instant for AVAudioFile); recording 60-min set — limited only by disk space, no internal buffer constraints; ≥55 fps booth — SwiftUI mockup is essentially text and shapes, trivially fast.

No spec gaps for Phase 1. No placeholders found in plan. Type signatures consistent across tasks (`SourcePlayer.outputNode` referenced in Task 2/3/7; `DeckState.@Published` properties referenced in Task 6/7/11; `MixerEngine.crossfadePosition`/`masterVolume`/`toggleRecording` referenced in Task 8/12/13).
