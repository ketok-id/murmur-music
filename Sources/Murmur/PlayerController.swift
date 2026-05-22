import AppKit
import Combine
import SwiftUI
import WebKit

// Default YouTube live stream loaded on first launch.
// To swap: paste any video ID here, or just use the favorites menu in the widget.
let kDefaultVideoID = "YmQ7jRgf4f0"

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
    /// Best-effort classification of the current video (music / podcast /
    /// talk / other). Updated whenever a title arrives from the JS bridge.
    /// The YouTube IFrame API doesn't expose categoryId, so this is
    /// title-heuristic only — `VideoCategoryHint.classify(categoryId: "", title:)`.
    @Published var categoryHint: VideoCategoryHint = .other
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
        // Initial load is deferred to `AppDelegate.applicationDidFinishLaunching`
        // so it can consult `LastSessionStore` / `UserPlaylistsStore` and
        // resume the user's last video / playlist instead of `kDefaultVideoID`.
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
          /* Opaque black cover hides YouTube's pre-play poster (thumbnail+title+big play button),
             the channel/branding overlay that flashes briefly on first frame, AND YouTube's
             paused-state overlay (Topic-channel "now playing" card + center prev/play/next pills).
             Visible whenever player state is not Playing. pointer-events:none keeps window dragging alive. */
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
          var initialHideDone = false;
          var coverShouldShow = true;
          var hideCover = function(){
            coverShouldShow = false;
            if (!cover) return;
            if (initialHideDone) {
              cover.classList.add('hidden');
              return;
            }
            initialHideDone = true;
            // First hide waits past YouTube's startup channel/branding overlay before fading.
            // Subsequent hides (resume from pause) are immediate.
            setTimeout(function(){
              if (cover && !coverShouldShow) cover.classList.add('hidden');
            }, 1500);
          };
          var showCover = function(){
            coverShouldShow = true;
            if (cover) cover.classList.remove('hidden');
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
              else if (d.info !== 3) showCover();
              notify('state', {state: d.info});
            } else if (d.event === 'infoDelivery' && d.info) {
              if (typeof d.info.playerState !== 'undefined') {
                if (d.info.playerState === 1) hideCover();
                else if (d.info.playerState !== 3) showCover();
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

    /// Strict YouTube videoID shape — 11 chars, URL-safe-base64 charset.
    /// Both extractors apply this to every return branch so attacker-
    /// controlled input can't smuggle attribute-injection characters
    /// (`"`, `<`, `>`, space, etc.) into the iframe `src=` we build later.
    private static let videoIDPattern = "^[A-Za-z0-9_-]{11}$"
    /// YouTube playlist IDs in the wild range from 13 chars (PL…) up to
    /// ~40 chars (RD…, OLAK5uy_…). 10–64 is a comfortable envelope that
    /// still rejects anything containing attribute-injection characters.
    private static let playlistIDPattern = "^[A-Za-z0-9_-]{10,64}$"

    static func isValidVideoID(_ s: String) -> Bool {
        s.range(of: videoIDPattern, options: .regularExpression) != nil
    }

    static func isValidPlaylistID(_ s: String) -> Bool {
        s.range(of: playlistIDPattern, options: .regularExpression) != nil
    }

    /// Pulls the `list=…` playlist ID out of any YouTube URL. Returns nil
    /// for plain video-ID strings, URLs without a `list` query parameter,
    /// or values that don't match the strict playlist-ID shape.
    static func extractPlaylistID(_ raw: String) -> String? {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty, let url = URL(string: s),
              let comp = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let value = comp.queryItems?.first(where: { $0.name == "list" })?.value,
              !value.isEmpty,
              isValidPlaylistID(value) else { return nil }
        return value
    }

    static func extractYouTubeID(_ raw: String) -> String? {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        if isValidVideoID(s) { return s }
        guard let url = URL(string: s) else { return nil }
        if let comp = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let v = comp.queryItems?.first(where: { $0.name == "v" })?.value,
           isValidVideoID(v) {
            return v
        }
        // youtu.be/<id>, youtube.com/embed/<id>, youtube.com/live/<id>, youtube.com/shorts/<id>
        let parts = url.pathComponents.filter { $0 != "/" && !$0.isEmpty }
        if let last = parts.last {
            // The full path component must match the videoID shape — no
            // truncation. Prevents `…/abcdefghij"x` from sneaking through.
            if isValidVideoID(last) { return last }
            // Some YouTube URL shapes prepend a prefix segment that's
            // still followed by an exact 11-char ID; accept only that case.
            if last.count == 11, isValidVideoID(last) { return last }
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

    /// Advance to the next track. Priority: active YT playlist → active user
    /// playlist → queue → trending auto-fill (if enabled). When a user playlist
    /// is active we stop at the end of the list — no fall-through to queue
    /// or trending, that's the explicit-curation contract.
    func playNext() {
        let playlist = PlaylistStore.shared
        if playlist.hasActivePlaylist,
           let idx = playlist.currentIndex,
           idx + 1 < playlist.items.count {
            let next = playlist.items[idx + 1]
            _ = load(input: "https://www.youtube.com/watch?v=\(next.videoID)&list=\(playlist.playlistID)")
            return
        }
        if UserPlaylistsStore.shared.hasActivePlaylist {
            if let next = UserPlaylistsStore.shared.nextItem() {
                _ = load(input: next.videoID)
            }
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

    /// Step back one track. Honors the active YT playlist first, then the
    /// active user playlist. Ad-hoc videos have no history to step back into.
    func playPrev() {
        let playlist = PlaylistStore.shared
        if playlist.hasActivePlaylist,
           let idx = playlist.currentIndex,
           idx > 0 {
            let prev = playlist.items[idx - 1]
            _ = load(input: "https://www.youtube.com/watch?v=\(prev.videoID)&list=\(playlist.playlistID)")
            return
        }
        if let prev = UserPlaylistsStore.shared.previousItem() {
            _ = load(input: prev.videoID)
        }
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

// MARK: - Script handler (JS → Swift bridge)

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
                if let t = body["title"] as? String, !t.isEmpty {
                    c.title = t
                    c.categoryHint = VideoCategoryHint.classify(categoryId: "", title: t)
                }
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
