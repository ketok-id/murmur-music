# AGENTS.md

Guidance for non-Claude coding agents (Codex, Cursor, Aider, etc.) working in this repository. Claude Code reads `CLAUDE.md` directly; this file is the equivalent brief for everyone else. **`CLAUDE.md` is the source of truth** — when the two drift, `CLAUDE.md` wins, and this file should be re-synced.

## Project

Murmur is a single-binary macOS menu-bar app (Swift + SwiftUI + WKWebView) that plays YouTube audio in the background, with an optional chromeless floating video window. macOS 13+, Swift 5.9+, no external dependencies — `Package.swift` declares only the `Murmur` executable target rooted at `Sources/Murmur`.

## Commands

- **Run locally:** `swift run -c release` (debug builds work but `-c release` is what the README documents and what build-app.sh ships).
- **Build a shareable `.app` + zip:** `./build-app.sh` (writes to `dist/`). Flags: `--sign` for ad-hoc codesign, `--open` to reveal in Finder.
- **Regenerate the app icon:** `swift make-icon.swift` rewrites `icon.png` from the in-app palette; rerun `./build-app.sh` to rebake `AppIcon.icns` into the bundle.
- **Regenerate social card:** `swift make-social-card.swift` overwrites `social-preview.png`.
- **Cut a release:** see the "publish an update" sequence in `CLAUDE.md` (bump `VERSION` in `build-app.sh` → build → commit → tag `v<VERSION>` → `gh release create … --latest`). The `v` prefix on the tag is required; `UpdateChecker` strips it before comparing to `CFBundleShortVersionString`.

There is **no test target** and no linter configured — `Package.swift` only defines the executable. Don't invent `swift test` instructions.

## File map (top-level under `Sources/Murmur/`)

| File | Owns |
|---|---|
| `Murmur.swift` | `@main MurmurApp: App` + `MainWindowView` wrapper. Tiny — just the SwiftUI scene structure and the activation-policy demote. |
| `AppDelegate.swift` | `AppDelegate` — player setup, audio engine start, Combine sinks, `NSStatusItem`, deep-link handler, activation-policy launch contract. |
| `PlayerController.swift` | `PlayerController` + `ScriptHandler` + `kDefaultVideoID`. The WKWebView ↔ JS bridge. |
| `VideoWindowController.swift` | `VideoWindowController` + `HoverTrackingView` + `WindowDragOverlay`. The floating chromeless video window. |
| `FavoritesStore.swift` | `FavoritesStore` singleton + `Favorite` struct. |
| `Launchers.swift` | `BoothLauncher` / `RecordingsLauncher` (env objects), `WindowOpenerBridge` / `YouTubeSearchState` (singletons), `.murmurDismissPopoverSheets` notification. |
| `ContentView.swift` | The main panel UI + the Discover catalog. |
| `MarqueeText.swift`, `PixelDancer.swift`, `VideoControlsHUD.swift`, `YouTubeSearchSheet.swift` | UI components. |

Sub-directories: `Ambient/` (data stores), `Booth/` (DJ booth + sheet views), `Audio/`, `Mood/`, `Recordings/`, `Scenes/`, `Decks/`, `Analysis/`.

**There is no `main.swift`.** Naming the entry file `main.swift` would force top-level-code parsing, which is incompatible with `@main` on an `App` struct. Don't rename `Murmur.swift` back.

## Architecture (the pieces that span files)

Read these together before changing playback or window behavior:

- **The WKWebView must always live inside a real on-screen-eligible NSWindow.** WebKit suspends media playback on 0×0 / detached views, so `VideoWindowController` keeps the window alive at all times — when the user wants "audio only" it's parked at `(-3000, -3000)` with a `.borderless` styleMask. Toggling video on swaps the styleMask to `[.titled, .closable, .resizable, .fullSizeContentView]` and lifts to `.floating`. Don't "destroy and recreate" the webview on toggle — you'll kill audio.
- **Pin-to-all-Spaces is a separate axis from window visibility.** `VideoWindowController.isPinned` (persisted under `youtube-audio-widget.videoWindow.pinned`) toggles `collectionBehavior` between `[.fullScreenAuxiliary]` and `[.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]`. Spaces, not physical displays — moving across monitors still needs a manual drag.
- **Window dragging is layered.** `WindowDragOverlay` is a transparent `NSView` on top of the WKWebView that calls `window.performDrag(with:)` in `mouseDown`. WKWebView swallows mouseDown before AppKit checks `isMovableByWindowBackground`, so both mechanisms are kept on purpose.
- **YouTube embed is iframe + postMessage, not the JS `YT.Player` constructor.** `PlayerController.loadPlayer` builds an HTML page that hosts a `youtube-nocookie.com/embed/<id>` iframe and talks to it via the IFrame API's `postMessage` / `listening` handshake. Swift→JS goes through `evaluateJavaScript("window.ytCmd(...)")`; JS→Swift goes through `webkit.messageHandlers.cb.postMessage` (handled by `ScriptHandler`). Don't switch to `YT.Player` — origin/baseURL issues with `loadHTMLString`.
- **Two layers of "loading mask" hide YouTube branding flashes.** A Swift-side opaque NSView (`VideoWindowController.loadingMask`) covers the webview during reload, and an in-page `#cover` div covers the iframe whenever the player isn't actively Playing (states ≠ 1, except Buffering). Keep both layers — each catches a different flash. Don't remove the cover from the DOM after first fade; it also masks YouTube's paused-state overlay.
- **Iframe pointer events are disabled** (`iframe { pointer-events: none }`) so YouTube's title/share/Watch-on-YouTube hover overlays never appear. All controls come from Swift.
- **`navigationDelegate.didFinish` has a 1.5s "force-ready" fallback** for live streams that never fire `onReady`. Preserve this fallback if you change autoplay logic.
- **`applicationShouldTerminateAfterLastWindowClosed → false`** and the close button is intercepted in `windowShouldClose` (hides instead of closing). Only the panel's "Quit" button calls `NSApp.terminate`.
- **Menu-bar icon is AppKit `NSStatusItem` (in `AppDelegate`), not SwiftUI `MenuBarExtra`.** `MenuBarExtra(.window)` and `.menu` were both tried and neither matches "click icon → main window opens, period." `NSStatusItem.button.action = #selector(statusItemClicked(_:))` gives a true single-click handler that calls `NSApp.activate(ignoringOtherApps: true)` then `WindowOpenerBridge.shared.openMain?()`. The bridge is a tiny singleton holding a captured `openWindow` closure, populated on `MainWindowView`'s `.onAppear` (since `@Environment(\.openWindow)` only exists inside SwiftUI view bodies). **Don't reintroduce `MenuBarExtra`.**
- **`AppDelegate` is attached via `@NSApplicationDelegateAdaptor` (`Murmur.swift`).** Owns `PlayerController`, `MixerEngine`, and the lazy `VideoWindowController` / `BoothWindowController` / `RecordingsWindowController`. The video / booth / recordings windows are `lazy var` and force-touched inside `applicationDidFinishLaunching` (`_ = videoWindow; _ = booth; _ = recordings`) so they're guaranteed initialized before SwiftUI evaluates the scene body.
- **`var body: some SwiftUI.Scene` is fully qualified.** `Sources/Murmur/Scenes/Scene.swift` ships its own `struct Scene` (DJ booth preset model) which shadows SwiftUI's `Scene` protocol at the call site. Don't drop the `SwiftUI.` qualifier.
- **Main UI is a `WindowGroup`; app ends up menu-bar-only via a `.regular → .accessory` activation-policy dance at launch.** SwiftUI's auto-presentation requires `.regular` at launch, but the user wants no Dock icon. So `AppDelegate.applicationDidFinishLaunching` sets `.regular`, SwiftUI auto-opens the WindowGroup, and `MainWindowView.onAppear` immediately demotes to `.accessory`. **`Info.plist` must NOT carry `LSUIElement = true`** — that forces `.accessory` at launch and SwiftUI skips the auto-open.
- **Auxiliary sheets are `Window` scenes, not `.sheet(isPresented:)` modifiers.** Queue, playlist, my-playlists, search, API-key are top-level `Window` scenes opened via `openWindow(id:)`. This fixes the close-button-closes-the-app bug and enables side-by-side layout. Sheets read `@EnvironmentObject var controller: PlayerController` and call `controller.load(input:)` themselves before `dismiss()`. Search's seed mode + query come from `YouTubeSearchState.shared`.

## State and persistence

See `Sources/Murmur/Ambient/CLAUDE.md` for the per-store UserDefaults keys and the last-session restore contract. Highlights:

- Favorites under `youtube-audio-widget.favorites.v1` — bump the suffix if the schema changes.
- User-composed playlists under `youtube-audio-widget.userPlaylists.v1`. Distinct from `PlaylistStore` (mirrors a YouTube `&list=…`). `activeID` / `activeIndex` persist via `didSet → save()`.
- Last-session resume: `LastSessionStore` snapshots `currentVideoID` + `currentPlaylistID` on every video change. On launch, `PlayerController.init` deliberately skips the initial `loadPlayer`; `AppDelegate.restoreLastSession()` runs after Combine sinks are installed.
- Discover catalog is hard-coded in `ContentView.swift` (`Self.catalog`). Stream IDs go stale — that's expected.
- Default video ID is `kDefaultVideoID` at the top of `PlayerController.swift`. The "Featured → Claude FM" entry references it; keep them tied.

## App lifecycle / packaging

- Runs as `LSUIElement` (no Dock icon) — set both via `Info.plist` in `build-app.sh` *and* `NSApp.setActivationPolicy(.accessory)` inside `AppDelegate`. The bundled app reads `Info.plist`; `swift run` doesn't, so the explicit call covers the dev-binary case. Both are needed.
- **`murmur://` URL scheme** registered in `Info.plist`'s `CFBundleURLTypes` (added by `build-app.sh`) and handled by `AppDelegate.application(_:open:)`. Format: `murmur://play?v=<videoID>[&list=<playlistID>]`. URL handling only works in the built `.app` — `swift run` doesn't load Info.plist.
- The menu-bar window closes-to-hide; the floating video window is independent and stays visible.
- `build-app.sh` produces an unsigned (or ad-hoc-signed) bundle. README documents the Gatekeeper workaround.
- **Update notifications** come from `UpdateChecker` (`Ambient/UpdateChecker.swift`), polling `https://api.github.com/repos/ketok-id/murmur-music/releases/latest` on launch + every 6h. The `v` prefix on tags is required (e.g. `v2026.05.21.0`); the numeric body must match `VERSION` in `build-app.sh`. The dev binary reports version `dev` and `hasUpdate` is always false there.

## Things to leave alone unless explicitly asked

- The `[.titled, .closable, .resizable, .fullSizeContentView]` styleMask combo plus hidden window buttons is what produces the "chromeless" look while keeping resize/drag working.
- `webView.setValue(false, forKey: "drawsBackground")` is required so the page background (`#0d0d12`) shows through instead of WKWebView's default white flash.
- The `youtube-nocookie.com` origin is intentional (no third-party cookies, fewer overlays). Don't switch to `youtube.com`.
