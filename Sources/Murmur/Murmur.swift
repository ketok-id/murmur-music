import AppKit
import SwiftUI

// MARK: - SwiftUI app entry
//
// `@main App` + `@NSApplicationDelegateAdaptor` is Apple's documented
// SwiftUI-first pattern for a macOS app that still needs AppDelegate
// lifecycle hooks. Scene structure:
//
//   - The main menu-bar window is *not* a SwiftUI scene — it's an
//     AppKit `NSHostingController`-backed window owned by
//     `MainWindowController` and shown by `AppDelegate`. Doing it this
//     way lets the app launch in `.accessory` activation policy from
//     the start (no Dock icon, ever), which a SwiftUI main scene
//     cannot do — auto-presentation requires `.regular`, and once an
//     app is `.regular` the Dock entry sticks even after demoting.
//   - `Window` scenes for each former sheet (queue / playlist /
//     user-playlists / search / api-key). Opened on demand via
//     `@Environment(\.openWindow)` from `ContentView`. These are fine
//     under `.accessory` because they only ever open on explicit
//     user-triggered `openWindow(id:)` calls — they're never
//     auto-presented at launch.
//
// `AppDelegate` (loaded via the adaptor) owns the player + audio
// engine + lazy `MainWindowController` / `VideoWindowController` /
// `BoothWindowController` / `RecordingsWindowController`. It also
// creates the `NSStatusItem` menu-bar icon and handles `murmur://`
// deep links. See `AppDelegate.swift` for the activation-policy
// contract.
@main
struct MurmurApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate

    // Qualified to `SwiftUI.Scene` because the project ships its own
    // `struct Scene` (`Sources/Murmur/Scenes/Scene.swift`, a DJ booth
    // scene preset) which would otherwise shadow the SwiftUI protocol
    // at this call site.
    var body: some SwiftUI.Scene {
        // Auxiliary sheets — each opens as its own NSWindow via
        // `openWindow(id:)`. Close-button dismissal here goes to the
        // sheet's own window (not the main panel) because each is a
        // separate scene. `.windowResizability(.contentSize)` makes
        // the window adopt the SwiftUI view's intrinsic `.frame(...)`
        // instead of macOS's default 800×600.
        //
        // The first `Window` scene auto-opens at launch (even under
        // `.accessory` policy on macOS 13+); `AppDelegate` closes that
        // auto-opened auxiliary window in `finishLaunchSetup` so only
        // the AppKit-hosted main window is visible at boot. The user's
        // explicit `openWindow(id:)` calls from `ContentView` reopen
        // closed scenes normally — `Window` is single-instance.
        Window("Queue", id: "queue") {
            QueueSheet()
                .environmentObject(delegate.controller)
        }
        .windowResizability(.contentSize)

        Window("Now Playing Playlist", id: "playlist") {
            PlaylistSheet()
                .environmentObject(delegate.controller)
        }
        .windowResizability(.contentSize)

        Window("My Playlists", id: "user-playlists") {
            UserPlaylistsSheet()
                .environmentObject(delegate.controller)
        }
        .windowResizability(.contentSize)

        Window("Search YouTube", id: "search") {
            YouTubeSearchSheet()
                .environmentObject(delegate.controller)
        }
        .windowResizability(.contentSize)

        Window("API Key", id: "api-key") {
            APIKeySetupSheet()
        }
        .windowResizability(.contentSize)
    }
}
