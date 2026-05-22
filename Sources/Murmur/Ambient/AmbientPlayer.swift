import AppKit
import WebKit

/// A hidden YouTube webview that plays an ambient source in the background.
///
/// Mirrors the iframe + postMessage handshake used by `PlayerController`.
/// The webview lives off-screen at (-3000, -3000) — WebKit suspends media
/// playback on detached / 0×0 views, so a real frame is required.
final class AmbientPlayer: NSObject, WKNavigationDelegate {
    let webView: WKWebView
    private var currentVideoID: String?
    private var pendingVolume: Int = 60
    /// Separate handler with a weak back-reference. `WKUserContentController`
    /// retains its message handler strongly — registering `self` would close
    /// the cycle `AmbientPlayer → webView → config → controller → AmbientPlayer`
    /// and `deinit` would never fire.
    private let scriptHandler: AmbientScriptHandler

    /// Owning container window. Hidden offscreen so playback stays alive
    /// without occupying visible real estate. Stays `orderOut`'d until the
    /// first `loadAndPlay` — an `orderFront`'d window present at app launch
    /// suppresses SwiftUI's `WindowGroup` auto-presentation, so the main
    /// menu-bar window never appears. See the READ-BEFORE-TOUCHING block
    /// in `AppDelegate.swift`.
    private let window: NSWindow

    override init() {
        let config = WKWebViewConfiguration()
        config.mediaTypesRequiringUserActionForPlayback = []
        self.webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 320, height: 180), configuration: config)
        self.window = NSWindow(
            contentRect: NSRect(x: -3000, y: -3000, width: 320, height: 180),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        self.scriptHandler = AmbientScriptHandler()
        super.init()
        scriptHandler.player = self
        webView.navigationDelegate = self
        webView.setValue(false, forKey: "drawsBackground")
        config.userContentController.add(scriptHandler, name: "ambientCB")
        window.contentView = webView
        window.isReleasedWhenClosed = false
    }

    deinit {
        webView.configuration.userContentController
            .removeScriptMessageHandler(forName: "ambientCB")
    }

    /// Load (or swap) the active video and start playing.
    func loadAndPlay(videoID: String) {
        // Defense-in-depth: even though the caller (search results / favorites)
        // generally feeds Google-derived IDs, validate before interpolating
        // into the iframe `src=` to avoid attribute-injection if the upstream
        // ever returns something malformed.
        guard PlayerController.isValidVideoID(videoID) else { return }
        currentVideoID = videoID
        // Lift the host window into the on-screen list now that we actually
        // need a real frame for WebKit's media session. Done here (not in
        // init) so we don't suppress the main WindowGroup auto-open at launch.
        window.orderFront(nil)
        let html = Self.htmlPage(videoID: videoID, initialVolume: pendingVolume)
        webView.loadHTMLString(html, baseURL: URL(string: "https://www.youtube-nocookie.com")!)
    }

    /// 0…100. Volume is applied via the iframe API.
    func setVolume(_ percent: Int) {
        pendingVolume = max(0, min(100, percent))
        webView.evaluateJavaScript("window.ytCmd && window.ytCmd('setVolume', \(pendingVolume))")
    }

    func pause() {
        webView.evaluateJavaScript("window.ytCmd && window.ytCmd('pauseVideo')")
    }

    /// Stop and clear the webview to release resources.
    func stop() {
        webView.loadHTMLString("<html><body style='background:#000'></body></html>", baseURL: nil)
        window.orderOut(nil)
        currentVideoID = nil
    }

    private static func htmlPage(videoID: String, initialVolume: Int) -> String {
        return """
        <!DOCTYPE html>
        <html>
        <head>
        <style>
          html, body { margin:0; padding:0; background:#000; overflow:hidden; }
          #player { position:absolute; top:0; left:0; width:100%; height:100%; }
        </style>
        </head>
        <body>
        <iframe id="player"
                src="https://www.youtube-nocookie.com/embed/\(videoID)?enablejsapi=1&autoplay=1&controls=0&modestbranding=1&playsinline=1&loop=1&playlist=\(videoID)"
                frameborder="0" allow="autoplay">
        </iframe>
        <script>
        let player = document.getElementById('player');
        function postCommand(func, args) {
          player.contentWindow.postMessage(JSON.stringify({event:'command', func:func, args:args || []}), '*');
        }
        window.ytCmd = function(cmd, value) {
          if (cmd === 'setVolume') postCommand('setVolume', [value]);
          else if (cmd === 'pauseVideo') postCommand('pauseVideo');
          else if (cmd === 'playVideo') postCommand('playVideo');
        };
        window.addEventListener('message', function(e) {
          window.webkit.messageHandlers.ambientCB.postMessage(String(e.data).slice(0, 200));
        });
        setTimeout(function() {
          player.contentWindow.postMessage('{"event":"listening","id":"\(videoID)"}', '*');
          setTimeout(function() {
            postCommand('setVolume', [\(initialVolume)]);
            postCommand('playVideo');
          }, 600);
        }, 400);
        </script>
        </body>
        </html>
        """
    }
}

/// Separate `WKScriptMessageHandler` so the user-content-controller's strong
/// retention of its handler doesn't close a retain cycle on `AmbientPlayer`.
/// The body is a no-op today; the handler exists only to receive the
/// fire-and-forget `ambientCB` messages emitted by the page script.
private final class AmbientScriptHandler: NSObject, WKScriptMessageHandler {
    weak var player: AmbientPlayer?
    func userContentController(_ controller: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        // No-op; ambient commands are fire-and-forget.
    }
}
