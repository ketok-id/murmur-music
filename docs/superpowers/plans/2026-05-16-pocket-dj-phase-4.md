# Pocket DJ Phase 4 — Murmur Identity Layer

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Bring Murmur's original ambient-instrument identity back into the DJ booth: an **Ambient Layer** of 1–2 YouTube channels playing texture under the mix (rain, lofi, cafe), a **Mood Dial** that biases the ambient mix toward Calm/Focus/Cozy/Energy, and **Scenes** that save and recall the entire mixer state from a top-bar chip.

**Architecture:** Ambient channels are hidden `WKWebView` instances running Murmur's existing YouTube iframe + postMessage handshake (the same `PlayerController` pattern lives in `main.swift`). A new `AmbientLayer` Swift type owns those webviews and exposes per-channel volume + mute + source. `MoodDial` is a small state object that, when its value changes, applies a curve to each ambient channel's volume. `SceneStore` is `UserDefaults`-backed (mirroring `FavoritesStore`); a scene captures every public `@Published` value on `DeckState` for both decks plus the Mood Dial position and ambient mix. UI: an `AmbientStripView` along the top of the booth, a `MoodDialView` in the master strip, and `SceneChipsView` above the booth content.

**Tech Stack:** Same as before. Reuses `WKWebView` for ambient YouTube playback; `UserDefaults` for scene persistence; no new dependencies.

**Testing:** `swift build -c release` + final manual smoke in Task 10. No Co-Authored-By trailer in subagent commits.

**Prerequisites:** Phase 3 merged into `main`. The booth window shows the full DJ surface: BPM, key, waveform with beat-grid + cue/loop overlay, sync/key-lock/master, hot cue pads, loop controls, FX strip, knobs, tempo slider, crossfader, master controls, phase meter.

---

## File Structure

**New files:**

```
Sources/Murmur/Ambient/
  AmbientSource.swift        Hardcoded curated catalog of YouTube sources (id, name, kind)
  AmbientChannelState.swift  ObservableObject for one channel (current source, volume, muted)
  AmbientPlayer.swift        WKWebView wrapper around the YouTube iframe (lighter than PlayerController)
  AmbientLayer.swift         Owns 2 ambient channels; lifecycle + per-channel API
Sources/Murmur/Mood/
  MoodDial.swift             Observable Mood state + preset curves
Sources/Murmur/Scenes/
  Scene.swift                Codable snapshot of mixer state
  SceneStore.swift           UserDefaults-backed CRUD
Sources/Murmur/Booth/
  AmbientStripView.swift     Top strip: 2 channels with mini-knob + source picker
  MoodDialView.swift         Circular dial with 4 mood anchors
  SceneChipsView.swift       Horizontal chips at the top of the booth, plus a "Save" chip
```

**Modified files:**

- `Sources/Murmur/Decks/MixerEngine.swift` — add `ambient: AmbientLayer`, `mood: MoodDial`, and `scenes: SceneStore`. Hook mood→ambient volume bias and engine start to ambient lifecycle.
- `Sources/Murmur/Booth/BoothView.swift` — insert `SceneChipsView` at the top, `AmbientStripView` above the decks row, `MoodDialView` in the master vstack.
- `Sources/Murmur/Booth/BoothWindowController.swift` — bump window size to fit the new top strip + mood dial.

---

### Task 1: AmbientSource + curated catalog

**Files:**
- Create: `Sources/Murmur/Ambient/AmbientSource.swift`

- [ ] **Step 1: Implement**

