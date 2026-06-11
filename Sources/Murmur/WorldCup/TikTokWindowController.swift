import AppKit
import WebKit

/// Floating window hosting TikTok's official single-video embed player
/// (`tiktok.com/embed/v2/<id>`), so News-tab TikTok posts play inside Murmur
/// instead of a browser tab.
///
/// Same lifecycle contract as `TVRIWindow`, and deliberately NOT part of the
/// PlayerController/VideoWindowController plumbing (that stack is a YouTube
/// iframe bridge with a keep-alive contract this doesn't need): fresh load on
/// every `show()`, blank page on close to kill audio, and the NSWindow itself
/// is reused only to keep its autosaved frame.
///
/// `.shared` singleton rather than an AppDelegate-owned env object: no
/// constructor dependencies, only `WorldCupSheet` reaches for it.
final class TikTokWindow: NSObject {
    static let shared = TikTokWindow()

    private var window: NSWindow?
    private var webView: WKWebView?

    /// Show the window playing one TikTok post. `title` is the window title
    /// (truncated caption / source label).
    func show(videoID: String, title: String) {
        guard let url = URL(string: "https://www.tiktok.com/embed/v2/\(videoID)") else { return }
        let window = ensureWindow()
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        window.title = trimmed.isEmpty ? "TikTok" : String(trimmed.prefix(60))
        ensureWebView().load(URLRequest(url: url))
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    // MARK: - Window / webview lifecycle

    private func ensureWindow() -> NSWindow {
        if let window { return window }

        // Portrait by default — TikTok posts are 9:16.
        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 720),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        w.title = "TikTok"
        w.isReleasedWhenClosed = false
        // Float like the video window so the clip stays visible over other apps.
        w.level = .floating
        w.titlebarAppearsTransparent = true
        w.appearance = NSAppearance(named: .darkAqua)
        w.backgroundColor = NSColor(srgbRed: 0.05, green: 0.05, blue: 0.07, alpha: 1)
        w.minSize = NSSize(width: 320, height: 560)
        w.setFrameAutosaveName("murmur.tiktok.window")
        if w.frame.origin == .zero { w.center() }
        w.delegate = self

        self.window = w
        return w
    }

    private func ensureWebView() -> WKWebView {
        if let webView { return webView }
        guard let window else { fatalError("ensureWindow() must run first") }

        let config = WKWebViewConfiguration()
        // Let the clip start without a click.
        config.mediaTypesRequiringUserActionForPlayback = []

        let web = WKWebView(frame: window.contentView?.bounds ?? .zero, configuration: config)
        web.autoresizingMask = [.width, .height]
        // Desktop Safari UA — TikTok UA-sniffs and a bare WKWebView UA can land
        // on app-install interstitials.
        web.customUserAgent =
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Safari/605.1.15"
        web.setValue(false, forKey: "drawsBackground")
        window.contentView?.addSubview(web)
        self.webView = web
        return web
    }
}

extension TikTokWindow: NSWindowDelegate {
    /// Closing must stop playback (audio included) — nothing here should
    /// outlive the window. The window object sticks around only for frame
    /// persistence; `show()` reloads.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        webView?.load(URLRequest(url: URL(string: "about:blank")!))
        return true
    }
}
