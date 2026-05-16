import AppKit
import SwiftUI

/// Hosts the SwiftUI BoothView in an independent NSWindow.
///
/// Lifecycle mirrors `VideoWindowController`: the window is created once and
/// kept alive for the lifetime of the app. Closing hides it rather than
/// terminating it — same `windowShouldClose → hide` pattern.
final class BoothWindowController: NSObject, NSWindowDelegate {
    private let window: NSWindow
    private let mixer: MixerEngine

    init(mixer: MixerEngine) {
        self.mixer = mixer
        let host = NSHostingController(
            rootView: BoothView(
                mixer: mixer,
                deck1State: mixer.deck1.state,
                deck2State: mixer.deck2.state
            )
        )
        let win = NSWindow(contentViewController: host)
        win.title = "Pocket DJ"
        win.styleMask = [.titled, .closable, .resizable, .miniaturizable]
        win.setContentSize(NSSize(width: 1100, height: 780))
        win.contentMinSize = NSSize(width: 1000, height: 720)
        win.center()
        win.isReleasedWhenClosed = false
        self.window = win
        super.init()
        self.window.delegate = self
    }

    func show() {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func hide() {
        window.orderOut(nil)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        hide()
        return false
    }
}
