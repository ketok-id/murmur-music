# Pocket DJ Phase 9 — Pro Waveform (Frequency-Colored)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the single-color cyan/orange waveform with a Serato-style frequency-colored one. Each peak bin's color reflects the relative energy in three bands (low / mid / high), so the user can see at a glance: bass-heavy drops glow red, vocal verses glow green, percussive sections glow blue, and dense full-range mixes are white.

**Architecture:** A new `BandExtractor` runs an FFT (vDSP) over the audio in 2048-sample windows with 50% overlap, integrating spectral magnitude into 3 frequency bands per window: low (20–250 Hz), mid (250–4000 Hz), high (4000+ Hz). FFT windows are then averaged into the same number of bins as the existing peaks, producing a parallel `[Float]` of length `N×3` (interleaved low/mid/high per bin). Stored as a sidecar binary file (`*.bands`) next to the existing `*.peaks` file, referenced from a new `bandPeaksPath` field on `TrackMetadata`. `DeckState` exposes both arrays. `WaveformView` blends per-bin RGB from band energies, falling back to plain tint when band data is missing.

**Tech Stack:** Accelerate (`vDSP_fft_zrip`) — same FFT setup pattern already used in `KeyDetector`. No new SwiftPM dependencies.

**Testing:** `swift build -c release` + final manual smoke in Task 7. No Co-Authored-By trailer in subagent commits.

**Prerequisites:** Phase 8 merged into `main`. WaveformView exists in single-tint form.

---

## File Structure

**New files:**

```
Sources/Murmur/Analysis/
  BandExtractor.swift     FFT-based 3-band peak extraction (interleaved low/mid/high)
```

**Modified files:**

- `Sources/Murmur/Analysis/TrackMetadata.swift` — add `bandPeaksPath: String`.
- `Sources/Murmur/Analysis/AnalysisService.swift` — compute band peaks alongside peaks + BPM + key.
- `Sources/Murmur/Decks/DeckState.swift` — add `bandPeaks: [Float]`.
- `Sources/Murmur/Decks/DeckController.swift` — restore + reset band peaks on load.
- `Sources/Murmur/Booth/WaveformView.swift` — blend RGB per bin from band peaks when present.

---

### Task 1: BandExtractor

**Files:**
- Create: `Sources/Murmur/Analysis/BandExtractor.swift`

Algorithm:
1. Decode the file to mono Float32 (same as `BPMDetector.readMono`).
2. Slide a 2048-sample Hann-windowed window across the audio with 50% overlap.
3. Per window: FFT → magnitude spectrum → sum bins into 3 bands by frequency cutoffs.
4. Map FFT windows to peak bins (multiple windows per bin → average).
5. Normalize the final array so the largest single-band value is 1.0.

- [ ] **Step 1: Implement**

