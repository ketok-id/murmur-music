import AppKit
import WebKit

/// Floating window that plays TVRI — Indonesia's official (free, FTA) World
/// Cup broadcaster — so matches can be *watched* inside Murmur instead of a
/// browser tab.
///
/// We used to embed TVRI Klik's website (klik.tvri.go.id) so their player
/// chrome/ads stayed intact, but as of June 2026 that site sits behind an
/// anti-bot CDN wall (302-to-self + `C3VK` cookie challenge that tar-pits
/// non-browser clients), which broke the embedded webview. The fix is to
/// play TVRI's own HLS publish points (`ott-balancer.tvri.go.id` — the same
/// origin their player pulls from, verified live, no DRM) directly in a
/// minimal local page; WebKit plays HLS natively, so the window needs no JS
/// player. If TVRI ever drops the wall, embedding the site again is fine.
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

    /// TVRI live channels relevant to the World Cup. Nasional carries all
    /// 104 matches per TVRI's rights announcement; Sport HD simulcasts
    /// sport programming (often higher quality); World is the international
    /// feed. Raw values are the legacy Klik ids — kept so the persisted
    /// channel preference survives; publish-point names verified against
    /// ott-balancer (June 2026).
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

        /// Publish-point name on TVRI's OTT origin.
        private var publishPoint: String {
            switch self {
            case .nasional: return "Nasional"
            case .sport:    return "SportHD"
            case .world:    return "TVRIWorld"
            }
        }

        var streamURL: URL {
            URL(string: "https://ott-balancer.tvri.go.id/live/eds/\(publishPoint)/hls/\(publishPoint).m3u8")!
        }
    }

    private static let kChannel = "youtube-audio-widget.worldcup.tvriChannel"
    private static let kQuality = "youtube-audio-widget.worldcup.tvriQuality"

    /// Pinnable rendition heights. **480 is the default on purpose**: TVRI
    /// puts a rights slate (station logo card) on the higher renditions
    /// during protected events while the real broadcast stays on 854×480 —
    /// WebKit's auto ABR climbs straight to 1080p and lands on the slate.
    static let qualities = ["Auto", "240p", "360p", "480p", "720p", "1080p"]

    private var window: NSWindow?
    private var webView: WKWebView?
    private var channelControl: NSSegmentedControl?
    private var qualityControl: NSPopUpButton?

    private(set) var channel: Channel = Channel(
        rawValue: UserDefaults.standard.string(forKey: kChannel) ?? "") ?? .nasional

    /// "Auto" or a `qualities` entry; persisted.
    private(set) var quality: String =
        UserDefaults.standard.string(forKey: kQuality) ?? "480p"

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

        // Quality pin next to it (see `qualities` doc for why 480p default).
        let popup = NSPopUpButton(frame: .zero, pullsDown: false)
        popup.addItems(withTitles: Self.qualities)
        popup.target = self
        popup.action = #selector(qualityPicked(_:))
        popup.controlSize = .small
        popup.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        popup.selectItem(withTitle: quality)
        let qualityAccessory = NSTitlebarAccessoryViewController()
        qualityAccessory.view = popup
        qualityAccessory.layoutAttribute = .trailing
        w.addTitlebarAccessoryViewController(qualityAccessory)
        qualityControl = popup

        self.window = w
        return w
    }

    @objc private func qualityPicked(_ sender: NSPopUpButton) {
        quality = sender.titleOfSelectedItem ?? "Auto"
        UserDefaults.standard.set(quality, forKey: Self.kQuality)
        loadStream()
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
        let master = channel.streamURL
        let pinnedHeight = Int(quality.dropLast(quality.hasSuffix("p") ? 1 : 0))

        Task { @MainActor [weak self] in
            guard let self else { return }
            // Pin to one rendition by resolving the master ladder fresh each
            // load (the variant URLs carry per-session tokens, so they can't
            // be hardcoded). Falls back to the master (auto ABR) on failure.
            var stream = master
            if let pinnedHeight,
               let variant = await Self.variantURL(master: master, height: pinnedHeight) {
                stream = variant
            }
            // Re-check the user didn't switch channels mid-resolve.
            guard self.channel.streamURL == master else { return }
            web.loadHTMLString(
                Self.playerHTML(stream: stream),
                baseURL: URL(string: "https://ott-balancer.tvri.go.id")
            )
            // WebKit refuses the page's own un-gestured play() — even muted —
            // on loadHTMLString pages, but JS injected via evaluateJavaScript
            // runs with user-activation privileges (the same reason the
            // YouTube bridge's ytCmd calls work). Kick playback while the
            // stream buffers; each kick is a no-op once playing, and the
            // long tail covers the error-retry reloads.
            for delay in [0.8, 2.0, 4.0, 7.0, 12.0, 18.0, 25.0] {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                    self?.kickPlayback()
                }
            }
        }
    }

    /// Fetch + parse the master playlist and return the variant whose
    /// RESOLUTION height is closest to `height`.
    private static func variantURL(master: URL, height: Int) async -> URL? {
        guard let (data, _) = try? await URLSession.shared.data(from: master),
              let text = String(data: data, encoding: .utf8)
        else { return nil }

        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        var best: (diff: Int, url: URL)? = nil
        var i = 0
        while i < lines.count {
            let line = lines[i]
            if line.hasPrefix("#EXT-X-STREAM-INF"),
               let match = line.range(of: #"RESOLUTION=\d+x(\d+)"#, options: .regularExpression),
               let h = Int(String(line[match]).split(separator: "x").last ?? "") {
                var j = i + 1
                while j < lines.count, lines[j].isEmpty || lines[j].hasPrefix("#") { j += 1 }
                if j < lines.count, let url = URL(string: lines[j], relativeTo: master)?.absoluteURL {
                    let diff = abs(h - height)
                    if best == nil || diff < best!.diff { best = (diff, url) }
                }
                i = j
            }
            i += 1
        }
        return best?.url
    }

    private func kickPlayback() {
        webView?.evaluateJavaScript(
            "(() => { const v = document.getElementById('v'); if (v && v.paused) { v.muted = false; v.play(); } })()",
            completionHandler: nil
        )
    }

    /// Minimal native-HLS page: a full-bleed `<video>` with system controls
    /// (which include volume and Picture-in-Picture on macOS) and a plain
    /// off-air message if the publish point errors.
    private static func playerHTML(stream: URL) -> String {
        """
        <!doctype html><html><head><meta charset="utf-8"><style>
          html,body{margin:0;height:100%;background:#0d0d12;overflow:hidden}
          video{width:100%;height:100%;object-fit:contain;background:#000}
          #err{position:absolute;inset:0;display:none;align-items:center;justify-content:center;
               color:#9a9aa2;font:13px -apple-system,sans-serif;text-align:center;padding:0 32px;line-height:1.5;cursor:pointer}
        </style></head><body>
        <video id="v" src="\(stream.absoluteString)" autoplay playsinline controls></video>
        <div id="err">TVRI’s stream isn’t answering right now.<br>
        The channel may be off-air — click here to retry, or pick another channel from the titlebar.</div>
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
