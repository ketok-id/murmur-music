# Pocket DJ Phase 7 — Spinning Jog Wheels

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the small 44×44 album-art thumbnail on each deck with a 100×100 **spinning jog wheel**: a circular platter with the album art rotating on its center label, a beat-pulse halo that brightens on every beat, and a subtle 3D tilt so it feels physical. Iconic DJ visual, achievable in native SwiftUI with no WKWebView/Three.js complexity.

**Architecture:** A new `JogWheelView` uses SwiftUI's `TimelineView(.animation)` to drive a per-frame rotation angle derived from the deck's playhead, BPM, and tempo rate. Album art is rendered inside a clipped circular label at the wheel's center. A `Circle().stroke()` halo brightens via `opacity` driven by phase-within-beat. A `rotation3DEffect` tilts the wheel slightly off-axis for the 3D look. The wheel reads `DeckState.currentTimeSeconds`, `bpm`, `tempoRate`, and `artworkPath` — no new state.

**Tech Stack:** SwiftUI native — `Canvas`, `TimelineView`, `rotation3DEffect`, `NSImage`. No new dependencies, no JS, no WebGL.

**Testing:** `swift build -c release` + final manual smoke in Task 6. No Co-Authored-By trailer in subagent commits.

**Prerequisites:** Phase 6 merged into `main`. Each `DeckState` has `bpm`, `tempoRate`, `currentTimeSeconds`, `artworkPath`, `title`, `artist`.

---

## File Structure

**New files:**

```
Sources/Murmur/Booth/
  JogWheelView.swift     The spinning platter with art + halo + 3D tilt
```

**Modified files:**

- `Sources/Murmur/Booth/DeckView.swift` — replace the 44×44 `AlbumArtView` + title/artist row with a 100×100 `JogWheelView` + larger title/artist column.
- `Sources/Murmur/Booth/BoothView.swift` — bump `minHeight` to fit the larger top row.
- `Sources/Murmur/Booth/BoothWindowController.swift` — bump initial size + min size.

---

### Task 1: JogWheelView

**Files:**
- Create: `Sources/Murmur/Booth/JogWheelView.swift`

The wheel spins at the track's effective BPM (bpm × tempoRate). One full revolution per bar (4 beats) — that's the classic DJ platter rate where each side of the label crosses the cue marker once per bar.

- [ ] **Step 1: Implement `JogWheelView`**

