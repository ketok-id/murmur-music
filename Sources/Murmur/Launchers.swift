import Combine
import SwiftUI

// MARK: - Notification names

extension Notification.Name {
    /// Safety hatch for tearing down any open SwiftUI sheet inside the
    /// menu-bar panel. Not posted by anyone in the current architecture
    /// (the system handles sheet teardown on dismiss when sheets are
    /// Window scenes), but `ContentView.onReceive` still listens —
    /// leaves a single notification post as the lever if a sheet ever
    /// gets stuck in a future regression.
    static let murmurDismissPopoverSheets = Notification.Name("murmur.dismissPopoverSheets")

    /// Posted by `AppDelegate.handleDeepLink` for `murmur://worldcup`.
    /// `ContentView` listens and opens the `world-cup` Window scene —
    /// AppDelegate can't call `openWindow(id:)` itself (no SwiftUI
    /// environment outside view bodies).
    static let murmurOpenWorldCup = Notification.Name("murmur.openWorldCup")
}

// MARK: - Booth launcher (SwiftUI bridge)
//
// Thin wrapper held by `AppDelegate.boothLauncher` because
// `BoothWindowController` has constructor dependencies (it needs a
// `MixerEngine`) — singleton .shared wouldn't fit cleanly. Used as an
// `@EnvironmentObject` so views can call `.show()` to summon the DJ
// booth window.
final class BoothLauncher: ObservableObject {
    let booth: BoothWindowController
    init(booth: BoothWindowController) { self.booth = booth }
    func show() { booth.show() }
}

// MARK: - Recordings launcher (SwiftUI bridge)

final class RecordingsLauncher: ObservableObject {
    let controller: RecordingsWindowController
    init(controller: RecordingsWindowController) { self.controller = controller }
    func show() { controller.show() }
}

// MARK: - YouTube search seed state
//
// Carries the `mode` and `query` the search Window should open with.
// The caller (`ContentView`) mutates `.shared` immediately before
// invoking `openWindow(id: "search")`, and the search view consumes +
// clears the seed inside `.onAppear`. We need this because the
// Window-scene API on macOS 13 takes no per-open value parameter —
// `WindowGroup(id:for:)` would let us pass a value directly but is
// macOS 14+ only.
final class YouTubeSearchState: ObservableObject {
    static let shared = YouTubeSearchState()
    @Published var mode: YouTubeSearchSheet.Mode = .videos
    @Published var query: String = ""
    private init() {}

    /// Drop the seed after the search view has read it. Subsequent
    /// `openWindow(id: "search")` calls without an explicit set land on
    /// default state (videos / empty) rather than replaying the last seed.
    func consume() {
        mode = .videos
        query = ""
    }
}
