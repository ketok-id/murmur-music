import AppKit
import AVKit
import WebKit

/// Floating window playing any iptv-org directory channel — the generic
/// sibling of `TVRIWindow` (same recipe: native-HLS page in a WKWebView,
/// fresh load per `show()`, blank page on close to kill audio, NSWindow
/// reused only for its autosaved frame, Swift-side playback kicks because
/// WebKit policy-blocks page-initiated play on loadHTMLString pages).
///
/// `ObservableObject` so `TVBrowseView` can highlight the playing row.
final class LiveTVWindow: NSObject, ObservableObject {
    static let shared = LiveTVWindow()

    @Published private(set) var currentID: String? = nil

    private var window: NSWindow?
    private var webView: WKWebView?
    private var playerView: AVPlayerView?
    private var avPlayer: AVPlayer?

    func show(channel: IPTVChannel) {
        let window = ensureWindow()
        window.title = "\(channel.name) — Live"
        currentID = channel.id

        if channel.streamURL.scheme == "http" {
            // Plain-http streams never load in the webview — WebKit's media
            // stack ignores the app's NSAllowsArbitraryLoadsForMedia
            // exception (observed: readyState stays 0, no error fired).
            // AVPlayer honors it, so http channels play in a native
            // AVPlayerView instead.
            webView?.isHidden = true
            webView?.loadHTMLString("", baseURL: nil)
            let pv = ensurePlayerView()
            pv.isHidden = false
            let player = AVPlayer(url: channel.streamURL)
            pv.player = player
            avPlayer = player
            player.play()
        } else {
            avPlayer?.pause()
            avPlayer = nil
            playerView?.player = nil
            playerView?.isHidden = true
            let web = ensureWebView()
            web.isHidden = false
            web.loadHTMLString(
                Self.playerHTML(stream: channel.streamURL),
                baseURL: channel.streamURL
            )
            for delay in [0.8, 2.0, 4.0, 7.0, 12.0, 18.0, 25.0] {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                    self?.kickPlayback()
                }
            }
        }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func ensurePlayerView() -> AVPlayerView {
        if let playerView { return playerView }
        guard let window else { fatalError("ensureWindow() must run first") }
        let pv = AVPlayerView(frame: window.contentView?.bounds ?? .zero)
        pv.autoresizingMask = [.width, .height]
        pv.controlsStyle = .floating
        pv.videoGravity = .resizeAspect
        window.contentView?.addSubview(pv)
        playerView = pv
        return pv
    }

    private func kickPlayback() {
        webView?.evaluateJavaScript(
            "(() => { const v = document.getElementById('v'); if (v && v.paused) { v.muted = false; v.play(); } })()",
            completionHandler: nil
        )
    }

    private static func playerHTML(stream: URL) -> String {
        """
        <!doctype html><html><head><meta charset="utf-8"><style>
          html,body{margin:0;height:100%;background:#0d0d12;overflow:hidden}
          video{width:100%;height:100%;object-fit:contain;background:#000}
          #err{position:absolute;inset:0;display:none;align-items:center;justify-content:center;
               color:#9a9aa2;font:13px -apple-system,sans-serif;text-align:center;padding:0 32px;line-height:1.5;cursor:pointer}
        </style></head><body>
        <video id="v" src="\(stream.absoluteString)" autoplay playsinline controls></video>
        <div id="err">This channel isn’t answering right now.<br>
        Community-indexed streams come and go — click here to retry, or try another channel.</div>
        <script>
          const v = document.getElementById('v');
          const err = document.getElementById('err');
          // Transient manifest/segment failures are common on live origins —
          // retry with backoff before declaring the channel off-air, and let
          // a click on the overlay try again (click = user activation, so
          // that play() is never policy-blocked).
          let retries = 0;
          const reload = () => {
            err.style.display = 'none';
            v.style.display = '';
            v.load();
            v.play().catch(() => {});
          };
          v.addEventListener('error', () => {
            if (retries < 4) { retries += 1; setTimeout(reload, 4000); }
            else { v.style.display = 'none'; err.style.display = 'flex'; }
          });
          err.addEventListener('click', () => { retries = 0; reload(); });
          v.play().catch(() => {});
        </script>
        </body></html>
        """
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
        w.title = "Live TV"
        w.isReleasedWhenClosed = false
        w.level = .floating
        w.titlebarAppearsTransparent = true
        w.appearance = NSAppearance(named: .darkAqua)
        w.backgroundColor = NSColor(srgbRed: 0.05, green: 0.05, blue: 0.07, alpha: 1)
        w.minSize = NSSize(width: 480, height: 300)
        w.setFrameAutosaveName("murmur.livetv.window")
        if w.frame.origin == .zero { w.center() }
        w.delegate = self

        self.window = w
        return w
    }

    private func ensureWebView() -> WKWebView {
        if let webView { return webView }
        guard let window else { fatalError("ensureWindow() must run first") }

        let config = WKWebViewConfiguration()
        config.mediaTypesRequiringUserActionForPlayback = []

        let web = WKWebView(frame: window.contentView?.bounds ?? .zero, configuration: config)
        web.autoresizingMask = [.width, .height]
        web.customUserAgent =
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Safari/605.1.15"
        web.setValue(false, forKey: "drawsBackground")
        window.contentView?.addSubview(web)
        self.webView = web
        return web
    }
}

extension LiveTVWindow: NSWindowDelegate {
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        webView?.load(URLRequest(url: URL(string: "about:blank")!))
        avPlayer?.pause()
        avPlayer = nil
        playerView?.player = nil
        currentID = nil
        return true
    }
}