```swift
import Foundation

/// One curated ambient source the user can pick from for an Ambient Layer channel.
struct AmbientSource: Codable, Equatable, Identifiable, Hashable {
    enum Kind: String, Codable {
        case rain, fire, cafe, nature, beats, vinyl, white
    }

    let id: String          // YouTube video ID
    let name: String
    let kind: Kind

    static let catalog: [AmbientSource] = [
        AmbientSource(id: "mPZkdNFkNps", name: "Rain on Window",          kind: .rain),
        AmbientSource(id: "qRTVg8HHzUo", name: "Heavy Rain & Thunder",    kind: .rain),
        AmbientSource(id: "L_LUpnjgPso", name: "Fireplace Crackle",       kind: .fire),
        AmbientSource(id: "BOdLmxy06H0", name: "Coffee Shop Ambience",    kind: .cafe),
        AmbientSource(id: "eKFTSSKCzWA", name: "Forest Birds",            kind: .nature),
        AmbientSource(id: "lTRiuFIWV54", name: "Ocean Waves",             kind: .nature),
        AmbientSource(id: "jfKfPfyJRdk", name: "Lofi Girl Stream",        kind: .beats),
        AmbientSource(id: "n61ULEU7CO0", name: "Vinyl Crackle",           kind: .vinyl),
        AmbientSource(id: "nMfPqeZjc2c", name: "Brown Noise",             kind: .white),
    ]

    /// Pretty kind label for UI.
    var kindLabel: String {
        switch kind {
        case .rain:    return "Rain"
        case .fire:    return "Fire"
        case .cafe:    return "Cafe"
        case .nature:  return "Nature"
        case .beats:   return "Beats"
        case .vinyl:   return "Vinyl"
        case .white:   return "Noise"
        }
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
git add Sources/Murmur/Ambient/AmbientSource.swift
git commit -m "feat(ambient): add AmbientSource catalog"
```

---

### Task 2: AmbientChannelState

**Files:**
- Create: `Sources/Murmur/Ambient/AmbientChannelState.swift`

- [ ] **Step 1: Implement**

```swift
import Foundation

/// Observable state for one Ambient Layer channel.
final class AmbientChannelState: ObservableObject {
    /// nil = empty slot (no source loaded).
    @Published var source: AmbientSource? = nil
    /// Per-channel volume 0…1. Final audible volume is `volume * moodBias`.
    @Published var volume: Float = 0.6
    @Published var muted: Bool = false

    /// Effective base volume considering mute.
    var baseGain: Float { muted ? 0 : volume }
}
```

- [ ] **Step 2: Build**

```bash
swift build -c release 2>&1 | tail -5
```

- [ ] **Step 3: Commit**

```bash
git add Sources/Murmur/Ambient/AmbientChannelState.swift
git commit -m "feat(ambient): add AmbientChannelState"
```

---

### Task 3: AmbientPlayer (WKWebView wrapper)

**Files:**
- Create: `Sources/Murmur/Ambient/AmbientPlayer.swift`

This is a slimmed-down version of `main.swift`'s `PlayerController` — same iframe + postMessage handshake, but with a much smaller surface area (just play, set volume, swap video).

- [ ] **Step 1: Implement**

```swift
import AppKit
import WebKit

/// A hidden YouTube webview that plays an ambient source in the background.
///
/// Mirrors the iframe + postMessage handshake used by `PlayerController` in
/// `main.swift`. The webview lives off-screen at (-3000, -3000) — WebKit
/// suspends media playback on detached / 0×0 views, so a real frame is required.
final class AmbientPlayer: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
    let webView: WKWebView
    private var currentVideoID: String?
    private var pendingVolume: Int = 60

    /// Owning container window. Hidden offscreen so playback stays alive
    /// without occupying visible real estate.
    private let window: NSWindow

    override init() {
        let config = WKWebViewConfiguration()
        config.mediaTypesRequiringUserActionForPlayback = []
        self.webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 320, height: 180), configuration: config)
        self.window = NSWindow(
            contentRect: NSRect(x: -3000, y: -3000, width: 320, height: 180),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        super.init()
        webView.navigationDelegate = self
        webView.setValue(false, forKey: "drawsBackground")
        config.userContentController.add(self, name: "ambientCB")
        window.contentView = webView
        window.isReleasedWhenClosed = false
        window.orderFront(nil)
    }

    /// Load (or swap) the active video and start playing.
    func loadAndPlay(videoID: String) {
        currentVideoID = videoID
        let html = Self.htmlPage(videoID: videoID, initialVolume: pendingVolume)
        webView.loadHTMLString(html, baseURL: URL(string: "https://www.youtube-nocookie.com")!)
    }

    /// 0…100. Volume is applied via the iframe API.
    func setVolume(_ percent: Int) {
        pendingVolume = max(0, min(100, percent))
        webView.evaluateJavaScript("window.ytCmd && window.ytCmd('setVolume', \(pendingVolume))")
    }

    func pause() {
        webView.evaluateJavaScript("window.ytCmd && window.ytCmd('pauseVideo')")
    }

    /// Stop and clear the webview to release resources.
    func stop() {
        webView.loadHTMLString("<html><body style='background:#000'></body></html>", baseURL: nil)
        currentVideoID = nil
    }

    // MARK: - WKScriptMessageHandler — receive iframe API messages

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        // No-op for ambient — we don't need to react to playerState changes.
        // The volume / play commands are fire-and-forget.
    }

    private static func htmlPage(videoID: String, initialVolume: Int) -> String {
        return """
        <!DOCTYPE html>
        <html>
        <head>
        <style>
          html, body { margin:0; padding:0; background:#000; overflow:hidden; }
          #player { position:absolute; top:0; left:0; width:100%; height:100%; }
        </style>
        </head>
        <body>
        <iframe id="player"
                src="https://www.youtube-nocookie.com/embed/\(videoID)?enablejsapi=1&autoplay=1&controls=0&modestbranding=1&playsinline=1&loop=1&playlist=\(videoID)"
                frameborder="0" allow="autoplay">
        </iframe>
        <script>
        let player = document.getElementById('player');
        function postCommand(func, args) {
          player.contentWindow.postMessage(JSON.stringify({event:'command', func:func, args:args || []}), '*');
        }
        window.ytCmd = function(cmd, value) {
          if (cmd === 'setVolume') postCommand('setVolume', [value]);
          else if (cmd === 'pauseVideo') postCommand('pauseVideo');
          else if (cmd === 'playVideo') postCommand('playVideo');
        };
        // YouTube iframe needs a listening handshake before commands are accepted.
        window.addEventListener('message', function(e) {
          window.webkit.messageHandlers.ambientCB.postMessage(String(e.data).slice(0, 200));
        });
        setTimeout(function() {
          player.contentWindow.postMessage('{"event":"listening","id":"\(videoID)"}', '*');
          setTimeout(function() {
            postCommand('setVolume', [\(initialVolume)]);
            postCommand('playVideo');
          }, 600);
        }, 400);
        </script>
        </body>
        </html>
        """
    }
}
```

