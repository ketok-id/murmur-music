import AppKit
import WebKit

/// A hidden YouTube webview that plays an ambient source in the background.
///
/// Mirrors the iframe + postMessage handshake used by `PlayerController` in
/// `main.swift`. The webview lives off-screen at (-3000, -3000) — WebKit
/// suspends media playback on detached / 0×0 views, so a real frame is required.
final class AmbientPlayer: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
    let webView: WKWebView
    private var currentVideoID: String?
    private var pendingVolume: Int = 60

    /// Owning container window. Hidden offscreen so playback stays alive
    /// without occupying visible real estate.
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
        super.init()
        webView.navigationDelegate = self
        webView.setValue(false, forKey: "drawsBackground")
        config.userContentController.add(self, name: "ambientCB")
        window.contentView = webView
        window.isReleasedWhenClosed = false
        window.orderFront(nil)
    }

    /// Load (or swap) the active video and start playing.
    func loadAndPlay(videoID: String) {
        currentVideoID = videoID
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
        currentVideoID = nil
    }

    // MARK: - WKScriptMessageHandler

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        // No-op for ambient — fire-and-forget commands.
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
