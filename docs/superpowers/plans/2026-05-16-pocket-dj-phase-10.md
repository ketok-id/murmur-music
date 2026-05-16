# Pocket DJ Phase 10 — Scrolling Detail Waveform

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a zoomed-in waveform below each deck's overview, showing ~10 seconds of audio around the playhead and scrolling left as the track plays. Pro DJ apps call this the "detail view" — it makes beat-level features (transients, kicks, breakdowns) visible without dragging the overview. Reuses Phase 9's frequency colors.

**Architecture:** A new `DetailWaveformView` reads the same `peaks` + `bandPeaks` arrays but renders only the bins within a window of `±N` seconds around the current playhead. The view's content shifts visually so the playhead stays fixed at the center of the view. Beat-grid lines from `BeatGridOverlay` are reused — they auto-position correctly given the time → x mapping. The detail view sits between the overview waveform and the sync controls in `DeckView`.

**Tech Stack:** SwiftUI native — same `Canvas` primitives as Phase 9. No new dependencies.

**Testing:** `swift build -c release` + final manual smoke in Task 5. No Co-Authored-By trailer in subagent commits.

**Prerequisites:** Phase 9 merged into `main`. `WaveformView` exists with frequency coloring.

---

## File Structure

**New files:**

```
Sources/Murmur/Booth/
  DetailWaveformView.swift   Zoomed scrolling waveform, peaks + bandPeaks + beat grid
```

**Modified files:**

- `Sources/Murmur/Booth/DeckView.swift` — insert `DetailWaveformView` between the overview waveform and the sync controls.
- `Sources/Murmur/Booth/BoothView.swift` — bump `minHeight` to fit the new detail row.
- `Sources/Murmur/Booth/BoothWindowController.swift` — bump initial size + min size.

---

### Task 1: DetailWaveformView

**Files:**
- Create: `Sources/Murmur/Booth/DetailWaveformView.swift`

Time window: 10 seconds total (5s before playhead, 5s after). Configurable via `viewWindowSeconds` parameter.

Beat grid: same algorithm as `BeatGridOverlay` but shifted so playhead is at center.

- [ ] **Step 1: Implement**