- [ ] **Step 2: Build**

```bash
swift build -c release 2>&1 | tail -5
```

- [ ] **Step 3: Commit**

```bash
git add Sources/Murmur/Ambient/AmbientPlayer.swift
git commit -m "feat(ambient): add AmbientPlayer (hidden YouTube webview)"
```

---

### Task 4: AmbientLayer

**Files:**
- Create: `Sources/Murmur/Ambient/AmbientLayer.swift`

- [ ] **Step 1: Implement**

```swift
import Combine
import Foundation

/// Owns the two Ambient Layer channels — backing webviews + observable state.
///
/// The layer wires `AmbientChannelState` mutations to the underlying
/// `AmbientPlayer`. A `moodBias` (0…1) is applied as a multiplier on top of
/// each channel's `volume`, so the Mood Dial can scale the whole layer
/// without overwriting per-channel levels.
final class AmbientLayer: ObservableObject {
    let channel1 = AmbientChannelState()
    let channel2 = AmbientChannelState()

    private let player1 = AmbientPlayer()
    private let player2 = AmbientPlayer()

    private var cancellables = Set<AnyCancellable>()

    /// 0…1 scalar applied to all ambient channel volumes (Mood Dial input).
    @Published var moodBias: Float = 0.7 {
        didSet { applyVolumes() }
    }

    init() {
        // When source changes, swap the underlying webview.
        channel1.$source.dropFirst().sink { [weak self] src in self?.applySource(src, to: self?.player1) }
            .store(in: &cancellables)
        channel2.$source.dropFirst().sink { [weak self] src in self?.applySource(src, to: self?.player2) }
            .store(in: &cancellables)
        // When volume or mute changes, re-apply.
        channel1.$volume.sink { [weak self] _ in self?.applyVolumes() }.store(in: &cancellables)
        channel2.$volume.sink { [weak self] _ in self?.applyVolumes() }.store(in: &cancellables)
        channel1.$muted.sink { [weak self] _ in self?.applyVolumes() }.store(in: &cancellables)
        channel2.$muted.sink { [weak self] _ in self?.applyVolumes() }.store(in: &cancellables)
    }

    private func applySource(_ source: AmbientSource?, to player: AmbientPlayer?) {
        guard let player = player else { return }
        if let src = source {
            player.loadAndPlay(videoID: src.id)
        } else {
            player.stop()
        }
        applyVolumes()
    }

    private func applyVolumes() {
        let v1 = channel1.baseGain * moodBias
        let v2 = channel2.baseGain * moodBias
        player1.setVolume(Int(v1 * 100))
        player2.setVolume(Int(v2 * 100))
    }
}
```

