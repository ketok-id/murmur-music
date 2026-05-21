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

# Integrated Popover System

## Overview

The additional screens should not feel like separate floating windows. They should feel like one integrated **MURMUR popover system** that appears above the main cassette-player interface.

These popovers are used for:

1. **Up Next**
2. **Playlists**
3. **Search YouTube**
   - Videos / Discover
   - Trending
   - Channels

All popovers should share one reusable SwiftUI container.

---

## Popover Design Goals

```text
1. Keep the same dark tactile cassette UI language.
2. Dim and softly blur the main MURMUR window behind the popover.
3. Use one consistent rounded sheet style.
4. Add a small top anchor notch so the sheet feels connected to the main app.
5. Keep content modular per popover type.
6. Use warm copper/orange accent only for active states and primary actions.
7. Make animations subtle, Mac-native, and developable in SwiftUI.
```

---

## Popover Container

### Shared Visual Style

```text
Popover width: 680–760
Popover min height: 520
Popover max height: 720
Corner radius: 28
Background: dark layered gradient
Border: soft gray/copper depending on focus
Shadow: large soft black shadow
Top notch: small centered rounded triangle/chevron
```

### Shared Layout

```text
IntegratedPopover
├── PopoverHeader
│   ├── Title
│   └── CloseButton
├── OptionalToolbar
├── ContentArea
└── OptionalBottomBar / MotionNotes
```

### SwiftUI Base Container

```swift
struct IntegratedPopover<Content: View, Footer: View>: View {
    let title: String
    let content: Content
    let footer: Footer
    let onClose: () -> Void

    init(
        title: String,
        onClose: @escaping () -> Void,
        @ViewBuilder content: () -> Content,
        @ViewBuilder footer: () -> Footer
    ) {
        self.title = title
        self.onClose = onClose
        self.content = content()
        self.footer = footer()
    }

    var body: some View {
        VStack(spacing: 0) {
            PopoverHeader(title: title, onClose: onClose)

            Divider()
                .background(MurmurColor.border.opacity(0.8))

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            footer
        }
        .frame(width: 720, height: 640)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(hex: "#171717"),
                            Color(hex: "#0B0B0B")
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        )
        .overlay(alignment: .top) {
            PopoverTopNotch()
                .offset(y: -14)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(MurmurColor.border.opacity(0.9), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.72), radius: 48, x: 0, y: 28)
    }
}
```

---

## Popover Background Integration

When a popover is visible, the main app should remain visible but inactive.

```swift
struct PopoverOverlay<PopoverContent: View>: View {
    let isPresented: Bool
    let popoverContent: PopoverContent

    init(
        isPresented: Bool,
        @ViewBuilder popoverContent: () -> PopoverContent
    ) {
        self.isPresented = isPresented
        self.popoverContent = popoverContent()
    }

    var body: some View {
        ZStack {
            if isPresented {
                Color.black.opacity(0.42)
                    .ignoresSafeArea()
                    .transition(.opacity)

                VisualEffectBlur(material: .hudWindow, blendingMode: .behindWindow)
                    .opacity(0.18)
                    .ignoresSafeArea()
                    .transition(.opacity)

                popoverContent
                    .transition(
                        .asymmetric(
                            insertion: .opacity
                                .combined(with: .scale(scale: 0.96, anchor: .top))
                                .combined(with: .offset(y: -8)),
                            removal: .opacity
                                .combined(with: .scale(scale: 0.98))
                        )
                    )
            }
        }
        .animation(.spring(response: 0.34, dampingFraction: 0.86), value: isPresented)
    }
}
```

> `VisualEffectBlur` can be implemented using `NSVisualEffectView` wrapped with `NSViewRepresentable`.

---

# Popover Header

## Header Rules

```text
Height: 64
Title alignment: leading
Close button: top-right circular button
Divider: subtle line below header
```

```swift
struct PopoverHeader: View {
    let title: String
    let onClose: () -> Void

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(MurmurColor.textPrimary)

            Spacer()

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(MurmurColor.textSecondary)
                    .frame(width: 28, height: 28)
                    .background(
                        Circle()
                            .fill(Color.white.opacity(0.08))
                    )
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 24)
        .frame(height: 64)
    }
}
```

