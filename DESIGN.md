# MURMUR — SwiftUI macOS Desktop App Design

## Overview

**MURMUR** is a compact macOS desktop music player with a dark, tactile, cassette-inspired interface.

The design should feel like a premium retro-futuristic audio device, but it must remain practical to build in **SwiftUI** without using heavy image assets, SceneKit, RealityKit, or complex 3D rendering.

**Visual style:** Dark Tactile Cassette UI

The interface combines:

- Dark rounded panels
- Soft 3D shadows
- Copper/orange accents
- Animated cassette reels
- Tactile playback buttons
- Clean macOS desktop layout

---

## Target Platform

| Item | Value |
|---|---|
| Platform | macOS |
| Framework | SwiftUI |
| Window type | Compact desktop utility app |
| Main layout | Fixed-first, resizable-friendly |
| Default size | 760 × 560 |
| Minimum size | 620 × 480 |

---

## Design Goals

1. Preserve the **MURMUR** identity.
2. Make the cassette player card the main visual focus.
3. Use soft 3D styling that is easy to implement in SwiftUI.
4. Keep the layout clean, premium, and desktop-friendly.
5. Avoid overly realistic cassette graphics.
6. Use reusable SwiftUI components.
7. Support empty, playing, paused, loading, and error states.

---

## Final Layout

```text
┌──────────────────────────────────────────────────────────────┐
│                                                              │
│  [screen] [refresh] [share]       MURMUR       [list] [gear] │
│                                                              │
│  ┌────────────────────────────────────────────────────────┐  │
│  │ 🔗  paste url or video id                       ☆  GO  │  │
│  └────────────────────────────────────────────────────────┘  │
│                                                              │
│  ┌────────────────────────────────────────────────────────┐  │
│  │ Tarot                                            TYPE I│  │
│  │ test • 1/2                                             │  │
│  │                                                        │  │
│  │      ◉──────────────── tape ────────────────◉         │  │
│  │                                                        │  │
│  │          [⏮]      [■]      [▶ / ❚❚]      [⏭]          │  │
│  └────────────────────────────────────────────────────────┘  │
│                                                              │
│  VOLUME 070      ━━━━━━━━━━━━━●───────────────        1x    │
│                                                              │
│  ● live                                      v2026.05.20.4  │
│                                                              │
└──────────────────────────────────────────────────────────────┘
```

---

## Visual Direction

The app should not look like a fully realistic cassette machine. Instead, it should look like a **digital cassette deck**.

### Use

- Soft gradients
- Rounded rectangles
- Inner shadows
- Outer shadows
- Glowing accent states
- Animated vector reels
- Native SwiftUI buttons
- Native SwiftUI slider

### Avoid

- Photorealistic metal
- Complex screws
- Bitmap cassette textures
- Heavy 3D assets
- Too many small decorative labels
- Overly fixed pixel layout

---

## Color System

```swift
enum MurmurColor {
    static let background = Color(hex: "#070707")

    static let shellTop = Color(hex: "#181818")
    static let shellBottom = Color(hex: "#0D0D0D")

    static let panel = Color(hex: "#141414")
    static let raisedPanel = Color(hex: "#1A1A1A")
    static let pressedPanel = Color(hex: "#0B0B0B")

    static let border = Color(hex: "#2C2C2C")
    static let borderSoft = Color.white.opacity(0.06)

    static let textPrimary = Color(hex: "#F4E8DC")
    static let textSecondary = Color(hex: "#A39A91")
    static let textMuted = Color(hex: "#6F6A65")

    static let accent = Color(hex: "#FF9F6E")
    static let accentLight = Color(hex: "#FFC19C")
    static let copper = Color(hex: "#C9784D")
    static let glow = Color(hex: "#FF9F6E").opacity(0.35)
}
```

### Color Hex Helper

```swift
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)

        let r, g, b: UInt64
        switch hex.count {
        case 6:
            r = (int >> 16) & 0xff
            g = (int >> 8) & 0xff
            b = int & 0xff
        default:
            r = 255
            g = 255
            b = 255
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: 1
        )
    }
}
```

---

## Typography

### App Title

| Property | Value |
|---|---|
| Text | MURMUR |
| Size | 22 |
| Weight | Semibold |
| Tracking | 10–12 |
| Color | Warm cream |
| Effect | Soft orange glow |

```swift
Text("MURMUR")
    .font(.system(size: 22, weight: .semibold, design: .rounded))
    .tracking(12)
    .foregroundStyle(MurmurColor.textPrimary)
    .shadow(color: MurmurColor.glow, radius: 12)
```

### Track Title

| Property | Value |
|---|---|
| Text example | Tarot |
| Size | 28 |
| Weight | Semibold |
| Design | Monospaced |
| Color | Accent orange |

