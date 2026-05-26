# Ambient/ — data stores

This directory holds the project's persistent stores and the YouTube Data API client. Most files here are pure data, `.shared` singletons backed by `UserDefaults` (per the singleton rule in the root `CLAUDE.md`).

## UserDefaults keys in use

All keys are namespaced under `youtube-audio-widget.`. Bump the version suffix (`.v1` → `.v2`) when changing a schema rather than silently migrating — there is no migration layer.

| Key | Owner | Notes |
|---|---|---|
| `youtube-audio-widget.favorites.v1` | `FavoritesStore` (root) | Seeds "Lofi Girl" on first launch. |
| `youtube-audio-widget.userPlaylists.v1` | `UserPlaylistsStore` | Local named playlists. `activeID` / `activeIndex` persist via `didSet → save()` so relaunch resumes inside the same playlist at the same cursor. |
| `youtube-audio-widget.lastSession.v1` | `LastSessionStore` | Snapshots `currentVideoID` + `currentPlaylistID` on every video change. |
| `youtube-audio-widget.videoWindow.pinned` | `VideoWindowController` | Pin-to-all-Spaces toggle. Read before first window show. |

Other stores in this directory (`PlayedVideoHistoryStore`, `PlaylistStore`, `TrendingRegionStore`, `SearchHistoryStore`, `APIKeyStore`, `ChannelFavoritesStore`, `QuotaTracker`, `PlaybackQueue`) follow the same pattern — `.shared` singleton, UserDefaults-backed, key prefix `youtube-audio-widget.`.

**Exception: `LyricsStore`.** Singleton like the others, but the cache is **in-memory only** — no UserDefaults key. Lyrics text isn't worth the disk pressure; LRCLIB usually responds in <300ms and the same-session cache covers the only ergonomic case. Don't add a `.v1` key here without a good reason.

## Last-session restore contract (the order is load-bearing)

1. `PlayerController.init` **deliberately skips** the initial `loadPlayer` call. Don't add one — `AppDelegate` must install its Combine sinks first.
2. `AppDelegate.applicationDidFinishLaunching` finishes wiring (`historyCancellable`, `positionCancellable`, `userPlaylistCancellable`, `lastSessionCancellable`).
3. `restoreLastSession()` runs and prefers, in order:
   1. The active user playlist's cursor item.
   2. `LastSessionStore`'s `videoID` + `ytPlaylistID` (rebuilt into a `watch?v=…&list=…` URL so `PlaylistStore` enumerates the list normally).
   3. `kDefaultVideoID` from `PlayerController.swift`.
4. In-track playhead is restored separately by `loadPlayer` from `PlayedVideoHistoryStore.lastPosition`.

`UserPlaylistsStore.load()` guards against stale state (deleted playlist, index past the now-shorter item list) by dropping the cursor — `restoreLastSession` then falls through to `LastSessionStore`.

## User playlists vs YouTube playlists

- **`UserPlaylistsStore`** (this directory): local, named, never round-trips to YouTube. End-of-playlist behavior in `PlayerController.playNext` / `playPrev` / `onEnded` is **stop** — no fall-through to trending, since the curated set is the explicit contract.
- **`PlaylistStore`** (this directory): mirrors a YouTube `&list=…` URL via the Data API.
- A Combine sink in `AppDelegate` on `$currentVideoID` deactivates the user playlist whenever the playing video isn't in its items — that's how "user pasted a different URL" implicitly exits playlist mode.

## UpdateChecker

`UpdateChecker.swift` polls `https://api.github.com/repos/ketok-id/murmur-music/releases/latest` on launch + every 6 hours. Tag format is `v<dotted-version>` (e.g. `v2026.05.21.0`); the `v` is stripped before comparison. The dev binary (`swift run`) reports its version as `dev` and `hasUpdate` always returns false there.

It also records the release's `Murmur.zip` asset URL as `downloadURL`, which powers the in-app self-update.

See the "publish an update" sequence in the root `CLAUDE.md` for the release flow that produces a tag this checker can find. **The release must keep shipping the `Murmur.zip` asset** — the self-updater installs from the zip (not the DMG, which it can't unpack without mounting). `build-app.sh` produces both.

## SelfUpdater (in-app update)

`SelfUpdater.swift` performs the update the footer badge triggers via `UpdateChecker.downloadAndInstall()`. Flow: download `Murmur.zip` → `ditto -x -k` unpack → `xattr -dr com.apple.quarantine` (Murmur is ad-hoc signed, not notarized, so the fresh copy must be de-quarantined or Gatekeeper refuses it) → write a detached `/bin/sh` helper that **waits for this PID to exit, swaps the bundle in place with rollback, then `open`s it** → `NSApp.terminate`.

Non-obvious bits to preserve:
- **A running `.app` can't overwrite its own bundle** — that's why the swap is deferred to an orphaned shell that outlives termination (reparented to launchd). Don't try to do the `mv` from inside the app.
- **Preconditions guard before any disk change:** must be a real `.app` (not `swift run`), not Gatekeeper-translocated (`/AppTranslocation/` path → read-only), and the parent dir must be writable. Failures throw and leave the install untouched; `installState` surfaces the message and the badge falls back to opening the GitHub release page.
- `installState` (`idle` / `working` / `failed`) drives the badge: spinner while working, error+GitHub-fallback on failure.

## Lyrics

`LyricsStore.shared` fetches from [LRCLIB](https://lrclib.net/docs) — free, no API key, CC0-licensed community data. Driven by **two** Combine sinks in `AppDelegate`:

1. `lyricsVideoCancellable` on `controller.$currentVideoID` — fires when the track changes.
2. `lyricsCategoryCancellable` on `controller.$categoryHint` — fires when the title-derived category arrives (the title comes from the JS bridge after the videoID, so without this second sink we'd miss the music-classification for the very first track on launch).

Both sinks call `AppDelegate.refreshLyrics(forVideoID:hint:)`, which is a no-op (and clears the store) when `hint != .music`. This is the gate that hides the lyrics button for non-music videos.

`VideoCategoryHint.classify(categoryId: "", title:)` falls back to a title heuristic for music — the IFrame embed API never exposes categoryId, so `PlayerController` always passes empty. The heuristic looks for markers like "(Official Video/Audio/Lyrics)" or for an "Artist - Song" split via `TrackQuery.split`. Call sites with real Data API categoryIds (`YouTubeSearchAPI`, `YouTubeResultsView`) are unaffected — they pass non-empty categoryIds and the original `switch categoryId` path handles them.

**Don't pull lyrics from Genius/Musixmatch** without revisiting licensing — both restrict display in third-party clients. LRCLIB's data is CC0.

## Singleton vs `@EnvironmentObject` for this directory

Every store in `Ambient/` is a `.shared` singleton. None are injected as `@EnvironmentObject`. If you find yourself wanting to add a constructor argument to one of them, that's a signal it might not belong here — see the root `CLAUDE.md` table.
