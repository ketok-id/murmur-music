import AppKit
import Combine
import SwiftUI

// MARK: - App delegate (player + audio setup; menu-bar UI lives in `MurmurApp` Scene)
//
// ╔══════════════════════════════════════════════════════════════════════╗
// ║  READ BEFORE TOUCHING ACTIVATION POLICY / LAUNCH ORDER               ║
// ║                                                                      ║
// ║  Murmur is a menu-bar app with an AppKit-hosted main window. The     ║
// ║  user contract is: **no Dock icon, ever.**                          ║
// ║                                                                      ║
// ║  Mechanism:                                                          ║
// ║    1. `applicationWillFinishLaunching` sets `.accessory` — the      ║
// ║       earliest delegate hook, runs before AppKit registers with     ║
// ║       the Dock manager. `Info.plist` also carries                   ║
// ║       `LSUIElement=true` so the bundled app launches `.accessory`   ║
// ║       from process start; the code path covers the `swift run`     ║
// ║       dev binary where Info.plist isn't read.                       ║
// ║    2. `applicationDidFinishLaunching` finishes wiring + force-      ║
// ║       creates `mainWindow: MainWindowController` and calls          ║
// ║       `mainWindow.show()`. The main window is an AppKit             ║
// ║       `NSHostingController` host — not a SwiftUI `Window` scene —   ║
// ║       because SwiftUI main-scene auto-presentation requires         ║
// ║       `.regular` policy, and once an app has ever been `.regular`   ║
// ║       the Dock entry sticks even after demoting to `.accessory`.    ║
// ║                                                                     ║
// ║  Things that break this:                                            ║
// ║    - Setting `.regular` anywhere on the launch path  → permanent    ║
// ║      Dock entry. Switching back to `.accessory` doesn't clear it.   ║
// ║    - Adding a SwiftUI `Window`/`WindowGroup` main scene with a      ║
// ║      visible body  → SwiftUI auto-presents it (which only works     ║
// ║      in `.regular`, breaking the no-Dock contract) or duplicates    ║
// ║      the AppKit window.                                             ║
// ║    - Removing the saved-state directory wipe below  → macOS's       ║
// ║      "Resume" feature can restore a stale window position from a    ║
// ║      previous run and visually replace `MainWindowController`'s     ║
// ║      centered first frame.                                          ║
// ║    - Reintroducing `MenuBarExtra`  → reintroduces the popover/menu  ║
// ║      UX the user rejected.                                          ║
// ║                                                                      ║
// ║  If you need to refactor here, run the app FROM A COLD LAUNCH       ║
// ║  on a fresh machine state and check the Dock at t=0/2/5s. The      ║
// ║  Dock manager keeps stale entries for the lifetime of the          ║
// ║  process — there is no "remove" call.                              ║
// ╚══════════════════════════════════════════════════════════════════════╝
final class AppDelegate: NSObject, NSApplicationDelegate {
    let controller = PlayerController()
    let mixer = MixerEngine()
    /// AppKit menu-bar icon. Owned by `AppDelegate` rather than declared
    /// as a SwiftUI `MenuBarExtra` because we need the click action to
    /// directly open the main `Window` scene (single click, no popover
    /// panel in between) — `MenuBarExtra` only supports `.window` /
    /// `.menu` styles, neither of which is "click = action".
    private var statusItem: NSStatusItem!

    // Lazy so they initialize on first access — happens in
    // `applicationDidFinishLaunching` below where we force-touch them.
    // By the time SwiftUI evaluates the `MurmurApp` scene body, these
    // are guaranteed non-nil. `lazy var` over `var ...!` so reading
    // before init won't crash; over `let` in property init so we can
    // reference `self.controller` / `self.mixer`.
    lazy var videoWindow: VideoWindowController = VideoWindowController(controller: controller)
    lazy var booth: BoothWindowController = BoothWindowController(mixer: mixer)
    lazy var recordings: RecordingsWindowController = RecordingsWindowController()
    lazy var boothLauncher: BoothLauncher = BoothLauncher(booth: booth)
    lazy var recordingsLauncher: RecordingsLauncher = RecordingsLauncher(controller: recordings)
    lazy var mainWindow: MainWindowController = MainWindowController(
        controller: controller,
        videoWindow: videoWindow,
        mixer: mixer,
        boothLauncher: boothLauncher,
        recordingsLauncher: recordingsLauncher
    )

