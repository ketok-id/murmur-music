# Pocket DJ Phase 3 — Effects Rack + Key Detection

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the two DJ staples the booth is missing without a major visual overhaul: per-deck **Echo + Reverb** effects (with a beat-synced echo time), and offline **key detection** displayed in both musical (e.g., "D minor") and Camelot ("7A") notation alongside BPM.

**Architecture:** Echo and Reverb are inserted into each `ChannelStrip` between the filter and the volume fader using `AVAudioUnitDelay` and `AVAudioUnitReverb`. Each effect has wet/dry mix + on-off; echo additionally has a beat-divider selector (1/4, 1/8, 1/16) that derives delay time from the deck's effective BPM. `KeyDetector` runs alongside `BPMDetector` in `AnalysisService` using a 12-bin chromagram from `vDSP` FFT correlated against Krumhansl-Schmuckler key profiles. Results cache in `TrackMetadata.key` + `camelot`. UI: a `FXControlsView` per deck (a Compact strip with two effect sections), and a small `KeyDisplay` next to the BPM label.

**Tech Stack:** Same as before. Adds `vDSP_fft_zrip` for FFT, `AVAudioUnitDelay`, `AVAudioUnitReverb`.

**Testing:** `swift build -c release` + final manual smoke in Task 9. No Co-Authored-By trailer in subagent commits.

**Prerequisites:** All previous phases merged into `main`. The booth window already shows BPM + waveform + sync + hot cues + loops + phase meter.

---

## File Structure

**New files:**

```
Sources/Murmur/Analysis/
  KeyDetector.swift      Chromagram + Krumhansl key profile correlation
Sources/Murmur/Audio/
  EffectsChain.swift     Owns Echo + Reverb units; exposes wet/dry + on/off + beat-sync echo
Sources/Murmur/Booth/
  FXControlsView.swift   2-section strip (ECHO + REVERB) with on/off + wet knob + beat-divider for echo
  KeyDisplay.swift       Small label showing "D minor · 7A"
```

**Modified files:**

- `Sources/Murmur/Analysis/TrackMetadata.swift` — add `keyName: String` and `camelot: String` (default empty).
- `Sources/Murmur/Analysis/AnalysisService.swift` — call `KeyDetector` after BPM detection.
- `Sources/Murmur/Audio/ChannelStrip.swift` — insert `EffectsChain` between filterEQ and volume.
- `Sources/Murmur/Decks/DeckState.swift` — add `keyName`, `camelot`, `echoEnabled`, `echoWet`, `echoDivider`, `reverbEnabled`, `reverbWet`.
- `Sources/Murmur/Decks/DeckController.swift` — restore key from metadata; wire FX state into the strip; beat-sync echo using effective BPM.
- `Sources/Murmur/Booth/DeckView.swift` — add `KeyDisplay` next to BPM, add `FXControlsView` row.
- `Sources/Murmur/Booth/BoothView.swift` — pass FX state through; bump window minHeight to 720.

---

### Task 1: KeyDetector

**Files:**
- Create: `Sources/Murmur/Analysis/KeyDetector.swift`

The algorithm:
1. Decode file to mono Float32 at the file's sample rate.
2. Take overlapping 4096-sample windows with 2048-sample hop.
3. Per window: FFT → magnitude spectrum → map each frequency bin to the closest of 12 pitch classes (C through B); accumulate into a 12-element chromagram.
4. Sum chromagrams across the entire track; normalize to unit length.
5. Correlate the resulting average chromagram against 24 Krumhansl-Schmuckler key profiles (12 major + 12 minor) rotated to each tonic.
6. The best-correlating profile is the detected key.

Krumhansl-Schmuckler profiles are 12-element relative-strength vectors. We rotate them to each of the 12 tonics for both major and minor, so we score 24 candidates.

- [ ] **Step 1: Create `Sources/Murmur/Analysis/KeyDetector.swift`**

