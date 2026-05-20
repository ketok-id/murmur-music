<div align="center">

# Murmur

**A tiny native macOS menu-bar app for YouTube background audio — with an optional chromeless floating video window.**

<img src="icon.png" width="128" alt="Murmur app icon" />

Swift · SwiftUI · WKWebView · ~2 MB binary · macOS 13+

</div>

---

## Features

- **Menu-bar widget** — lives in the menu bar, no Dock icon.
- **YouTube audio** — paste any URL or video ID, or pick from the built-in Discover catalog (lofi, synthwave, jazz, classical, electronic).
- **Chromeless floating video** — optional 16:9 window with no title bar, draggable from anywhere, always-on-top, aspect-ratio-locked.
- **Cassette tape UI** — animated reels with play/pause inside the cassette; rotation speed tied to volume.
- **Favorites** — save the current stream, recall it instantly. Active item is marked in both Favorites and Discover.
- **Smart loading** — opaque mask hides any flash between stream switches, so you never see YouTube's overlay or branding.

## Requirements

- macOS 13 (Ventura) or later
- Xcode Command Line Tools (Swift 5.9+) — install with:
  ```bash
  xcode-select --install
  ```

Recipients of a shared `.app` only need macOS 13+ — no Swift toolchain.

## Quick start

### Run locally

```bash
swift run -c release
```

First build takes ~15 seconds; subsequent launches are instant.

### Build a shareable `.app`

```bash
./build-app.sh
```

Produces:

| File | Purpose |
| --- | --- |
| `dist/Murmur.app` | Double-clickable app |
| `dist/Murmur.zip` | Send this to others (~250 KB zipped) |

Optional flags:

- `--no-sign` — skip ad-hoc codesign (default is **on**; turning it off will produce a binary Apple Silicon refuses to launch)
- `--open` — open the `dist/` folder in Finder when done

### Sharing

1. Send `dist/Murmur.zip`.
2. Recipient unzips.
3. First launch: **right-click → Open → Open** in the Gatekeeper warning. After that, normal double-click works forever.
4. Optional: drag `Murmur.app` into `/Applications`.

If Gatekeeper says "app is damaged":

```bash
xattr -dr com.apple.quarantine /path/to/Murmur.app
```

## Customizing

### Default stream

Edit [`Sources/Murmur/main.swift`](Sources/Murmur/main.swift):

```swift
let kDefaultVideoID = "AUQKjgKQF7w"
```

Replace with any YouTube video ID (the part after `v=`). Rebuild.

### Discover catalog

Edit the `catalog` array near the bottom of [`Sources/Murmur/ContentView.swift`](Sources/Murmur/ContentView.swift). Add categories or items — they'll appear in the ★ menu under "Discover live music".

### App icon

The icon is generated from a Swift script so it stays in sync with the in-app palette:

```bash
swift make-icon.swift
```

That regenerates `icon.png`. Then `./build-app.sh` rebakes the `.icns` into the bundle.

## Architecture

```
Sources/Murmur/
├── main.swift          # AppDelegate, PlayerController, VideoWindowController, JS bridge
├── ContentView.swift   # SwiftUI popover, Discover catalog, header / footer
└── PixelDancer.swift   # Procedural cassette (Canvas + TimelineView)
```

### How it works

- An `NSStatusItem` lives in the menu bar and opens a SwiftUI popover.
- A `WKWebView` hosts the YouTube embed iframe and lives in a real `NSWindow` (off-screen by default) so WebKit doesn't suspend media playback.
- Toggling the video on changes the window's `styleMask` to a chromeless `[.titled, .closable, .resizable, .fullSizeContentView]` floating window.
- A transparent `WindowDragOverlay` on top of the WKWebView calls `window.performDrag(with:)` so the entire video surface drags the window — `isMovableByWindowBackground` alone is unreliable when stacked over WebKit.
- Swift ↔ iframe communication uses the YouTube IFrame API's postMessage protocol, with state and title posted back via `webkit.messageHandlers`.
- Stream switches trigger a Swift-side opaque mask **and** an in-page JS cover, so neither the WKWebView reload flash nor YouTube's branding overlay are ever visible.

## Notes

- Live streams require an internet connection.
- Closing the floating video window only hides it — audio keeps playing. Use the **Quit** button in the popover footer to fully exit.
- Drag from anywhere on the video to move the window.
- The app runs as `LSUIElement` (no Dock icon), so there's no app menu — Quit is in the popover.

## License

[MIT](LICENSE) — do whatever you like, just keep the copyright notice.
