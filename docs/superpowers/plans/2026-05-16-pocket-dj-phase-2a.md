# Pocket DJ Phase 2a — Beatmatching Foundation

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make two local-file decks audibly beatmatched. Detect BPM and waveform peaks on load, render a scrollable waveform with beat-grid markers, let the user tempo-shift each deck with optional key-lock, and provide a single SYNC button that locks the slave deck to the master's tempo.

**Architecture:** A new `Analysis/` module owns background analysis: `PeakExtractor` decodes audio to a compact waveform peaks array; `BPMDetector` runs an amplitude-onset autocorrelation; `AnalysisService` orchestrates them on a background queue and writes results into `LibraryIndex` (JSON in Application Support). `ChannelStrip` gains an `AVAudioUnitTimePitch` between the source and EQ chain to provide tempo + optional key-lock. `MixerEngine` adds a `masterDeckId` and a `sync(slave:)` method. `DeckView` gets a waveform area, tempo slider, and SYNC / KEY-LOCK / MASTER controls. All analysis results are cached so a second load of the same file is instant.

**Tech Stack:** Swift 5.9+, AVFoundation (`AVAudioFile`, `AVAudioUnitTimePitch`), Accelerate (`vDSP_rmsqv` for fast RMS), SwiftUI Canvas for waveform rendering. macOS 13+. No new SwiftPM dependencies.

**On testing:** Same as Phase 1 — `CLAUDE.md` rules out `swift test`. Verify each task with `swift build -c release` + a focused manual smoke step. For the algorithmic tasks (BPM detection, peak extraction) the manual smoke prints results to `NSLog` so you can compare against a track of known BPM.