```swift
import AVFoundation
import Accelerate

/// Detects the musical key of an audio file via chromagram + Krumhansl-Schmuckler.
///
/// Returns both the human-readable musical name ("D minor") and the Camelot
/// notation ("7A") used in harmonic mixing.
enum KeyDetector {
    static let fftSize = 4096
    static let hopSize = 2048
    static let referenceFreq: Double = 440.0   // A4

    /// 12 pitch class names, C..B (semitones up from C).
    static let pitchNames = ["C", "C♯", "D", "D♯", "E", "F", "F♯", "G", "G♯", "A", "A♯", "B"]

    /// Camelot wheel mapping. Index = (mode 0 = major / 1 = minor, pitchClass 0..11).
    /// Major: C=8B, G=9B, D=10B, A=11B, E=12B, B=1B, F♯=2B, C♯=3B, G♯=4B, D♯=5B, A♯=6B, F=7B
    /// Minor: A=8A, E=9A, B=10A, F♯=11A, C♯=12A, G♯=1A, D♯=2A, A♯=3A, F=4A, C=5A, G=6A, D=7A
    static let camelotMajor: [Int: String] = [
        0: "8B", 1: "3B", 2: "10B", 3: "5B", 4: "12B", 5: "7B",
        6: "2B", 7: "9B", 8: "4B", 9: "11B", 10: "6B", 11: "1B"
    ]
    static let camelotMinor: [Int: String] = [
        0: "5A", 1: "12A", 2: "7A", 3: "2A", 4: "9A", 5: "4A",
        6: "11A", 7: "6A", 8: "1A", 9: "8A", 10: "3A", 11: "10A"
    ]

    /// Krumhansl-Schmuckler major profile (C major), to be rotated.
    static let majorProfile: [Float] = [6.35, 2.23, 3.48, 2.33, 4.38, 4.09,
                                         2.52, 5.19, 2.39, 3.66, 2.29, 2.88]
    /// Krumhansl-Schmuckler minor profile (C minor), to be rotated.
    static let minorProfile: [Float] = [6.33, 2.68, 3.52, 5.38, 2.60, 3.53,
                                         2.54, 4.75, 3.98, 2.69, 3.34, 3.17]

    struct Result {
        let keyName: String     // e.g. "D minor"
        let camelot: String     // e.g. "7A"
    }

    /// Synchronously detect key. Call from a background queue.
    static func detect(from url: URL) throws -> Result {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        let sampleRate = format.sampleRate
        let mono = try readMono(file: file)
        let chromagram = computeChromagram(mono: mono, sampleRate: sampleRate)
        let (pitchClass, isMinor) = bestKeyProfile(chromagram: chromagram)
        let nameSuffix = isMinor ? "minor" : "major"
        let keyName = "\(pitchNames[pitchClass]) \(nameSuffix)"
        let camelot = (isMinor ? camelotMinor : camelotMajor)[pitchClass] ?? "?"
        return Result(keyName: keyName, camelot: camelot)
    }

    private static func readMono(file: AVAudioFile) throws -> [Float] {
        let format = file.processingFormat
        let chunkFrames: AVAudioFrameCount = 32768
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunkFrames) else {
            throw NSError(domain: "KeyDetector", code: 1)
        }
        var mono = [Float]()
        mono.reserveCapacity(Int(file.length))
        while file.framePosition < file.length {
            try file.read(into: buffer)
            let frameCount = Int(buffer.frameLength)
            if frameCount == 0 { break }
            guard let channelData = buffer.floatChannelData else { continue }
            let ch = Int(format.channelCount)
            for i in 0..<frameCount {
                var s: Float = 0
                for c in 0..<ch { s += channelData[c][i] }
                mono.append(s / Float(ch))
            }
        }
        return mono
    }

    private static func computeChromagram(mono: [Float], sampleRate: Double) -> [Float] {
        let n = fftSize
        let log2n = vDSP_Length(log2(Double(n)))
        guard let setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else {
            return [Float](repeating: 0, count: 12)
        }
        defer { vDSP_destroy_fftsetup(setup) }

        var window = [Float](repeating: 0, count: n)
        vDSP_hann_window(&window, vDSP_Length(n), Int32(vDSP_HANN_NORM))

        var chroma = [Float](repeating: 0, count: 12)
        let halfN = n / 2

        var realp = [Float](repeating: 0, count: halfN)
        var imagp = [Float](repeating: 0, count: halfN)
        var magnitudes = [Float](repeating: 0, count: halfN)

        var pos = 0
        while pos + n <= mono.count {
            // 1) Windowed frame.
            var frame = [Float](repeating: 0, count: n)
            vDSP_vmul(Array(mono[pos..<pos + n]), 1, window, 1, &frame, 1, vDSP_Length(n))

            // 2) FFT: pack input as split complex, run forward FFT.
            realp.withUnsafeMutableBufferPointer { rp in
                imagp.withUnsafeMutableBufferPointer { ip in
                    var split = DSPSplitComplex(realp: rp.baseAddress!, imagp: ip.baseAddress!)
                    frame.withUnsafeBufferPointer { fp in
                        fp.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: halfN) {
                            vDSP_ctoz($0, 2, &split, 1, vDSP_Length(halfN))
                        }
                    }
                    vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
                    vDSP_zvabs(&split, 1, &magnitudes, 1, vDSP_Length(halfN))
                }
            }

            // 3) Map each magnitude bin to a pitch class and accumulate.
            //    Skip bin 0 (DC) and bins above 5kHz to avoid percussive transients.
            let binHz = sampleRate / Double(n)
            for bin in 1..<halfN {
                let freq = Double(bin) * binHz
                if freq < 30 || freq > 5000 { continue }
                let midi = 69.0 + 12.0 * log2(freq / referenceFreq)
                let pc = Int(midi.rounded().truncatingRemainder(dividingBy: 12) + 12) % 12
                chroma[pc] += magnitudes[bin]
            }
            pos += hopSize
        }

        // Normalize.
        var maxV: Float = 0
        vDSP_maxv(chroma, 1, &maxV, vDSP_Length(12))
        if maxV > 0 { vDSP_vsdiv(chroma, 1, &maxV, &chroma, 1, vDSP_Length(12)) }
        return chroma
    }

    /// Returns (pitchClass, isMinor) of best-correlating Krumhansl profile.
    private static func bestKeyProfile(chromagram: [Float]) -> (Int, Bool) {
        var bestPC = 0
        var bestMinor = false
        var bestScore: Float = -.greatestFiniteMagnitude

        for pc in 0..<12 {
            for (profile, isMinor) in [(majorProfile, false), (minorProfile, true)] {
                // Rotate profile to this tonic and dot-product with chromagram.
                var score: Float = 0
                for i in 0..<12 {
                    score += chromagram[i] * profile[(i - pc + 12) % 12]
                }
                if score > bestScore {
                    bestScore = score
                    bestPC = pc
                    bestMinor = isMinor
                }
            }
        }
        return (bestPC, bestMinor)
    }
}
```

