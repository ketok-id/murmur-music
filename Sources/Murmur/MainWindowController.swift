import AppKit
import SwiftUI

/// Owns the main menu-bar window as an `NSHostingController`-backed
/// AppKit window. We host the main UI in AppKit (instead of a SwiftUI
/// `Window` scene) so we can launch in `.accessory` activation policy
/// from the start — once an app has ever been `.regular`, switching to
/// `.accessory` later leaves a stale Dock entry that doesn't clear.
/// SwiftUI's main-scene auto-presentation requires `.regular`, so the
/// only way to ship truly Dock-icon-free is to bypass auto-presentation
/// and surface the window from AppKit on demand.
final class MainWindowController: NSObject, NSWindowDelegate {
    private let window: NSWindow

    init(
        controller: PlayerController,
        videoWindow: VideoWindowController,
        mixer: MixerEngine,
        boothLauncher: BoothLauncher,
        recordingsLauncher: RecordingsLauncher
    ) {
        let host = NSHostingController(
            rootView: ContentView()
                .frame(width: 500, height: 370)
                .environmentObject(controller)
                .environmentObject(videoWindow)
                .environmentObject(mixer)
                .environmentObject(boothLauncher)
                .environmentObject(recordingsLauncher)
        )
        let win = NSWindow(contentViewController: host)
        win.title = "Murmur"
        win.styleMask = [.titled, .closable, .miniaturizable]
        win.setContentSize(NSSize(width: 500, height: 370))
        win.center()
        win.isReleasedWhenClosed = false
        self.window = win
        super.init()
        self.window.delegate = self
    }

    func show() {
        window.makeKeyAndOrderFront(nil)
        // `.accessory` apps aren't frontmost by default, so a status-item
        // click leaves the window behind whatever app currently has focus
        // unless we also activate.
        NSApp.activate(ignoringOtherApps: true)
    }

    func hide() {
        window.orderOut(nil)
    }

    // Audio must keep playing when the user closes the main window — hide
    // instead of destroying, same pattern as `VideoWindowController`.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        hide()
        return false
    }
}