```swift
struct PopoverTopNotch: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(Color(hex: "#171717"))
            .frame(width: 38, height: 22)
            .rotationEffect(.degrees(45))
            .overlay(
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .stroke(MurmurColor.border.opacity(0.8), lineWidth: 1)
            )
    }
}
```

---

# Shared Popover Components

## Segmented Tabs

Used by **Search YouTube** for Videos, Trending, and Channels.

```swift
enum YouTubeSearchTab: String, CaseIterable {
    case videos = "Videos"
    case trending = "Trending"
    case channels = "Channels"
}
```

```swift
struct MurmurSegmentedTabs<T: Hashable & RawRepresentable>: View where T.RawValue == String {
    let tabs: [T]
    @Binding var selectedTab: T

    var body: some View {
        HStack(spacing: 0) {
            ForEach(tabs, id: \.self) { tab in
                Button {
                    selectedTab = tab
                } label: {
                    Text(tab.rawValue)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(selectedTab == tab ? MurmurColor.textPrimary : MurmurColor.textSecondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 38)
                        .background {
                            if selectedTab == tab {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(
                                        LinearGradient(
                                            colors: [
                                                MurmurColor.accent.opacity(0.72),
                                                MurmurColor.copper.opacity(0.52)
                                            ],
                                            startPoint: .top,
                                            endPoint: .bottom
                                        )
                                    )
                                    .matchedGeometryEffect(id: "tab-highlight", in: namespace)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(MurmurColor.border, lineWidth: 1)
        )
    }

    @Namespace private var namespace
}
```

## Primary Search Field

```swift
struct PopoverSearchField: View {
    let placeholder: String
    @Binding var text: String
    let onSearch: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(isFocused ? MurmurColor.accent : MurmurColor.textSecondary)

            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .focused($isFocused)
                .font(.system(size: 15, weight: .medium, design: .monospaced))
                .foregroundStyle(MurmurColor.textPrimary)

            Button("Search", action: onSearch)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(MurmurColor.accentLight)
                .padding(.horizontal, 18)
                .frame(height: 36)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color(hex: "#7A432D"), Color(hex: "#3A2118")],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                )
        }
        .padding(.horizontal, 14)
        .frame(height: 52)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.black.opacity(0.25))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(
                    isFocused ? MurmurColor.accent.opacity(0.55) : MurmurColor.border,
                    lineWidth: 1
                )
        )
        .shadow(color: isFocused ? MurmurColor.glow : .clear, radius: 12)
    }
}
```

## Motion Notes Bar

Use this only in design/debug builds or as a design spec reference. It should not necessarily ship in production.

```swift
struct MotionNotesBar: View {
    let notes: [MotionNote]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(notes) { note in
                HStack(spacing: 10) {
                    Image(systemName: note.icon)
                        .foregroundStyle(MurmurColor.accent)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(note.title)
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundStyle(MurmurColor.textPrimary)

                        Text(note.description)
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(MurmurColor.textMuted)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)

                if note.id != notes.last?.id {
                    Divider()
                        .background(MurmurColor.border.opacity(0.7))
                }
            }
        }
        .frame(height: 58)
        .background(Color.black.opacity(0.16))
        .overlay(alignment: .top) {
            Divider()
                .background(MurmurColor.border.opacity(0.8))
        }
    }
}

struct MotionNote: Identifiable, Equatable {
    let id = UUID()
    let icon: String
    let title: String
    let description: String
}
```

---

# Up Next Popover

## Purpose

The **Up Next** popover shows queued tracks. In the empty state, it guides the user to add items from search results.

## Layout

```text
Up Next (0)
├── EmptyState
│   ├── Queue icon
│   ├── Queue is empty.
│   └── Right-click a search result → Add to queue.
├── Auto-fill from Trending toggle bar
└── Motion notes
```

## Empty State Visual

```text
Center icon: queue/list glyph inside faint circle
Headline: Queue is empty.
Helper: Right-click a search result → Add to queue.
```

## Auto-fill Footer

```text
[flame icon] Auto-fill from Trending              [toggle]
```

## SwiftUI View