- [ ] **Step 2: Build**

```bash
swift build -c release 2>&1 | tail -5
```

- [ ] **Step 3: Commit**

```bash
git add Sources/Murmur/Analysis/KeyDetector.swift
git commit -m "feat(analysis): add KeyDetector with chromagram + Krumhansl-Schmuckler"
```

---

### Task 2: TrackMetadata + AnalysisService integration

**Files:**
- Modify: `Sources/Murmur/Analysis/TrackMetadata.swift`
- Modify: `Sources/Murmur/Analysis/AnalysisService.swift`

- [ ] **Step 1: Extend TrackMetadata**

Find:
```swift
struct TrackMetadata: Codable, Equatable {
    let bpm: Double
    let duration: Double
    var firstBeat: Double
    let peaksPath: String
    var hotCues: [HotCue] = []
}
```

Replace with:
```swift
struct TrackMetadata: Codable, Equatable {
    let bpm: Double
    let duration: Double
    var firstBeat: Double
    let peaksPath: String
    var hotCues: [HotCue] = []
    var keyName: String = ""
    var camelot: String = ""
}
```

- [ ] **Step 2: Wire KeyDetector into AnalysisService**

Open `Sources/Murmur/Analysis/AnalysisService.swift`. Find the `runAnalysis(url:)` method's body — the existing block that does peaks + BPM + file metadata. Find:

```swift
            let peaks = try PeakExtractor.extract(from: url)
            let bpm = try BPMDetector.detect(from: url)
            let file = try AVAudioFile(forReading: url)
            let duration = Double(file.length) / file.processingFormat.sampleRate

            let peaksFilename = url.deletingPathExtension().lastPathComponent + "-" +
                String(url.path.hashValue, radix: 16) + ".peaks"
            let peaksURL = LibraryIndex.peaksDirectory.appendingPathComponent(peaksFilename)
            try PeakExtractor.writePeaks(peaks, to: peaksURL)

            let metadata = TrackMetadata(bpm: bpm, duration: duration, firstBeat: 0, peaksPath: peaksFilename)
            LibraryIndex.shared.setMetadata(metadata, forPath: url.path)

            NSLog("[Analysis] %@ → BPM=%.2f, duration=%.1fs", url.lastPathComponent, bpm, duration)
            return Result(url: url, metadata: metadata, peaks: peaks)
```

Replace with:

```swift
            let peaks = try PeakExtractor.extract(from: url)
            let bpm = try BPMDetector.detect(from: url)
            let keyResult = (try? KeyDetector.detect(from: url))
                ?? KeyDetector.Result(keyName: "", camelot: "")
            let file = try AVAudioFile(forReading: url)
            let duration = Double(file.length) / file.processingFormat.sampleRate

            let peaksFilename = url.deletingPathExtension().lastPathComponent + "-" +
                String(url.path.hashValue, radix: 16) + ".peaks"
            let peaksURL = LibraryIndex.peaksDirectory.appendingPathComponent(peaksFilename)
            try PeakExtractor.writePeaks(peaks, to: peaksURL)

            let metadata = TrackMetadata(
                bpm: bpm,
                duration: duration,
                firstBeat: 0,
                peaksPath: peaksFilename,
                hotCues: [],
                keyName: keyResult.keyName,
                camelot: keyResult.camelot
            )
            LibraryIndex.shared.setMetadata(metadata, forPath: url.path)

            NSLog("[Analysis] %@ → BPM=%.2f, key=%@ (%@), duration=%.1fs",
                  url.lastPathComponent, bpm,
                  keyResult.keyName.isEmpty ? "?" : keyResult.keyName,
                  keyResult.camelot.isEmpty ? "?" : keyResult.camelot,
                  duration)
            return Result(url: url, metadata: metadata, peaks: peaks)
```

- [ ] **Step 3: Build and commit**

```bash
swift build -c release 2>&1 | tail -5
git add Sources/Murmur/Analysis/TrackMetadata.swift Sources/Murmur/Analysis/AnalysisService.swift
git commit -m "feat(analysis): wire KeyDetector into AnalysisService + cache"
```

---

### Task 3: EffectsChain (Echo + Reverb units)

**Files:**
- Create: `Sources/Murmur/Audio/EffectsChain.swift`

- [ ] **Step 1: Implement EffectsChain**