```swift
import SwiftUI

/// A zoomed-in waveform showing `viewWindowSeconds` of audio around the current
/// playhead. The playhead stays fixed at the horizontal center of the view;
/// the audio scrolls left as the track plays.
///
/// Reuses Phase 9's frequency coloring (`bandPeaks`) when available.
/// Renders beat-grid lines using the same `firstBeat` + `bpm` model as
/// `BeatGridOverlay`.
struct DetailWaveformView: View {
    let peaks: [Float]
    let bandPeaks: [Float]
    let bpm: Double
    let firstBeat: Double
    let duration: Double
    let currentTimeSeconds: Double
    var tint: Color = .cyan
    /// Total seconds visible in the view window (split equally before/after the playhead).
    var viewWindowSeconds: Double = 10

    var body: some View {
        Canvas { context, size in
            guard peaks.count >= 2, duration > 0 else {
                drawPlaceholder(context: context, size: size)
                return
            }
            let pairCount = peaks.count / 2
            let useBands = bandPeaks.count >= pairCount * 3

            // Time → x mapping inside the visible window.
            let half = viewWindowSeconds / 2
            let viewStart = currentTimeSeconds - half
            let viewEnd = currentTimeSeconds + half
            let pxPerSecond = size.width / CGFloat(viewWindowSeconds)
            let midY = size.height / 2

            // Iterate only over the peak bins that fall in the visible window.
            let firstBin = max(0, Int((viewStart / duration) * Double(pairCount)))
            let lastBin = min(pairCount, Int((viewEnd / duration) * Double(pairCount)) + 1)
            guard lastBin > firstBin else {
                drawPlaceholder(context: context, size: size)
                return
            }

            // Stride: pick at most ~200 visible bins so the detail view renders smoothly.
            let visibleBins = lastBin - firstBin
            let stride = max(1, visibleBins / 200)

            var i = firstBin
            while i < lastBin {
                // The center time of this bin.
                let binCenterT = (Double(i) + 0.5) / Double(pairCount) * duration
                let x = CGFloat(binCenterT - viewStart) * pxPerSecond
                guard x >= -2 && x <= size.width + 2 else {
                    i += stride
                    continue
                }
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
                let widthPx = max(1.5, CGFloat(stride) * pxPerSecond * (duration / Double(pairCount)))
                context.stroke(path, with: .color(color), lineWidth: widthPx)
                i += stride
            }

            // Beat grid (bar lines brighter, every 4 beats).
            if bpm > 0 {
                let beatInterval = 60.0 / bpm
                // Start at the first beat at or before viewStart.
                var beatT = firstBeat
                if beatT > viewStart {
                    let count = ceil((beatT - viewStart) / beatInterval)
                    beatT -= count * beatInterval
                } else {
                    let count = floor((viewStart - beatT) / beatInterval)
                    beatT += count * beatInterval
                }
                var beatIndex = Int(round((beatT - firstBeat) / beatInterval))
                while beatT <= viewEnd {
                    let x = CGFloat(beatT - viewStart) * pxPerSecond
                    if x >= 0 && x <= size.width {
                        let isBar = (beatIndex % 4 == 0)
                        var line = Path()
                        line.move(to: CGPoint(x: x, y: 0))
                        line.addLine(to: CGPoint(x: x, y: size.height))
                        context.stroke(
                            line,
                            with: .color(isBar ? tint.opacity(0.55) : tint.opacity(0.20)),
                            lineWidth: isBar ? 1.5 : 0.5
                        )
                    }
                    beatIndex += 1
                    beatT += beatInterval
                }
            }

            // Playhead at center.
            let center = size.width / 2
            var head = Path()
            head.move(to: CGPoint(x: center, y: 0))
            head.addLine(to: CGPoint(x: center, y: size.height))
            context.stroke(head, with: .color(.white), lineWidth: 2)

            // Triangle indicator above playhead.
            var tri = Path()
            tri.move(to: CGPoint(x: center - 5, y: 0))
            tri.addLine(to: CGPoint(x: center + 5, y: 0))
            tri.addLine(to: CGPoint(x: center, y: 6))
            tri.closeSubpath()
            context.fill(tri, with: .color(.white))
        }
        .background(Color.black.opacity(0.55))
        .cornerRadius(4)
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
    }

    private func drawPlaceholder(context: GraphicsContext, size: CGSize) {
        let center = size.width / 2
        var head = Path()
        head.move(to: CGPoint(x: center, y: 0))
        head.addLine(to: CGPoint(x: center, y: size.height))
        context.stroke(head, with: .color(.white.opacity(0.3)), lineWidth: 1)
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
git add Sources/Murmur/Booth/DetailWaveformView.swift
git commit -m "feat(booth): add DetailWaveformView (zoomed scrolling waveform)"
```

---

### Task 2: Wire DetailWaveformView into DeckView

**Files:**
- Modify: `Sources/Murmur/Booth/DeckView.swift`

- [ ] **Step 1: Insert below the overview waveform**

Find the existing waveform ZStack:

```swift
            ZStack {
                WaveformView(
                    peaks: state.peaks,
                    bandPeaks: state.bandPeaks,
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

Add IMMEDIATELY AFTER it (still inside the outer `VStack`):

```swift

            DetailWaveformView(
                peaks: state.peaks,
                bandPeaks: state.bandPeaks,
                bpm: state.bpm,
                firstBeat: state.firstBeat,
                duration: state.durationSeconds,
                currentTimeSeconds: state.currentTimeSeconds,
                tint: tint,
                viewWindowSeconds: 10
            )
            .frame(height: 40)