```swift
struct UpNextPopoverView: View {
    @Binding var autoFillFromTrending: Bool
    let onClose: () -> Void

    var body: some View {
        IntegratedPopover(title: "Up Next (0)", onClose: onClose) {
            VStack(spacing: 0) {
                Spacer()

                VStack(spacing: 18) {
                    Image(systemName: "list.bullet")
                        .font(.system(size: 38, weight: .medium))
                        .foregroundStyle(MurmurColor.accent.opacity(0.7))
                        .frame(width: 86, height: 86)
                        .background(
                            Circle()
                                .fill(Color.white.opacity(0.035))
                        )
                        .overlay(
                            Circle()
                                .stroke(MurmurColor.border.opacity(0.7), lineWidth: 1)
                        )

                    Text("Queue is empty.")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(MurmurColor.textPrimary)

                    Text("Right-click a search result → Add to queue.")
                        .font(.system(size: 14, weight: .medium, design: .monospaced))
                        .foregroundStyle(MurmurColor.textSecondary)
                }

                Spacer()

                HStack {
                    HStack(spacing: 10) {
                        Image(systemName: "flame.fill")
                            .foregroundStyle(MurmurColor.accent)

                        Text("Auto-fill from Trending")
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundStyle(MurmurColor.textPrimary)
                    }

                    Spacer()

                    Toggle("", isOn: $autoFillFromTrending)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }
                .padding(.horizontal, 24)
                .frame(height: 70)
                .background(Color.black.opacity(0.18))
                .overlay(alignment: .top) {
                    Divider()
                        .background(MurmurColor.border)
                }
            }
        } footer: {
            MotionNotesBar(notes: [
                MotionNote(icon: "sparkles", title: "Sheet", description: "Fade + scale in"),
                MotionNote(icon: "switch.2", title: "Toggle", description: "Spring animation"),
                MotionNote(icon: "list.bullet.rectangle", title: "Queued Items", description: "Slide in from below")
            ])
        }
    }
}
```

## Animation

```text
Sheet open:
- opacity 0 → 1
- scale 0.96 → 1.0
- y offset -8 → 0

Empty state:
- icon appears first
- headline fades up after 0.06s
- helper text fades up after 0.12s

Auto-fill toggle:
- native macOS spring toggle
- flame icon softly brightens when enabled

Queued item insertion:
- slide in from bottom
- fade in
- slight scale 0.98 → 1
```

---

# Playlists Popover

## Purpose

The **Playlists** popover manages saved playlists and playlist creation.

## Layout

```text
Playlists (2)
├── New Playlist Input
├── Playlist Rows
│   ├── indonesia — 0 items
│   └── test — 2 items
└── Motion notes
```

## Design Behavior

```text
Input focused:
- copper border glow
- visible text cursor
- plus icon remains leading action

Playlist row:
- dark rounded card
- icon on the left
- name + item count
- active row has copper border and small play triangle on right
```

## SwiftUI View

```swift
struct PlaylistsPopoverView: View {
    @State private var newPlaylistName = ""
    @State private var activePlaylistID: String? = "test"

    let onClose: () -> Void

    var body: some View {
        IntegratedPopover(title: "Playlists (2)", onClose: onClose) {
            VStack(spacing: 18) {
                NewPlaylistInput(text: $newPlaylistName)

                VStack(spacing: 12) {
                    PlaylistRow(
                        title: "indonesia",
                        subtitle: "0 items",
                        isActive: activePlaylistID == "indonesia"
                    ) {
                        activePlaylistID = "indonesia"
                    }

                    PlaylistRow(
                        title: "test",
                        subtitle: "2 items",
                        isActive: activePlaylistID == "test"
                    ) {
                        activePlaylistID = "test"
                    }
                }

                Spacer()
            }
            .padding(24)
        } footer: {
            MotionNotesBar(notes: [
                MotionNote(icon: "sparkles", title: "Sheet", description: "Fade + scale in"),
                MotionNote(icon: "circle.hexagongrid.fill", title: "Input Focus", description: "Subtle glow"),
                MotionNote(icon: "arrow.down.circle", title: "New Playlist", description: "Expand + slide down"),
                MotionNote(icon: "play.circle", title: "Active Row", description: "Highlight fade")
            ])
        }
    }
}
```

## New Playlist Input