```swift
import AVFoundation

/// Per-deck FX bus: Echo (delay) + Reverb in series, inserted between the
/// filter and the volume fader.
///
/// Each unit exposes wet/dry + on-off. Echo additionally has a beat-divider
/// (1/4, 1/8, 1/16 = 4, 8, 16) — call `setEchoBeatDivider(_:bpm:)` whenever
/// the deck's effective BPM changes so the delay time stays musical.
final class EffectsChain {
    private let engine: AVAudioEngine
    let delay = AVAudioUnitDelay()
    let reverb = AVAudioUnitReverb()

    /// 0.0…1.0. 1.0 = fully wet.
    var echoWet: Float {
        get { delay.wetDryMix / 100 }
        set { delay.wetDryMix = max(0, min(100, newValue * 100)) }
    }

    /// 0.0…1.0.
    var reverbWet: Float {
        get { reverb.wetDryMix / 100 }
        set { reverb.wetDryMix = max(0, min(100, newValue * 100)) }
    }

    /// Bypass the echo unit entirely.
    var echoEnabled: Bool {
        get { !delay.bypass }
        set { delay.bypass = !newValue }
    }

    /// Bypass the reverb unit entirely.
    var reverbEnabled: Bool {
        get { !reverb.bypass }
        set { reverb.bypass = !newValue }
    }

    init(engine: AVAudioEngine) {
        self.engine = engine

        // Reasonable defaults.
        delay.delayTime = 0.5
        delay.feedback = 35           // percent, -100..100
        delay.wetDryMix = 0           // start dry
        delay.bypass = true           // start off

        reverb.loadFactoryPreset(.mediumHall)
        reverb.wetDryMix = 0
        reverb.bypass = true

        engine.attach(delay)
        engine.attach(reverb)
        // Internal: delay → reverb. Connections to/from this chain are external.
        engine.connect(delay, to: reverb, format: nil)
    }

    /// Set the echo's delay time from a beat-divider and an effective BPM.
    /// Divider is 4 (quarter), 8 (eighth), or 16 (sixteenth).
    func setEchoBeatDivider(_ divider: Int, bpm: Double) {
        guard bpm > 0, divider > 0 else { return }
        // Quarter note = 60/bpm seconds. Divider 4 → quarter; 8 → eighth; 16 → 16th.
        let quarter = 60.0 / bpm
        let secondsPerNote = quarter * (4.0 / Double(divider))
        delay.delayTime = max(0, min(2.0, secondsPerNote))
    }

    /// Input node — connect upstream signal here.
    var input: AVAudioNode { delay }
    /// Output node — connect this to the deck's volume fader.
    var output: AVAudioNode { reverb }
}
```

- [ ] **Step 2: Build and commit**

```bash
swift build -c release 2>&1 | tail -5
git add Sources/Murmur/Audio/EffectsChain.swift
git commit -m "feat(audio): add EffectsChain with beat-synced Echo + Reverb"
```

---

### Task 4: Insert EffectsChain into ChannelStrip

**Files:**
- Modify: `Sources/Murmur/Audio/ChannelStrip.swift`

The current strip is `[source] → timePitch → eq3band → filterEQ → volume`. After this task: `[source] → timePitch → eq3band → filterEQ → fx.input → ... → fx.output → volume`.

- [ ] **Step 1: Add EffectsChain property**

Find the property block at the top of `ChannelStrip`. After `let timePitch = AVAudioUnitTimePitch()` add:

```swift
    /// FX bus inserted between the filter and the volume fader.
    let effects: EffectsChain
```

- [ ] **Step 2: Update init to construct EffectsChain and reroute connections**

Find the init body — specifically the engine.attach / engine.connect block:

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

Replace with:

```swift
        engine.attach(timePitch)
        engine.attach(eq3band)
        engine.attach(filterEQ)
        engine.attach(volume)

        // Construct effects chain (attaches its own nodes).
        effects = EffectsChain(engine: engine)

        // Internal connections: timePitch → eq3band → filterEQ → effects.input → ... → effects.output → volume.
        engine.connect(timePitch, to: eq3band, format: nil)
        engine.connect(eq3band, to: filterEQ, format: nil)
        engine.connect(filterEQ, to: effects.input, format: nil)
        engine.connect(effects.output, to: volume, format: nil)
```

Note: the `effects = EffectsChain(engine: engine)` line must come AFTER the `engine.attach(volume)` because `EffectsChain.init` requires the engine reference. Swift will compile this fine because `effects` is a stored property declared with `let` and assigned exactly once in `init`.

- [ ] **Step 3: Build and commit**

```bash
swift build -c release 2>&1 | tail -10
git add Sources/Murmur/Audio/ChannelStrip.swift
git commit -m "feat(audio): insert EffectsChain into ChannelStrip"
```

