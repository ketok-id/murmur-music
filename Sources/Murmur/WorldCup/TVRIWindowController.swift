import AppKit
import WebKit

/// Floating window that embeds TVRI Klik — TVRI's official (free, FTA)
/// streaming site — so World Cup matches can be *watched* inside Murmur
/// instead of a browser tab. The stream is plain HLS (no DRM), which WebKit
/// plays natively, and we render their full player page, so their ads /
/// analytics / player chrome stay intact.
///
/// Deliberately NOT part of the PlayerController/VideoWindowController
/// plumbing: that stack is a YouTube-iframe bridge with a keep-alive
/// contract (offscreen parking, postMessage handshake). TVRI needs none of
/// that — closing this window should simply stop the stream. So: fresh page
/// load on every `show()`, blank page on close to kill audio, and the
/// NSWindow itself is reused only to keep its autosaved frame.
///
/// `.shared` singleton rather than an AppDelegate-owned env object: it has
/// no constructor dependencies and only `WorldCupSheet` reaches for it
/// (same pragmatic category as `WindowOpenerBridge` / `YouTubeSearchState`).
final class TVRIWindow: NSObject {
    static let shared = TVRIWindow()

    /// TVRI Klik live channels relevant to the World Cup. Nasional carries
    /// all 104 matches per TVRI's rights announcement; Sport HD simulcasts
    /// sport programming (often higher quality); World is the international
    /// feed. IDs verified against klik.tvri.go.id's channel list.
    enum Channel: String, CaseIterable {
        case nasional = "TVRI_CH_00"
        case sport    = "TVRI_CH_03"
        case world    = "TVRI_CH_02"

        var label: String {
            switch self {
            case .nasional: return "Nasional"
            case .sport:    return "Sport HD"
            case .world:    return "World"
            }
        }

        var url: URL { URL(string: "https://klik.tvri.go.id/detailchannel/\(rawValue)")! }
    }

    private static let kChannel = "youtube-audio-widget.worldcup.tvriChannel"

    private var window: NSWindow?
    private var webView: WKWebView?
    private var channelControl: NSSegmentedControl?

    private(set) var channel: Channel = Channel(
        rawValue: UserDefaults.standard.string(forKey: kChannel) ?? "") ?? .nasional

    /// Show the window on `channel` (nil = last used).
    func show(channel requested: Channel? = nil) {
        if let requested {
            channel = requested
            UserDefaults.standard.set(requested.rawValue, forKey: Self.kChannel)
        }
        let window = ensureWindow()
        syncChannelControl()
        loadStream()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    // MARK: - Window / webview lifecycle

    private func ensureWindow() -> NSWindow {
        if let window { return window }

        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 560),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        w.title = "TVRI — Live"
        w.isReleasedWhenClosed = false
        // Float like the video window so the match stays visible over other
        // apps; movable/resizable via the normal titlebar.
        w.level = .floating
        w.titlebarAppearsTransparent = true
        w.appearance = NSAppearance(named: .darkAqua)
        w.backgroundColor = NSColor(srgbRed: 0.05, green: 0.05, blue: 0.07, alpha: 1)
        w.minSize = NSSize(width: 480, height: 300)
        w.setFrameAutosaveName("murmur.tvri.window")
        if w.frame.origin == .zero { w.center() }
        w.delegate = self

        // Channel switcher in the titlebar — Nasional / Sport HD / World.
        let control = NSSegmentedControl(
            labels: Channel.allCases.map(\.label),
            trackingMode: .selectOne,
            target: self,
            action: #selector(channelPicked(_:)))
        control.segmentStyle = .roundRect
        control.controlSize = .small
        let accessory = NSTitlebarAccessoryViewController()
        accessory.view = control
        accessory.layoutAttribute = .trailing
        w.addTitlebarAccessoryViewController(accessory)
        channelControl = control

        self.window = w
        return w
    }

    @objc private func channelPicked(_ sender: NSSegmentedControl) {
        let all = Channel.allCases
        guard sender.selectedSegment >= 0, sender.selectedSegment < all.count else { return }
        channel = all[sender.selectedSegment]
        UserDefaults.standard.set(channel.rawValue, forKey: Self.kChannel)
        loadStream()
    }

    private func syncChannelControl() {
        channelControl?.selectedSegment = Channel.allCases.firstIndex(of: channel) ?? 0
    }

    private func loadStream() {
        window?.title = "TVRI \(channel.label) — Live"
        let web = ensureWebView()
        web.load(URLRequest(url: channel.url))
    }

    private func ensureWebView() -> WKWebView {
        if let webView { return webView }
        guard let window else { fatalError("ensureWindow() must run first") }

        let config = WKWebViewConfiguration()
        // Let the live stream start without a click.
        config.mediaTypesRequiringUserActionForPlayback = []

        let web = WKWebView(frame: window.contentView?.bounds ?? .zero, configuration: config)
        web.autoresizingMask = [.width, .height]
        // Desktop Safari UA — TVRI Klik UA-sniffs and a bare WKWebView UA can
        // land on mobile layouts or "unsupported browser" walls.
        web.customUserAgent =
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Safari/605.1.15"
        web.setValue(false, forKey: "drawsBackground")
        window.contentView?.addSubview(web)
        self.webView = web
        return web
    }
}

extension TVRIWindow: NSWindowDelegate {
    /// Closing must stop the stream (audio included) — unlike the YouTube
    /// player window, nothing here should outlive the window. The window
    /// object itself sticks around for frame persistence; `show()` reloads.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        webView?.load(URLRequest(url: URL(string: "about:blank")!))
        return true
    }
}