```swift
struct NewPlaylistInput: View {
    @Binding var text: String
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "plus.circle")
                .foregroundStyle(isFocused ? MurmurColor.accent : MurmurColor.textSecondary)

            TextField("New playlist name", text: $text)
                .textFieldStyle(.plain)
                .focused($isFocused)
                .font(.system(size: 18, weight: .semibold, design: .monospaced))
                .foregroundStyle(MurmurColor.textPrimary)
        }
        .padding(.horizontal, 18)
        .frame(height: 58)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.black.opacity(0.22))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(
                    isFocused ? MurmurColor.accent.opacity(0.55) : MurmurColor.border,
                    lineWidth: 1
                )
        )
        .shadow(color: isFocused ? MurmurColor.glow : .clear, radius: 12)
    }
}
```

## Playlist Row

```swift
struct PlaylistRow: View {
    let title: String
    let subtitle: String
    let isActive: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(0.055))
                    .frame(width: 64, height: 64)
                    .overlay {
                        Image(systemName: "music.note.list")
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundStyle(MurmurColor.textSecondary)
                    }

                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(MurmurColor.textPrimary)

                    Text(subtitle)
                        .font(.system(size: 15, weight: .medium, design: .monospaced))
                        .foregroundStyle(MurmurColor.textMuted)
                }

                Spacer()

                if isActive {
                    Image(systemName: "play.fill")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(MurmurColor.accent)
                        .transition(.opacity.combined(with: .scale))
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.white.opacity(isHovering ? 0.07 : 0.045))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(
                        isActive ? MurmurColor.accent.opacity(0.6) : MurmurColor.border.opacity(0.8),
                        lineWidth: 1
                    )
            )
            .shadow(color: isActive ? MurmurColor.glow.opacity(0.55) : .clear, radius: 14)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .animation(.spring(response: 0.28, dampingFraction: 0.86), value: isActive)
    }
}
```

## Animation

```text
Sheet:
- fade + scale in

Input focus:
- border glow fades in
- plus icon shifts to accent color

New playlist creation:
- new row expands vertically from height 0
- row slides down from input
- opacity 0 → 1

Active playlist:
- row border fades to copper
- play icon scales 0.8 → 1.0
- subtle glow appears
```

---

# Search YouTube Popover

## Purpose

The **Search YouTube** popover is the main discovery/search system. It has three tabs:

1. **Videos**
2. **Trending**
3. **Channels**

## Shared Layout

```text
Search YouTube
├── Tabs
│   ├── Videos
│   ├── Trending
│   └── Channels
├── Tab-specific toolbar/search area
├── Tab-specific content
└── Motion notes
```

---

## Search YouTube — Videos / Discover State

### Purpose

This is the default search screen. It gives users quick category entry points before they search.

### Layout

```text
Search YouTube
├── Segmented Tabs: Videos selected
├── Search Field
├── Discover Section
│   ├── Lofi & Chill
│   ├── Music Mixes
│   ├── Jazz & Soul
│   ├── Classical
│   ├── Ambient
│   ├── EDM
│   ├── Indie
│   ├── Piano
│   ├── Tech Podcasts
│   ├── Interviews
│   ├── Audiobooks
│   ├── Science Talks
│   ├── Rain Sounds
│   ├── Fireplace
│   ├── Live Radio
│   └── Nature Sounds
├── Recent Videos
└── Motion notes
```

### Discover Category Card

```swift
struct DiscoverCategoryCard: View {
    let icon: String
    let title: String
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Text(icon)
                    .font(.system(size: 24))

                Text(title)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(MurmurColor.textPrimary)

                Spacer()
            }
            .padding(.horizontal, 16)
            .frame(height: 48)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(isHovering ? 0.075 : 0.045))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(
                        isHovering ? MurmurColor.accent.opacity(0.45) : MurmurColor.border.opacity(0.7),
                        lineWidth: 1
                    )
            )
            .offset(y: isHovering ? -1 : 0)
            .shadow(color: isHovering ? MurmurColor.glow.opacity(0.45) : .clear, radius: 12)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .animation(.spring(response: 0.25, dampingFraction: 0.82), value: isHovering)
    }
}
```

### Recent Video Card