- [ ] **Step 2: Build**

```bash
swift build -c release 2>&1 | tail -5
```

- [ ] **Step 3: Commit**

```bash
git add Sources/Murmur/Ambient/AmbientLayer.swift
git commit -m "feat(ambient): add AmbientLayer with 2 channels + mood bias"
```

---

### Task 5: MoodDial

**Files:**
- Create: `Sources/Murmur/Mood/MoodDial.swift`

- [ ] **Step 1: Implement**

```swift
import Combine
import Foundation

/// 4 mood anchors arranged on a unit circle.
///
/// `angle` is the dial's current position in radians (0 = right, π/2 = top, etc.).
/// Each anchor has a target ambient-bias level + suggested effect preset that
/// the rest of the app can read.
final class MoodDial: ObservableObject {
    enum Mood: String, CaseIterable {
        case calm, focus, cozy, energy
    }

    /// 0…2π. Top of the dial is π/2; we map clockwise from top.
    @Published var angle: Double = 0 {
        didSet { recomputeBlend() }
    }

    /// Current bias on the Ambient Layer's overall volume. 0…1.
    @Published private(set) var ambientBias: Float = 0.7
    /// Currently dominant mood (the closest anchor).
    @Published private(set) var dominant: Mood = .focus

    /// Returns the angle (radians) for a given mood anchor on the dial.
    static func anchorAngle(_ mood: Mood) -> Double {
        switch mood {
        case .focus:  return  .pi / 2     // top
        case .energy: return  0           // right
        case .cozy:   return  -.pi / 2    // bottom (or 3π/2)
        case .calm:   return  .pi         // left
        }
    }

    /// Ambient bias per anchor (how loud the ambient layer should be in this mood).
    static func anchorAmbient(_ mood: Mood) -> Float {
        switch mood {
        case .calm:   return 0.85
        case .focus:  return 0.55
        case .cozy:   return 0.80
        case .energy: return 0.30
        }
    }

    init(initial: Mood = .focus) {
        self.angle = Self.anchorAngle(initial)
        recomputeBlend()
    }

    /// Click an anchor to snap to it.
    func snap(to mood: Mood) {
        angle = Self.anchorAngle(mood)
    }

    private func recomputeBlend() {
        // Find closest anchor.
        var bestMood: Mood = .focus
        var bestDelta: Double = .infinity
        for m in Mood.allCases {
            let a = Self.anchorAngle(m)
            // Shortest angular distance.
            var delta = abs(angle - a).truncatingRemainder(dividingBy: 2 * .pi)
            if delta > .pi { delta = 2 * .pi - delta }
            if delta < bestDelta {
                bestDelta = delta
                bestMood = m
            }
        }
        dominant = bestMood
        ambientBias = Self.anchorAmbient(bestMood)
    }
}
```

- [ ] **Step 2: Build**

```bash
swift build -c release 2>&1 | tail -5
```

- [ ] **Step 3: Commit**

```bash
git add Sources/Murmur/Mood/MoodDial.swift
git commit -m "feat(mood): add MoodDial with 4 anchors and ambient bias"
```

---

### Task 6: Scene model + SceneStore

**Files:**
- Create: `Sources/Murmur/Scenes/Scene.swift`
- Create: `Sources/Murmur/Scenes/SceneStore.swift`

- [ ] **Step 1: Create `Scene.swift`**

```swift
import Foundation

/// A serialized snapshot of the full mixer state.
///
/// Stored values are intentionally narrow: just per-deck levels + FX state +
/// crossfader + ambient channels + mood. Hot cues, track loads, beat grid
/// adjustments etc. are NOT part of a scene — those are intrinsic to the
/// track, not the live mixer state.
struct Scene: Codable, Equatable, Identifiable {
    let id: UUID
    var name: String

    var crossfade: Float
    var masterVolume: Float

    var deck1: DeckSnapshot
    var deck2: DeckSnapshot

    var ambient1Source: String?   // YouTube ID
    var ambient1Volume: Float
    var ambient1Muted: Bool
    var ambient2Source: String?
    var ambient2Volume: Float
    var ambient2Muted: Bool

    var moodAngle: Double
}

/// Per-deck portion of a scene.
struct DeckSnapshot: Codable, Equatable {
    var volume: Float
    var lowGain: Float
    var midGain: Float
    var highGain: Float
    var filter: Float
    var tempoRate: Float
    var keyLock: Bool
    var echoEnabled: Bool
    var echoWet: Float
    var echoDivider: Int
    var reverbEnabled: Bool
    var reverbWet: Float
}
```