```swift
Text("Tarot")
    .font(.system(size: 28, weight: .semibold, design: .monospaced))
    .foregroundStyle(MurmurColor.accent)
```

### Metadata

| Property | Value |
|---|---|
| Size | 13–14 |
| Weight | Medium |
| Design | Monospaced |
| Color | Muted warm gray |

---

## Spacing System

| Token | Value |
|---|---|
| Outer shell padding | 24 |
| Main section gap | 18 |
| Card padding | 20 |
| Input horizontal padding | 16 |
| Button gap | 10–12 |
| Small label gap | 4–8 |

---

## Radius System

| Token | Value |
|---|---|
| App shell | 32 |
| Main card | 24 |
| Input bar | 18 |
| Buttons | 12–14 |
| Badges | 8 |
| Reels | Circle |

---

## Component Structure

```text
MurmurApp
└── MurmurWindowView
    └── MurmurShellView
        ├── HeaderBarView
        ├── URLInputBarView
        ├── CassettePlayerCardView
        │   ├── TrackInfoHeaderView
        │   ├── TapeVisualizerView
        │   │   ├── TapeReelView
        │   │   ├── TapeLineView
        │   │   └── TapeReelView
        │   └── PlaybackControlsView
        └── FooterControlsView
```

---

## Main Shell

The shell is the main visible app container. It should look like a premium black audio device.

```swift
struct MurmurShellView: View {
    var body: some View {
        VStack(spacing: 18) {
            HeaderBarView()
            URLInputBarView()
            CassettePlayerCardView()
            FooterControlsView()
        }
        .padding(24)
        .frame(width: 760, height: 560)
        .background(
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            MurmurColor.shellTop,
                            MurmurColor.shellBottom
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .stroke(MurmurColor.border, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.65), radius: 40, x: 0, y: 24)
    }
}
```

---

## Header Bar

The header should balance utility actions, brand identity, and settings.

```text
Left actions        Center brand        Right controls
[screen][refresh][share]   MURMUR   [playlist][settings]
```

```swift
struct HeaderBarView: View {
    var body: some View {
        HStack {
            HStack(spacing: 10) {
                IconButton(systemName: "display")
                IconButton(systemName: "arrow.clockwise")
                IconButton(systemName: "square.and.arrow.up")
            }

            Spacer()

            Text("MURMUR")
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .tracking(12)
                .foregroundStyle(MurmurColor.textPrimary)
                .shadow(color: MurmurColor.glow, radius: 12)

            Spacer()

            HStack(spacing: 10) {
                IconButton(systemName: "list.bullet")
                IconButton(systemName: "gearshape")
            }
        }
    }
}
```

---

## Icon Button

Reusable button for header actions.

```swift
struct IconButton: View {
    let systemName: String
    @State private var isHovering = false

    var body: some View {
        Button(action: {}) {
            Image(systemName: systemName)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(isHovering ? MurmurColor.accent : MurmurColor.textSecondary)
                .frame(width: 42, height: 36)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(hex: "#242424"),
                                    Color(hex: "#111111")
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(
                            isHovering ? MurmurColor.accent.opacity(0.4) : MurmurColor.border,
                            lineWidth: 1
                        )
                )
                .shadow(color: .black.opacity(0.45), radius: 8, x: 0, y: 4)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovering = hovering
        }
    }
}
```

---

## URL Input Bar

The input should be one strong horizontal control row.

```text
[link icon] paste url or video id                 [star] [GO]
```

```swift
struct URLInputBarView: View {
    @State private var input = ""
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "link")
                .foregroundStyle(MurmurColor.accent)

            TextField("paste url or video id", text: $input)
                .textFieldStyle(.plain)
                .font(.system(size: 16, weight: .medium, design: .monospaced))
                .foregroundStyle(MurmurColor.textPrimary)

            Button(action: {}) {
                Image(systemName: "star")
                    .foregroundStyle(MurmurColor.accent)
            }
            .buttonStyle(.plain)

            Button(action: {}) {
                Text("GO")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(MurmurColor.accentLight)
                    .frame(width: 72, height: 38)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color(hex: "#2A211C"),
                                        Color(hex: "#15110F")
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(MurmurColor.accent.opacity(0.45), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .frame(height: 58)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(hex: "#181818"),
                            Color(hex: "#0E0E0E")
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(
                    isHovering ? MurmurColor.accent.opacity(0.35) : MurmurColor.border,
                    lineWidth: 1
                )
        )
        .onHover { hovering in
            isHovering = hovering
        }
    }
}
```

---

## Cassette Player Card

This is the main hero component.

