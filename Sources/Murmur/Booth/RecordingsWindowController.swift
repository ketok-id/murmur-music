import AppKit
import SwiftUI

/// Standalone NSWindow hosting `RecordingsView`.
final class RecordingsWindowController: NSObject, NSWindowDelegate {
    private let window: NSWindow
    let store: RecordingsStore
    let player: RecordingPlayer

    override init() {
        self.store = RecordingsStore()
        self.player = RecordingPlayer()
        let host = NSHostingController(
            rootView: RecordingsView(store: store, player: player)
        )
        let win = NSWindow(contentViewController: host)
        win.title = "Murmur Recordings"
        win.styleMask = [.titled, .closable, .resizable, .miniaturizable]
        win.setContentSize(NSSize(width: 540, height: 440))
        win.center()
        win.isReleasedWhenClosed = false
        self.window = win
        super.init()
        self.window.delegate = self
    }

    func show() {
        store.refresh()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func hide() {
        player.stop()
        window.orderOut(nil)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        hide()
        return false
    }
}