- [ ] **Step 2: Create `SceneStore.swift`**

```swift
import Foundation

/// `UserDefaults`-backed CRUD for `Scene` objects.
///
/// Mirrors the pattern of `FavoritesStore` from `main.swift`. Persists under
/// `youtube-audio-widget.scenes.v1`.
final class SceneStore: ObservableObject {
    @Published private(set) var scenes: [Scene] = []

    private let key = "youtube-audio-widget.scenes.v1"

    init() { load() }

    func add(_ scene: Scene) {
        scenes.append(scene)
        save()
    }

    func remove(id: UUID) {
        scenes.removeAll { $0.id == id }
        save()
    }

    func update(_ scene: Scene) {
        guard let i = scenes.firstIndex(where: { $0.id == scene.id }) else { return }
        scenes[i] = scene
        save()
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let list = try? JSONDecoder().decode([Scene].self, from: data) else { return }
        scenes = list
    }

    private func save() {
        if let data = try? JSONEncoder().encode(scenes) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
```

- [ ] **Step 3: Build and commit**

```bash
swift build -c release 2>&1 | tail -5
git add Sources/Murmur/Scenes/Scene.swift Sources/Murmur/Scenes/SceneStore.swift
git commit -m "feat(scenes): add Scene model + UserDefaults-backed SceneStore"
```

---

### Task 7: Extend MixerEngine with ambient + mood + scenes

**Files:**
- Modify: `Sources/Murmur/Decks/MixerEngine.swift`

- [ ] **Step 1: Add the three properties + scene capture/recall**

Find the property block in `MixerEngine`. After `let phaseAnalyzer = PhaseAnalyzer()`, add:

```swift

    // ── Phase 4: Murmur identity layer ────────────────────────────────────

    let ambient = AmbientLayer()
    let mood = MoodDial()
    let scenes = SceneStore()
```

In `init()`, after `phaseAnalyzer.attach(...)`, add:

```swift

        // Mood Dial → Ambient Layer volume bias.
        mood.$ambientBias.assign(to: &ambient.$moodBias)
```