```swift
struct RecentVideoCard: View {
    let title: String
    let subtitle: String
    let duration: String

    var body: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(hex: "#34231F"), Color(hex: "#101010")],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 112, height: 64)
                .overlay {
                    Image(systemName: "play.fill")
                        .foregroundStyle(MurmurColor.textPrimary)
                        .padding(8)
                        .background(Circle().fill(Color.black.opacity(0.35)))
                }
                .overlay(alignment: .bottomTrailing) {
                    Text(duration)
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.black.opacity(0.65)))
                        .foregroundStyle(MurmurColor.textPrimary)
                        .padding(6)
                }

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(MurmurColor.textPrimary)
                    .lineLimit(2)

                Text(subtitle)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(MurmurColor.textMuted)
                    .lineLimit(1)
            }
        }
        .padding(8)
        .frame(width: 220, height: 80)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.045))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(MurmurColor.border.opacity(0.7), lineWidth: 1)
        )
    }
}
```

### Videos Tab Animation

```text
Tab switch:
- selected tab highlight slides using matchedGeometryEffect

Discover cards:
- staggered fade-up, 0.025s delay per item
- hover lift by -1px
- copper border glow on hover

Recent videos:
- horizontal cards fade in after Discover section
```

---

## Search YouTube — Trending State

### Purpose

The Trending tab displays popular videos, filterable by region and category.

### Layout

```text
Search YouTube
├── Segmented Tabs: Trending selected
├── Filter Row
│   ├── flame TRENDING
│   ├── region selector: ID
│   ├── category selector: All
│   └── refresh button
├── Trending Results List
└── Motion notes
```

### Filter Row

```swift
struct TrendingFilterRow: View {
    var body: some View {
        HStack(spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: "flame.fill")
                    .foregroundStyle(MurmurColor.accent)

                Text("TRENDING")
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .tracking(3)
                    .foregroundStyle(MurmurColor.textPrimary)
            }

            FilterChip(title: "ID")
            FilterChip(title: "All", icon: "sparkles")

            Spacer()

            IconButton(systemName: "arrow.clockwise")
        }
        .padding(.horizontal, 14)
        .frame(height: 46)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.black.opacity(0.22))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(MurmurColor.border.opacity(0.8), lineWidth: 1)
        )
    }
}
```

```swift
struct FilterChip: View {
    let title: String
    var icon: String? = nil

    var body: some View {
        HStack(spacing: 6) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(MurmurColor.accent)
            }

            Text(title)
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundStyle(MurmurColor.textPrimary)

            Image(systemName: "chevron.down")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(MurmurColor.textSecondary)
        }
    }
}
```

### Trending Result Row

```swift
struct VideoResultRow: View {
    let title: String
    let channel: String
    let duration: String
    let isHovered: Bool

    var body: some View {
        HStack(spacing: 16) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(hex: "#3A2525"), Color(hex: "#151515")],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 132, height: 74)
                .overlay(alignment: .bottomTrailing) {
                    Text(duration)
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.black.opacity(0.75)))
                        .foregroundStyle(MurmurColor.textPrimary)
                        .padding(6)
                }

            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(MurmurColor.textPrimary)
                    .lineLimit(2)

                Text(channel)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(MurmurColor.textMuted)
            }

            Spacer()

            if isHovered {
                Button(action: {}) {
                    Image(systemName: "ellipsis")
                        .foregroundStyle(MurmurColor.accent)
                        .frame(width: 32, height: 32)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.white.opacity(0.06))
                        )
                }
                .buttonStyle(.plain)
                .transition(.opacity.combined(with: .scale))
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(isHovered ? MurmurColor.accent.opacity(0.08) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(isHovered ? MurmurColor.accent.opacity(0.5) : Color.clear, lineWidth: 1)
        )
    }
}
```

### Trending Animation

```text
Rows:
- stagger in from y: 8
- opacity 0 → 1

Hover:
- row background fades to copper opacity 0.08
- border appears
- more button fades/scales in

Refresh:
- icon rotates 180–360 degrees
- list crossfades after reload
```

---

## Search YouTube — Channels State

### Purpose

The Channels tab allows users to search and manage saved YouTube channels.

### Layout

```text
Search YouTube
├── Segmented Tabs: Channels selected
├── Channel Search Field
├── Saved Channels
│   └── Raditya Dika
└── Motion notes
```

### Saved Channel Row

