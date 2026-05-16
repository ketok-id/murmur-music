# Pocket DJ — Design Spec

**Status:** Draft for review (v3 — DJ-forward rewrite)
**Date:** 2026-05-16
**Parent project:** Murmur (macOS menu-bar YouTube audio widget)
**Direction chosen:** "C — Lean into DJ" (full DJ app with ambient layer)

---

## 1. One-paragraph summary

Pocket DJ is a 4-deck macOS DJ app built on Murmur's WKWebView + Swift foundation, with a 3D mixing surface, beatmatching, key-aware mixing, cue points, effects, and master/headphone cueing. The DJ surface operates on **local audio files** (and Apple Music with reduced controls). YouTube — Murmur's original source — is demoted to a thin **Ambient Layer** strip that plays atmospheric beds (rain, cafe, vinyl crackle) underneath your mix. Recording bounces the master output to a file. Mood Dial / scenes / Right Now survive as a side panel for picking ambient beds and effect presets.

## 2. Goals

- A real DJ app: beatmatch, sync, cue, hot cues, loops, effects rack, headphone cue, key-aware mixing helpers.
- A distinctive **3D mixing surface**: spinning jog wheels with album art, beat-pulsing platter rims, physical-feeling crossfader, effect knobs with momentum.
- Stay **single-binary**, macOS 13+, Swift/SwiftUI + WKWebView for visuals + AVAudioEngine for audio.
- Preserve Murmur's identity touch: ambient beds, scenes, Mood Dial — but as a layer on top of the DJ surface, not the center.

## 3. Non-goals

- No video DJing (no music videos synced to mix). The floating window is the DJ booth, not a video output.
- No streaming-service DJ integration beyond Apple Music (no Spotify, Tidal, Beatport).
- No vinyl-control / DVS (timecoded vinyl input).
- No MIDI controller mapping in v1 (stretch in v2).
- No live broadcast (Mixcloud Live, Twitch streaming) in v1.
- No bouncing Apple Music or YouTube audio to a recorded file (DRM + ToS).

## 4. The two surfaces: DJ deck + Ambient Layer

The app has two clearly separated audio surfaces shown together in the floating window:

### 4.1 The DJ surface (primary)
- **Four decks** arranged 2-up-2-down (or 2 with a "open deck 3/4" toggle for first-time users).
- Each deck shows: jog wheel + album art, large waveform with playhead and beat grid, BPM and key display, tempo slider, sync button, 8 hot-cue pads, loop in/out, FX assigns.
- Decks load **local files** (full feature set) or **Apple Music tracks** (reduced feature set — see §4.2).
- Crossfader at center mixes between deck pairs (1+3 ↔ 2+4, assignable).

### 4.2 Deck capabilities by source type

| Capability | Local file | Apple Music | YouTube |
|---|---|---|---|
| Play/pause, volume, 3-band EQ | ✅ | ✅ | (in Ambient Layer only) |
| Filter sweep (HPF/LPF) | ✅ | ✅ | ❌ |
| Tempo (pitch fader) | ✅ | limited (±6%, no time-stretch) | ❌ |
| Sync to master tempo | ✅ | limited | ❌ |
| Scratch / jog spin | ✅ | ❌ | ❌ |
| Cue points + hot cues | ✅ | start-position only | ❌ |
| Loops (beat-quantized) | ✅ | ❌ | ❌ |
| Effects rack | ✅ | filter+echo only | ❌ |
| Key detection | ✅ | (metadata if available) | ❌ |
| Pre-listen / headphone cue | ✅ | ❌ (DRM) | ❌ |
| Bounceable in master record | ✅ | ❌ | ❌ |

Apple Music decks visibly show a "limited" badge so the user understands why fewer controls are active. The user can still drop Apple Music tracks onto a deck and mix them; just no scratching or cue points.

