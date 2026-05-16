# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Murmur is a single-binary macOS menu-bar app (Swift + SwiftUI + WKWebView) that plays YouTube audio in the background, with an optional chromeless floating video window. macOS 13+, Swift 5.9+, no external dependencies — `Package.swift` declares only the `Murmur` executable target rooted at `Sources/Murmur`.

## Commands

- **Run locally:** `swift run -c release` (debug builds work but `-c release` is what the README documents and what build-app.sh ships).
- **Build a shareable `.app` + zip:** `./build-app.sh` (writes to `dist/`). Flags: `--sign` for ad-hoc codesign, `--open` to reveal in Finder.
- **Regenerate the app icon:** `swift make-icon.swift` rewrites `icon.png` from the in-app palette; rerun `./build-app.sh` to rebake `AppIcon.icns` into the bundle.
- **Regenerate social card:** `swift make-social-card.swift` overwrites `social-preview.png`.

There is **no test target** and no linter configured — `Package.swift` only defines the executable. Don't invent `swift test` instructions.

## Architecture (the pieces that span files)

The non-obvious design decisions live across `main.swift` and `VideoWindowController`/`PlayerController`. Read these together before changing playback or window behavior:

- **The WKWebView must always live inside a real on-screen-eligible NSWindow.** WebKit suspends media playback on 0×0 / detached views, so `VideoWindowController` keeps the window alive at all times — when the user wants "audio only" it's parked at `(-3000, -3000)` with a `.borderless` styleMask. Toggling video on swaps the styleMask to `[.titled, .closable, .resizable, .fullSizeContentView]` and lifts to `.floating`. Don't "destroy and recreate" the webview on toggle — you'll kill audio.
- **Window dragging is layered.** `WindowDragOverlay` is a transparent `NSView` on top of the WKWebView that calls `window.performDrag(with:)` in `mouseDown`. WKWebView swallows mouseDown before AppKit checks `isMovableByWindowBackground`, so that flag alone is unreliable — both mechanisms are kept on purpose.
- **YouTube embed is iframe + postMessage, not the JS `YT.Player` constructor.** `PlayerController.loadPlayer` builds an HTML page that hosts a `youtube-nocookie.com/embed/<id>` iframe and talks to it via the IFrame API's `postMessage` / `listening` handshake. Swift→JS goes through `evaluateJavaScript("window.ytCmd(...)")`; JS→Swift goes through `webkit.messageHandlers.cb.postMessage` (handled by `ScriptHandler`). Using `YT.Player` inside `loadHTMLString` runs into origin/baseURL issues — don't switch to it.
- **Two layers of "loading mask" hide YouTube branding flashes.** A Swift-side opaque NSView (`VideoWindowController.loadingMask`, fired from `controller.onWillLoadStream` → `flashLoadingMask()`) covers the webview during reload, and an in-page `#cover` div covers the iframe until the first `playerState === 1` event. Keep both — each catches a different flash (Swift-side: WKWebView reload; JS-side: YouTube's startup branding overlay).
- **Iframe pointer events are disabled** (`iframe { pointer-events: none }`) so YouTube's title/share/Watch-on-YouTube hover overlays never appear. All controls come from Swift; the iframe is never meant to be clicked.
- **`navigationDelegate.didFinish` has a 1.5s "force-ready" fallback.** Some live streams never fire `onReady` through the IFrame API channel handshake. After 1.5s `isReady` is forced true so the user can hit play manually. If you change autoplay logic, preserve this fallback.
- **`applicationShouldTerminateAfterLastWindowClosed → false`** and the close button is intercepted in `windowShouldClose` (hides instead of closing). The popover and floating video window are NSWindows; closing them must not quit the app — only the popover's "Quit" button calls `NSApp.terminate`.

## State and persistence

- **Favorites** persist via `UserDefaults` under key `youtube-audio-widget.favorites.v1` (`FavoritesStore` in main.swift). On first launch a single seed favorite ("Lofi Girl") is written. If you change the schema, bump the key suffix.
- **Discover catalog** is hard-coded in `ContentView.swift` (`Self.catalog`). Adding categories/items there is the documented extension point. Stream IDs go stale when channels restart — that's expected.
- **Default video ID** is `kDefaultVideoID` at the top of `main.swift`. `ContentView`'s "Featured → Claude FM" entry references the same constant; keep them tied.

## App lifecycle / packaging

- Runs as `LSUIElement` (no Dock icon) — set both via `Info.plist` in build-app.sh and `app.setActivationPolicy(.accessory)` in `main.swift`. Both are needed.
- The popover is `.transient` and closes on outside click; the floating video window is independent and stays visible.
- `build-app.sh` produces an unsigned (or ad-hoc-signed) bundle. Recipients hit Gatekeeper on first launch — README documents the right-click → Open workaround and the `xattr -dr com.apple.quarantine` fallback.

## Things to leave alone unless explicitly asked

- The `[.titled, .closable, .resizable, .fullSizeContentView]` styleMask combo plus hidden window buttons is what produces the "chromeless" look while keeping resize/drag working. Simpler combos (`.borderless` alone, or omitting `fullSizeContentView`) lose either resize or drag.
- `webView.setValue(false, forKey: "drawsBackground")` is required so the page background (`#0d0d12`) shows through instead of WKWebView's default white flash.
- The `youtube-nocookie.com` origin is intentional (no third-party cookies, fewer overlays). Don't switch to `youtube.com`.