```swift
struct SavedChannelRow: View {
    let name: String
    let isFavorite: Bool
    let onFavorite: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 16) {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [Color(hex: "#2B2B2B"), Color(hex: "#111111")],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 54, height: 54)
                .overlay {
                    Image(systemName: "person.fill")
                        .foregroundStyle(MurmurColor.textSecondary)
                }

            Text(name)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(MurmurColor.textPrimary)

            Spacer()

            Button(action: onFavorite) {
                Image(systemName: isFavorite ? "star.fill" : "star")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(MurmurColor.accent)
                    .symbolEffect(.pulse, value: isFavorite)
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(isHovering ? 0.065 : 0.045))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(isHovering ? MurmurColor.accent.opacity(0.35) : MurmurColor.border.opacity(0.7), lineWidth: 1)
        )
        .onHover { isHovering = $0 }
        .animation(.spring(response: 0.25, dampingFraction: 0.86), value: isHovering)
    }
}
```

### Channels Animation

```text
Tab switch:
- highlight slides to Channels

Search focus:
- field border glows
- magnifier changes to accent

Saved channel row:
- fades up
- hover raises opacity
- favorite star pulses on toggle
```

---

# Search YouTube Main View

```swift
struct SearchYouTubePopoverView: View {
    @State private var selectedTab: YouTubeSearchTab = .videos
    @State private var searchText = ""
    let onClose: () -> Void

    var body: some View {
        IntegratedPopover(title: "Search YouTube", onClose: onClose) {
            VStack(spacing: 14) {
                MurmurSegmentedTabs(
                    tabs: YouTubeSearchTab.allCases,
                    selectedTab: $selectedTab
                )
                .padding(.horizontal, 96)
                .padding(.top, 16)

                Group {
                    switch selectedTab {
                    case .videos:
                        SearchVideosDiscoverView(searchText: $searchText)
                    case .trending:
                        SearchTrendingView()
                    case .channels:
                        SearchChannelsView(searchText: $searchText)
                    }
                }
                .transition(.opacity.combined(with: .offset(y: 6)))
                .animation(.easeOut(duration: 0.18), value: selectedTab)
            }
            .padding(.horizontal, 20)
        } footer: {
            MotionNotesBar(notes: motionNotes)
        }
    }

    private var motionNotes: [MotionNote] {
        switch selectedTab {
        case .videos:
            return [
                MotionNote(icon: "sparkles", title: "Popover", description: "Fade + scale in"),
                MotionNote(icon: "rectangle.2.swap", title: "Tabs", description: "Sliding highlight"),
                MotionNote(icon: "square.grid.2x2", title: "Cards", description: "Staggered entrance"),
                MotionNote(icon: "rectangle.and.hand.point.up.left", title: "Hover", description: "Lift + glow"),
                MotionNote(icon: "scroll", title: "Scrollbar", description: "Fades while idle")
            ]
        case .trending:
            return [
                MotionNote(icon: "sparkles", title: "Sheet", description: "Fade + scale in"),
                MotionNote(icon: "rectangle.2.swap", title: "Tabs", description: "Slide highlight"),
                MotionNote(icon: "list.bullet", title: "List Rows", description: "Stagger in"),
                MotionNote(icon: "hand.point.up.left", title: "Row Hover", description: "Lift + glow"),
                MotionNote(icon: "scroll", title: "Scrollbar", description: "Fades while idle")
            ]
        case .channels:
            return [
                MotionNote(icon: "sparkles", title: "Sheet", description: "Fade + scale in"),
                MotionNote(icon: "rectangle.2.swap", title: "Tabs", description: "Highlight slide"),
                MotionNote(icon: "person.crop.circle", title: "Row", description: "Fade up"),
                MotionNote(icon: "star", title: "Favorite", description: "Star pulse"),
                MotionNote(icon: "magnifyingglass", title: "Focus", description: "Search glow")
            ]
        }
    }
}
```

---

# Popover Presentation State

Use one enum to control which popover is currently open.

```swift
enum ActivePopover: Equatable {
    case none
    case upNext
    case playlists
    case searchYouTube(initialTab: YouTubeSearchTab)
}
```

Example integration:

```swift
struct MurmurWindowView: View {
    @State private var activePopover: ActivePopover = .none
    @State private var autoFillFromTrending = false

    var body: some View {
        ZStack {
            MurmurShellView()
                .disabled(activePopover != .none)
                .blur(radius: activePopover == .none ? 0 : 2.5)
                .scaleEffect(activePopover == .none ? 1 : 0.985)
                .animation(.spring(response: 0.34, dampingFraction: 0.88), value: activePopover)

            PopoverOverlay(isPresented: activePopover != .none) {
                switch activePopover {
                case .none:
                    EmptyView()

                case .upNext:
                    UpNextPopoverView(
                        autoFillFromTrending: $autoFillFromTrending,
                        onClose: { activePopover = .none }
                    )

                case .playlists:
                    PlaylistsPopoverView(
                        onClose: { activePopover = .none }
                    )

                case .searchYouTube(let initialTab):
                    SearchYouTubePopoverView(
                        initialTab: initialTab,
                        onClose: { activePopover = .none }
                    )
                }
            }
        }
    }
}
```

---

# Animation System

## Global Popover Animation

```text
Open:
- background dim opacity 0 → 0.42
- main shell blur 0 → 2.5
- main shell scale 1 → 0.985
- popover opacity 0 → 1
- popover scale 0.96 → 1
- popover y -8 → 0

Close:
- reverse with faster ease
```

Recommended SwiftUI timing:

```swift
.animation(.spring(response: 0.34, dampingFraction: 0.86), value: activePopover)
```

## Content Entrance

```text
Header:
- appears with sheet

Tabs:
- fade in
- selected highlight slides via matchedGeometryEffect

Cards:
- staggered fade-up

Rows:
- staggered slide from y: 8
- hover state uses lift + glow

Scrollbar:
- opacity 0 by default
- opacity 0.65 while scrolling
- fade back after delay
```

## Hover States

```text
Cards:
- y offset -1
- border accent opacity 0.45
- background opacity increases slightly

Rows:
- background becomes accent opacity 0.08
- border becomes accent opacity 0.5
- trailing action appears

Buttons:
- icon color becomes textPrimary or accent
- border becomes accent opacity 0.35
```

---

# Scrollbar Design

Use a custom overlay scrollbar only if the default macOS scrollbar feels visually inconsistent.

```swift
struct MurmurScrollbar: View {
    let progress: CGFloat
    let visibleRatio: CGFloat
    let isVisible: Bool

    var body: some View {
        GeometryReader { proxy in
            let height = proxy.size.height * visibleRatio
            let y = proxy.size.height * progress

            RoundedRectangle(cornerRadius: 999)
                .fill(MurmurColor.textSecondary.opacity(0.55))
                .frame(width: 7, height: max(44, height))
                .offset(y: y)
                .opacity(isVisible ? 1 : 0)
                .animation(.easeOut(duration: 0.18), value: isVisible)
        }
        .frame(width: 10)
    }
}
```

---

# Context Menu Integration

Search result rows should support right-click actions.

```text
Video Result Context Menu:
- Play Now
- Add to Queue
- Add to Playlist
- Copy YouTube URL

Channel Row Context Menu:
- Search Channel
- Remove from Saved
- Copy Channel URL

Playlist Row Context Menu:
- Play Playlist
- Rename
- Delete
```

SwiftUI example:

```swift
.contextMenu {
    Button("Play Now") {}
    Button("Add to Queue") {}
    Button("Add to Playlist") {}
    Divider()
    Button("Copy YouTube URL") {}
}
```

---

# Final Popover Design Summary

The new popover system should feel like a natural extension of the main MURMUR cassette deck.

```text
Main app:
Soft 3D digital cassette deck

Popover system:
Dark floating control sheet connected to the app shell

Shared behavior:
Dim + blur background
Fade + scale popover
Sliding tab highlight
Staggered rows/cards
Copper hover glow
Native macOS interactions
```

The redesigned screens should now feel unified:

```text
Up Next:
Calm empty queue state + auto-fill toggle

Playlists:
Focused playlist management with strong active row

Search YouTube / Videos:
Discovery grid + recent videos

Search YouTube / Trending:
Scrollable results with filters and row hover actions

Search YouTube / Channels:
Saved channel management with favorite pulse
```

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