**Prerequisites:**
- Phase 1 complete and merged into the working branch (the booth window must already be functional).
- Two test audio files with **known BPM** (look it up on the track's website / Wikipedia / Beatport):
  - `~/Music/test-track-A.m4a` — e.g., something solidly in the 100-130 BPM range with clear drums.
  - `~/Music/test-track-B.m4a` — different BPM (ideally 5-10 BPM off A) for sync testing.

---

## File Structure

**New files:**

```
Sources/Murmur/Analysis/
  TrackMetadata.swift        Codable struct: bpm, duration, firstBeat, peaksPath
  LibraryIndex.swift         JSON-backed track cache at ~/Library/Application Support/Murmur/library.json
  PeakExtractor.swift        Decodes audio file → fixed-count min/max peak pairs
  BPMDetector.swift          Amplitude-onset autocorrelation with octave correction
  AnalysisService.swift      Background queue orchestrating PeakExtractor + BPMDetector + LibraryIndex
Sources/Murmur/Booth/
  WaveformView.swift         SwiftUI Canvas rendering peaks + playhead
  BeatGridOverlay.swift      Beat-mark vertical lines + draggable first-downbeat handle
  TempoSliderView.swift      Per-deck tempo control (±8% default)
  SyncControlsView.swift     SYNC button + KEY-LOCK toggle + MASTER badge
```

**Modified files:**

- `Sources/Murmur/Audio/ChannelStrip.swift` — insert `AVAudioUnitTimePitch` at the head of the chain, expose `rate` and `pitch`.
- `Sources/Murmur/Decks/DeckState.swift` — add `bpm`, `firstBeat`, `peaks`, `tempoRate`, `keyLock`, `isMaster`.
- `Sources/Murmur/Decks/DeckController.swift` — trigger analysis on load, subscribe to results, wire tempo/key-lock/firstBeat into the strip.
- `Sources/Murmur/Decks/MixerEngine.swift` — add `masterDeckId`, `setMaster(_:)`, `sync(slave:)`.
- `Sources/Murmur/Booth/DeckView.swift` — insert waveform area, tempo slider, sync controls, BPM display.

---

### Task 1: TrackMetadata + LibraryIndex

**Files:**
- Create: `Sources/Murmur/Analysis/TrackMetadata.swift`
- Create: `Sources/Murmur/Analysis/LibraryIndex.swift`

- [ ] **Step 1: Create `TrackMetadata.swift`**

```swift
import Foundation

/// Cached analysis output for a single file.
/// `peaksPath` references a sidecar binary file written by `PeakExtractor`.
struct TrackMetadata: Codable, Equatable {
    let bpm: Double
    let duration: Double
    /// Seconds offset to the first downbeat. Defaults to 0; user-adjustable.
    var firstBeat: Double
    /// Filename (not full path) of the peaks sidecar inside the peaks directory.
    let peaksPath: String
}
```

- [ ] **Step 2: Create `LibraryIndex.swift`**

```swift
import Foundation

/// JSON-backed cache of analysis results keyed by absolute file path.
///
/// The index is loaded on init from
/// `~/Library/Application Support/Murmur/library.json` and persisted on every
/// write. Reads are O(1); writes serialize the entire index (small enough at
/// this stage that incremental serialization isn't worth the complexity).
final class LibraryIndex {
    static let shared = LibraryIndex()

    private(set) var tracks: [String: TrackMetadata] = [:]
    private let url: URL
    private let queue = DispatchQueue(label: "murmur.library-index")

    private init() {
        let appSupport = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
            .appendingPathComponent("Murmur", isDirectory: true)
        try? FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
        self.url = appSupport.appendingPathComponent("library.json")
        load()
    }

    /// Where peak sidecar files live.
    static var peaksDirectory: URL {
        let dir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
            .appendingPathComponent("Murmur", isDirectory: true)
            .appendingPathComponent("peaks", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func metadata(forPath path: String) -> TrackMetadata? {
        queue.sync { tracks[path] }
    }

    func setMetadata(_ metadata: TrackMetadata, forPath path: String) {
        queue.sync {
            tracks[path] = metadata
            save()
        }
    }

    /// Update only the firstBeat (user-adjusted downbeat).
    func setFirstBeat(_ firstBeat: Double, forPath path: String) {
        queue.sync {
            guard var existing = tracks[path] else { return }
            existing.firstBeat = firstBeat
            tracks[path] = existing
            save()
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([String: TrackMetadata].self, from: data) else {
            return
        }
        tracks = decoded
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(tracks)
            try data.write(to: url, options: .atomic)
        } catch {
            NSLog("LibraryIndex save error: \(error)")
        }
    }
}
```

- [ ] **Step 3: Verify build**

```bash
cd /Users/mm/Documents/youtube-audio-widget
swift build -c release 2>&1 | tail -5
```

Expected: clean build.

- [ ] **Step 4: Commit**

```bash
git add Sources/Murmur/Analysis/TrackMetadata.swift Sources/Murmur/Analysis/LibraryIndex.swift
git commit -m "feat(analysis): add TrackMetadata + LibraryIndex JSON cache"
```

---

### Task 2: PeakExtractor

**Files:**
- Create: `Sources/Murmur/Analysis/PeakExtractor.swift`

- [ ] **Step 1: Implement `PeakExtractor`**

```swift
import AVFoundation
import Accelerate

/// Decodes an audio file into a fixed-count array of (min, max) sample pairs
/// for waveform rendering.
///
/// Output is interleaved: `[min0, max0, min1, max1, ...]`. The total pair
/// count is `binCount` regardless of source duration — short files produce
/// fine-grained bins, long files produce coarser bins.
enum PeakExtractor {
    /// Synchronously extract peaks. Call from a background queue.
    static func extract(from url: URL, binCount: Int = 2000) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        let totalFrames = AVAudioFrameCount(file.length)
        let framesPerBin = max(1, Int(totalFrames) / binCount)

        // Read in chunks; downmix to mono on the fly.
        let chunkFrames: AVAudioFrameCount = AVAudioFrameCount(framesPerBin * 4)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunkFrames) else {
            throw NSError(domain: "PeakExtractor", code: 1)
        }

        var peaks = [Float]()
        peaks.reserveCapacity(binCount * 2)

        var binAccumMin: Float = .greatestFiniteMagnitude
        var binAccumMax: Float = -.greatestFiniteMagnitude
        var samplesInBin: Int = 0

        while file.framePosition < file.length {
            try file.read(into: buffer)
            let frameCount = Int(buffer.frameLength)
            if frameCount == 0 { break }
            guard let channelData = buffer.floatChannelData else { continue }
            let channelCount = Int(format.channelCount)

            for frame in 0..<frameCount {
                // Downmix: average across channels.
                var sample: Float = 0
                for ch in 0..<channelCount {
                    sample += channelData[ch][frame]
                }
                sample /= Float(channelCount)

                binAccumMin = min(binAccumMin, sample)
                binAccumMax = max(binAccumMax, sample)
                samplesInBin += 1

                if samplesInBin >= framesPerBin && peaks.count < binCount * 2 {
                    peaks.append(binAccumMin)
                    peaks.append(binAccumMax)
                    binAccumMin = .greatestFiniteMagnitude
                    binAccumMax = -.greatestFiniteMagnitude
                    samplesInBin = 0
                }
            }
        }
        // Drain remaining samples into a final bin if room.
        if samplesInBin > 0 && peaks.count < binCount * 2 {
            peaks.append(binAccumMin)
            peaks.append(binAccumMax)
        }
        return peaks
    }

    /// Write a `[Float]` peaks array to a sidecar file as raw Float32.
    static func writePeaks(_ peaks: [Float], to url: URL) throws {
        try peaks.withUnsafeBufferPointer { buf in
            let data = Data(buffer: buf)
            try data.write(to: url, options: .atomic)
        }
    }

    /// Read a peaks sidecar file back into a `[Float]`.
    static func readPeaks(from url: URL) throws -> [Float] {
        let data = try Data(contentsOf: url)
        return data.withUnsafeBytes { raw -> [Float] in
            let floats = raw.bindMemory(to: Float.self)
            return Array(floats)
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
git add Sources/Murmur/Analysis/PeakExtractor.swift
git commit -m "feat(analysis): add PeakExtractor for waveform peaks"
```

---

### Task 3: BPMDetector

**Files:**
- Create: `Sources/Murmur/Analysis/BPMDetector.swift`

- [ ] **Step 1: Implement `BPMDetector`**

```swift
import AVFoundation
import Accelerate

/// Detects BPM via amplitude-onset autocorrelation.
///
/// Algorithm:
///   1. Decode full file to mono Float32 (mixing channels).
///   2. Compute frame-RMS envelope at hopSize=512 samples.
///   3. Half-wave rectified first-order difference (= onset envelope).
///   4. Autocorrelate onset at lags corresponding to 60-180 BPM.
///   5. Octave correction: if peak BPM > 140 and BPM/2 has correlation ≥ 0.7 * peak,
///      prefer the lower BPM.
///
/// Naive O(N·L) autocorrelation is fine here — for a 4-min file the envelope
/// is ~10k samples and L ≈ 30 lags, so ~300k mul-adds. Well under a second
/// on M1.
enum BPMDetector {
    static let hopSize = 512
    static let minBPM: Double = 60
    static let maxBPM: Double = 180

    /// Synchronously detect BPM. Call from a background queue.
    static func detect(from url: URL) throws -> Double {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        let sampleRate = format.sampleRate
        let totalFrames = AVAudioFrameCount(file.length)

        // 1) Read whole file, downmix to mono.
        let mono = try readMono(file: file, totalFrames: totalFrames)

        // 2) Frame RMS envelope.
        let envelope = rmsEnvelope(mono: mono, hopSize: hopSize)

        // 3) Onset = half-wave rectified first difference.
        let onset = onsetEnvelope(envelope: envelope)

        // 4) Autocorrelation in BPM lag range.
        let frameRate = sampleRate / Double(hopSize)
        let minLag = Int(frameRate * 60.0 / maxBPM)
        let maxLag = Int(frameRate * 60.0 / minBPM)
        var bestLag = minLag
        var bestCorr: Float = 0
        var corrAtLag = [Int: Float]()
        for lag in minLag...maxLag {
            let n = onset.count - lag
            if n <= 0 { break }
            var corr: Float = 0
            for i in 0..<n {
                corr += onset[i] * onset[i + lag]
            }
            corrAtLag[lag] = corr
            if corr > bestCorr {
                bestCorr = corr
                bestLag = lag
            }
        }
        var bpm = 60.0 * frameRate / Double(bestLag)

        // 5) Octave correction.
        if bpm > 140 {
            let halfLag = Int(frameRate * 60.0 / (bpm / 2))
            if let halfCorr = corrAtLag[halfLag], halfCorr >= 0.7 * bestCorr {
                bpm = bpm / 2
            }
        }
        return bpm
    }

    private static func readMono(file: AVAudioFile, totalFrames: AVAudioFrameCount) throws -> [Float] {
        let format = file.processingFormat
        let chunkFrames: AVAudioFrameCount = 32768
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunkFrames) else {
            throw NSError(domain: "BPMDetector", code: 1)
        }
        var mono = [Float]()
        mono.reserveCapacity(Int(totalFrames))

        while file.framePosition < file.length {
            try file.read(into: buffer)
            let frameCount = Int(buffer.frameLength)
            if frameCount == 0 { break }
            guard let channelData = buffer.floatChannelData else { continue }
            let channelCount = Int(format.channelCount)

            for frame in 0..<frameCount {
                var sample: Float = 0
                for ch in 0..<channelCount {
                    sample += channelData[ch][frame]
                }
                mono.append(sample / Float(channelCount))
            }
        }
        return mono
    }

    private static func rmsEnvelope(mono: [Float], hopSize: Int) -> [Float] {
        let numHops = mono.count / hopSize
        var env = [Float](repeating: 0, count: numHops)
        mono.withUnsafeBufferPointer { ptr in
            for i in 0..<numHops {
                var rms: Float = 0
                vDSP_rmsqv(ptr.baseAddress!.advanced(by: i * hopSize),
                           1, &rms, vDSP_Length(hopSize))
                env[i] = rms
            }
        }
        return env
    }

    private static func onsetEnvelope(envelope: [Float]) -> [Float] {
        var onset = [Float](repeating: 0, count: envelope.count)
        for i in 1..<envelope.count {
            onset[i] = max(0, envelope[i] - envelope[i-1])
        }
        return onset
    }
}
```

- [ ] **Step 2: Verify build**

```bash
swift build -c release 2>&1 | tail -5
```

- [ ] **Step 3: Commit**

```bash
git add Sources/Murmur/Analysis/BPMDetector.swift
git commit -m "feat(analysis): add BPMDetector with octave correction"
```

---

### Task 4: AnalysisService

**Files:**
- Create: `Sources/Murmur/Analysis/AnalysisService.swift`

- [ ] **Step 1: Implement `AnalysisService`**

```swift
import AVFoundation
import Combine
import Foundation

/// Orchestrates background analysis of an audio file.
///
/// On `analyze(url:)`, checks the `LibraryIndex` first. If cached, the cached
/// metadata + sidecar peaks are returned via the completion immediately. If
/// not, queues both PeakExtractor and BPMDetector on the analysis queue,
/// writes the results, and fires completion.
///
/// One analysis per file at a time; calling `analyze(url:)` twice for the same
/// URL while the first is in-flight returns the same result to both callers.
final class AnalysisService {
    static let shared = AnalysisService()

    struct Result {
        let url: URL
        let metadata: TrackMetadata
        let peaks: [Float]
    }

    private let queue = DispatchQueue(label: "murmur.analysis", qos: .userInitiated)
    private let resultQueue = DispatchQueue.main
    private var inFlight: [String: [(Result?) -> Void]] = [:]
    private let inFlightLock = NSLock()

    private init() {}

    func analyze(url: URL, completion: @escaping (Result?) -> Void) {
        let path = url.path

        // 1) Cache hit.
        if let cached = LibraryIndex.shared.metadata(forPath: path) {
            let peaksURL = LibraryIndex.peaksDirectory.appendingPathComponent(cached.peaksPath)
            if FileManager.default.fileExists(atPath: peaksURL.path),
               let peaks = try? PeakExtractor.readPeaks(from: peaksURL) {
                resultQueue.async {
                    completion(Result(url: url, metadata: cached, peaks: peaks))
                }
                return
            }
        }

        // 2) Coalesce concurrent requests for the same path.
        inFlightLock.lock()
        if var callbacks = inFlight[path] {
            callbacks.append(completion)
            inFlight[path] = callbacks
            inFlightLock.unlock()
            return
        }
        inFlight[path] = [completion]
        inFlightLock.unlock()

        // 3) Run analysis.
        queue.async {
            let result = self.runAnalysis(url: url)
            self.inFlightLock.lock()
            let callbacks = self.inFlight.removeValue(forKey: path) ?? []
            self.inFlightLock.unlock()
            self.resultQueue.async {
                for cb in callbacks { cb(result) }
            }
        }
    }

    private func runAnalysis(url: URL) -> Result? {
        do {
            let peaks = try PeakExtractor.extract(from: url)
            let bpm = try BPMDetector.detect(from: url)
            let file = try AVAudioFile(forReading: url)
            let duration = Double(file.length) / file.processingFormat.sampleRate

            // Write peaks sidecar.
            let peaksFilename = url.deletingPathExtension().lastPathComponent + "-" +
                String(url.path.hashValue, radix: 16) + ".peaks"
            let peaksURL = LibraryIndex.peaksDirectory.appendingPathComponent(peaksFilename)
            try PeakExtractor.writePeaks(peaks, to: peaksURL)

            let metadata = TrackMetadata(bpm: bpm, duration: duration, firstBeat: 0, peaksPath: peaksFilename)
            LibraryIndex.shared.setMetadata(metadata, forPath: url.path)

            NSLog("[Analysis] %@ → BPM=%.2f, duration=%.1fs", url.lastPathComponent, bpm, duration)
            return Result(url: url, metadata: metadata, peaks: peaks)
        } catch {
            NSLog("[Analysis] failed for \(url.lastPathComponent): \(error)")
            return nil
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
git add Sources/Murmur/Analysis/AnalysisService.swift
git commit -m "feat(analysis): add AnalysisService orchestrating peaks + BPM"
```

---

### Task 5: Insert TimePitch into ChannelStrip

**Files:**
- Modify: `Sources/Murmur/Audio/ChannelStrip.swift`

This task changes the signal flow inside the strip so tempo and pitch are controllable. The current chain is `[source] → eq3band → filterEQ → volume`. The new chain is `[source] → timePitch → eq3band → filterEQ → volume`.

- [ ] **Step 1: Add `timePitch` to `ChannelStrip`**

Open `Sources/Murmur/Audio/ChannelStrip.swift`. Find the properties block at the top of the class:

```swift
    let eq3band: AVAudioUnitEQ
    let filterEQ: AVAudioUnitEQ
    let volume = AVAudioMixerNode()
```

Insert a new property after `let volume`:

```swift
    /// Tempo + pitch control. `rate` 1.0 = normal speed, `pitch` in cents
    /// (-2400 to +2400). Key-lock = "rate changes, pitch stays at 0".
    let timePitch = AVAudioUnitTimePitch()
```

Then add accessors above the `init`:

```swift
    /// 1.0 = normal speed. Valid range 1/32 to 32; clamped to ±50% in practice.
    var rate: Float {
        get { timePitch.rate }
        set { timePitch.rate = max(0.5, min(2.0, newValue)) }
    }

    /// Pitch shift in cents, ±2400. 0 = no shift.
    var pitch: Float {
        get { timePitch.pitch }
        set { timePitch.pitch = max(-2400, min(2400, newValue)) }
    }
```

- [ ] **Step 2: Wire `timePitch` into the engine chain inside `init`**

Find the `init(engine:)` body. After the filter EQ setup block (search for `f.gain = 0`), find the existing block:

```swift
        engine.attach(eq3band)
        engine.attach(filterEQ)
        engine.attach(volume)

        // Internal connections: eq3band → filterEQ → volume.
        engine.connect(eq3band, to: filterEQ, format: nil)
        engine.connect(filterEQ, to: volume, format: nil)
```

Replace with:

```swift
        engine.attach(timePitch)
        engine.attach(eq3band)
        engine.attach(filterEQ)
        engine.attach(volume)

        // Internal connections: timePitch → eq3band → filterEQ → volume.
        engine.connect(timePitch, to: eq3band, format: nil)
        engine.connect(eq3band, to: filterEQ, format: nil)
        engine.connect(filterEQ, to: volume, format: nil)
```

- [ ] **Step 3: Update `connectSource` so the source feeds `timePitch`, not `eq3band`**

Find:

```swift
    func connectSource(_ source: SourcePlayer) {
        engine.connect(source.outputNode, to: eq3band, format: nil)
    }
```

Replace with:

```swift
    func connectSource(_ source: SourcePlayer) {
        engine.connect(source.outputNode, to: timePitch, format: nil)
    }
```

- [ ] **Step 4: Verify build**

```bash
swift build -c release 2>&1 | tail -5
```

- [ ] **Step 5: Commit**

```bash
git add Sources/Murmur/Audio/ChannelStrip.swift
git commit -m "feat(audio): insert AVAudioUnitTimePitch into ChannelStrip"
```

---

### Task 6: DeckState additions

**Files:**
- Modify: `Sources/Murmur/Decks/DeckState.swift`

- [ ] **Step 1: Add the new published properties**

Open `Sources/Murmur/Decks/DeckState.swift`. Find the existing `@Published` properties. After the existing block, add:

```swift
    // ── Phase 2a: analysis + beatmatching ─────────────────────────────────

    /// Detected BPM, or 0 if not yet analyzed.
    @Published var bpm: Double = 0
    /// Seconds offset to the first downbeat (user-adjustable post-analysis).
    @Published var firstBeat: Double = 0
    /// Waveform peaks: interleaved min/max pairs. Empty until analysis completes.
    @Published var peaks: [Float] = []

    /// Tempo rate, 0.92…1.08 for ±8%. 1.0 = unmodified.
    @Published var tempoRate: Float = 1.0
    /// When true, tempo changes preserve pitch (uses TimePitch.rate only).
    /// When false, varispeed: pitch shifts with rate.
    @Published var keyLock: Bool = true
    /// True when this deck is the sync master.
    @Published var isMaster: Bool = false
```

- [ ] **Step 2: Verify build**

```bash
swift build -c release 2>&1 | tail -5
```

- [ ] **Step 3: Commit**

```bash
git add Sources/Murmur/Decks/DeckState.swift
git commit -m "feat(decks): add Phase 2a state — bpm, peaks, tempo, keyLock, isMaster"
```

---

### Task 7: DeckController — analysis + tempo wiring

**Files:**
- Modify: `Sources/Murmur/Decks/DeckController.swift`

- [ ] **Step 1: Trigger analysis on load**

Find the `load(url:)` method. Replace the entire method with:

```swift
    func load(url: URL) {
        do {
            try player.load(url: url)
            state.displayName = player.displayName
            state.isLoaded = true
            state.durationSeconds = player.durationSeconds
            state.currentTimeSeconds = 0
            state.isPlaying = false
            // Reset analysis-derived state until we have new results.
            state.bpm = 0
            state.firstBeat = 0
            state.peaks = []

            AnalysisService.shared.analyze(url: url) { [weak self] result in
                guard let self = self, let result = result else { return }
                // Guard: only apply if the user hasn't loaded a different track
                // in the meantime.
                guard self.player.isLoaded,
                      self.state.displayName == result.url.deletingPathExtension().lastPathComponent
                else { return }
                self.state.bpm = result.metadata.bpm
                self.state.firstBeat = result.metadata.firstBeat
                self.state.peaks = result.peaks
            }
        } catch {
            NSLog("DeckController load error: \(error)")
            player.pause()
            state.isLoaded = false
            state.displayName = "Load failed"
            state.durationSeconds = 0
            state.currentTimeSeconds = 0
            state.isPlaying = false
            state.bpm = 0
            state.firstBeat = 0
            state.peaks = []
        }
    }
```

- [ ] **Step 2: Wire tempo + key-lock + firstBeat persistence into the bindings**

Find `wireStateBindings()`. Replace its body with:

```swift
    private func wireStateBindings() {
        state.$volume.sink { [weak self] v in self?.strip.fader = v }.store(in: &cancellables)
        state.$lowGain.sink { [weak self] v in self?.strip.lowGain = v }.store(in: &cancellables)
        state.$midGain.sink { [weak self] v in self?.strip.midGain = v }.store(in: &cancellables)
        state.$highGain.sink { [weak self] v in self?.strip.highGain = v }.store(in: &cancellables)
        state.$filter.sink { [weak self] v in self?.strip.filterPosition = v }.store(in: &cancellables)

        // Tempo + key-lock: combineLatest so a change to either re-applies both.
        state.$tempoRate
            .combineLatest(state.$keyLock)
            .sink { [weak self] (rate, keyLock) in
                guard let self = self else { return }
                self.strip.rate = rate
                // Varispeed: pitch shift = 1200 * log2(rate). Key-lock: pitch = 0.
                self.strip.pitch = keyLock ? 0 : 1200 * log2(rate)
            }
            .store(in: &cancellables)

        // Persist user-adjusted firstBeat.
        state.$firstBeat
            .dropFirst() // skip the initial 0 emitted on assignment
            .sink { [weak self] firstBeat in
                guard let player = self?.player, let url = player.loadedURL else { return }
                LibraryIndex.shared.setFirstBeat(firstBeat, forPath: url.path)
            }
            .store(in: &cancellables)
    }
```

- [ ] **Step 3: Expose `loadedURL` on `LocalFilePlayer`**

The persistence sink above reads `player.loadedURL` which is currently `private`. Open `Sources/Murmur/Audio/LocalFilePlayer.swift` and find:

```swift
    private var loadedURL: URL?
```

Change to:

```swift
    private(set) var loadedURL: URL?
```

- [ ] **Step 4: Verify build**

```bash
swift build -c release 2>&1 | tail -5
```

- [ ] **Step 5: Commit**

```bash
git add Sources/Murmur/Decks/DeckController.swift Sources/Murmur/Audio/LocalFilePlayer.swift
git commit -m "feat(decks): trigger analysis on load; wire tempo/keyLock/firstBeat"
```

---

### Task 8: MixerEngine — master deck + sync method

**Files:**
- Modify: `Sources/Murmur/Decks/MixerEngine.swift`

- [ ] **Step 1: Add masterDeckId + sync method**

Find the properties block in `MixerEngine`. After `@Published private(set) var lastRecordingURL: URL?`, add:

```swift
    /// The deck currently designated as sync master. nil = no master.
    @Published private(set) var masterDeckId: Int? = nil
```

In the `init`, after the existing `deck1.connect(...)` and `deck2.connect(...)` lines, add bindings so toggling `state.isMaster` is reflected on the engine:

(Already wired via DeckState — but the engine needs to know which deck is master. Add a public setter.)

Find the `func toggleRecording()` method. Just above it, add:

```swift
    /// Make a deck the sync master. Pass nil to clear.
    func setMaster(_ deckId: Int?) {
        masterDeckId = deckId
        deck1.state.isMaster = (deckId == 1)
        deck2.state.isMaster = (deckId == 2)
    }

    /// Sync `slave` to whichever deck is currently master.
    ///
    /// 1) Reads master's *effective* BPM = master.bpm * master.tempoRate
    /// 2) Reads slave's BPM
    /// 3) Sets slave.tempoRate so its effective BPM matches the master's
    ///
    /// Does nothing if either deck lacks a BPM or if `slave` IS the master.
    func sync(slave: DeckController) {
        guard let masterId = masterDeckId else { return }
        let master = (masterId == 1) ? deck1 : deck2
        if slave === master { return }
        let masterBPM = master.state.bpm
        let slaveBPM = slave.state.bpm
        guard masterBPM > 0, slaveBPM > 0 else { return }
        let masterEffective = masterBPM * Double(master.state.tempoRate)
        let newRate = Float(masterEffective / slaveBPM)
        // Clamp to the ±8% the slider allows so the UI stays in range.
        slave.state.tempoRate = max(0.92, min(1.08, newRate))
    }
```

- [ ] **Step 2: Verify build**

```bash
swift build -c release 2>&1 | tail -5
```

- [ ] **Step 3: Commit**

```bash
git add Sources/Murmur/Decks/MixerEngine.swift
git commit -m "feat(mixer): add master deck pointer and sync(slave:)"
```

---

### Task 9: WaveformView

**Files:**
- Create: `Sources/Murmur/Booth/WaveformView.swift`

- [ ] **Step 1: Implement `WaveformView`**

```swift
import SwiftUI

/// Renders an interleaved min/max peaks array as a stereo-look waveform with
/// a playhead. Beat-grid markers are drawn by a separate overlay
/// (`BeatGridOverlay`) so this view stays focused.
struct WaveformView: View {
    /// Interleaved min/max pairs (e.g., `[min0, max0, min1, max1, ...]`).
    let peaks: [Float]
    /// 0…1 representing the current playhead position.
    let progress: Double
    /// Color of the rendered waveform.
    var tint: Color = .cyan

    var body: some View {
        Canvas { context, size in
            guard peaks.count >= 2 else { return }
            let pairCount = peaks.count / 2
            let stepX = size.width / CGFloat(pairCount)
            let midY = size.height / 2

            // Pre-built path for the whole waveform.
            var path = Path()
            for i in 0..<pairCount {
                let x = CGFloat(i) * stepX + stepX / 2
                let minV = CGFloat(peaks[i * 2])
                let maxV = CGFloat(peaks[i * 2 + 1])
                path.move(to: CGPoint(x: x, y: midY - maxV * midY))
                path.addLine(to: CGPoint(x: x, y: midY - minV * midY))
            }
            context.stroke(path, with: .color(tint.opacity(0.85)), lineWidth: max(1, stepX * 0.9))

            // Playhead.
            let px = CGFloat(progress) * size.width
            var head = Path()
            head.move(to: CGPoint(x: px, y: 0))
            head.addLine(to: CGPoint(x: px, y: size.height))
            context.stroke(head, with: .color(.white), lineWidth: 1.5)
        }
        .background(Color.black.opacity(0.4))
        .cornerRadius(4)
    }
}
```

- [ ] **Step 2: Verify build**

```bash
swift build -c release 2>&1 | tail -5
```

- [ ] **Step 3: Commit**

```bash
git add Sources/Murmur/Booth/WaveformView.swift
git commit -m "feat(booth): add WaveformView rendering peaks + playhead"
```

---

### Task 10: BeatGridOverlay

**Files:**
- Create: `Sources/Murmur/Booth/BeatGridOverlay.swift`

- [ ] **Step 1: Implement `BeatGridOverlay`**

```swift
import SwiftUI

/// Overlays vertical beat-grid markers on top of a waveform. The first
/// downbeat is draggable horizontally to align the grid with the audio.
///
/// Bar lines (every 4 beats) render brighter than off-bar beats.
struct BeatGridOverlay: View {
    let bpm: Double
    let duration: Double
    @Binding var firstBeat: Double
    var tint: Color = .cyan.opacity(0.5)

    @State private var dragStartFirstBeat: Double = 0

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                Canvas { context, size in
                    guard bpm > 0, duration > 0 else { return }
                    let beatInterval = 60.0 / bpm
                    var beatIndex = 0
                    var t = firstBeat
                    while t < duration {
                        let x = CGFloat(t / duration) * size.width
                        var line = Path()
                        line.move(to: CGPoint(x: x, y: 0))
                        line.addLine(to: CGPoint(x: x, y: size.height))
                        let isBar = (beatIndex % 4 == 0)
                        context.stroke(
                            line,
                            with: .color(isBar ? tint.opacity(0.9) : tint.opacity(0.35)),
                            lineWidth: isBar ? 1.5 : 0.5
                        )
                        beatIndex += 1
                        t += beatInterval
                    }
                }

                // Draggable downbeat handle anchored at firstBeat.
                if bpm > 0, duration > 0 {
                    let handleX = CGFloat(firstBeat / duration) * geo.size.width
                    Rectangle()
                        .fill(Color.yellow)
                        .frame(width: 6, height: geo.size.height)
                        .position(x: handleX, y: geo.size.height / 2)
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { drag in
                                    if drag.translation == .zero {
                                        dragStartFirstBeat = firstBeat
                                    }
                                    let dt = Double(drag.translation.width / geo.size.width) * duration
                                    let beatInterval = 60.0 / bpm
                                    var newFirstBeat = dragStartFirstBeat + dt
                                    // Keep within [0, beatInterval) so the grid stays positioned.
                                    while newFirstBeat < 0 { newFirstBeat += beatInterval }
                                    while newFirstBeat >= beatInterval { newFirstBeat -= beatInterval }
                                    firstBeat = newFirstBeat
                                }
                        )
                }
            }
            .allowsHitTesting(true)
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
git add Sources/Murmur/Booth/BeatGridOverlay.swift
git commit -m "feat(booth): add BeatGridOverlay with draggable downbeat"
```

---

### Task 11: TempoSliderView

**Files:**
- Create: `Sources/Murmur/Booth/TempoSliderView.swift`

- [ ] **Step 1: Implement `TempoSliderView`**

```swift
import SwiftUI

/// Vertical-ish tempo slider with detent at 1.0 (unity).
/// Range: 0.92…1.08 (±8%). Double-click to reset to 1.0.
struct TempoSliderView: View {
    @Binding var rate: Float
    var tint: Color = .cyan

    var body: some View {
        VStack(spacing: 4) {
            Text(percentString(rate))
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .tracking(0.5)
                .foregroundColor(tint)
                .frame(width: 50)

            Slider(value: Binding(
                get: { Double(rate) },
                set: { rate = Float($0) }
            ), in: 0.92...1.08)
                .frame(width: 50)
                .onTapGesture(count: 2) { rate = 1.0 }

            Text("TEMPO")
                .font(.system(size: 8, weight: .medium, design: .monospaced))
                .tracking(1)
                .foregroundColor(.white.opacity(0.5))
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.03))
        .cornerRadius(4)
    }

    private func percentString(_ rate: Float) -> String {
        let pct = (rate - 1.0) * 100
        let sign = pct >= 0 ? "+" : ""
        return String(format: "%@%.1f%%", sign, pct)
    }
}
```

- [ ] **Step 2: Verify build**

```bash
swift build -c release 2>&1 | tail -5
```

- [ ] **Step 3: Commit**

```bash
git add Sources/Murmur/Booth/TempoSliderView.swift
git commit -m "feat(booth): add TempoSliderView with ±8% range and unity detent"
```

---

### Task 12: SyncControlsView

**Files:**
- Create: `Sources/Murmur/Booth/SyncControlsView.swift`

- [ ] **Step 1: Implement `SyncControlsView`**

```swift
import SwiftUI

/// Three small controls under each deck: SYNC button, KEY-LOCK toggle,
/// MASTER toggle.
///
/// - SYNC engages: pulls this deck to match the master deck's effective BPM.
///   Disabled when no master is set, or when this deck IS master.
/// - KEY-LOCK toggles whether tempo changes preserve pitch.
/// - MASTER assigns/clears this deck as the sync master.
struct SyncControlsView: View {
    @ObservedObject var state: DeckState
    var tint: Color
    /// True if any deck currently has master designation.
    var hasMaster: Bool
    var onSync: () -> Void
    var onToggleMaster: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Button(action: onSync) {
                Text("SYNC")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .tracking(1)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .foregroundColor(syncEnabled ? tint : .white.opacity(0.25))
                    .background(syncEnabled ? tint.opacity(0.15) : Color.white.opacity(0.03))
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(syncEnabled ? tint.opacity(0.6) : Color.white.opacity(0.08), lineWidth: 1))
                    .cornerRadius(4)
            }
            .buttonStyle(.plain)
            .disabled(!syncEnabled)

            Button(action: { state.keyLock.toggle() }) {
                Text("KEY-LOCK")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .tracking(1)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .foregroundColor(state.keyLock ? Color.green : .white.opacity(0.4))
                    .background(state.keyLock ? Color.green.opacity(0.12) : Color.white.opacity(0.03))
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(state.keyLock ? Color.green.opacity(0.5) : Color.white.opacity(0.08), lineWidth: 1))
                    .cornerRadius(4)
            }
            .buttonStyle(.plain)

            Button(action: onToggleMaster) {
                Text("MASTER")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .tracking(1)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .foregroundColor(state.isMaster ? Color.yellow : .white.opacity(0.4))
                    .background(state.isMaster ? Color.yellow.opacity(0.12) : Color.white.opacity(0.03))
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(state.isMaster ? Color.yellow.opacity(0.6) : Color.white.opacity(0.08), lineWidth: 1))
                    .cornerRadius(4)
            }
            .buttonStyle(.plain)

            Spacer()
        }
    }

    private var syncEnabled: Bool {
        hasMaster && !state.isMaster && state.bpm > 0
    }
}
```

- [ ] **Step 2: Verify build**

```bash
swift build -c release 2>&1 | tail -5
```

- [ ] **Step 3: Commit**

```bash
git add Sources/Murmur/Booth/SyncControlsView.swift
git commit -m "feat(booth): add SyncControlsView (SYNC/KEY-LOCK/MASTER)"
```

---

### Task 13: Wire into DeckView; final integration

**Files:**
- Modify: `Sources/Murmur/Booth/DeckView.swift`
- Modify: `Sources/Murmur/Booth/BoothView.swift`

- [ ] **Step 1: Add waveform + sync controls + tempo slider to `DeckView`**

Open `Sources/Murmur/Booth/DeckView.swift`. Add a new property to the view:

Find the existing properties at the top of `struct DeckView`:

```swift
struct DeckView: View {
    @ObservedObject var state: DeckState
    var deckNumber: Int
    var tint: Color
    var onLoad: (URL) -> Void
    var onTogglePlay: () -> Void
```

Add below `onTogglePlay`:

```swift
    var hasMaster: Bool
    var onSync: () -> Void
    var onToggleMaster: () -> Void
```

Then find the body. Find this section:

```swift
            Text(state.displayName)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white)
                .lineLimit(1)
```

Add immediately below (still inside the outer `VStack`):

```swift
            HStack {
                if state.bpm > 0 {
                    Text(String(format: "%.1f BPM", state.bpm))
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundColor(tint)
                } else if state.isLoaded {
                    Text("analyzing…")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.white.opacity(0.4))
                }
                Spacer()
            }

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

            SyncControlsView(
                state: state,
                tint: tint,
                hasMaster: hasMaster,
                onSync: onSync,
                onToggleMaster: onToggleMaster
            )
```

Then find the existing knobs `HStack`:

```swift
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
```

Wrap it together with the tempo slider so they share a row:

```swift
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
                TempoSliderView(rate: $state.tempoRate, tint: tint)
            }
```

- [ ] **Step 2: Update `BoothView` to pass the new closures and hasMaster**

Open `Sources/Murmur/Booth/BoothView.swift`. Replace the entire body of `BoothView` (inside `var body: some View`) with:

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
                    }
                )
                MasterControlsView(mixer: mixer)
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
                    }
                )
            }

            CrossfaderView(position: $mixer.crossfadePosition)
                .frame(height: 36)
                .background(Color(white: 0.04))
                .cornerRadius(8)
        }
        .padding(14)
        .frame(minWidth: 760, minHeight: 460)
        .background(Color(white: 0.02))