```

- [ ] **Step 2: Build and commit**

```bash
swift build -c release 2>&1 | tail -10
git add Sources/Murmur/Booth/DeckView.swift
git commit -m "feat(booth): add detail waveform row below each overview"
```

---

### Task 3: Bump booth window size

**Files:**
- Modify: `Sources/Murmur/Booth/BoothView.swift`
- Modify: `Sources/Murmur/Booth/BoothWindowController.swift`

The detail waveform adds 40px + spacing per deck panel. Need to grow the booth.

- [ ] **Step 1: Update BoothView minHeight**

Open `Sources/Murmur/Booth/BoothView.swift`. Find:

```swift
        .frame(minWidth: 1000, minHeight: 900)
```

Replace with:

```swift
        .frame(minWidth: 1000, minHeight: 960)
```

- [ ] **Step 2: Update BoothWindowController**

Open `Sources/Murmur/Booth/BoothWindowController.swift`. Find:

```swift
        win.setContentSize(NSSize(width: 1100, height: 960))
        win.contentMinSize = NSSize(width: 1000, height: 900)
```

Replace with:

```swift
        win.setContentSize(NSSize(width: 1100, height: 1020))
        win.contentMinSize = NSSize(width: 1000, height: 960)
```

- [ ] **Step 3: Build and commit**

```bash
swift build -c release 2>&1 | tail -5
git add Sources/Murmur/Booth/BoothView.swift Sources/Murmur/Booth/BoothWindowController.swift
git commit -m "feat(booth): grow window to fit detail waveform"
```

---

### Task 4: Build bundle + smoke + tag + merge

- [ ] **Step 1: Build the .app bundle**

```bash
./build-app.sh --sign 2>&1 | tail -10
```

- [ ] **Step 2: Manual smoke**

`open dist/Murmur.app`. Open booth.

1. **Below each deck's overview waveform**, there's a new **40px detail row** with a black-ish background. A vertical white **playhead line** with a tiny white triangle at the top sits at the **horizontal center**.
2. Load a track. Even before playing, the detail view shows the audio waveform around playback position 0 (the playhead is at center; the start of the track is at left).
3. Play the track. The waveform **scrolls leftward** under the fixed center playhead. Beat-grid lines move with the audio.
4. The detail waveform uses the **same frequency colors** as the overview (Phase 9 colors).
5. **Tempo changes** smoothly affect the scroll rate (because rendering is driven by `currentTimeSeconds`, which is audio-clock-paced).
6. **Pause** → scrolling stops. **Resume** → scrolling continues from the same position.
7. **Scrub via the jog wheel** → detail waveform jumps to the new position.
8. **At the start** or **end of the track**, the detail view shows what's available (audio on one side, blank on the other). Playhead stays centered; the waveform shifts to one side.

- [ ] **Step 3: Tag**

```bash
git tag -a phase-10-detail-waveform -m "Pocket DJ Phase 10: scrolling detail waveform"
```

- [ ] **Step 4: Merge to main**

```bash
git checkout main
git merge --no-ff pocket-dj-phase-10 -m "Merge phase 10: scrolling detail waveform"
./build-app.sh --sign 2>&1 | tail -5
```

---

## Out of Scope for Phase 10

- **Click-to-seek on the detail view** — could be added later; currently you scrub via the jog wheel.
- **Hot-cue / loop markers on the detail view** — overview shows them; detail doesn't, intentionally less busy.
- **Configurable zoom level** in the UI — hardcoded to 10s.
- **Smooth interpolation between adjacent bins** — current rendering shows vertical bars at peak-bin centers. Looks slightly steppy on very long tracks (where a 10s window spans only a few peak bins). Adequate for v1.

---

## Self-Review

- **Scrolling detail waveform** ✅ implemented with `currentTimeSeconds`-driven scroll.
- **Frequency coloring reused** ✅ same blend math as Phase 9's `WaveformView`.
- **Beat grid in detail view** ✅ same algorithm as `BeatGridOverlay`, time-aligned.
- **Performance** — the inner loop is O(visible_bins) capped at ~200 per frame via stride. Cheap.

No spec gaps for the in-scope set. Type signatures consistent.