---

### Task 5: DeckState additions for FX + key

**Files:**
- Modify: `Sources/Murmur/Decks/DeckState.swift`

- [ ] **Step 1: Add new properties**

Find the existing Phase 2b property block. After `let loop = LoopState()`, add:

```swift

    // ── Phase 3: effects + key display ────────────────────────────────────

    /// Musical key name (e.g. "D minor"), empty if not yet detected.
    @Published var keyName: String = ""
    /// Camelot wheel notation (e.g. "7A"), empty if not yet detected.
    @Published var camelot: String = ""

    /// Echo on/off.
    @Published var echoEnabled: Bool = false
    /// Echo wet/dry, 0…1.
    @Published var echoWet: Float = 0.3
    /// Beat divider for echo time: 4 = quarter, 8 = eighth, 16 = 16th.
    @Published var echoDivider: Int = 8

    /// Reverb on/off.
    @Published var reverbEnabled: Bool = false
    /// Reverb wet/dry, 0…1.
    @Published var reverbWet: Float = 0.3
```

- [ ] **Step 2: Build and commit**

```bash
swift build -c release 2>&1 | tail -5
git add Sources/Murmur/Decks/DeckState.swift
git commit -m "feat(decks): add Phase 3 state — key + echo + reverb"
```

---

### Task 6: DeckController FX wiring + key restore

**Files:**
- Modify: `Sources/Murmur/Decks/DeckController.swift`

- [ ] **Step 1: Restore key from analysis metadata**

Find the `AnalysisService.shared.analyze` completion block (inside `load(url:)`):

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

Replace with:

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
                self.state.keyName = result.metadata.keyName
                self.state.camelot = result.metadata.camelot
            }
```

Then find both places in `load(url:)` where state is reset on load (top of try block AND catch block) — currently:

Top:
```swift
            state.bpm = 0
            state.firstBeat = 0
            state.peaks = []
            state.hotCues = []
            state.loop.clear()
            loopEngine.disengage()
```

Replace with:
```swift
            state.bpm = 0
            state.firstBeat = 0
            state.peaks = []
            state.hotCues = []
            state.loop.clear()
            loopEngine.disengage()
            state.keyName = ""
            state.camelot = ""
```

Bottom (catch):
```swift
            state.bpm = 0
            state.firstBeat = 0
            state.peaks = []
            state.hotCues = []
            state.loop.clear()
            loopEngine.disengage()
```

Replace with:
```swift
            state.bpm = 0
            state.firstBeat = 0
            state.peaks = []
            state.hotCues = []
            state.loop.clear()
            loopEngine.disengage()
            state.keyName = ""
            state.camelot = ""
```

- [ ] **Step 2: Wire FX state into the strip**

Find `wireStateBindings()`. After the existing tempo+keyLock combineLatest sink and BEFORE the firstBeat sink, add:

```swift

        // Echo: enabled, wet, divider all roll into ChannelStrip.effects.
        state.$echoEnabled
            .sink { [weak self] v in self?.strip.effects.echoEnabled = v }
            .store(in: &cancellables)
        state.$echoWet
            .sink { [weak self] v in self?.strip.effects.echoWet = v }
            .store(in: &cancellables)
        // Echo divider also depends on bpm * tempoRate for beat-sync.
        state.$echoDivider
            .combineLatest(state.$bpm, state.$tempoRate)
            .sink { [weak self] (divider, bpm, rate) in
                self?.strip.effects.setEchoBeatDivider(divider, bpm: bpm * Double(rate))
            }
            .store(in: &cancellables)

        // Reverb.
        state.$reverbEnabled
            .sink { [weak self] v in self?.strip.effects.reverbEnabled = v }
            .store(in: &cancellables)
        state.$reverbWet
            .sink { [weak self] v in self?.strip.effects.reverbWet = v }
            .store(in: &cancellables)