(Requires `import Combine` — it's already in MixerEngine via DeckController, but verify.)

Then add scene capture + recall methods at the bottom of `MixerEngine`, before the closing `}`:

```swift
    // MARK: - Scenes

    /// Capture the current state as a Scene with the given name.
    func captureScene(named name: String) -> Scene {
        let s = Scene(
            id: UUID(),
            name: name,
            crossfade: crossfadePosition,
            masterVolume: masterVolume,
            deck1: snapshot(of: deck1.state),
            deck2: snapshot(of: deck2.state),
            ambient1Source: ambient.channel1.source?.id,
            ambient1Volume: ambient.channel1.volume,
            ambient1Muted: ambient.channel1.muted,
            ambient2Source: ambient.channel2.source?.id,
            ambient2Volume: ambient.channel2.volume,
            ambient2Muted: ambient.channel2.muted,
            moodAngle: mood.angle
        )
        scenes.add(s)
        return s
    }

    /// Apply a scene: restores mixer levels + ambient + mood. Does NOT load tracks.
    func recallScene(_ scene: Scene) {
        crossfadePosition = scene.crossfade
        masterVolume = scene.masterVolume
        apply(scene.deck1, to: deck1.state)
        apply(scene.deck2, to: deck2.state)
        let cat = AmbientSource.catalog
        ambient.channel1.source = scene.ambient1Source.flatMap { id in cat.first(where: { $0.id == id }) }
        ambient.channel1.volume = scene.ambient1Volume
        ambient.channel1.muted = scene.ambient1Muted
        ambient.channel2.source = scene.ambient2Source.flatMap { id in cat.first(where: { $0.id == id }) }
        ambient.channel2.volume = scene.ambient2Volume
        ambient.channel2.muted = scene.ambient2Muted
        mood.angle = scene.moodAngle
    }

    private func snapshot(of state: DeckState) -> DeckSnapshot {
        DeckSnapshot(
            volume: state.volume,
            lowGain: state.lowGain,
            midGain: state.midGain,
            highGain: state.highGain,
            filter: state.filter,
            tempoRate: state.tempoRate,
            keyLock: state.keyLock,
            echoEnabled: state.echoEnabled,
            echoWet: state.echoWet,
            echoDivider: state.echoDivider,
            reverbEnabled: state.reverbEnabled,
            reverbWet: state.reverbWet
        )
    }

    private func apply(_ snapshot: DeckSnapshot, to state: DeckState) {
        state.volume = snapshot.volume
        state.lowGain = snapshot.lowGain
        state.midGain = snapshot.midGain
        state.highGain = snapshot.highGain
        state.filter = snapshot.filter
        state.tempoRate = snapshot.tempoRate
        state.keyLock = snapshot.keyLock
        state.echoEnabled = snapshot.echoEnabled
        state.echoWet = snapshot.echoWet
        state.echoDivider = snapshot.echoDivider
        state.reverbEnabled = snapshot.reverbEnabled
        state.reverbWet = snapshot.reverbWet
    }
```

- [ ] **Step 2: Build and commit**

```bash
swift build -c release 2>&1 | tail -10
git add Sources/Murmur/Decks/MixerEngine.swift
git commit -m "feat(mixer): wire ambient + mood + scenes into MixerEngine"
```

---

### Task 8: AmbientStripView + MoodDialView + SceneChipsView

**Files:**
- Create: `Sources/Murmur/Booth/AmbientStripView.swift`
- Create: `Sources/Murmur/Booth/MoodDialView.swift`
- Create: `Sources/Murmur/Booth/SceneChipsView.swift`

- [ ] **Step 1: AmbientStripView**

```swift
import SwiftUI

/// Thin strip showing two Ambient Layer channels with source picker + volume knob.
struct AmbientStripView: View {
    @ObservedObject var channel1: AmbientChannelState
    @ObservedObject var channel2: AmbientChannelState

    var body: some View {
        HStack(spacing: 12) {
            Text("AMBIENT")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .tracking(2)
                .foregroundColor(.cyan.opacity(0.7))
            channelControls(state: channel1, label: "1")
            channelControls(state: channel2, label: "2")
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.cyan.opacity(0.04))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.cyan.opacity(0.15), style: StrokeStyle(lineWidth: 1, dash: [3, 2])))
        .cornerRadius(6)
    }

    private func channelControls(state: AmbientChannelState, label: String) -> some View {
        HStack(spacing: 8) {
            Menu {
                Button("— Off —") { state.source = nil }
                Divider()
                ForEach(AmbientSource.catalog) { src in
                    Button("\(src.kindLabel) · \(src.name)") {
                        state.source = src
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Circle()
                        .fill(state.source != nil ? Color.cyan : Color.white.opacity(0.15))
                        .frame(width: 8, height: 8)
                    Text(state.source?.name ?? "Pick a bed…")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(state.source != nil ? .white : .white.opacity(0.4))
                        .lineLimit(1)
                }
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            Button(action: { state.muted.toggle() }) {
                Image(systemName: state.muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.system(size: 10))
                    .foregroundColor(state.muted ? .red.opacity(0.6) : .white.opacity(0.6))
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.plain)

            Slider(value: Binding(
                get: { Double(state.volume) },
                set: { state.volume = Float($0) }
            ), in: 0...1)
            .frame(width: 60)
        }
    }
}
```

- [ ] **Step 2: MoodDialView**

```swift
import SwiftUI

/// Circular mood dial with 4 anchors. Drag to rotate; click an anchor to snap.
struct MoodDialView: View {
    @ObservedObject var mood: MoodDial
    var size: CGFloat = 84

    @State private var dragStartAngle: Double = 0

    var body: some View {
        VStack(spacing: 4) {
            Text("MOOD")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .tracking(1.5)
                .foregroundColor(.white.opacity(0.5))

            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
                    .frame(width: size, height: size)

                // 4 anchor dots.
                ForEach(MoodDial.Mood.allCases, id: \.self) { mood in
                    let a = MoodDial.anchorAngle(mood)
                    let x = cos(a) * Double(size) / 2 * 0.85
                    let y = -sin(a) * Double(size) / 2 * 0.85   // Y inverted in screen coords
                    VStack(spacing: 2) {
                        Circle()
                            .fill(self.mood.dominant == mood ? anchorColor(mood) : Color.white.opacity(0.2))
                            .frame(width: 8, height: 8)
                            .shadow(color: self.mood.dominant == mood ? anchorColor(mood).opacity(0.7) : .clear, radius: 4)
                        Text(label(for: mood))
                            .font(.system(size: 7, weight: .semibold, design: .monospaced))
                            .tracking(1)
                            .foregroundColor(self.mood.dominant == mood ? anchorColor(mood) : .white.opacity(0.35))
                    }
                    .offset(x: x, y: y)
                    .onTapGesture { self.mood.snap(to: mood) }
                }

                // Center indicator pointing toward current angle.
                Rectangle()
                    .fill(anchorColor(mood.dominant))
                    .frame(width: 2, height: size * 0.32)
                    .offset(y: -size * 0.16)
                    .rotationEffect(.radians(-mood.angle + .pi / 2))
                    .shadow(color: anchorColor(mood.dominant).opacity(0.5), radius: 3)
            }
            .frame(width: size, height: size)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        let dx = drag.translation.width / 80
                        if drag.translation == .zero {
                            dragStartAngle = mood.angle
                        }
                        mood.angle = (dragStartAngle - dx).truncatingRemainder(dividingBy: 2 * .pi)
                    }
            )
        }
    }

    private func label(for m: MoodDial.Mood) -> String {
        switch m {
        case .calm:   return "CALM"
        case .focus:  return "FOCUS"
        case .cozy:   return "COZY"
        case .energy: return "ENERGY"
        }
    }

    private func anchorColor(_ m: MoodDial.Mood) -> Color {
        switch m {
        case .calm:   return Color(red: 0.43, green: 0.77, blue: 1.0)
        case .focus:  return Color(red: 0.66, green: 0.55, blue: 0.98)
        case .cozy:   return Color(red: 1.0, green: 0.75, blue: 0.47)
        case .energy: return Color(red: 1.0, green: 0.48, blue: 0.71)
        }
    }
}
```

- [ ] **Step 3: SceneChipsView**

```swift
import SwiftUI

/// Horizontal row of scene chips along the top of the booth.
///
/// Each chip recalls a scene on click. A "+" chip prompts for a name and
/// captures the current state as a new scene. Long-press (context menu)
/// to delete or rename.
struct SceneChipsView: View {
    @ObservedObject var store: SceneStore
    var onRecall: (Scene) -> Void
    var onCapture: (String) -> Void

    @State private var promptingName = false
    @State private var draftName: String = ""

    var body: some View {
        HStack(spacing: 6) {
            Text("SCENES")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .tracking(2)
                .foregroundColor(.white.opacity(0.45))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(store.scenes) { scene in
                        chip(scene: scene)
                    }
                    captureChip
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
    }

    private func chip(scene: Scene) -> some View {
        Button(action: { onRecall(scene) }) {
            Text(scene.name)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .foregroundColor(.white.opacity(0.85))
                .background(Color.white.opacity(0.06))
                .overlay(RoundedRectangle(cornerRadius: 999).stroke(Color.white.opacity(0.12), lineWidth: 1))
                .cornerRadius(999)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Delete scene", role: .destructive) {
                store.remove(id: scene.id)
            }
        }
    }

    private var captureChip: some View {
        Button(action: { promptingName = true; draftName = "" }) {
            Text("+ save scene")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .foregroundColor(.cyan.opacity(0.85))
                .background(Color.cyan.opacity(0.08))
                .overlay(RoundedRectangle(cornerRadius: 999).stroke(Color.cyan.opacity(0.4), lineWidth: 1))
                .cornerRadius(999)
        }
        .buttonStyle(.plain)
        .alert("Save scene", isPresented: $promptingName) {
            TextField("Scene name", text: $draftName)
            Button("Save") {
                let name = draftName.trimmingCharacters(in: .whitespaces)
                if !name.isEmpty { onCapture(name) }
            }
            Button("Cancel", role: .cancel) {}
        }
    }
}
```

- [ ] **Step 4: Build and commit**

```bash
swift build -c release 2>&1 | tail -5
git add Sources/Murmur/Booth/AmbientStripView.swift Sources/Murmur/Booth/MoodDialView.swift Sources/Murmur/Booth/SceneChipsView.swift
git commit -m "feat(booth): add AmbientStrip + MoodDial + SceneChips views"
```

---

### Task 9: Wire Phase 4 views into BoothView

**Files:**
- Modify: `Sources/Murmur/Booth/BoothView.swift`
- Modify: `Sources/Murmur/Booth/BoothWindowController.swift`

- [ ] **Step 1: Update BoothView body**

Open `Sources/Murmur/Booth/BoothView.swift`. Replace the ENTIRE body (inside `var body: some View { ... }`) with:

```swift
        VStack(spacing: 6) {
            SceneChipsView(
                store: mixer.scenes,
                onRecall: { mixer.recallScene($0) },
                onCapture: { name in _ = mixer.captureScene(named: name) }
            )

            AmbientStripView(
                channel1: mixer.ambient.channel1,
                channel2: mixer.ambient.channel2
            )

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
                    LivePhaseMeter(analyzer: mixer.phaseAnalyzer)
                        .frame(height: 30)
                    MoodDialView(mood: mixer.mood)
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
        .frame(minWidth: 1000, minHeight: 840)
        .background(Color(white: 0.02))
```

The center VStack now contains 3 elements: MasterControls, phase meter, MoodDialView. `minHeight` bumped to 840 to fit scene chips + ambient strip.

- [ ] **Step 2: Update BoothWindowController**

Find:
```swift
        win.setContentSize(NSSize(width: 1100, height: 780))
        win.contentMinSize = NSSize(width: 1000, height: 720)
```

Replace with:
```swift
        win.setContentSize(NSSize(width: 1100, height: 900))
        win.contentMinSize = NSSize(width: 1000, height: 840)
```

- [ ] **Step 3: Build and commit**

```bash
swift build -c release 2>&1 | tail -10
git add Sources/Murmur/Booth/BoothView.swift Sources/Murmur/Booth/BoothWindowController.swift
git commit -m "feat(booth): wire ambient strip + mood dial + scene chips into the booth"
```

---

### Task 10: Build bundle + smoke + tag

- [ ] **Step 1: Build**

```bash
./build-app.sh --sign 2>&1 | tail -10
```

- [ ] **Step 2: Manual smoke**

`open dist/Murmur.app`. Open the booth:

1. **Ambient Layer**: at the top of the booth, two channels with "Pick a bed…" buttons. Click the first one → menu of curated sources opens (Rain on Window, Heavy Rain & Thunder, Fireplace Crackle, etc.). Pick one. Within a couple seconds you should hear the ambient bed playing.
2. Drag the channel's volume slider → ambient gets quieter/louder. Click the speaker icon → mutes.
3. Pick a different bed on channel 2 → both play simultaneously under your DJ tracks.
4. **Mood Dial**: located under the master controls. Click each anchor (CALM / FOCUS / COZY / ENERGY). The needle should rotate to that anchor. The Ambient Layer volume should bias accordingly (CALM/COZY = louder ambient; ENERGY = quieter ambient).
5. Drag around the dial to move continuously between anchors → ambient volume scales smoothly.
6. **Scenes**: at the very top, click **+ save scene**. Name it "Late Night". The chip appears. Adjust some knobs / change mood. Click the "Late Night" chip → mixer state reverts: knobs jump back, mood snaps back, ambient sources & volumes restored.
7. Right-click a scene chip → "Delete scene" → removes it.
8. Quit and re-open the app — saved scenes persist (they're in UserDefaults). Ambient channel selections do NOT persist (intentional — only via scenes).

- [ ] **Step 3: Tag**

```bash
git tag -a phase-4-murmur-identity -m "Pocket DJ Phase 4: Ambient Layer + Mood Dial + Scenes"
```

---

## Out of Scope for Phase 4

- Animated scene recall (current implementation snaps; smooth knob animation is polish for later).
- "Right Now" recipe (time-of-day suggestions for scene auto-loading).
- Saving track-load + hot cues as part of a scene (would conflict with track-intrinsic metadata).
- Onboarding flow / first-launch guided blend.

---

## Self-Review

- **§4.6 Mood Dial:** ✅ Implemented as a side-panel widget per the "lean into DJ" decision.
- **§4.3 Ambient Layer:** ✅ 2 channels with curated catalog, per-channel volume + mute.
- **§4.2–4.3 Murmur stack rules preserved:** ✅ Ambient `WKWebView`s parked at (-3000, -3000), iframe + postMessage handshake, `youtube-nocookie.com` origin.
- **Scenes:** ✅ Captures and recalls mixer state. Does NOT capture loaded tracks (those are track-intrinsic).
- **Mood→FX preset application:** explicitly deferred — Mood currently biases only the ambient layer. Loading effect presets from Mood is a Phase 5+ refinement.

No spec gaps for the in-scope set. No placeholders. Type signatures consistent across tasks.