    private var historyCancellable: AnyCancellable?
    private var positionCancellable: AnyCancellable?
    private var userPlaylistCancellable: AnyCancellable?
    private var lastSessionCancellable: AnyCancellable?
    private var lyricsVideoCancellable: AnyCancellable?
    private var lyricsCategoryCancellable: AnyCancellable?

    /// Demote to `.accessory` *before* AppKit registers with the Dock
    /// manager — `applicationWillFinishLaunching` is the earliest
    /// delegate hook and runs before AppKit reads the default
    /// activation policy. For the bundled app `LSUIElement=true` in
    /// `Info.plist` already does this; this call covers the `swift run`
    /// dev binary (no Info.plist), where without it the binary would
    /// boot in `.regular` and leave a permanent Dock entry that
    /// switching to `.accessory` later does not clear.
    func applicationWillFinishLaunching(_ n: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }

    func applicationDidFinishLaunching(_ n: Notification) {
        // 0) Install a minimal main menu. Even with `.accessory` policy
        //    (no menu bar visible), an installed `NSApp.mainMenu` is
        //    what routes standard edit shortcuts — Cmd+C/V/X/A/Z —
        //    through the responder chain to the focused `NSTextField`.
        //    Without this the URL field and the search field can't be
        //    pasted into.
        installMainMenu()

        // Disable macOS state restoration for windows. See the
        // top-of-file READ BEFORE TOUCHING block.
        UserDefaults.standard.set(false, forKey: "NSQuitAlwaysKeepsWindows")
        if let bundleID = Bundle.main.bundleIdentifier {
            let savedState = NSHomeDirectory() + "/Library/Saved Application State/\(bundleID).savedState"
            try? FileManager.default.removeItem(atPath: savedState)
        }

        // Activation policy is already `.accessory` (set in
        // `applicationWillFinishLaunching`). Heavy launch work runs
        // immediately — there is no SwiftUI main-scene auto-presentation
        // to wait on, since the main window is now AppKit-hosted by
        // `MainWindowController` and shown explicitly at the end of this
        // method.
        finishLaunchSetup()
    }

    private func finishLaunchSetup() {
        // 1) Force-init the lazy windows so SwiftUI scene bodies that
        //    read `delegate.videoWindow` / `boothLauncher` /
        //    `recordingsLauncher` as env objects see them ready when an
        //    auxiliary Window scene is opened from `ContentView`.
        _ = videoWindow
        _ = booth
        _ = recordings

        // 2) Menu-bar icon. Persistent re-entry point after the user
        //    closes the main window — click reopens it via the captured
        //    `WindowOpenerBridge.shared.openMain` closure.
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            let img = NSImage(systemSymbolName: "music.note", accessibilityDescription: "Murmur")
            img?.isTemplate = true
            button.image = img
            button.action = #selector(statusItemClicked(_:))
            button.target = self
        }

        // Mask the webview during a stream switch so YouTube's loading
        // overlay / brief flash of the previous stream never shows in
        // the visible video window.
        controller.onWillLoadStream = { [weak self] in
            self?.videoWindow.flashLoadingMask()
        }

        // Start the DJ mixer engine.
        do {
            try mixer.start()
        } catch {
            NSLog("MixerEngine failed to start: \(error)")
        }

        // Kick off the GitHub Releases update poller. Best-effort,
        // silent on failure; surfaces a badge in the panel footer when
        // a newer tag is found.
        UpdateChecker.shared.startBackgroundChecks()

        // Record videos to history as their titles arrive.
        historyCancellable = controller.$title
            .removeDuplicates()
            .sink { [weak self] title in
                guard let self = self else { return }
                let trimmedTitle = title.trimmingCharacters(in: .whitespaces)
                let videoID = self.controller.currentVideoID
                guard !trimmedTitle.isEmpty,
                      trimmedTitle != "Loading…",
                      trimmedTitle != "YouTube Live Stream",
                      !videoID.isEmpty else { return }
                PlayedVideoHistoryStore.shared.record(videoID: videoID, title: trimmedTitle)
            }

        // Throttle position writes to ~5s so we don't hammer UserDefaults.
        positionCancellable = controller.$currentTime
            .throttle(for: .seconds(5), scheduler: DispatchQueue.main, latest: true)
            .sink { [weak self] seconds in
                guard let self = self else { return }
                let videoID = self.controller.currentVideoID
                guard !videoID.isEmpty, seconds > 1 else { return }
                PlayedVideoHistoryStore.shared.updatePosition(videoID: videoID, seconds: seconds)
            }