```

- [ ] **Step 3: Build and commit**

```bash
swift build -c release 2>&1 | tail -10
git add Sources/Murmur/Decks/DeckController.swift
git commit -m "feat(decks): wire FX state + restore key on load"
```

---

### Task 7: FXControlsView

**Files:**
- Create: `Sources/Murmur/Booth/FXControlsView.swift`

- [ ] **Step 1: Implement**

```swift
import SwiftUI

/// Per-deck effects strip: ECHO section (on + wet + divider) and REVERB section (on + wet).
struct FXControlsView: View {
    @ObservedObject var state: DeckState
    var tint: Color

    var body: some View {
        HStack(spacing: 10) {
            echoSection
            Divider().frame(height: 36).background(Color.white.opacity(0.08))
            reverbSection
            Spacer()
        }
    }

    private var echoSection: some View {
        HStack(spacing: 6) {
            toggle(label: "ECHO", on: $state.echoEnabled)
            KnobView(value: $state.echoWet, range: 0...1, defaultValue: 0.3,
                     label: "WET", tint: tint, diameter: 28)
            dividerPicker
        }
    }

    private var reverbSection: some View {
        HStack(spacing: 6) {
            toggle(label: "REV", on: $state.reverbEnabled)
            KnobView(value: $state.reverbWet, range: 0...1, defaultValue: 0.3,
                     label: "WET", tint: tint, diameter: 28)
        }
    }

    private var dividerPicker: some View {
        VStack(spacing: 2) {
            HStack(spacing: 2) {
                divButton(4, "¼")
                divButton(8, "⅛")
                divButton(16, "16")
            }
            Text("BEAT")
                .font(.system(size: 7, weight: .medium, design: .monospaced))
                .tracking(0.5)
                .foregroundColor(.white.opacity(0.4))
        }
    }

    private func divButton(_ value: Int, _ label: String) -> some View {
        let isOn = state.echoDivider == value
        return Button(action: { state.echoDivider = value }) {
            Text(label)
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundColor(isOn ? tint : .white.opacity(0.4))
                .frame(width: 18, height: 16)
                .background(isOn ? tint.opacity(0.15) : Color.white.opacity(0.03))
                .cornerRadius(2)
        }
        .buttonStyle(.plain)
    }

    private func toggle(label: String, on: Binding<Bool>) -> some View {
        Button(action: { on.wrappedValue.toggle() }) {
            Text(label)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .tracking(0.5)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .foregroundColor(on.wrappedValue ? tint : .white.opacity(0.4))
                .background(on.wrappedValue ? tint.opacity(0.15) : Color.white.opacity(0.03))
                .overlay(RoundedRectangle(cornerRadius: 3).stroke(on.wrappedValue ? tint.opacity(0.5) : Color.white.opacity(0.08), lineWidth: 1))
                .cornerRadius(3)
        }
        .buttonStyle(.plain)
    }
}
```

- [ ] **Step 2: Build and commit**

```bash
swift build -c release 2>&1 | tail -5
git add Sources/Murmur/Booth/FXControlsView.swift
git commit -m "feat(booth): add FXControlsView with Echo + Reverb sections"
```

---

### Task 8: Wire key display + FX row into DeckView; bump window size

**Files:**
- Modify: `Sources/Murmur/Booth/DeckView.swift`
- Modify: `Sources/Murmur/Booth/BoothView.swift`
- Modify: `Sources/Murmur/Booth/BoothWindowController.swift`

- [ ] **Step 1: Add key display next to the BPM label**

Open `Sources/Murmur/Booth/DeckView.swift`. Find this block:

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
```

Replace with:

```swift
            HStack(spacing: 12) {
                if state.bpm > 0 {
                    Text(String(format: "%.1f BPM", state.bpm))
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundColor(tint)
                } else if state.isLoaded {
                    Text("analyzing…")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.white.opacity(0.4))
                }
                if !state.keyName.isEmpty {
                    Text("\(state.keyName)  ·  \(state.camelot)")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundColor(.yellow.opacity(0.85))
                }
                Spacer()
            }
```

- [ ] **Step 2: Insert FXControlsView after LoopControlsView**