```

(The `.frame(minWidth: 760, minHeight: 460)` — height bumped from 320 to 460 to accommodate the new waveform + sync controls.)

Also update `BoothWindowController.swift` to give the window a larger default size. Find:

```swift
        win.setContentSize(NSSize(width: 820, height: 360))
```

Replace with:

```swift
        win.setContentSize(NSSize(width: 820, height: 500))
```

- [ ] **Step 3: Verify build**

```bash
swift build -c release 2>&1 | tail -10
```

Expected: clean build.

- [ ] **Step 4: Commit**

```bash
git add Sources/Murmur/Booth/DeckView.swift Sources/Murmur/Booth/BoothView.swift Sources/Murmur/Booth/BoothWindowController.swift
git commit -m "feat(booth): wire waveform/beat-grid/tempo/sync into DeckView"
```

---

### Task 14: Manual smoke + ship

- [ ] **Step 1: Run the app and walk through the new flow**

Either `swift run -c release` or `open dist/Murmur.app` after `./build-app.sh --sign`.

Expected sequence:
1. Open booth, load Track A on Deck 1.
2. Within ~1 second, "analyzing…" replaces with the detected BPM (e.g., "124.0 BPM"). Waveform appears with cyan beat-grid lines.
3. Console (Console.app, filter "Murmur") shows `[Analysis] track-A.m4a → BPM=124.00, duration=…`.
4. Play Deck 1. Beat-grid lines should appear visually aligned to the kick drum / downbeats. If off, drag the yellow first-downbeat handle until they line up.
5. Quit and re-open the app, reload the same track on Deck 1. Analysis is INSTANT (cached). BPM displays immediately. First-beat persistence: any adjustment from step 4 is recalled.
6. Load Track B on Deck 2. Different BPM should be detected.
7. Click **MASTER** on Deck 1. Yellow MASTER badge appears.
8. On Deck 2: click **SYNC**. Deck 2's tempo slider jumps to whatever percent is needed to match Deck 1's BPM. The "+X.X%" label updates.
9. Play both decks. They should stay locked in tempo for at least a few bars. (Phase drift will occur over time — fixing that is Phase 2b's job.)
10. Toggle KEY-LOCK off on Deck 2 with tempo at +3.0%. Pitch should now shift up by ~52 cents (audible). Toggle back on → pitch returns to natural.
11. Click MASTER on Deck 1 again to clear. SYNC button on Deck 2 becomes disabled (greyed out).

- [ ] **Step 2: Verify BPM detection against a known track**

Pick a track whose BPM you know (most electronic / pop tracks have it on Beatport, Tunebat, or musicbrainz). Load it. The detected BPM should be within ±2 of the published value. If off by exactly 2x (e.g., detected 150 for a 75 BPM track or 60 for a 120 BPM track), the octave correction missed — surface this as a bug. If off by more, that's a detection failure worth investigating.

- [ ] **Step 3: Build the bundle**

```bash
./build-app.sh --sign
```

Verify `dist/Murmur.app` runs as expected (still no Dock icon — `LSUIElement` preserved).

- [ ] **Step 4: Tag the milestone**

```bash
git tag -a phase-2a-beatmatching -m "Pocket DJ Phase 2a: BPM + waveform + beat grid + tempo + sync"
```

(Don't push.)

---

## Out of Scope for Phase 2a (Phase 2b and beyond)

- Hot cues (8 per deck, persistence, color coding)
- Beat-quantized loops (in/out, halve/double, save)
- Phase meter (visual indicator of beat alignment drift)
- Continuous-sync ("sync hold" that re-corrects drift)
- Variable tempo ranges (±16%, ±50% toggles in Preferences)
- Key detection + Camelot notation + key-compatible track highlighting
- Library panel (crates, prep crate, search, sort)
- Effects rack (echo, reverb, flanger)
- Headphone cue / dual-output device
- Apple Music / YouTube Ambient Layer / Mood Dial integration

Anything in this list that "feels needed" is a sign of phase drift — defer it.

---

## Self-Review Notes

Run against the design spec on 2026-05-16:

- **§5.1 Loading and library:** Phase 2a covers offline BPM + waveform analysis on load + caching in `library.json`. ✅ Crates / prep crate deferred (Phase 6).
- **§5.2 Beatmatching:** BPM detection, beat grid (auto + manual downbeat), sync, tempo with key-lock. ✅ Implemented.
  - Phase meter — explicitly deferred to Phase 2b per scope split.
- **§5.3 Key-aware mixing:** key detection — explicitly deferred. ✅ Phase 4.
- **§5.4 Cue points and hot cues:** explicitly deferred to Phase 2b. ✅
- **§5.5 Effects rack:** deferred (Phase 4). ✅
- **§5.6 Headphone cue:** deferred (Phase 4). ✅
- **§5.7 Recording the master:** Phase 1 already covered the local-file path. ✅
- **§7.2 BPM and key analysis:** amplitude-onset autocorrelation, octave correction, background queue, cached in `library.json`. ✅ All implemented in Tasks 3-4.
- **§7.3 Latency and timing:** TimePitch insertion preserves engine timing. Tempo adjustments use `AVAudioUnitTimePitch.rate`. ✅
- **§7.6 Components:** `AnalysisService`, `LibraryIndex`, `DeckController` extension, `SyncEngine` (rolled into `MixerEngine.sync(slave:)`), `WaveformView`, `BeatGridOverlay`. ✅

No spec gaps for Phase 2a. No placeholders. Type signatures consistent (`TrackMetadata.bpm`, `DeckState.bpm`, `MixerEngine.masterDeckId` all referenced consistently across tasks).