        // Note: `userPlaylistCancellable` and `lastSessionCancellable`
        // are installed AFTER `restoreLastSession()` below. `@Published`'s
        // publisher replays the current value on subscribe, and at this
        // point `currentVideoID` is still `kDefaultVideoID` — installing
        // those sinks here would (a) reconcile the just-loaded active
        // user playlist against `kDefaultVideoID` and deactivate it, and
        // (b) overwrite the saved `LastSessionStore.videoID` with the
        // default before we ever read it.

        // Auto-advance when a track ends. Priority: active user playlist
        // (stops at end — no fall-through), then queue, then trending
        // refill. YouTube playlists handle their own internal
        // auto-advance inside the iframe so they don't appear here.
        controller.onEnded = { [weak self] in
            guard let self = self else { return }
            if UserPlaylistsStore.shared.hasActivePlaylist {
                if let next = UserPlaylistsStore.shared.nextItem() {
                    _ = self.controller.load(input: next.videoID)
                }
                return
            }
            if let next = PlaybackQueue.shared.popNext() {
                _ = self.controller.load(input: next.videoID)
                return
            }
            guard TrendingRegionStore.shared.autoFillFromTrending else { return }
            let finishedID = self.controller.currentVideoID
            Task { @MainActor in
                await PlaybackQueue.shared.refillFromTrending(excluding: finishedID)
                if let next = PlaybackQueue.shared.popNext() {
                    _ = self.controller.load(input: next.videoID)
                }
            }
        }

        // Resume the last session. Priority: an active user playlist
        // (its cursor item wins), then `LastSessionStore` (last single
        // video + YouTube playlist context), then the hard-coded
        // default. Both stores already loaded from UserDefaults at
        // singleton init. The in-track playhead is restored downstream
        // inside `loadPlayer` from `PlayedVideoHistoryStore.lastPosition`.
        restoreLastSession()

        // NOW it's safe to install sinks that depend on `currentVideoID`.
        // Their immediate replay fires with the restored videoID, so:
        //   - `userPlaylistCancellable` reconciles against the restored
        //     value (no-op when the active playlist already contains it).
        //   - `lastSessionCancellable` writes back the same videoID it
        //     just read (guarded as a no-op inside `LastSessionStore.update`).
        userPlaylistCancellable = controller.$currentVideoID
            .removeDuplicates()
            .sink { videoID in
                UserPlaylistsStore.shared.reconcile(currentVideoID: videoID)
            }
        lastSessionCancellable = controller.$currentVideoID
            .removeDuplicates()
            .sink { [weak self] videoID in
                guard let self = self else { return }
                LastSessionStore.shared.update(
                    videoID: videoID,
                    ytPlaylistID: self.controller.currentPlaylistID
                )
            }

        // Drive LyricsStore from videoID + categoryHint. Two separate
        // sinks because the title (and so the category) often arrives
        // after the videoID changes — the second sink catches that.
        lyricsVideoCancellable = controller.$currentVideoID
            .removeDuplicates()
            .sink { [weak self] videoID in
                guard let self = self else { return }
                Task { @MainActor in
                    self.refreshLyrics(forVideoID: videoID,
                                       hint: self.controller.categoryHint)
                }
            }
        lyricsCategoryCancellable = controller.$categoryHint
            .removeDuplicates()
            .sink { [weak self] hint in
                guard let self = self else { return }
                Task { @MainActor in
                    self.refreshLyrics(forVideoID: self.controller.currentVideoID,
                                       hint: hint)
                }
            }

        // Surface the main window now that the launch contract is wired.
        mainWindow.show()