It should feel like a cassette deck, but it should still be built from native SwiftUI shapes.

```swift
struct CassettePlayerCardView: View {
    var body: some View {
        VStack(spacing: 18) {
            TrackInfoHeaderView()
            TapeVisualizerView(isPlaying: true)
            PlaybackControlsView(isPlaying: true)
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(hex: "#1A1A1A"),
                            Color(hex: "#101010")
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(MurmurColor.accent.opacity(0.45), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.45), radius: 30, x: 0, y: 18)
    }
}
```

---

## Track Info Header

```text
Tarot                                            TYPE I
test • 1/2
```

```swift
struct TrackInfoHeaderView: View {
    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Tarot")
                    .font(.system(size: 28, weight: .semibold, design: .monospaced))
                    .foregroundStyle(MurmurColor.accent)

                Text("test • 1/2")
                    .font(.system(size: 14, weight: .medium, design: .monospaced))
                    .foregroundStyle(MurmurColor.textMuted)
            }

            Spacer()

            Text("TYPE I")
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(MurmurColor.textSecondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.black.opacity(0.25))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(MurmurColor.border, lineWidth: 1)
                )
        }
    }
}
```

---

## Tape Visualizer

The tape visualizer should be the main animated part of the app.

```text
Left Reel — Tape Line — Right Reel
```

```swift
struct TapeVisualizerView: View {
    let isPlaying: Bool

    var body: some View {
        HStack(spacing: 24) {
            TapeReelView(isPlaying: isPlaying)
            TapeLineView()
            TapeReelView(isPlaying: isPlaying)
        }
        .padding(.horizontal, 28)
        .frame(height: 130)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(hex: "#0B0B0B"),
                            Color(hex: "#151515")
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color(hex: "#292929"), lineWidth: 1)
        )
    }
}
```

---

## Tape Reel

Use `AngularGradient` to make the reel feel graphic and dimensional.

```swift
struct TapeReelView: View {
    let isPlaying: Bool

    @State private var rotation: Double = 0

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    AngularGradient(
                        colors: [
                            MurmurColor.accent,
                            Color(hex: "#222222"),
                            Color(hex: "#222222"),
                            MurmurColor.accent,
                            Color(hex: "#222222"),
                            Color(hex: "#222222"),
                            MurmurColor.accent
                        ],
                        center: .center
                    )
                )

            Circle()
                .fill(Color(hex: "#101010"))
                .frame(width: 28, height: 28)

            Circle()
                .stroke(MurmurColor.accent.opacity(0.8), lineWidth: 2)
        }
        .frame(width: 86, height: 86)
        .rotationEffect(.degrees(rotation))
        .shadow(color: MurmurColor.glow, radius: 12, x: 0, y: 0)
        .onAppear {
            if isPlaying {
                withAnimation(.linear(duration: 2).repeatForever(autoreverses: false)) {
                    rotation = 360
                }
            }
        }
        .onChange(of: isPlaying) { _, playing in
            if playing {
                rotation = 0
                withAnimation(.linear(duration: 2).repeatForever(autoreverses: false)) {
                    rotation = 360
                }
            }
        }
    }
}
```

---

## Tape Line

```swift
struct TapeLineView: View {
    var body: some View {
        VStack(spacing: 10) {
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            MurmurColor.accent.opacity(0.15),
                            MurmurColor.accent.opacity(0.85),
                            MurmurColor.accent.opacity(0.15)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(height: 2)

            HStack(spacing: 10) {
                ForEach(0..<12, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(MurmurColor.accent.opacity(0.45))
                        .frame(width: 2, height: 12)
                }
            }
        }
    }
}
```

---

## Playback Controls

The playback controls should feel tactile, like soft physical buttons.

```text
[previous] [stop] [play/pause] [next]
```

```swift
struct PlaybackControlsView: View {
    let isPlaying: Bool

    var body: some View {
        HStack(spacing: 12) {
            PlayerControlButton(systemName: "backward.fill")
            PlayerControlButton(systemName: "stop.fill")
            PlayerControlButton(
                systemName: isPlaying ? "pause.fill" : "play.fill",
                isActive: true,
                width: 96
            )
            PlayerControlButton(systemName: "forward.fill")
        }
    }
}
```

---

## Player Control Button

