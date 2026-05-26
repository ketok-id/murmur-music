<div align="center">

# Murmur

**A tiny native macOS menu-bar app for YouTube background audio — with an optional chromeless floating video window, local playlists, sharing, and pin-to-all-Spaces.**

<img src="icon.png" width="128" alt="Murmur app icon" />

Swift · SwiftUI · WKWebView · ~1.4 MB zipped · macOS 13+

**[murmur.ketok.id](https://murmur.ketok.id)**

</div>

---

## Features

### Listening
- **Menu-bar widget** — lives in the menu bar, no Dock icon.
- **YouTube audio** — paste any URL or video ID, or pick from the built-in Discover catalog (lofi, synthwave, jazz, classical, electronic).
- **YouTube playlists** — paste any `&list=PL…` URL and Murmur enumerates the items via the Data API, follows auto-advance, and shows track index in the header. Mix playlists (`RD…`) play but can't auto-advance — the app warns you.
- **YouTube search** — built-in search sheet for videos, trending (regional), and channels. Browse a channel's recent uploads. Recent searches and recently-played videos are tracked.
- **Trending tab** — regional picker, optional auto-fill into the playback queue when it empties.
- **Playback queue** — "Play next" / "Add to queue" from any search result or history row; reorderable, persisted.
- **Local playlists** — create / rename / delete / reorder named playlists. Right-click any video → "Add to: My Mix". Lives entirely on your Mac (UserDefaults), nothing pushed to your YouTube account.
- **Favorites** — save the current stream and the active item gets marked in the ★ menu.
- **Playback rate** — 0.5× to 2.0× via a small menu next to the volume slider.

### Window
- **Chromeless floating video** — optional window with no title bar, draggable from anywhere, always-on-top, aspect-ratio-locked.
- **HUD overlay** — fades in on hover: play/pause, scrub, time, volume, **orientation**, **pin**, **full screen**, close.
- **Portrait / landscape toggle** — flip the window between 16:9 (regular videos) and 9:16 (YouTube Shorts and other vertical content); the choice persists across launches.
- **Full screen** — borderless full-screen on the current display, covering the menu bar; exits cleanly back to the floating window (Esc or the HUD button).
- **Pin to all Spaces** — pinning toggles `.canJoinAllSpaces` so the video follows you across Mission Control desktops and into full-screen apps. Persists across launches.
- **Cassette tape UI** — animated reels with play/pause inside the cassette; the cassette's label carries the now-playing title + playlist context; rotation speed tied to volume.
- **Smart loading** — opaque mask hides any flash between stream switches, and an in-page cover masks YouTube's paused-state overlay (Topic-channel "now playing" card, center pills) — so the floating window only ever shows the video itself.

### Sharing & updates
- **Share menu** in the popover — system share sheet via `ShareLink`, plus copy actions for: YouTube link, Murmur deep link, title, title + link, rich "now playing" card.
- **`murmur://` URL scheme** — `murmur://play?v=<id>[&list=<playlistID>]`. Recipients with Murmur installed open straight into playback.
- **In-app self-update** — when a newer release is published, the footer version label flips into a tappable accent badge. Clicking it downloads the new build, swaps it in place, and relaunches — no trip to GitHub, no manual reinstall. (Falls back to opening the release page if the in-place update can't run, e.g. the app isn't in a writable location.) Background check runs on launch + every 6 hours against GitHub Releases.

## Requirements

- macOS 13 (Ventura) or later
- Xcode Command Line Tools (Swift 5.9+) — install with:
  ```bash
  xcode-select --install
  ```
- **Optional:** a YouTube Data API v3 key for search / trending / playlist enumeration. The gear icon in the popover walks you through adding one.

Recipients of a shared `.app` only need macOS 13+ — no Swift toolchain.

## Quick start

### Run locally

```bash
swift run -c release
```

First build takes ~15–20 seconds; subsequent launches are instant.

> The dev binary reports its version as `dev` and skips the update check.

### Build a shareable `.app`

```bash
./build-app.sh
```

Produces:

| File | Purpose |
| --- | --- |
| `dist/Murmur.app` | Double-clickable app |
| `dist/Murmur.zip` | Send this to others (~1.4 MB zipped) |
| `dist/Murmur.dmg` | Drag-to-Applications installer — the download to host on the website (~1.6 MB) |

Optional flags:

- `--no-sign` — skip ad-hoc codesign (default is **on**; turning it off will produce a binary Apple Silicon refuses to launch)
- `--no-dmg` — skip building the `.dmg` (just `.app` + `.zip`)
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

### Publishing a new release

1. Bump `VERSION` in [`build-app.sh`](build-app.sh).
2. `./build-app.sh` to build + zip.
3. Commit, then tag with the **`v` prefix** (matching the existing release history):
   ```bash
   git tag v2026.05.20.5
   git push origin main v2026.05.20.5
   ```
4. Publish the release with the bundled zip:
   ```bash
   gh release create v2026.05.20.5 \
     --latest --title "v2026.05.20.5 — …" \
     --notes "…" dist/Murmur.zip
   ```

Anyone running an older build sees the update badge within 6 hours of their next launch.

## Customizing

### Default stream

Edit [`Sources/Murmur/main.swift`](Sources/Murmur/main.swift):

```swift
let kDefaultVideoID = "YmQ7jRgf4f0"
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

### Update-check endpoint

`UpdateChecker.releasesAPI` in [`Sources/Murmur/Ambient/UpdateChecker.swift`](Sources/Murmur/Ambient/UpdateChecker.swift) points to the GitHub Releases API for this fork. If you fork the project, update that constant.

## Architecture

```
Sources/Murmur/
├── main.swift                  # AppDelegate, PlayerController, VideoWindowController, JS bridge, URL-scheme handler
├── ContentView.swift           # SwiftUI popover (wordmark, header toolbar, URL row, cassette, volume, status)
├── PixelDancer.swift           # Procedural cassette (Canvas + TimelineView) with title overlay
├── VideoControlsHUD.swift      # HUD bar on the floating window (play, scrub, volume, pin, close)
├── MarqueeText.swift           # Scrolling text helper (used in the cassette label)
├── YouTubeSearchSheet.swift    # Search / trending / channels / history sheet
├── Ambient/
│   ├── PlaybackQueue.swift     # FIFO queue, persisted to UserDefaults
│   ├── PlaylistStore.swift     # Enumerates YouTube &list=… playlists
│   ├── UserPlaylistsStore.swift # Local named playlists (CRUD + active-cursor)
│   ├── PlayedVideoHistoryStore.swift
│   ├── SearchHistoryStore.swift
│   ├── TrendingRegionStore.swift
│   └── UpdateChecker.swift     # Polls GitHub Releases
├── Booth/                      # Search/results panels, sheets, picker UIs
└── (Audio · Analysis · Decks · Mood · Recordings · Scenes — DJ booth stack)
```

### How it works

- An `NSStatusItem` lives in the menu bar and opens an `NSPopover` (behavior `.applicationDefined` + a global `NSEvent` monitor for click-outside-to-close — `.transient` causes SwiftUI Menu hover flicker).
- A `WKWebView` hosts the YouTube embed iframe and lives in a real `NSWindow` (off-screen by default) so WebKit doesn't suspend media playback.
- Toggling the video on changes the window's `styleMask` to a chromeless `[.titled, .closable, .resizable, .fullSizeContentView]` floating window. Pinning flips `collectionBehavior` to `[.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]` so the window joins every Space.
- The orientation toggle swaps the window's `contentAspectRatio` / `minSize` between 16:9 and 9:16 (re-anchored around the current center) and persists the choice. Full screen is manual — a borderless `setFrame(screen.frame)` at `.popUpMenu` level rather than AppKit's native `toggleFullScreen(_:)`, which would strand a menu-bar-only app on its own Space.
- A transparent `WindowDragOverlay` on top of the WKWebView calls `window.performDrag(with:)` so the entire video surface drags the window — `isMovableByWindowBackground` alone is unreliable when stacked over WebKit.
- Swift ↔ iframe communication uses the YouTube IFrame API's postMessage protocol, with state and title posted back via `webkit.messageHandlers`.
- Stream switches trigger a Swift-side opaque mask **and** an in-page JS cover, so neither the WKWebView reload flash nor YouTube's paused/branding overlays are ever visible.
- `playNext` / `playPrev` / `onEnded` honor (in order): active YouTube playlist → active user playlist → playback queue → trending auto-fill.
- `murmur://` deep links are registered in `Info.plist`'s `CFBundleURLTypes` (added by `build-app.sh`) and handled by `AppDelegate.application(_:open:)`.

## Notes

- Live streams require an internet connection.
- Closing the floating video window only hides it — audio keeps playing. Use the **Quit** button in the popover footer to fully exit.
- Drag from anywhere on the video to move the window.
- The app runs as `LSUIElement` (no Dock icon), so there's no app menu — Quit is in the popover.
- The `murmur://` URL scheme only works in the built `.app` (`swift run` doesn't load `Info.plist`).

## License

[MIT](LICENSE) — do whatever you like, just keep the copyright notice.
