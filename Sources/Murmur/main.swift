import AppKit
import Combine
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
    /// Current YouTube playlist ID (the `list=PL…` parameter), empty if not playing a playlist.
    /// When set, the iframe is loaded with `&list=…` so YouTube auto-advances to the next entry.
    @Published private(set) var currentPlaylistID: String = ""
    /// Non-empty when the loaded `list=…` looks like a YouTube Mix/Radio (`RD…`).
    /// These are auto-generated and the IFrame embed often refuses to auto-advance them.
    @Published var mixHint: String = ""
    /// Current playhead in seconds, updated from iframe infoDelivery events.
    @Published var currentTime: Double = 0
    /// Total video duration in seconds. 0 if unknown or for live streams.
    @Published var duration: Double = 0
    /// Speed multiplier; 1.0 = normal. YouTube supports 0.25 – 2.0.
    @Published var playbackRate: Double = 1.0 {
        didSet { applyPlaybackRate() }
    }
    /// Called when the YouTube playerState transitions to ended (state 0).
    var onEnded: (() -> Void)?
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

    func loadPlayer(videoID: String, playlistID: String = "") {
        // Look up resume position from history. Skip if too small (just
        // started) or near the end (don't resume the last few seconds).
        // Skipped entirely when playing a playlist — YouTube manages the cursor.
        let savedPosition: Double = {
            guard playlistID.isEmpty, !videoID.isEmpty else { return 0 }
            return PlayedVideoHistoryStore.shared.entries
                .first(where: { $0.videoID == videoID })?
                .lastPosition ?? 0
        }()
        let startSeconds: Int = (savedPosition > 5) ? Int(savedPosition) : 0
        let embedSrc = Self.buildEmbedSrc(videoID: videoID,
                                          playlistID: playlistID,
                                          startSeconds: startSeconds)
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
          src="\(embedSrc)"
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
          // Begin listening for player events. YouTube's internal player JS
          // doesn't always finish initializing by the time the iframe's load
          // event fires, so a single 'listening' post can race past it and be
          // ignored. Retry on a short interval until onReady arrives (or give
          // up after ~3s so we don't leak the interval).
          var listeningInterval = null;
          var listeningAttempts = 0;
          function stopListeningRetry(){
            if (listeningInterval) { clearInterval(listeningInterval); listeningInterval = null; }
          }
          iframe.addEventListener('load', function(){
            notify('iframe-loaded');
            stopListeningRetry();
            listeningAttempts = 0;
            post({event:'listening', id:'player', channel:'widget'});
            listeningInterval = setInterval(function(){
              listeningAttempts += 1;
              if (listeningAttempts > 20) { stopListeningRetry(); return; }
              post({event:'listening', id:'player', channel:'widget'});
            }, 150);
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
              stopListeningRetry();
              notify('ready');
            } else if (d.event === 'onStateChange') {
              if (d.info === 1) hideCover();
              notify('state', {state: d.info});
            } else if (d.event === 'infoDelivery' && d.info) {
              if (typeof d.info.playerState !== 'undefined') {
                if (d.info.playerState === 1) hideCover();
                notify('state', {state:d.info.playerState});
              }
              if (d.info.videoData) {
                if (d.info.videoData.title) notify('title', {title:d.info.videoData.title});
                // When playing a YouTube playlist, video_id changes as it auto-advances.
                // Notify only on transition so we don't spam Swift on every infoDelivery tick.
                var vid = d.info.videoData.video_id;
                if (vid && vid !== window.__lastVideoId) {
                  window.__lastVideoId = vid;
                  notify('video', {videoId: vid});
                }
              }
              if (typeof d.info.currentTime === 'number') notify('time', {time: d.info.currentTime});
              if (typeof d.info.duration === 'number' && d.info.duration > 0) notify('duration', {duration: d.info.duration});
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
        currentPlaylistID = playlistID
        duration = 0
        // Sync the playlist cursor right away. If items are already loaded,
        // this moves the highlight (and gates prev/next correctly) without
        // waiting for the iframe's `video` notification — which would
        // otherwise be short-circuited by the equality guard in
        // `updateCurrentVideoID` since we just assigned currentVideoID above.
        if !videoID.isEmpty {
            PlaylistStore.shared.updateCurrent(videoID: videoID)
        }
    }

    private static func buildEmbedSrc(videoID: String, playlistID: String, startSeconds: Int) -> String {
        let path = videoID.isEmpty
            ? "https://www.youtube-nocookie.com/embed/videoseries"
            : "https://www.youtube-nocookie.com/embed/\(videoID)"
        var params = [
            "enablejsapi=1",
            "autoplay=1",
            "controls=0",
            "playsinline=1",
            "modestbranding=1",
            "rel=0",
            "fs=0",
            "iv_load_policy=3",
            "origin=https://www.youtube-nocookie.com",
        ]
        if !playlistID.isEmpty {
            params.append("list=\(playlistID)")
            // listType is required for `embed/videoseries`; harmless when starting at a specific video.
            if videoID.isEmpty { params.append("listType=playlist") }
        } else {
            params.append("start=\(startSeconds)")
        }
        return "\(path)?\(params.joined(separator: "&"))"
    }

    /// Accepts a plain video ID, or any youtube.com / youtu.be URL. Extracts the
    /// 11-char video ID and (if present) the `list=…` playlist ID, then loads them.
    /// Returns true if either piece could be parsed.
    @discardableResult
    func load(input: String) -> Bool {
        let videoID = PlayerController.extractYouTubeID(input) ?? ""
        let playlistID = PlayerController.extractPlaylistID(input) ?? ""
        if videoID.isEmpty && playlistID.isEmpty {
            status = "Couldn't read a video ID from that input"
            return false
        }
        isReady = false; isPlaying = false; status = "Loading…"
        mixHint = PlayerController.isMixPlaylistID(playlistID)
            ? "YouTube Mix — may not auto-advance"
            : ""
        // Enumerate the playlist into PlaylistStore so the UI can show it +
        // follow YouTube's auto-advance. Mixes (RD…) are skipped because the
        // Data API can't enumerate them.
        if !playlistID.isEmpty, !PlayerController.isMixPlaylistID(playlistID) {
            // Pass the videoID as a seed so the cursor lands on the right
            // entry once items finish fetching (initial paste case where
            // updateCurrent in loadPlayer no-ops on empty items).
            PlaylistStore.shared.load(
                playlistID: playlistID,
                apiKey: APIKeyStore.shared.youtubeKey,
                seedVideoID: videoID
            )
        } else {
            PlaylistStore.shared.clear()
        }
        loadPlayer(videoID: videoID, playlistID: playlistID)
        return true
    }

    /// YouTube Mix/Radio playlists start with `RD` (e.g. `RDo97DaNnADeM`, `RDMM…`, `RDCLAK…`).
    /// They're server-generated and the IFrame embed frequently won't auto-advance them.
    static func isMixPlaylistID(_ id: String) -> Bool {
        id.hasPrefix("RD")
    }

    /// Pulls the `list=…` playlist ID out of any YouTube URL. Returns nil for
    /// plain video-ID strings or URLs without a `list` query parameter.
    static func extractPlaylistID(_ raw: String) -> String? {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty, let url = URL(string: s),
              let comp = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let value = comp.queryItems?.first(where: { $0.name == "list" })?.value,
              !value.isEmpty else { return nil }
        return value
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

    /// Seek to a specific point in the current video. Updates `currentTime`
    /// optimistically so scrubber UI doesn't jump back to the old value while
    /// the iframe's next infoDelivery tick catches up.
    func seek(to seconds: Double) {
        let clamped = max(0, seconds)
        currentTime = clamped
        webView.evaluateJavaScript("window.ytCmd && ytCmd('seekTo', [\(clamped), true]);", completionHandler: nil)
    }

    /// Advance to the next track. Priority: active playlist → queue → trending
    /// auto-fill (if enabled). Matches the onEnded auto-advance flow.
    func playNext() {
        let playlist = PlaylistStore.shared
        if playlist.hasActivePlaylist,
           let idx = playlist.currentIndex,
           idx + 1 < playlist.items.count {
            let next = playlist.items[idx + 1]
            _ = load(input: "https://www.youtube.com/watch?v=\(next.videoID)&list=\(playlist.playlistID)")
            return
        }
        if let next = PlaybackQueue.shared.popNext() {
            _ = load(input: next.videoID)
            return
        }
        guard TrendingRegionStore.shared.autoFillFromTrending else { return }
        let finishedID = currentVideoID
        Task { @MainActor in
            await PlaybackQueue.shared.refillFromTrending(excluding: finishedID)
            if let next = PlaybackQueue.shared.popNext() {
                _ = self.load(input: next.videoID)
            }
        }
    }

    /// Step back one track. Only meaningful when a playlist is loaded — we
    /// don't keep a play history for ad-hoc videos.
    func playPrev() {
        let playlist = PlaylistStore.shared
        guard playlist.hasActivePlaylist,
              let idx = playlist.currentIndex,
              idx > 0 else { return }
        let prev = playlist.items[idx - 1]
        _ = load(input: "https://www.youtube.com/watch?v=\(prev.videoID)&list=\(playlist.playlistID)")
    }
    func reload() { isReady = false; isPlaying = false; status = "Reloading…"; loadPlayer(videoID: currentVideoID, playlistID: currentPlaylistID) }

    func setPlaybackRate(_ rate: Double) {
        playbackRate = rate
    }

    /// Called when YouTube reports the currently-playing video has changed.
    /// Mainly fires during playlist playback when the player auto-advances.
    fileprivate func updateCurrentVideoID(_ id: String) {
        guard !id.isEmpty, id != currentVideoID else { return }
        currentVideoID = id
        currentTime = 0
        // Follow the cursor through an enumerated playlist (if any).
        PlaylistStore.shared.updateCurrent(videoID: id)
    }

    private func applyPlaybackRate() {
        let rate = max(0.25, min(2.0, playbackRate))
        webView.evaluateJavaScript("window.ytCmd && ytCmd('setPlaybackRate', [\(rate)]);",
                                   completionHandler: nil)
    }

    // MARK: WKNavigationDelegate
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            // Some live streams never fire onReady through the channel handshake on
            // the initial load. After a beat, mark ready so the user can press play.
            // Also fire a best-effort play() — on subsequent reloads (e.g. user
            // hit Next), onReady can be missed by the listening handshake race;
            // if YouTube's player is in fact ready, this kicks autoplay; if it
            // isn't, ytCmd silently no-ops and the user can still press Play.
            if !self.isReady {
                self.isReady = true
                self.status = "Ready (autoplay may have been blocked — press Play)"
                self.unmute()
                self.setVolume(Int(self.volume))
                self.play()
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
                if c.playbackRate != 1.0 {
                    c.setPlaybackRate(c.playbackRate)
                }
            case "state":
                if let s = body["state"] as? Int {
                    // -1 unstarted, 0 ended, 1 playing, 2 paused, 3 buffering, 5 cued
                    switch s {
                    case 1: c.isPlaying = true;  c.status = "Live"
                    case 2: c.isPlaying = false; c.status = "Paused"
                    case 3: c.status = "Buffering…"
                    case 0:
                        c.isPlaying = false
                        c.status = "Ended"
                        c.onEnded?()
                    default: break
                    }
                }
            case "title":
                if let t = body["title"] as? String, !t.isEmpty { c.title = t }
            case "video":
                if let id = body["videoId"] as? String { c.updateCurrentVideoID(id) }
            case "time":
                if let t = body["time"] as? Double { c.currentTime = t }
            case "duration":
                if let d = body["duration"] as? Double, d > 0 { c.duration = d }
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
/// Container view for the video window. Catches mouseMoved/mouseExited via an
/// NSTrackingArea owned by the view itself so the HUD can fade in on motion and
/// out on idle. The HUD is a child view; this only handles the tracking signal.
final class HoverTrackingView: NSView {
    var onMouseMoved: (() -> Void)?
    var onMouseExited: (() -> Void)?
    override func mouseMoved(with event: NSEvent) { onMouseMoved?() }
    override func mouseEntered(with event: NSEvent) { onMouseMoved?() }
    override func mouseExited(with event: NSEvent) { onMouseExited?() }
}

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
    private let hudContainer: NSVisualEffectView
    private var hudHideWorkItem: DispatchWorkItem?
    private var trackingArea: NSTrackingArea?
    /// HUD layout is recomputed on every resize so the bar scales with the
    /// window. Heights/insets are clamped so we don't get a microscopic HUD on
    /// a tiny window or a giant one on a maximized window.
    private static let hudHeightMin: CGFloat = 36
    private static let hudHeightMax: CGFloat = 72
    private static let hudInsetMin: CGFloat = 8
    private static let hudInsetMax: CGFloat = 20

    init(controller: PlayerController) {
        let webView = controller.webView
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 270),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false

        // Container holds (bottom-up): webView, opaque loading mask, transparent
        // drag overlay, HUD controls overlay. The mask hides any flash of the
        // previous stream during a WKWebView reload; the drag overlay catches
        // mouseDowns everywhere except inside the HUD frame.
        let container = HoverTrackingView(frame: NSRect(x: 0, y: 0, width: 480, height: 270))
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

        // HUD bar: NSVisualEffectView for native QuickTime-style vibrancy,
        // bottom-anchored with side+bottom insets. NSHostingView paints the
        // SwiftUI controls on top of the vibrancy material. Frame is
        // recomputed in layoutHUD() on every resize so the bar scales.
        hudContainer = NSVisualEffectView(frame: .zero)
        hudContainer.material = .hudWindow
        hudContainer.blendingMode = .withinWindow
        hudContainer.state = .active
        hudContainer.wantsLayer = true
        hudContainer.layer?.masksToBounds = true
        hudContainer.alphaValue = 0
        container.addSubview(hudContainer)

        window.contentView = container
        window.setFrameOrigin(NSPoint(x: -3000, y: -3000))
        window.orderBack(nil)
        super.init()
        window.delegate = self

        // Mount the SwiftUI HUD inside the visual-effect container.
        let hudView = VideoControlsHUD(controller: controller) { [weak self] in
            self?.setVisible(false)
        }
        let hosting = NSHostingView(rootView: hudView)
        hosting.frame = hudContainer.bounds
        hosting.autoresizingMask = [.width, .height]
        hudContainer.addSubview(hosting)

        container.onMouseMoved = { [weak self] in self?.revealHUD() }
        container.onMouseExited = { [weak self] in self?.scheduleHUDHide(after: 0.4) }
        rebuildTrackingArea(container: container)
        layoutHUD()
    }

    /// Recompute HUD frame + corner radius based on current window size so the
    /// bar scales with the video. Called from init and `windowDidResize`.
    private func layoutHUD() {
        guard let container = window.contentView else { return }
        let h = container.bounds.height
        // Height tracks ~14% of window height, clamped to a sensible range.
        let hudHeight = max(Self.hudHeightMin, min(Self.hudHeightMax, h * 0.14))
        let inset = max(Self.hudInsetMin, min(Self.hudInsetMax, h * 0.045))
        let cornerRadius = min(14, hudHeight * 0.28)
        hudContainer.frame = NSRect(
            x: inset,
            y: inset,
            width: max(120, container.bounds.width - inset * 2),
            height: hudHeight
        )
        hudContainer.layer?.cornerRadius = cornerRadius
        // Resize the hosting view (and therefore the SwiftUI HUD) to match.
        if let hosting = hudContainer.subviews.first {
            hosting.frame = hudContainer.bounds
        }
    }

    func windowDidResize(_ notification: Notification) {
        layoutHUD()
    }

    private func rebuildTrackingArea(container: NSView) {
        if let existing = trackingArea {
            container.removeTrackingArea(existing)
        }
        let area = NSTrackingArea(
            rect: container.bounds,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
            owner: container,
            userInfo: nil
        )
        container.addTrackingArea(area)
        trackingArea = area
    }

    private func revealHUD() {
        hudHideWorkItem?.cancel()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            hudContainer.animator().alphaValue = 1
        }
        scheduleHUDHide(after: 2.5)
    }

    private func scheduleHUDHide(after seconds: TimeInterval) {
        hudHideWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.fadeOutHUD() }
        hudHideWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    private func fadeOutHUD() {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.4
            hudContainer.animator().alphaValue = 0
        }
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
    let mixer = MixerEngine()
    var booth: BoothWindowController!
    var recordings: RecordingsWindowController!
    let queueLauncher = QueueLauncher()
    private var historyCancellable: AnyCancellable?
    private var positionCancellable: AnyCancellable?

    func applicationDidFinishLaunching(_ n: Notification) {
        // 1) Video window — owns the webview. Hidden off-screen by default;
        //    user can toggle it visible from the popover.
        videoWindow = VideoWindowController(controller: controller)
        // Mask the webview during a stream switch so YouTube's loading overlay /
        // brief flash of the previous stream never shows in the visible window.
        controller.onWillLoadStream = { [weak self] in
            self?.videoWindow.flashLoadingMask()
        }

        // Start the DJ mixer engine.
        do {
            try mixer.start()
        } catch {
            NSLog("MixerEngine failed to start: \(error)")
        }

        // Booth window — kept alive for the life of the app; hidden by default.
        booth = BoothWindowController(mixer: mixer)
        recordings = RecordingsWindowController()

        // 2) Popover — the actual UI, shown only when the menu bar icon is clicked.
        popover = NSPopover()
        popover.contentSize = NSSize(width: 340, height: 280)
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        popover.contentViewController = NSHostingController(
            rootView: ContentView()
                .environmentObject(controller)
                .environmentObject(favorites)
                .environmentObject(videoWindow)
                .environmentObject(mixer)
                .environmentObject(BoothLauncher(booth: booth))
                .environmentObject(RecordingsLauncher(controller: recordings))
                .environmentObject(queueLauncher)
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

        // Queue auto-advance. If the queue is empty AND the user has opted
        // into auto-fill, fetch trending and refill the queue, then advance.
        controller.onEnded = { [weak self] in
            guard let self = self else { return }
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

    func applicationWillTerminate(_ n: Notification) {
        mixer.graph.stop()
    }

    // Audio must keep playing when the popover (a "window") closes.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

// MARK: - Booth launcher (SwiftUI bridge)
final class BoothLauncher: ObservableObject {
    let booth: BoothWindowController
    init(booth: BoothWindowController) { self.booth = booth }
    func show() { booth.show() }
}

// MARK: - Recordings launcher (SwiftUI bridge)
final class RecordingsLauncher: ObservableObject {
    let controller: RecordingsWindowController
    init(controller: RecordingsWindowController) { self.controller = controller }
    func show() { controller.show() }
}

// MARK: - Queue launcher (SwiftUI bridge)
final class QueueLauncher: ObservableObject {
    @Published var isShowing = false
    func show() { isShowing = true }
}

// MARK: - Boot
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)   // No Dock icon — menu bar only.
app.run()