```swift
import AVFoundation
import Accelerate

/// Extracts 3-band frequency energy per peak bin for waveform coloring.
///
/// Output: interleaved `[low0, mid0, high0, low1, mid1, high1, ...]` — `binCount × 3`
/// floats in 0…1 (normalized so the loudest single-band value is 1.0).
///
/// Band cutoffs:
///   - low:  20 – 250 Hz   (kick, sub-bass)
///   - mid:  250 – 4000 Hz (vocals, melody)
///   - high: 4000 Hz +     (cymbals, percussion, air)
enum BandExtractor {
    static let fftSize = 2048
    static let hopSize = 1024
    static let lowCutoffHz: Double = 250
    static let midCutoffHz: Double = 4000

    /// Synchronously extract band peaks. Call from a background queue.
    static func extract(from url: URL, binCount: Int = 2000) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        let sampleRate = format.sampleRate

        let mono = try readMono(file: file)
        if mono.isEmpty { return [] }

        let n = fftSize
        let log2n = vDSP_Length(log2(Double(n)))
        guard let setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else {
            return []
        }
        defer { vDSP_destroy_fftsetup(setup) }

        var window = [Float](repeating: 0, count: n)
        vDSP_hann_window(&window, vDSP_Length(n), Int32(vDSP_HANN_NORM))

        let halfN = n / 2
        var realp = [Float](repeating: 0, count: halfN)
        var imagp = [Float](repeating: 0, count: halfN)
        var magnitudes = [Float](repeating: 0, count: halfN)

        let binHz = sampleRate / Double(n)
        let lowBandBin = max(1, Int(lowCutoffHz / binHz))
        let midBandBin = max(lowBandBin + 1, Int(midCutoffHz / binHz))

        // Per FFT window: (low, mid, high) total magnitudes.
        var fftLow = [Float]()
        var fftMid = [Float]()
        var fftHigh = [Float]()
        fftLow.reserveCapacity(mono.count / hopSize)
        fftMid.reserveCapacity(mono.count / hopSize)
        fftHigh.reserveCapacity(mono.count / hopSize)

        var pos = 0
        while pos + n <= mono.count {
            var frame = [Float](repeating: 0, count: n)
            vDSP_vmul(Array(mono[pos..<pos + n]), 1, window, 1, &frame, 1, vDSP_Length(n))

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

            var low: Float = 0
            var mid: Float = 0
            var high: Float = 0
            for bin in 1..<halfN {
                let m = magnitudes[bin]
                if bin < lowBandBin { low += m }
                else if bin < midBandBin { mid += m }
                else { high += m }
            }
            fftLow.append(low)
            fftMid.append(mid)
            fftHigh.append(high)
            pos += hopSize
        }

        let windowCount = fftLow.count
        guard windowCount > 0 else { return [] }

        // Map FFT windows → peak bins. Each bin averages N consecutive FFT windows.
        var output = [Float](repeating: 0, count: binCount * 3)
        var maxBand: Float = 0
        for binIdx in 0..<binCount {
            let startWin = Int(Double(binIdx) / Double(binCount) * Double(windowCount))
            let endWin = max(startWin + 1,
                             Int(Double(binIdx + 1) / Double(binCount) * Double(windowCount)))
            let clamped = min(endWin, windowCount)
            guard clamped > startWin else { continue }
            var low: Float = 0
            var mid: Float = 0
            var high: Float = 0
            for w in startWin..<clamped {
                low += fftLow[w]
                mid += fftMid[w]
                high += fftHigh[w]
            }
            let div = Float(clamped - startWin)
            let lowAvg = low / div
            let midAvg = mid / div
            let highAvg = high / div
            output[binIdx * 3 + 0] = lowAvg
            output[binIdx * 3 + 1] = midAvg
            output[binIdx * 3 + 2] = highAvg
            maxBand = max(maxBand, lowAvg, midAvg, highAvg)
        }

        // Normalize so the loudest band value across the whole track is 1.0.
        if maxBand > 0 {
            var scale = 1.0 / maxBand
            vDSP_vsmul(output, 1, &scale, &output, 1, vDSP_Length(output.count))
        }

        return output
    }

    /// Write `[Float]` to sidecar as raw Float32.
    static func writeBands(_ bands: [Float], to url: URL) throws {
        try bands.withUnsafeBufferPointer { buf in
            let data = Data(buffer: buf)
            try data.write(to: url, options: .atomic)
        }
    }

    /// Read sidecar back into `[Float]`.
    static func readBands(from url: URL) throws -> [Float] {
        let data = try Data(contentsOf: url)
        return data.withUnsafeBytes { raw -> [Float] in
            let floats = raw.bindMemory(to: Float.self)
            return Array(floats)
        }
    }

    /// Mono Float32 read (lifted from BPMDetector pattern).
    private static func readMono(file: AVAudioFile) throws -> [Float] {
        let format = file.processingFormat
        let chunkFrames: AVAudioFrameCount = 32768
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunkFrames) else {
            throw NSError(domain: "BandExtractor", code: 1)
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
}
```

- [ ] **Step 2: Build**

```bash
cd /Users/mm/Documents/youtube-audio-widget
swift build -c release 2>&1 | tail -5
```

- [ ] **Step 3: Commit**

```bash
git add Sources/Murmur/Analysis/BandExtractor.swift
git commit -m "feat(analysis): add BandExtractor (FFT-based 3-band peaks)"
```

---

### Task 2: TrackMetadata + AnalysisService

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
    var keyName: String = ""
    var camelot: String = ""
    var title: String = ""
    var artist: String = ""
    var album: String = ""
    var artworkPath: String = ""
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
    var title: String = ""
    var artist: String = ""
    var album: String = ""
    var artworkPath: String = ""
    var bandPeaksPath: String = ""
}
```

- [ ] **Step 2: Extend AnalysisService.Result and runAnalysis**

Open `Sources/Murmur/Analysis/AnalysisService.swift`. Find the `Result` struct:

```swift
    struct Result {
        let url: URL
        let metadata: TrackMetadata
        let peaks: [Float]
    }
