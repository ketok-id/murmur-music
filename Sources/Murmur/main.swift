import AppKit
import SwiftUI
import WebKit

// Default YouTube live stream loaded on first launch.
// To swap: paste any video ID here, or just use the favorites menu in the widget.
let kDefaultVideoID = "YmQ7jRgf4f0"

// MARK: - Favorites (persisted to UserDefaults)
struct Favorite: Codable, Identifiable, Hashable {
    var name: String
    var videoID: String
    var id: String { videoID }
}

final class FavoritesStore: ObservableObject {
    @Published var items: [Favorite] = []
    private let key = "youtube-audio-widget.favorites.v1"

    init() { load() }

    func load() {
        if let data = UserDefaults.standard.data(forKey: key),
           let list = try? JSONDecoder().decode([Favorite].self, from: data) {
            items = list
            return
        }
        // First-launch seed.
        items = [
            Favorite(name: "Lofi Girl", videoID: "jfKfPfyJRdk"),
        ]
        save()
    }

    func save() {
        if let data = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    func add(name: String, videoID: String) {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayName = cleanName.isEmpty ? videoID : cleanName
        // Replace if same ID already exists, otherwise append.
        if let i = items.firstIndex(where: { $0.videoID == videoID }) {
            items[i].name = displayName
        } else {
            items.append(Favorite(name: displayName, videoID: videoID))
        }
        save()
    }

    func remove(_ favorite: Favorite) {
        items.removeAll { $0.videoID == favorite.videoID }
        save()
    }
}

// MARK: - Player controller (shared state + JS bridge)
final class PlayerController: NSObject, ObservableObject, WKNavigationDelegate {
    @Published var isPlaying = false
    @Published var isReady = false
    @Published var volume: Double = 70
    @Published var title: String = "YouTube Live Stream"
    @Published var status: String = "Loading…"
    @Published private(set) var currentVideoID: String = kDefaultVideoID
    let webView: WKWebView
    /// Fired immediately before a new stream's HTML is loaded into the webview.
    /// Used by VideoWindowController to mask the WKWebView reload flash.
    var onWillLoadStream: (() -> Void)?
    private var handler: ScriptHandler!