        // SwiftUI auto-presents the first declared `Window` scene at
        // launch — under `.accessory` policy, on macOS 13+, this still
        // happens. That scene here is the Queue sheet. Close any
        // SwiftUI-managed auxiliary window so only the AppKit-hosted
        // main window is visible at boot. They reopen normally on
        // `openWindow(id:)` because `Window` scenes are single-instance.
        DispatchQueue.main.async {
            let auxIDs = ["queue", "playlist", "user-playlists", "search", "api-key", "lyrics"]
            for window in NSApp.windows {
                guard let id = window.identifier?.rawValue else { continue }
                if auxIDs.contains(where: id.contains), window.isVisible {
                    window.close()
                }
            }
        }
    }

    private func restoreLastSession() {
        let upStore = UserPlaylistsStore.shared
        if let p = upStore.activePlaylist,
           let idx = upStore.activeIndex,
           idx >= 0, idx < p.items.count {
            _ = controller.load(input: p.items[idx].videoID)
            return
        }
        let session = LastSessionStore.shared
        if !session.videoID.isEmpty {
            let input: String
            if !session.ytPlaylistID.isEmpty {
                input = "https://www.youtube.com/watch?v=\(session.videoID)&list=\(session.ytPlaylistID)"
            } else {
                input = session.videoID
            }
            _ = controller.load(input: input)
            return
        }
        _ = controller.load(input: kDefaultVideoID)
    }

    /// Install a minimal main menu. The Edit submenu (Cut/Copy/Paste/
    /// Select All/Undo/Redo) is what routes Cmd+V to the focused text
    /// field. With `.accessory` policy we have no visible menu bar, but
    /// `NSApp.mainMenu` is still consulted by the responder chain when
    /// shortcuts are pressed.
    private func installMainMenu() {
        let mainMenu = NSMenu()

        // App menu — required for `Quit` to wire up cleanly. The first
        // item in a main menu is always the application menu (its title
        // is replaced by AppKit with the app's process name).
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit Murmur",
                        action: #selector(NSApplication.terminate(_:)),
                        keyEquivalent: "q")
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        // Edit menu — enables Cmd+V routing into the focused responder.
        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo",
                         action: Selector(("undo:")),
                         keyEquivalent: "z")
        let redo = NSMenuItem(title: "Redo",
                              action: Selector(("redo:")),
                              keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(redo)
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(withTitle: "Cut",
                         action: #selector(NSText.cut(_:)),
                         keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy",
                         action: #selector(NSText.copy(_:)),
                         keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste",
                         action: #selector(NSText.paste(_:)),
                         keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All",
                         action: #selector(NSText.selectAll(_:)),
                         keyEquivalent: "a")
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        NSApp.mainMenu = mainMenu
    }

    /// Handle `murmur://` deep links registered in `Info.plist`'s
    /// `CFBundleURLTypes`. Format:
    /// `murmur://play?v=<videoID>[&list=<playlistID>][&t=<seconds>]`
    /// Loads the video into the running app's player.
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls { handleDeepLink(url) }
    }

    private func handleDeepLink(_ url: URL) {
        guard url.scheme?.lowercased() == "murmur" else { return }
        guard let comp = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return }
        // Accept both murmur://play?v=… and murmur://?v=… for compatibility.
        let action = (comp.host ?? "").lowercased()
        guard action.isEmpty || action == "play" else { return }
        let q = comp.queryItems ?? []
        guard let v = q.first(where: { $0.name == "v" })?.value, !v.isEmpty else { return }
        // Validate at the trust boundary — `murmur://` is the one path where
        // an external attacker (any webpage) can hand us URL fragments.
        // Reject anything that doesn't match YouTube's strict ID shapes
        // before reconstructing a URL for `controller.load`.
        guard let validVideoID = PlayerController.extractYouTubeID(v) else { return }
        let listRaw = q.first(where: { $0.name == "list" })?.value ?? ""
        // Empty list is fine; non-empty must validate as a playlist ID.
        var validList = ""
        if !listRaw.isEmpty {
            guard let id = PlayerController.extractPlaylistID(
                "https://www.youtube.com/watch?v=\(validVideoID)&list=\(listRaw)"
            ) else { return }
            validList = id
        }
        // Reuse `controller.load` so the same parse / clear-other-playlist /
        // history / queue plumbing runs as any other load path.
        let input: String
        if !validList.isEmpty {
            input = "https://www.youtube.com/watch?v=\(validVideoID)&list=\(validList)"
        } else {
            input = validVideoID
        }
        _ = controller.load(input: input)
    }

    /// Menu-bar icon click action. Brings the AppKit-hosted main window
    /// forward; `MainWindowController.show` is idempotent so repeat
    /// clicks just re-key/order-front the existing window.
    @objc func statusItemClicked(_ sender: AnyObject?) {
        mainWindow.show()
    }

    func applicationWillTerminate(_ n: Notification) {
        mixer.graph.stop()
    }

    // Audio must keep playing when the main window closes.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    @MainActor
    private func refreshLyrics(forVideoID videoID: String, hint: VideoCategoryHint) {
        guard hint == .music else {
            LyricsStore.shared.clear()
            return
        }
        guard !videoID.isEmpty else { return }
        LyricsStore.shared.fetch(
            videoID: videoID,
            title: controller.title,
            duration: controller.duration
        )
    }
}