```

Replace with:
```swift
    struct Result {
        let url: URL
        let metadata: TrackMetadata
        let peaks: [Float]
        let bandPeaks: [Float]
    }
```

Find the existing cache-hit branch (top of `analyze(url:)`):

```swift
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
```

Replace with:
```swift
        if let cached = LibraryIndex.shared.metadata(forPath: path) {
            let peaksURL = LibraryIndex.peaksDirectory.appendingPathComponent(cached.peaksPath)
            if FileManager.default.fileExists(atPath: peaksURL.path),
               let peaks = try? PeakExtractor.readPeaks(from: peaksURL) {
                var bandPeaks: [Float] = []
                if !cached.bandPeaksPath.isEmpty {
                    let bandURL = LibraryIndex.peaksDirectory.appendingPathComponent(cached.bandPeaksPath)
                    if FileManager.default.fileExists(atPath: bandURL.path) {
                        bandPeaks = (try? BandExtractor.readBands(from: bandURL)) ?? []
                    }
                }
                resultQueue.async {
                    completion(Result(url: url, metadata: cached, peaks: peaks, bandPeaks: bandPeaks))
                }
                return
            }
        }
```

Then find the body of `runAnalysis(url:)`. Replace the ENTIRE method with:

```swift
    private func runAnalysis(url: URL) -> Result? {
        do {
            let peaks = try PeakExtractor.extract(from: url)
            let bands = (try? BandExtractor.extract(from: url)) ?? []
            let bpm = try BPMDetector.detect(from: url)
            let keyResult = (try? KeyDetector.detect(from: url))
                ?? KeyDetector.Result(keyName: "", camelot: "")
            let meta = runMetadataExtract(url: url)
            let file = try AVAudioFile(forReading: url)
            let duration = Double(file.length) / file.processingFormat.sampleRate

            let baseName = url.deletingPathExtension().lastPathComponent + "-" +
                String(url.path.hashValue, radix: 16)
            let peaksFilename = baseName + ".peaks"
            let bandsFilename = baseName + ".bands"
            let peaksURL = LibraryIndex.peaksDirectory.appendingPathComponent(peaksFilename)
            let bandsURL = LibraryIndex.peaksDirectory.appendingPathComponent(bandsFilename)
            try PeakExtractor.writePeaks(peaks, to: peaksURL)
            if !bands.isEmpty {
                try? BandExtractor.writeBands(bands, to: bandsURL)
            }

            let metadata = TrackMetadata(
                bpm: bpm,
                duration: duration,
                firstBeat: 0,
                peaksPath: peaksFilename,
                hotCues: [],
                keyName: keyResult.keyName,
                camelot: keyResult.camelot,
                title: meta.title,
                artist: meta.artist,
                album: meta.album,
                artworkPath: meta.artworkPath,
                bandPeaksPath: bands.isEmpty ? "" : bandsFilename
            )
            LibraryIndex.shared.setMetadata(metadata, forPath: url.path)

            NSLog("[Analysis] %@ → BPM=%.2f, key=%@ (%@), \"%@\" by %@, duration=%.1fs, bands=%d",
                  url.lastPathComponent, bpm,
                  keyResult.keyName.isEmpty ? "?" : keyResult.keyName,
                  keyResult.camelot.isEmpty ? "?" : keyResult.camelot,
                  meta.title, meta.artist.isEmpty ? "unknown" : meta.artist,
                  duration, bands.count / 3)
            return Result(url: url, metadata: metadata, peaks: peaks, bandPeaks: bands)
        } catch {
            NSLog("[Analysis] failed for \(url.lastPathComponent): \(error)")
            return nil
        }
    }