    override init() {
        let config = WKWebViewConfiguration()
        config.mediaTypesRequiringUserActionForPlayback = []
        config.allowsAirPlayForMediaPlayback = true
        // Real frame so WebKit doesn't suspend media on a 0x0 / hidden view
        self.webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 320, height: 150), configuration: config)
        super.init()
        self.handler = ScriptHandler(controller: self)
        self.webView.configuration.userContentController.add(self.handler, name: "cb")
        self.webView.navigationDelegate = self
        self.webView.setValue(false, forKey: "drawsBackground")
        if #available(macOS 13.3, *) {
            self.webView.isInspectable = true   // right-click → Inspect Element for debugging
        }
        loadPlayer(videoID: kDefaultVideoID)
    }

    func loadPlayer(videoID: String) {
        // We embed the official YouTube embed page in an iframe and talk to it via
        // the IFrame API's postMessage protocol. This avoids origin/baseURL issues
        // that plague using the YT.Player JS constructor inside loadHTMLString.
        let html = """
        <!DOCTYPE html>
        <html><head><meta charset="utf-8">
        <style>
          html,body{margin:0;padding:0;background:#0d0d12;overflow:hidden;
                    width:100%;height:100%;color:#888;font:11px -apple-system}
          #wrap{position:absolute;inset:0;display:flex;align-items:center;justify-content:center}
          /* Block mouse so YouTube's title/share/Watch-on-YouTube overlays never appear on hover.
             All controls are driven from the Swift side, so the iframe never needs to be clicked. */
          iframe{position:absolute;left:0;top:0;width:100%;height:100%;border:0;pointer-events:none}
          /* Opaque black cover hides YouTube's pre-play poster (thumbnail+title+big play button)
             plus the channel/branding overlay that flashes briefly on first frame.
             Removed a beat after playback starts. pointer-events:none keeps window dragging alive. */
          #cover{position:absolute;inset:0;background:#000;z-index:10;pointer-events:none;
                 transition:opacity .6s linear}
          #cover.hidden{opacity:0}
        </style>
        </head><body>
        <div id="wrap"></div>
        <iframe id="player"
          src="https://www.youtube-nocookie.com/embed/\(videoID)?enablejsapi=1&autoplay=1&controls=0&playsinline=1&modestbranding=1&rel=0&fs=0&iv_load_policy=3&origin=https://www.youtube-nocookie.com"
          allow="autoplay; encrypted-media; picture-in-picture"
          allowfullscreen></iframe>
        <div id="cover"></div>
        <script>
          var iframe = document.getElementById('player');
          var post = function(payload){
            try { iframe.contentWindow.postMessage(JSON.stringify(payload), '*'); } catch(e){}
          };
          var cmd = function(func, args){
            post({event:'command', func:func, args: args || []});
          };
          // Expose to Swift
          window.ytCmd = cmd;
          // Tell Swift the page itself is up
          function notify(t, extra){
            try {
              var m = Object.assign({type:t}, extra||{});
              window.webkit.messageHandlers.cb.postMessage(m);
            } catch(e){}
          }
          // Begin listening for player events
          iframe.addEventListener('load', function(){
            // Required handshake to start receiving onReady / onStateChange events
            post({event:'listening', id:'player', channel:'widget'});
            notify('iframe-loaded');
          });
          var cover = document.getElementById('cover');
          var coverDismissed = false;
          var hideCover = function(){
            if (!cover || coverDismissed) return;
            coverDismissed = true;
            // Wait past YouTube's startup channel/branding overlay, then fade.
            setTimeout(function(){
              if (!cover) return;
              cover.classList.add('hidden');
              setTimeout(function(){ if (cover && cover.parentNode) cover.parentNode.removeChild(cover); }, 700);
            }, 1500);
          };
          window.addEventListener('message', function(e){
            if (typeof e.data !== 'string') return;
            if (e.origin.indexOf('youtube') === -1 && e.origin.indexOf('youtube-nocookie') === -1) return;
            var d;
            try { d = JSON.parse(e.data); } catch(_) { return; }
            if (d.event === 'onReady') {
              notify('ready');
            } else if (d.event === 'onStateChange') {
              if (d.info === 1) hideCover();
              notify('state', {state: d.info});
            } else if (d.event === 'infoDelivery' && d.info) {
              if (typeof d.info.playerState !== 'undefined') {
                if (d.info.playerState === 1) hideCover();
                notify('state', {state:d.info.playerState});
              }
              if (d.info.videoData && d.info.videoData.title) notify('title', {title:d.info.videoData.title});
            } else if (d.event === 'onError') {
              notify('error', {code: d.info});
            }
          });
        </script>
        </body></html>
        """
        onWillLoadStream?()
        webView.loadHTMLString(html, baseURL: URL(string: "https://www.youtube-nocookie.com/"))
        currentVideoID = videoID
    }

    /// Accepts a plain video ID, or any youtube.com / youtu.be URL, extracts the
    /// 11-char video ID, and loads it. Returns true if it could parse an ID.
    @discardableResult
    func load(input: String) -> Bool {
        guard let id = PlayerController.extractYouTubeID(input) else {
            status = "Couldn't read a video ID from that input"
            return false
        }
        isReady = false; isPlaying = false; status = "Loading…"
        loadPlayer(videoID: id)
        return true
    }

    static func extractYouTubeID(_ raw: String) -> String? {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        // Plain 11-char ID
        if s.range(of: "^[A-Za-z0-9_-]{11}$", options: .regularExpression) != nil {
            return s
        }
        guard let url = URL(string: s) else { return nil }
        if let comp = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let v = comp.queryItems?.first(where: { $0.name == "v" })?.value, !v.isEmpty {
            return String(v.prefix(11))
        }
        // youtu.be/<id>, youtube.com/embed/<id>, youtube.com/live/<id>, youtube.com/shorts/<id>
        let parts = url.pathComponents.filter { $0 != "/" && !$0.isEmpty }
        if let last = parts.last, last.count >= 11 {
            return String(last.prefix(11))
        }
        return nil
    }

    func play()  { webView.evaluateJavaScript("window.ytCmd && ytCmd('playVideo');", completionHandler: nil) }
    func pause() { webView.evaluateJavaScript("window.ytCmd && ytCmd('pauseVideo');", completionHandler: nil) }
    func toggle(){ isPlaying ? pause() : play() }
    func setVolume(_ v: Int) { webView.evaluateJavaScript("window.ytCmd && ytCmd('setVolume', [\(v)]);", completionHandler: nil) }
    func unmute() { webView.evaluateJavaScript("window.ytCmd && ytCmd('unMute');", completionHandler: nil) }
    func reload() { isReady = false; isPlaying = false; status = "Reloading…"; loadPlayer(videoID: currentVideoID) }

    // MARK: WKNavigationDelegate
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            // Some live streams never fire onReady through the channel handshake on
            // the initial load. After a beat, mark ready so the user can press play.
            if !self.isReady {
                self.isReady = true
                self.status = "Ready (autoplay may have been blocked — press Play)"
            }
        }
    }
}