```swift
import AppKit
import SwiftUI

/// A circular platter that rotates at the deck's beat rate, with album art
/// on its center label, a beat-pulse halo ring, and a subtle 3D tilt.
///
/// Rotation rate: one revolution per bar (4 beats) — a deliberate slow rate
/// that reads as "playing" without being dizzying.
struct JogWheelView: View {
    @ObservedObject var state: DeckState
    var tint: Color = .cyan
    var size: CGFloat = 100

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            let now = timeline.date.timeIntervalSinceReferenceDate
            let rotation = currentRotation(at: now)
            let pulse = beatPulse(at: now)

            ZStack {
                // Halo ring (audio-reactive on beat).
                Circle()
                    .stroke(tint, lineWidth: 2)
                    .blur(radius: 1.5)
                    .opacity(0.25 + 0.55 * pulse)
                    .scaleEffect(1.0 + 0.04 * pulse)

                // Platter base.
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color(white: 0.18), Color(white: 0.05)],
                            center: .center, startRadius: size * 0.05, endRadius: size * 0.55
                        )
                    )
                    .overlay(
                        Circle().stroke(Color.white.opacity(0.08), lineWidth: 1)
                    )

                // Grooves — concentric rings that imply vinyl.
                ForEach(0..<6, id: \.self) { i in
                    Circle()
                        .stroke(Color.white.opacity(0.04), lineWidth: 0.5)
                        .frame(width: size * (0.55 + CGFloat(i) * 0.07),
                               height: size * (0.55 + CGFloat(i) * 0.07))
                }

                // Album art on the center label.
                centerLabel
                    .rotationEffect(.radians(rotation))

                // Cue marker — a tiny notch at the top of the platter (does NOT rotate).
                Circle()
                    .fill(tint)
                    .frame(width: 4, height: 4)
                    .shadow(color: tint.opacity(0.8), radius: 2)
                    .offset(y: -size * 0.46)
            }
            .frame(width: size, height: size)
            .rotation3DEffect(.degrees(18), axis: (x: 1, y: 0, z: 0), perspective: 0.6)
            .shadow(color: .black.opacity(0.6), radius: 10, x: 0, y: 4)
        }
    }

    /// Album art on the platter's center, sized to ~45% of platter diameter,
    /// with a small dark ring around it.
    private var centerLabel: some View {
        let labelSize = size * 0.45
        return ZStack {
            Group {
                if let img = loadArtwork() {
                    Image(nsImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    LinearGradient(
                        colors: [tint.opacity(0.4), Color(white: 0.1)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                    .overlay(
                        Image(systemName: "music.note")
                            .font(.system(size: labelSize * 0.4))
                            .foregroundColor(.white.opacity(0.4))
                    )
                }
            }
            .frame(width: labelSize, height: labelSize)
            .clipShape(Circle())
            .overlay(Circle().stroke(Color.white.opacity(0.15), lineWidth: 1))
            .overlay(
                // Spindle hole.
                Circle().fill(Color.black)
                    .frame(width: labelSize * 0.08, height: labelSize * 0.08)
            )
        }
    }

    /// Current rotation angle in radians, computed from the deck's effective BPM
    /// and elapsed playback time. 1 revolution per bar (4 beats).
    private func currentRotation(at wallTime: Double) -> Double {
        guard state.bpm > 0 else { return 0 }
        guard state.isPlaying else {
            // When paused, freeze rotation at a position derived from
            // currentTimeSeconds alone (no wall-clock contribution).
            return rotation(forPlayhead: state.currentTimeSeconds)
        }
        // Continuous rotation while playing: derive from currentTimeSeconds.
        // currentTimeSeconds advances at the audio clock rate, which already
        // accounts for tempoRate (via AVAudioUnitTimePitch). So 1 rev per bar
        // of audible time.
        return rotation(forPlayhead: state.currentTimeSeconds)
    }

    private func rotation(forPlayhead t: Double) -> Double {
        let effectiveBPM = state.bpm * Double(state.tempoRate)
        let beatsPerSecond = effectiveBPM / 60.0
        // 1 revolution per 4 beats = beatsPerSecond / 4 revolutions per second.
        return t * (beatsPerSecond / 4.0) * (2 * .pi)
    }

    /// Beat-pulse intensity 0…1, peaking on each beat and decaying.
    private func beatPulse(at wallTime: Double) -> Double {
        guard state.bpm > 0, state.isPlaying else { return 0 }
        let effectiveBPM = state.bpm * Double(state.tempoRate)
        let beatInterval = 60.0 / effectiveBPM
        let offsetFromFirst = state.currentTimeSeconds - state.firstBeat
        let phase = (offsetFromFirst / beatInterval).truncatingRemainder(dividingBy: 1)
        let phaseInBeat = phase < 0 ? phase + 1 : phase
        // Triangle pulse: rises sharply at beat boundary, decays over the rest.
        // 0.0 = on the beat → peak intensity 1.0.
        // Decay over ~50ms of the beat for a sharp visible pulse.
        let decay = max(0, 1.0 - phaseInBeat * 20.0)
        return decay
    }

    private func loadArtwork() -> NSImage? {
        guard !state.artworkPath.isEmpty else { return nil }
        let url = LibraryIndex.artworkDirectory.appendingPathComponent(state.artworkPath)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return NSImage(contentsOf: url)
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
git add Sources/Murmur/Booth/JogWheelView.swift
git commit -m "feat(booth): add JogWheelView with spinning platter + beat halo"
```

---

### Task 2: Replace AlbumArtView row in DeckView with JogWheelView

**Files:**
- Modify: `Sources/Murmur/Booth/DeckView.swift`

- [ ] **Step 1: Replace the top row**

Find this block (added in Phase 5):

```swift
            HStack(alignment: .top, spacing: 10) {
                AlbumArtView(artworkPath: state.artworkPath, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(displayTitle)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    if !state.artist.isEmpty {
                        Text(state.artist)
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.55))
                            .lineLimit(1)
                    }
                }
                Spacer()
            }
```

Replace with:

```swift
            HStack(alignment: .center, spacing: 14) {
                JogWheelView(state: state, tint: tint, size: 96)
                VStack(alignment: .leading, spacing: 4) {
                    Text(displayTitle)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    if !state.artist.isEmpty {
                        Text(state.artist)
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.6))
                            .lineLimit(1)
                    }
                    if !state.album.isEmpty {
                        Text(state.album)
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.4))
                            .lineLimit(1)
                    }
                }
                Spacer()
            }
            .frame(height: 100)
```

- [ ] **Step 2: Build**

```bash
swift build -c release 2>&1 | tail -5
```

- [ ] **Step 3: Commit**

```bash
git add Sources/Murmur/Booth/DeckView.swift
git commit -m "feat(booth): replace album art with JogWheelView on each deck"
```

---