```

- [ ] **Step 3: Build and commit**

```bash
swift build -c release 2>&1 | tail -10
git add Sources/Murmur/Analysis/TrackMetadata.swift Sources/Murmur/Analysis/AnalysisService.swift
git commit -m "feat(analysis): extract and cache 3-band peaks alongside amplitude peaks"
```

---

### Task 3: DeckState + DeckController

**Files:**
- Modify: `Sources/Murmur/Decks/DeckState.swift`
- Modify: `Sources/Murmur/Decks/DeckController.swift`

- [ ] **Step 1: DeckState**

Find the Phase 5 property block. After `@Published var artworkPath: String = ""`, add:

```swift

    /// Interleaved low/mid/high band energies per peak bin, 0..1 normalized.
    /// Empty when not yet analyzed.
    @Published var bandPeaks: [Float] = []
```

- [ ] **Step 2: DeckController — restore band peaks**

Find the analysis completion block. It currently ends with:

```swift
                self.state.title = result.metadata.title
                self.state.artist = result.metadata.artist
                self.state.album = result.metadata.album
                self.state.artworkPath = result.metadata.artworkPath
            }
```

Replace with:
```swift
                self.state.title = result.metadata.title
                self.state.artist = result.metadata.artist
                self.state.album = result.metadata.album
                self.state.artworkPath = result.metadata.artworkPath
                self.state.bandPeaks = result.bandPeaks
            }
```

- [ ] **Step 3: DeckController — reset on load (both paths)**

There are TWO reset blocks in `load(url:)` (one in success, one in catch). Both end with:

```swift
            state.title = ""
            state.artist = ""
            state.album = ""
            state.artworkPath = ""
```

Replace BOTH occurrences with:
```swift
            state.title = ""
            state.artist = ""
            state.album = ""
            state.artworkPath = ""
            state.bandPeaks = []
```

- [ ] **Step 4: Build and commit**

```bash
swift build -c release 2>&1 | tail -5
git add Sources/Murmur/Decks/DeckState.swift Sources/Murmur/Decks/DeckController.swift
git commit -m "feat(decks): expose and restore band peaks per deck"
```

---

### Task 4: WaveformView — RGB blend per bin

**Files:**
- Modify: `Sources/Murmur/Booth/WaveformView.swift`

The current view takes `peaks: [Float]` (interleaved min/max amplitude). We're going to optionally take `bandPeaks: [Float]` (interleaved low/mid/high energy 0..1) and use it to color each bin. If bandPeaks is empty, fall back to the single-tint render.

- [ ] **Step 1: Update the view signature + blend math**

Replace the ENTIRE contents of `Sources/Murmur/Booth/WaveformView.swift` with:

```swift
import SwiftUI

/// Renders an interleaved min/max peaks array as a stereo-look waveform with
/// a playhead. When `bandPeaks` is non-empty, each bin is tinted by an RGB
/// blend of its low/mid/high frequency energy (Serato-style): bass→red,
/// mid→green, high→blue. White = full-range mix.
struct WaveformView: View {
    let peaks: [Float]
    let bandPeaks: [Float]   // Interleaved low/mid/high per bin, 0..1. Empty = plain tint.
    let progress: Double
    var tint: Color = .cyan