final class ScriptHandler: NSObject, WKScriptMessageHandler {
    weak var controller: PlayerController?
    init(controller: PlayerController) { self.controller = controller }
    func userContentController(_ uc: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let type = body["type"] as? String,
              let c = controller else { return }
        DispatchQueue.main.async {
            switch type {
            case "iframe-loaded":
                c.status = "Connecting to YouTube…"
            case "ready":
                c.isReady = true
                c.status = "Ready"
                c.unmute()                       // some browsers autoplay muted
                c.setVolume(Int(c.volume))
                c.play()                         // attempt autoplay
            case "state":
                if let s = body["state"] as? Int {
                    // -1 unstarted, 0 ended, 1 playing, 2 paused, 3 buffering, 5 cued
                    switch s {
                    case 1: c.isPlaying = true;  c.status = "Live"
                    case 2: c.isPlaying = false; c.status = "Paused"
                    case 3: c.status = "Buffering…"
                    case 0: c.isPlaying = false; c.status = "Ended"
                    default: break
                    }
                }
            case "title":
                if let t = body["title"] as? String, !t.isEmpty { c.title = t }
            case "error":
                let code = body["code"] as? Int ?? -1
                c.status = "YouTube error \(code)"
            default: break
            }
        }
    }
}

// Transparent overlay that sits on top of the WKWebView so the entire video
// surface drags the window. WKWebView captures mouseDown by default, which
// defeats `isMovableByWindowBackground` on its own — this view returns
// `mouseDownCanMoveWindow = true` so AppKit treats clicks as window drags.
final class WindowDragOverlay: NSView {
    // Explicitly drive the window drag — `mouseDownCanMoveWindow` alone is
    // unreliable when this view is layered over a WKWebView, because WebKit's
    // event dispatch can swallow the mouseDown before AppKit consults that flag.
    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }
}

// MARK: - Video window
// Owns the single NSWindow that the WKWebView lives in. The webview must always
// be inside a real window or WebKit suspends media — so when the user wants
// "audio only", the window stays parked at -3000,-3000 with a borderless mask.
// When the user toggles the video on, we change the styleMask to a normal
// titled/resizable window, lift it on-screen at .floating level, and lock its
// content to 16:9 so the YouTube iframe never letterboxes.
final class VideoWindowController: NSObject, ObservableObject, NSWindowDelegate {
    @Published var isVisible: Bool = false
    let window: NSWindow
    private var savedFrame: NSRect?
    private let loadingMask: NSView
    private var hideMaskWorkItem: DispatchWorkItem?

    init(webView: WKWebView) {
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 270),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false

