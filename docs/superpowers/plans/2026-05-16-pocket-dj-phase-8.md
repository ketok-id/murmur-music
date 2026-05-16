# Pocket DJ Phase 8 — Jog Wheel Scratch

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the spinning jog wheels from Phase 7 interactive. Drag a wheel horizontally to scrub the deck's playhead; release to resume playback at the new position. Brings the booth from "wheels spin and look pretty" to "wheels are a control surface."

**Architecture:** `DeckController` gets `beginScrub()` / `scrub(toSeconds:)` / `endScrub()` that pause the player on drag begin, seek without auto-resume during the drag, and restore play state on release. `JogWheelView` adds a `DragGesture(minimumDistance: 1)` that calls these via three closures the parent passes in. `BoothView` wires the closures to `mixer.deck1`/`deck2`. No state model changes.

**Scrub sensitivity:** 240 pixels of horizontal drag = 10 seconds of audio scrub. Tweak in JogWheelView if it feels too sensitive.

**Tech Stack:** Same as before. No new dependencies.

**Testing:** `swift build -c release` + manual smoke in Task 4.

**Prerequisites:** Phase 7 merged into `main`. JogWheelView is a 96px platter on each deck.

---

## File Structure

**Modified files only:**

- `Sources/Murmur/Decks/DeckController.swift` — add scrub methods.
- `Sources/Murmur/Booth/JogWheelView.swift` — add DragGesture + closures.
- `Sources/Murmur/Booth/BoothView.swift` — wire closures to deck controllers.

---

### Task 1: DeckController scrub methods

**Files:**
- Modify: `Sources/Murmur/Decks/DeckController.swift`

- [ ] **Step 1: Add scrub state and methods**

At the top of the `DeckController` class, after `let loopEngine = LoopEngine()`, add:

```swift
    /// True while a scrub gesture is in progress. Suppresses play-state mirror.
    private(set) var isScrubbing: Bool = false
    private var wasPlayingBeforeScrub: Bool = false
```

At the bottom of the class (after the existing `beatSnap(_:)` private helper, before the final closing `}`), add:

```swift
    // MARK: - Scrub (jog wheel)

    /// Begin a scrub gesture. Pauses playback and remembers whether to resume.
    func beginScrub() {
        guard state.isLoaded else { return }
        wasPlayingBeforeScrub = player.isPlaying
        if player.isPlaying { player.pause() }
        isScrubbing = true
        state.isPlaying = false
    }

    /// Seek to a target time during an active scrub. Does not auto-resume —
    /// `endScrub()` does that.
    func scrub(toSeconds seconds: Double) {
        guard isScrubbing, state.isLoaded else { return }
        let clamped = max(0, min(state.durationSeconds, seconds))
        player.seek(toSeconds: clamped)
        state.currentTimeSeconds = clamped
    }

    /// End the scrub. Restores playback state from before the scrub began.
    func endScrub() {
        guard isScrubbing else { return }
        isScrubbing = false
        if wasPlayingBeforeScrub {
            player.play()
            state.isPlaying = true
        }
    }
```

- [ ] **Step 2: Build and commit**

```bash
cd /Users/mm/Documents/youtube-audio-widget
swift build -c release 2>&1 | tail -5
git add Sources/Murmur/Decks/DeckController.swift
git commit -m "feat(decks): add beginScrub/scrub/endScrub to DeckController"
```

---

### Task 2: JogWheelView drag gesture

**Files:**
- Modify: `Sources/Murmur/Booth/JogWheelView.swift`

- [ ] **Step 1: Add closure properties + drag state**

Find the property block at the top of `struct JogWheelView`:

```swift
struct JogWheelView: View {
    @ObservedObject var state: DeckState
    var tint: Color = .cyan
    var size: CGFloat = 100
```

Add immediately after:

```swift
    /// Called once when the user starts dragging the wheel.
    var onScrubBegan: () -> Void = {}
    /// Called continuously with the target playhead time during drag.
    var onScrub: (Double) -> Void = { _ in }
    /// Called once when the drag ends.
    var onScrubEnded: () -> Void = {}

    /// Pixels of horizontal drag = `scrubPixelsPerSecond` seconds of audio.
    private let scrubPixelsPerSecond: CGFloat = 24

    @State private var dragStartSeconds: Double = 0
    @State private var dragActive: Bool = false
```

- [ ] **Step 2: Add the gesture to the outer ZStack**

Find the closing brace of the inner `ZStack { ... }` and the modifiers that follow it. Currently:

```swift
            .frame(width: size, height: size)
            .rotation3DEffect(.degrees(18), axis: (x: 1, y: 0, z: 0), perspective: 0.6)
            .shadow(color: .black.opacity(0.6), radius: 10, x: 0, y: 4)
        }
    }
```

Replace with:

```swift
            .frame(width: size, height: size)
            .rotation3DEffect(.degrees(18), axis: (x: 1, y: 0, z: 0), perspective: 0.6)
            .shadow(color: .black.opacity(0.6), radius: 10, x: 0, y: 4)
            .scaleEffect(dragActive ? 0.97 : 1.0)
            .animation(.easeOut(duration: 0.12), value: dragActive)
            .contentShape(Circle())
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { drag in
                        if !dragActive {
                            dragActive = true
                            dragStartSeconds = state.currentTimeSeconds
                            onScrubBegan()
                        }
                        let dtSeconds = Double(drag.translation.width / scrubPixelsPerSecond)
                        onScrub(dragStartSeconds + dtSeconds)
                    }
                    .onEnded { _ in
                        dragActive = false
                        onScrubEnded()
                    }
            )
        }
    }
```

- [ ] **Step 3: Build and commit**