### 4.3 The Ambient Layer (secondary)
- Thin strip above the decks, 1-2 channels.
- YouTube-sourced beds (rain, cafe, fireplace, vinyl crackle, white noise, lofi station).
- Per-channel volume + duck-on-cue (auto-ducks when you're cuing a track in headphones).
- Mood Dial drives the Ambient Layer (Calm/Focus/Cozy/Energy → texture + level + EQ).
- Performance recording captures Ambient Layer automation but excludes it from the bounced audio file (no YouTube capture).

## 5. DJ feature set

### 5.1 Loading and library
- **Crates** = the user's library. Build from watched folders (Music.app library, custom folders).
- **Library panel** slides in from the left: crates tree, search, sort (BPM, key, artist, date added), filter (key-compatible only).
- **Drag a track onto a deck** to load. While loading: Murmur decodes via `AVAudioFile`, computes peak waveform, runs BPM + key detection.
- **Preparation crate**: tag tracks for tonight's set; tracks here pre-warm into a memory cache.

### 5.2 Beatmatching
- **BPM detection** via offline analysis on first load (~1s for a 4-min track on M1). Stored in `library.json`.
- **Beat grid** is editable: drag the first downbeat marker if auto-detect misses; entire grid shifts.
- **Sync button** matches the deck's BPM to the "master deck" (the deck assigned as master, or whichever is louder if "auto-master" is on).
- **Tempo slider**: ±8% / ±16% / ±50% ranges. Key lock toggle (uses `AVAudioUnitTimePitch` to time-stretch without pitch shift).
- **Phase meter**: visual showing alignment of two decks' beats — a vertical needle that drifts left/right of center. The user nudges the platter to correct.

### 5.3 Key-aware mixing
- **Key detection** on load using HPCP-based chromagram analysis. Stored as both musical (e.g., "D minor") and Camelot notation (e.g., "7A").
- **Compatible-key highlight**: in the library, tracks compatible with what's currently in the master deck glow green. Compatible = same Camelot, ±1 Camelot, or relative major/minor.
- **Key shift**: per-deck +/- semitone shift (uses `AVAudioUnitTimePitch` independent of tempo).

### 5.4 Cue points and hot cues
- **Main cue point**: set with the Cue button, jump back with Cue.
- **8 hot cues per deck**, color-coded pads. Click to set/jump; right-click to delete or rename.
- Hot cues are persisted per track in the library index, not per-deck.
- **Loop**: in/out buttons set a loop region. Halve/double buttons (1/32 to 32 bars). Saved loops appear as a 9th–16th pad row when toggled.

### 5.5 Effects rack
Per-deck FX assigns + a global "send" FX bus:
- **Filter** (HPF/LPF combined sweep, default-assigned to every deck)
- **Echo** (1/4, 1/8, 1/16 beat divisions, feedback, wet)
- **Reverb** (size, damping, wet)
- **Flanger** (rate, depth, feedback)
- Effects are Web Audio nodes (for local/Apple Music decks routed through AVAudioEngine via `AVAudioUnitEffect` subclasses).
- Up to 2 effects per deck, plus 1 global send FX. Each shown as a 3D knob with on/off pad.

### 5.6 Headphone cue (pre-listen)
- Requires a second audio output device (typically a USB DJ controller or split-cable). User picks "master output" + "cue output" in Preferences.
- Cue button on each deck routes that deck to the headphone bus pre-fader.
- Cue mix knob blends the cue bus with the master in the headphones.
- Visible indicator on each deck when it's in the cue bus.

### 5.7 Recording the master
- **Master record** taps the AVAudioEngine main mixer output and writes to WAV (48 kHz / 24-bit) or AAC (256 kbps).
- Apple Music decks are excluded from the bounce (DRM); a "muted from recording" badge shows on those decks while recording is active.
- Ambient Layer is excluded from the bounce (YouTube ToS).
- A persistent banner during recording explains what's being captured to set expectations.
- Recordings appear in a "Mixes" library section with auto-generated waveform thumbnails and timestamps.

## 6. 3D mixing surface

The floating window is the 3D mixing surface, rendered with Three.js inside a WKWebView (same pattern as today's Murmur, just a much richer scene).

### 6.1 Layout
- Top strip: **Ambient Layer** (2 small knobs + texture badges).
- Middle: **two large jog wheels** (Decks 1 + 2 by default). 3D platters with album art on the center label, BPM "halo" rim that pulses on the beat.
- Below jog wheels: **waveforms** with beat grid, hot cue markers, playhead.
- Between waveforms: **crossfader** + master VU meter.
- Below: **EQ + filter + FX** strip for each visible deck.
- Right side: **transport** + record + master.
- "Open decks 3 & 4" tab adds another row below.

### 6.2 Signature 3D / animation moments
- **Jog wheels spin** at track tempo; album art tilts slightly to the platter perspective.
- **Beat-pulse halo** — the rim of each jog wheel glows on each beat; brighter on bars, brightest on downbeats.
- **Cue-point flags** rise out of the waveform as colored 3D markers.
- **Scratch animation**: when the user grabs a jog wheel (mouse or trackpad), the platter physically follows the cursor with realistic inertia; releasing lets it spring back to tempo.
- **Loop region** glows on the waveform with audio-reactive intensity.
- **Sync flash**: when sync engages, both decks' halos pulse white for one beat.
- **Effects activation**: turning an FX knob lights a colored aura around the affected deck (filter = blue, echo = orange, reverb = purple, flanger = green).
- **Crossfader weight**: physical fader with magnetic detent at center; release inertia + soft landing.
- **Phase meter**: a needle that subtly tilts with BPM drift; goes green when locked.

### 6.3 Album mosaic backplate (kept from earlier spec)
- Soft, blurred composite of currently loaded decks' artwork sits behind the booth. Cross-fades when tracks change.

### 6.4 Mood Dial (demoted)
- Lives in a small side panel, not the center of the booth.
- Drives the Ambient Layer + recommends effect presets ("Cozy" loads warm reverb on master send; "Energy" boosts mid filter resonance).
- Optional — invisible by default. Toggled on from Preferences.

## 7. Architecture

### 7.1 Audio pipeline

A single `AVAudioEngine` is the heart of the app. Source players plug into channel strips on the engine's main mixer:

```
[Source]  →  [SourcePlayer]   →  [Channel strip]                →  [Crossfader]  →  [Master FX]  →  [Recorder tap]  →  [Output]
                                  (EQ → Filter → FX1 → FX2 → Fader)                                                  ↘  [Cue bus]   →  [Cue output]
```

`SourcePlayer` (Swift protocol) implementations:
- **`LocalFilePlayer`** — `AVAudioPlayerNode` driven by an `AVAudioFile` reader. Supports scrub, scratch, tempo (`AVAudioUnitTimePitch`), key lock.
- **`AppleMusicPlayer`** — wraps `ApplicationMusicPlayer` from MusicKit. Limited control surface; no audio buffer access.
- **`YouTubeAmbientPlayer`** — hidden WKWebView running Murmur's existing iframe + postMessage handshake. Only used for the Ambient Layer; routes to a dedicated Ambient channel strip.

### 7.2 BPM and key analysis
- **BPM**: autocorrelation on the onset envelope of a downsampled mono mix of the file. Targets 60–180 BPM with octave-error correction.
- **Key**: 12-bin chromagram on overlapping STFT windows; Krumhansl-Schmuckler profile correlation; outputs major/minor + Camelot.
- Runs in a `DispatchQueue` background pool when a file is loaded; results cached in `library.json`. Re-analysis available from context menu.

### 7.3 Latency and timing
- AVAudioEngine sample rate locked to 48 kHz internally; resampled per device on output.
- I/O buffer size = 256 frames (~5.3ms) by default; user-adjustable in Preferences (128 / 256 / 512 / 1024).
- Beat-quantized loops use the engine's `lastRenderTime` and the active beat grid; quantization snaps to next sample-accurate beat boundary.

### 7.4 Visual layer
- Three.js scene in the floating-window WKWebView. Renders the booth, jog wheels, waveforms, knobs, faders.
- Swift drives the scene over `evaluateJavaScript`; user input from the scene flows back via `webkit.messageHandlers.cb.postMessage`.
- Waveforms are pre-rendered to canvas textures on load (peak data computed once during analysis).
- Live beat-grid playhead + jog-wheel rotation animated by Swift sending frame-paced updates derived from `AVAudioEngine.lastRenderTime` — the visual is locked to the audio clock, not requestAnimationFrame.

### 7.5 State and persistence
- `library.json` in `~/Library/Application Support/Murmur/`: tracks, BPM, key, waveform peak data path, hot cues, durations.
- `crates.json`: user crates + prep crate.
- `scenes.json`: Mood Dial states + Ambient Layer scene presets.
- `recordings/`: bounced master mixes + thumbnails.
- `prefs.plist`: output device selections, buffer size, sync mode, key-lock default.
- Existing `UserDefaults` keys from Murmur stay untouched.

### 7.6 Components

- **`AudioGraph`** — owns `AVAudioEngine`, channel strips, crossfader bus, cue bus, master FX, recorder tap.
- **`SourcePlayer`** protocol with `LocalFilePlayer`, `AppleMusicPlayer`, `YouTubeAmbientPlayer`.
- **`DeckController`** (×4) — owns one channel strip + source player + per-deck state (cue points, loop, tempo).
- **`AnalysisService`** — BPM/key detection, waveform peak generation, cached results.
- **`LibraryIndex`** — watched folders, Music.app library, search, key-compatibility queries.
- **`RecordingService`** — master tap to file, recording state, ducking for excluded sources.
- **`AmbientController`** — owns the YouTube WKWebViews for the Ambient Layer + Mood Dial integration.
- **`BoothWindowController`** — the floating 3D window; bridges Swift state to the Three.js scene.
- **`booth.html` + `booth.js`** — the Three.js scene + interaction code.
- **`PopoverView`** — menu-bar quick controls: now-playing, master volume, ambient on/off, "Open Booth →".
- **`LibraryPanelView`**, **`PreferencesView`** — SwiftUI.

## 8. Murmur stack rules preserved

From `CLAUDE.md` — these stay non-negotiable:

- YouTube embed stays iframe + postMessage, never `YT.Player`.
- Hidden YouTube WKWebViews stay parked at `(-3000, -3000)` for the Ambient Layer (never destroyed/recreated).
- Both loading-mask layers (Swift NSView + in-page `#cover`) kept on the Ambient Layer webviews.
- `iframe { pointer-events: none }` kept.
- 1.5s `didFinish` force-ready fallback kept.
- `applicationShouldTerminateAfterLastWindowClosed → false` and `windowShouldClose → hide` interception kept.
- `webView.setValue(false, forKey: "drawsBackground")` kept.
- `youtube-nocookie.com` embed origin kept.
- Single-binary, no external Swift package dependencies. Three.js loads from a bundled `Resources/web/` directory.

## 9. Suggested phasing

Larger than the previous spec — strongly recommend phasing:

- **Phase 1 — Audio foundation:** `AudioGraph` + `LocalFilePlayer` + 2 decks + crossfader + EQ + filter + master record. No 3D yet — temporary SwiftUI mockup booth. **Goal:** can play and crossfade two local tracks.
- **Phase 2 — DJ core:** BPM detection, waveform render, beat grid, sync, tempo, hot cues, loops. **Goal:** can beatmatch and mix two tracks confidently.
- **Phase 3 — 3D booth:** Three.js scene, jog wheels, beat-pulse halos, scratch interaction, 3D effects knobs, crossfader physics.
- **Phase 4 — Full DJ feature set:** decks 3+4, key detection + harmonic mixing helpers, effects rack (echo, reverb, flanger), headphone cue.
- **Phase 5 — Murmur identity:** Ambient Layer (YouTube beds), Mood Dial, scenes, Right Now recipe.
- **Phase 6 — Polish:** prep crate, library filters, recording library, onboarding, idle screensaver.
- **Phase 7 — Stretch:** Apple Music deck (MusicKit), MIDI controller mapping, performance recording (control-surface stream).

## 10. Open questions for v1 scope

1. **2 decks vs 4 in Phase 1** — start with 2 to lock the core experience, or design for 4 from the start? (Recommended: 2 first, 4 in Phase 4.)
2. **Time-stretch quality** — `AVAudioUnitTimePitch` is good but not Serato-grade. Acceptable for v1, or invest in a better algorithm later?
3. **Key detection accuracy** — chromagram + Krumhansl is ~85% accurate. Good enough for v1, or budget for a better algorithm?
4. **MIDI controller mapping** — required at launch or v2? (Recommended: v2.)
5. **Apple Music deck** — ship in v1 with reduced features, or defer to v1.1?
6. **Sandbox / hardened runtime** — currently unsigned. DJ users often have audio interfaces with their own permissions; signing earlier than originally planned might be wise.

## 11. Success criteria

- A user can drag a local MP3 onto a deck and start playing within 250ms (analysis runs in background, not blocking).
- BPM detection accuracy ≥90% on a corpus of 50 known-BPM tracks across genres (acceptance test).
- Sync engages and holds for ≥4 minutes without audible drift on M1 baseline.
- Master recording at 48kHz/24-bit produces a clean WAV with no underruns over a 60-minute set.
- Cue bus latency from cue-button press to audible-in-headphones is ≤30ms.
- The 3D booth renders ≥55 fps during a typical 2-deck mix on M1; audio never underruns when the visual is animating.
- App still ships as a single signed binary via the existing `build-app.sh` (signing newly required for some macOS audio permissions but the script handles it).