```swift
struct PlayerControlButton: View {
    let systemName: String
    var isActive: Bool = false
    var width: CGFloat = 72

    @State private var isHovering = false

    var body: some View {
        Button(action: {}) {
            Image(systemName: systemName)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(
                    isActive
                    ? MurmurColor.accentLight
                    : isHovering
                        ? MurmurColor.textPrimary
                        : MurmurColor.textSecondary
                )
                .frame(width: width, height: 48)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: isActive
                                ? [Color(hex: "#3A251B"), Color(hex: "#17100C")]
                                : [Color(hex: "#242424"), Color(hex: "#111111")],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(
                            isActive
                            ? MurmurColor.accent.opacity(0.7)
                            : isHovering
                                ? MurmurColor.accent.opacity(0.35)
                                : MurmurColor.border,
                            lineWidth: 1
                        )
                )
                .shadow(
                    color: isActive ? MurmurColor.glow : .black.opacity(0.45),
                    radius: isActive ? 18 : 8,
                    x: 0,
                    y: isActive ? 0 : 5
                )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovering = hovering
        }
    }
}
```

---

## Footer Controls

The footer contains volume, speed, live status, and version info.

```text
VOLUME 070       Slider       1x
● live           version
```

```swift
struct FooterControlsView: View {
    @State private var volume: Double = 70

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("VOLUME")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(MurmurColor.textSecondary)

                    Text(String(format: "%03d", Int(volume)))
                        .font(.system(size: 22, weight: .semibold, design: .monospaced))
                        .foregroundStyle(MurmurColor.accent)
                }

                Slider(value: $volume, in: 0...100)
                    .tint(MurmurColor.accent)

                Text("1x")
                    .font(.system(size: 18, weight: .bold, design: .monospaced))
                    .foregroundStyle(MurmurColor.textSecondary)
            }

            HStack {
                HStack(spacing: 8) {
                    Circle()
                        .fill(MurmurColor.accent)
                        .frame(width: 8, height: 8)
                        .shadow(color: MurmurColor.accent, radius: 8)

                    Text("live")
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                        .foregroundStyle(MurmurColor.textSecondary)
                }

                Spacer()

                Text("v2026.05.20.4")
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundStyle(MurmurColor.textMuted)
            }
        }
    }
}
```

---

## App States

### Empty State

| Item | Value |
|---|---|
| Title | No track loaded |
| Message | Paste a URL or video ID to start listening. |
| Visual | Reels static, play disabled, tape line dim |

### Loading State

| Item | Value |
|---|---|
| Title | Fetching track... |
| Visual | Input disabled, GO loading, cassette border pulses, playback disabled |

### Playing State

| Item | Value |
|---|---|
| Visual | Reels rotate, play button glows, live dot glows, tape line brightens |

### Paused State

| Item | Value |
|---|---|
| Visual | Reels stop, play button less intense, live dot remains visible |

### Error State

| Item | Value |
|---|---|
| Message | Could not load this source. |
| Visual | Input border changes to muted warning orange, GO remains available |

---

## macOS Interaction Rules

### Hover

| Component | Behavior |
|---|---|
| Buttons | Border becomes slightly orange, icon becomes brighter |
| Input | Border becomes accent opacity 0.35 |
| Cassette card | No strong hover needed |

### Pressed

Buttons should have:

- Slight vertical movement
- Reduced shadow
- More inner darkness

### Focus

Text field should have:

- Accent border
- Accent cursor color if possible

---

## Recommended File Structure

```text
MurmurApp.swift
MurmurWindowView.swift
MurmurShellView.swift

DesignSystem/
├── MurmurColor.swift
├── MurmurSpacing.swift
├── MurmurRadius.swift
└── Color+Hex.swift

Components/
├── HeaderBarView.swift
├── URLInputBarView.swift
├── CassettePlayerCardView.swift
├── TrackInfoHeaderView.swift
├── TapeVisualizerView.swift
├── TapeReelView.swift
├── TapeLineView.swift
├── PlaybackControlsView.swift
├── FooterControlsView.swift
├── IconButton.swift
└── PlayerControlButton.swift
```

---

## Development Notes

Use SwiftUI-native rendering:

- `RoundedRectangle`
- `Circle`
- `LinearGradient`
- `AngularGradient`
- `RadialGradient`
- `overlay`
- `shadow`
- `animation`
- `Slider`
- `ButtonStyle`
- `onHover`

Avoid first version complexity:

- SceneKit
- RealityKit
- Metal
- Heavy bitmap textures
- Large SVG illustrations
- Photorealistic 3D assets

---

## Final Design Summary

MURMUR should be developed as a **soft 3D digital cassette deck for macOS**.

The strongest design elements are:

1. A compact dark rounded shell.
2. A centered **MURMUR** brand title.
3. A practical URL input row.
4. A large cassette-inspired player card.
5. Animated vector tape reels.
6. Glowing play state.
7. Tactile playback buttons.
8. Simple footer controls for volume, speed, live status, and version.

The final result should feel:

- Premium
- Retro-futuristic
- Warm
- Minimal
- Tactile
- Mac-native
- Buildable in SwiftUI