### Task 3: Bump booth window size

**Files:**
- Modify: `Sources/Murmur/Booth/BoothView.swift`
- Modify: `Sources/Murmur/Booth/BoothWindowController.swift`

The jog wheel adds ~60px of height to each deck panel (44px album art → 100px wheel). Need to grow the booth window.

- [ ] **Step 1: Update BoothView minHeight**

Open `Sources/Murmur/Booth/BoothView.swift`. Find:

```swift
        .frame(minWidth: 1000, minHeight: 840)
```

Replace with:

```swift
        .frame(minWidth: 1000, minHeight: 900)
```

- [ ] **Step 2: Update BoothWindowController**

Open `Sources/Murmur/Booth/BoothWindowController.swift`. Find:

```swift
        win.setContentSize(NSSize(width: 1100, height: 900))
        win.contentMinSize = NSSize(width: 1000, height: 840)
```

Replace with:

```swift
        win.setContentSize(NSSize(width: 1100, height: 960))
        win.contentMinSize = NSSize(width: 1000, height: 900)
```

- [ ] **Step 3: Build and commit**

```bash
swift build -c release 2>&1 | tail -5
git add Sources/Murmur/Booth/BoothView.swift Sources/Murmur/Booth/BoothWindowController.swift
git commit -m "feat(booth): grow window to fit jog wheels"
```

---

### Task 4: Build bundle + smoke + tag + merge

- [ ] **Step 1: Build the .app bundle**

```bash
./build-app.sh --sign 2>&1 | tail -10
```

- [ ] **Step 2: Manual smoke**

`open dist/Murmur.app`. Open the booth.

1. Each deck now has a **100×100 spinning platter** in place of the small album art.
2. The platter has a subtle **3D tilt** (top tilted slightly back).
3. The center label shows the **album art** (or a music-note placeholder if none).
4. A tiny **cyan cue marker** sits at the top of the platter (doesn't rotate — it's a fixed reference).
5. Load a track and play it. The platter **rotates** at "one revolution per bar" — slow, dignified, easy to track visually. (For a 120 BPM track, one full rev takes 2 seconds.)
6. On each beat, a **halo ring** around the platter brightens momentarily — visible as a quick cyan flash.
7. Drag the tempo slider while playing — rotation speed changes smoothly (it tracks effective BPM = bpm × tempoRate).
8. Pause playback — platter freezes immediately. Resume — rotation continues from its current position.
9. Track with no artwork → music-note placeholder fills the label. Track with art → real cover spins on the label.
10. Watch BOTH decks playing in SYNC — wheels should rotate at the same rate, halos pulse in sync when phase is locked.

Performance check: CPU should stay reasonable. The TimelineView animates at 30 fps; total per-frame work is two SwiftUI shape renders + an `NSImage` lookup. Should be cheap.

- [ ] **Step 3: Tag**

```bash
git tag -a phase-7-jog-wheels -m "Pocket DJ Phase 7: spinning jog wheels with beat pulse"
```

- [ ] **Step 4: Merge to main**

```bash
git checkout main
git merge --no-ff pocket-dj-phase-7 -m "Merge phase 7: spinning jog wheels"
./build-app.sh --sign 2>&1 | tail -5
```

---

## Out of Scope for Phase 7

- Scratch interaction (drag wheel to scrub). Adds complex pointer-event handling; deferred.
- Configurable revolutions-per-bar (some users prefer 1 rev per beat). Hardcoded 1/4 for v1.
- True 3D rendering via SceneKit / Three.js. The SwiftUI `rotation3DEffect` + radial gradient + grooves gives a "good enough 3D" without a new render pipeline.
- Per-deck wheel size customization.

---

## Self-Review

- **§6.1 3D booth — spinning jog wheels:** ✅ Implemented as a SwiftUI native component with `rotation3DEffect` for the perspective.
- **§6.2 Beat-pulse halo:** ✅ Audio-clock-driven via `state.currentTimeSeconds` + `firstBeat` + `bpm`.
- **§6.3 Album art on platter:** ✅ Center label uses the same `LibraryIndex.artworkDirectory` PNG sidecars from Phase 5.
- **§7.4 Visual layer locked to audio clock:** ✅ Rotation derived from `currentTimeSeconds` (audio-clock-paced) rather than wall time, so it can't drift from audible playback.
- **Scratch interaction:** explicitly deferred (out of scope §1).

No spec gaps for the in-scope set. No placeholders. Type signatures consistent — `JogWheelView` reads `DeckState.bpm`, `tempoRate`, `currentTimeSeconds`, `firstBeat`, `isPlaying`, `artworkPath` (all existing).