Find the existing `LoopControlsView(...)` call. Add IMMEDIATELY AFTER it:

```swift

            FXControlsView(state: state, tint: tint)
```

- [ ] **Step 3: Bump window minimum sizes**

Open `Sources/Murmur/Booth/BoothView.swift`. Find:

```swift
        .frame(minWidth: 1000, minHeight: 600)
```

Replace with:

```swift
        .frame(minWidth: 1000, minHeight: 720)
```

Open `Sources/Murmur/Booth/BoothWindowController.swift`. Find:

```swift
        win.setContentSize(NSSize(width: 1100, height: 660))
        win.contentMinSize = NSSize(width: 1000, height: 600)
```

Replace with:

```swift
        win.setContentSize(NSSize(width: 1100, height: 780))
        win.contentMinSize = NSSize(width: 1000, height: 720)
```

- [ ] **Step 4: Build and commit**

```bash
swift build -c release 2>&1 | tail -10
git add Sources/Murmur/Booth/DeckView.swift Sources/Murmur/Booth/BoothView.swift Sources/Murmur/Booth/BoothWindowController.swift
git commit -m "feat(booth): show key + add FX row; bump window size"
```

---

### Task 9: Build bundle + smoke + tag

- [ ] **Step 1: Build the .app**

```bash
./build-app.sh --sign 2>&1 | tail -10
```

- [ ] **Step 2: Manual smoke**

`open dist/Murmur.app`. With a track loaded on Deck 1:

1. Wait for analysis — BPM appears in cyan, **key + Camelot** appear next to it in yellow (e.g., "D minor · 7A"). Console.app should show `[Analysis] track → BPM=…, key=… (…)`.
2. Re-loading the same track is still instant (cache hit) AND the key is restored from cache (no re-analysis).
3. Click the **ECHO** toggle on Deck 1 — playback should pick up a quarter-note echo behind it. Knob the **WET** dial up — echo gets louder.
4. Click **⅛** in the BEAT picker — echo's rhythmic feel halves.
5. Click **REV** toggle — adds reverb. Knob the **WET** dial — reverb gets wetter.
6. Drag the **TEMPO** slider while echo is on — the echo time should track the new tempo (still aligned to the same beat fraction).
7. Toggle both effects off — sound returns to dry.
8. Verify a track in a different key shows a different musical name + Camelot.

- [ ] **Step 3: Tag the milestone**

```bash
git tag -a phase-3-fx-and-key -m "Pocket DJ Phase 3: Echo + Reverb effects, key detection"
```

---

## Out of scope for Phase 3

- Headphone cue (needs separate AVAudioEngine output device routing)
- Key-compatible track highlighting in a library panel (requires library UI, Phase 6)
- Additional decks 3 + 4 (Phase 5 stretch)
- 3D booth visuals (separate phase)
- Flanger / phaser / bit-crusher / other DJ effects

---

## Self-Review

- **§5.5 Effects rack — Echo + Reverb + Flanger + Filter:** Phase 3 ships Echo + Reverb. Filter is already in `ChannelStrip` (Phase 1). Flanger deferred — no built-in AVAudioUnit, would need custom Audio Unit work.
- **§5.5 Per-deck FX assigns:** ✅ Echo + Reverb are both per-deck.
- **§5.5 Beat-synced echo:** ✅ `setEchoBeatDivider` derives from `bpm * tempoRate`.
- **§5.3 Key detection:** ✅ Chromagram + Krumhansl, both musical + Camelot stored, displayed on deck.
- **§5.3 Compatible-key highlight:** deferred — needs library panel.
- **§5.3 Key shift:** deferred to a later phase.

No spec gaps for the in-scope set. Type signatures consistent: `EffectsChain.echoEnabled/echoWet/reverbEnabled/reverbWet/setEchoBeatDivider`, `DeckState.echoEnabled/echoWet/echoDivider/reverbEnabled/reverbWet/keyName/camelot`, `KeyDetector.Result.keyName/camelot`, `TrackMetadata.keyName/camelot`.