    var body: some View {
        Canvas { context, size in
            guard peaks.count >= 2 else { return }
            let pairCount = peaks.count / 2
            let stepX = size.width / CGFloat(pairCount)
            let midY = size.height / 2
            let useBands = bandPeaks.count >= pairCount * 3

            for i in 0..<pairCount {
                let x = CGFloat(i) * stepX + stepX / 2
                let minV = CGFloat(peaks[i * 2])
                let maxV = CGFloat(peaks[i * 2 + 1])

                let color: Color
                if useBands {
                    let low = CGFloat(bandPeaks[i * 3])
                    let mid = CGFloat(bandPeaks[i * 3 + 1])
                    let high = CGFloat(bandPeaks[i * 3 + 2])
                    color = Color(
                        red:   min(1, 0.15 + low * 1.2),
                        green: min(1, 0.15 + mid * 1.2),
                        blue:  min(1, 0.15 + high * 1.2),
                        opacity: 0.95
                    )
                } else {
                    color = tint.opacity(0.85)
                }

                var path = Path()
                path.move(to: CGPoint(x: x, y: midY - maxV * midY))
                path.addLine(to: CGPoint(x: x, y: midY - minV * midY))
                context.stroke(path, with: .color(color), lineWidth: max(1, stepX * 0.9))
            }

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

- [ ] **Step 2: Update DeckView call site**

Open `Sources/Murmur/Booth/DeckView.swift`. Find:

```swift
                WaveformView(
                    peaks: state.peaks,
                    progress: state.durationSeconds > 0 ? state.currentTimeSeconds / state.durationSeconds : 0,
                    tint: tint
                )
```

Replace with:
```swift
                WaveformView(
                    peaks: state.peaks,
                    bandPeaks: state.bandPeaks,
                    progress: state.durationSeconds > 0 ? state.currentTimeSeconds / state.durationSeconds : 0,
                    tint: tint
                )
```

- [ ] **Step 3: Build and commit**

```bash
swift build -c release 2>&1 | tail -10
git add Sources/Murmur/Booth/WaveformView.swift Sources/Murmur/Booth/DeckView.swift
git commit -m "feat(booth): frequency-colored waveform via 3-band RGB blend"
```

---

### Task 5: Build bundle + smoke + tag + merge

- [ ] **Step 1: Build**

```bash
./build-app.sh --sign 2>&1 | tail -10
```

- [ ] **Step 2: Manual smoke**

`open dist/Murmur.app`. Open booth, load a fresh track (one not yet analyzed, OR delete `~/Library/Application Support/Murmur/library.json` to force re-analysis of all tracks).

1. After analysis (may take ~1s longer than before due to FFT cost), the waveform is **no longer monochrome cyan/orange**. Each vertical bar is colored by frequency content:
   - **Bass-heavy** sections → red/orange
   - **Vocal/melody** sections → green/yellow
   - **Hi-hat / cymbal** sections → blue
   - **Full-range** mixes → white
2. Console.app, filter "Murmur": `[Analysis] track.m4a → BPM=…, key=…, "title" by artist, duration=…, bands=2000`. The `bands=2000` confirms band extraction worked.
3. Reload the same track → instant (cache hit). Colors are unchanged.
4. Load a track without band peaks (e.g., legacy cache from before Phase 9):
   - The library.json has the track but `bandPeaksPath` is empty.
   - WaveformView falls back to plain tint color (cyan/orange) — no errors, no flicker.
   - Re-analyzing the file (delete its sidecar manually OR clear library.json) gets it colored on next load.
5. Compare two visually-different tracks: a vocal-heavy pop song should look more green; a percussion-heavy hip-hop track more blue; a dubstep drop more red. The visual gives genuine information about the track.

Note: re-analyzing every track takes time. To do it in bulk:
```bash
rm "$HOME/Library/Application Support/Murmur/library.json"
rm -rf "$HOME/Library/Application Support/Murmur/peaks"
```
Then reload each track in the app.

- [ ] **Step 3: Tag**

```bash
git tag -a phase-9-pro-waveform -m "Pocket DJ Phase 9: 3-band frequency-colored waveform"
```

- [ ] **Step 4: Merge to main**

```bash
git checkout main
git merge --no-ff pocket-dj-phase-9 -m "Merge phase 9: frequency-colored waveform"
./build-app.sh --sign 2>&1 | tail -5
```

---

## Out of Scope for Phase 9

- **Scrolling detail view** zoomed in around the playhead — a second waveform below the overview. Defer if useful.
- **Band-aware loop quantization** — quantizing loops to perceptually "good" boundaries based on band energy.
- **User-tunable band cutoffs** — the 250 / 4000 Hz boundaries are hardcoded; advanced users might want to tweak.
- **Migrating old cached tracks** — they re-analyze on next load if their `bandPeaksPath` is empty. No bulk migration script.

---

## Self-Review

- **§ Phase 9 plan: frequency-colored waveform with low/mid/high band coloring:** ✅ FFT-based via `BandExtractor`.
- **Backward compat:** ✅ Tracks without `bandPeaksPath` (legacy cache) render with the plain tint via the `useBands` fallback.
- **Cache sidecar:** ✅ Stored as `.bands` next to existing `.peaks` in the peaks directory.
- **Normalization:** ✅ Band magnitudes are normalized so the max single-band value across the track is 1.0 — keeps coloring stable across tracks of different loudness.
- **Type signatures consistent:** `WaveformView.peaks/bandPeaks`, `DeckState.bandPeaks`, `TrackMetadata.bandPeaksPath`, `AnalysisService.Result.bandPeaks`.

No spec gaps for the in-scope set. No placeholders.