```bash
swift build -c release 2>&1 | tail -5
git add Sources/Murmur/Booth/JogWheelView.swift
git commit -m "feat(booth): jog wheel drag-to-scrub gesture + active scale feedback"
```

---

### Task 3: BoothView — wire scrub closures

**Files:**
- Modify: `Sources/Murmur/Booth/BoothView.swift`

The Deck 1 + Deck 2 wiring happens inside `DeckView(...)`. JogWheelView is constructed inside DeckView with `JogWheelView(state: state, tint: tint, size: 96)` — we need a way to pass the scrub closures down.

Two approaches:
- (a) Add three new closure parameters to `DeckView`, threaded to `JogWheelView`.
- (b) Construct `JogWheelView` directly in BoothView with closures and pass it into DeckView as a parameter.

Going with (a) — it's the same pattern as every other deck callback.

- [ ] **Step 1: Add three closures to `DeckView`**

Open `Sources/Murmur/Booth/DeckView.swift`. Find the property block (last property is `var onToggleLoop: () -> Void`):

```swift
    var onToggleLoop: () -> Void
```

Add immediately after:

```swift
    var onScrubBegan: () -> Void
    var onScrub: (Double) -> Void
    var onScrubEnded: () -> Void
```

- [ ] **Step 2: Pass them into JogWheelView**

Find the existing `JogWheelView(state: state, tint: tint, size: 96)` call. Replace with:

```swift
                JogWheelView(
                    state: state,
                    tint: tint,
                    size: 96,
                    onScrubBegan: onScrubBegan,
                    onScrub: onScrub,
                    onScrubEnded: onScrubEnded
                )
```

- [ ] **Step 3: Wire BoothView**

Open `Sources/Murmur/Booth/BoothView.swift`. Both Deck 1 and Deck 2 are constructed with a `DeckView(...)` call. Find the Deck 1 call. After the existing `onToggleLoop: { mixer.deck1.toggleLoop() }`, add the three new closures:

```swift
                    onToggleLoop: { mixer.deck1.toggleLoop() },
                    onScrubBegan: { mixer.deck1.beginScrub() },
                    onScrub: { mixer.deck1.scrub(toSeconds: $0) },
                    onScrubEnded: { mixer.deck1.endScrub() }
                )
```

(Note the existing `onToggleLoop:` line ends with `}` — change that trailing `)` of the entire `DeckView(...)` call to come after the new closures. The added lines slot in between `onToggleLoop:` and the closing `)` of `DeckView(...)`.)

Do the SAME for Deck 2 — replace its `mixer.deck1` references with `mixer.deck2`:

```swift
                    onToggleLoop: { mixer.deck2.toggleLoop() },
                    onScrubBegan: { mixer.deck2.beginScrub() },
                    onScrub: { mixer.deck2.scrub(toSeconds: $0) },
                    onScrubEnded: { mixer.deck2.endScrub() }
                )
```

- [ ] **Step 4: Build and commit**

```bash
swift build -c release 2>&1 | tail -10
git add Sources/Murmur/Booth/DeckView.swift Sources/Murmur/Booth/BoothView.swift
git commit -m "feat(booth): wire jog wheel scrub to DeckControllers"
```

---

### Task 4: Build bundle + smoke + tag + merge

- [ ] **Step 1: Build**

```bash
./build-app.sh --sign 2>&1 | tail -10
```

- [ ] **Step 2: Manual smoke**

`open dist/Murmur.app`. Open booth, load a track on Deck 1, play it.

1. **Hover over the jog wheel** — cursor stays normal (no special hover state yet, that's OK).
2. **Click and drag right** on the wheel. The wheel briefly shrinks ~3% (the `scaleEffect(0.97)`). Playback pauses, the playhead jumps forward, the waveform's playhead position shifts.
3. **Continue dragging right** — playhead keeps moving forward at ~24px/sec. Drag back left → playhead moves backward.
4. **Release** the mouse. The wheel pops back to full size; playback resumes from the new position.
5. **Drag while paused** — wheel shrinks, playhead moves, releasing leaves playback paused (since it was paused before the drag).
6. **Drag past the start of the track** (or past the end) — clamps to [0, durationSeconds].
7. **Drag both wheels** — each independently scrubs its own deck.
8. Quick test of normal play during/after: after a scrub, the wheel rotates from its new playhead position, the beat halo continues pulsing in sync with the new playback position.

- [ ] **Step 3: Tag**

```bash
git tag -a phase-8-scratch -m "Pocket DJ Phase 8: jog wheel drag-to-scrub"
```

- [ ] **Step 4: Merge to main**

```bash
git checkout main
git merge --no-ff pocket-dj-phase-8 -m "Merge phase 8: jog wheel scratch"
./build-app.sh --sign 2>&1 | tail -5
```

---

## Out of Scope for Phase 8

- **True scratch** (audio reverses/pitches with hand speed) — complex DSP. The current scrub is a "ribbon" interaction: drag = seek, no audio plays during the drag.
- **Angular scratch math** (rotate the wheel by following the cursor's angle around the center) — interesting but requires careful pointer-to-angle math. Horizontal drag is simpler and works well enough.
- **Beat-quantized scrubbing** (snap playhead to nearest beat on release).
- **Touch trackpad support** with two-finger gesture.

---

## Self-Review

- **§6.2 Scratch interaction:** ✅ Implemented as horizontal drag-to-seek (the simplified scrub model).
- **§7.4 Audio clock anchoring:** ✅ During scrub, `state.currentTimeSeconds` is updated, so the wheel rotation and beat halo follow the new position immediately.
- **No new state in DeckState:** ✅ `isScrubbing` lives only on `DeckController` (transient).

No spec gaps. Type signatures consistent: `DeckController.beginScrub/scrub(toSeconds:)/endScrub`, `JogWheelView.onScrubBegan/onScrub/onScrubEnded`.