        // Container holds (bottom-up): webView, opaque loading mask, transparent
        // drag overlay. The mask hides any flash of the previous stream during a
        // WKWebView reload; the drag overlay stays on top so dragging always works.
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 480, height: 270))
        container.autoresizingMask = [.width, .height]

        webView.frame = container.bounds
        webView.autoresizingMask = [.width, .height]
        container.addSubview(webView)

        loadingMask = NSView(frame: container.bounds)
        loadingMask.autoresizingMask = [.width, .height]
        loadingMask.wantsLayer = true
        loadingMask.layer?.backgroundColor = NSColor.black.cgColor
        loadingMask.isHidden = true
        container.addSubview(loadingMask)

        let dragOverlay = WindowDragOverlay(frame: container.bounds)
        dragOverlay.autoresizingMask = [.width, .height]
        container.addSubview(dragOverlay)

        window.contentView = container
        window.setFrameOrigin(NSPoint(x: -3000, y: -3000))
        window.orderBack(nil)
        super.init()
        window.delegate = self
    }

    func toggle() { setVisible(!isVisible) }

    func setVisible(_ visible: Bool) {
        guard visible != isVisible else { return }
        isVisible = visible
        if visible {
            // Titled+fullSizeContentView gives us a window that's still resizable
            // from the edges and draggable from the top, but with no visible chrome.
            window.styleMask = [.titled, .closable, .resizable, .fullSizeContentView]
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isMovableByWindowBackground = true   // drag from anywhere, not just the invisible title strip
            window.standardWindowButton(.closeButton)?.isHidden = true
            window.standardWindowButton(.miniaturizeButton)?.isHidden = true
            window.standardWindowButton(.zoomButton)?.isHidden = true
            window.contentAspectRatio = NSSize(width: 16, height: 9)
            window.minSize = NSSize(width: 240, height: 135)
            window.level = .floating
            if let f = savedFrame {
                window.setFrame(f, display: true)
            } else {
                window.setContentSize(NSSize(width: 480, height: 270))
                window.center()
            }
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        } else {
            savedFrame = window.frame
            window.level = .normal
            window.styleMask = [.borderless]
            window.setFrameOrigin(NSPoint(x: -3000, y: -3000))
            window.orderBack(nil)
        }
    }

    // Show an opaque black mask over the webview, then fade it out 2s later.
    // Called when a new stream starts loading so the user never sees a frame
    // of the previous video, the YouTube embed's loading branding, or any flash
    // between unload and mount of the WKWebView's HTML.
    func flashLoadingMask() {
        loadingMask.isHidden = false
        loadingMask.alphaValue = 1
        hideMaskWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.fadeOutLoadingMask() }
        hideMaskWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: work)
    }

    private func fadeOutLoadingMask() {
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.5
            loadingMask.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            self?.loadingMask.isHidden = true
        })
    }

    // Red close button hides the window instead of destroying it, so audio keeps playing.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        setVisible(false)
        return false
    }
}

// MARK: - App delegate (menu bar item + popover; no Dock icon, no window)
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    var statusItem: NSStatusItem!
    var popover: NSPopover!
    let controller = PlayerController()
    let favorites = FavoritesStore()
    var videoWindow: VideoWindowController!

    func applicationDidFinishLaunching(_ n: Notification) {
        // 1) Video window — owns the webview. Hidden off-screen by default;
        //    user can toggle it visible from the popover.
        videoWindow = VideoWindowController(webView: controller.webView)
        // Mask the webview during a stream switch so YouTube's loading overlay /
        // brief flash of the previous stream never shows in the visible window.
        controller.onWillLoadStream = { [weak self] in
            self?.videoWindow.flashLoadingMask()
        }

        // 2) Popover — the actual UI, shown only when the menu bar icon is clicked.
        popover = NSPopover()
        popover.contentSize = NSSize(width: 300, height: 250)
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        popover.contentViewController = NSHostingController(
            rootView: ContentView()
                .environmentObject(controller)
                .environmentObject(favorites)
                .environmentObject(videoWindow)
        )

        // 3) Menu bar icon.
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            let img = NSImage(systemSymbolName: "music.note", accessibilityDescription: "Murmur")
            img?.isTemplate = true
            button.image = img
            button.action = #selector(togglePopover(_:))
            button.target = self
        }
    }

    @objc func togglePopover(_ sender: AnyObject?) {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    // Audio must keep playing when the popover (a "window") closes.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

// MARK: - Boot
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)   // No Dock icon — menu bar only.
app.run()
