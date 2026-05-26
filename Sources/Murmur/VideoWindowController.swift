import AppKit
import Combine
import SwiftUI

// MARK: - Hover + drag overlay views (used by VideoWindowController)

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

/// Transparent overlay that sits on top of the WKWebView so the entire video
/// surface drags the window. WKWebView captures mouseDown by default, which
/// defeats `isMovableByWindowBackground` on its own — this view explicitly
/// calls `window.performDrag(with:)` because WebKit's event dispatch can
/// swallow the mouseDown before AppKit consults the movable-by-background flag.
final class WindowDragOverlay: NSView {
    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }
}

// MARK: - Video window
//
// Owns the single NSWindow that the WKWebView lives in. The webview must always
// be inside a real window or WebKit suspends media — so when the user wants
// "audio only", the window stays parked at -3000,-3000 with a borderless mask.
// When the user toggles the video on, we change the styleMask to a normal
// titled/resizable window, lift it on-screen at .floating level, and lock its
// content to 16:9 so the YouTube iframe never letterboxes.
/// Window aspect-ratio mode. `.landscape` is the default 16:9 (regular YouTube
/// videos, long-form C-dramas). `.portrait` flips to 9:16 for vertical content
/// (YouTube Shorts, ReelShort-style mini-dramas). Affects content aspect lock,
/// min size, default frame, and the restored frame after exit-fullscreen.
enum VideoOrientation: String {
    case landscape
    case portrait

    var aspect: NSSize {
        switch self {
        case .landscape: return NSSize(width: 16, height: 9)
        case .portrait:  return NSSize(width: 9, height: 16)
        }
    }

    var minSize: NSSize {
        switch self {
        case .landscape: return NSSize(width: 240, height: 135)
        case .portrait:  return NSSize(width: 180, height: 320)
        }
    }

    var defaultContentSize: NSSize {
        switch self {
        case .landscape: return NSSize(width: 480, height: 270)
        case .portrait:  return NSSize(width: 360, height: 640)
        }
    }
}

final class VideoWindowController: NSObject, ObservableObject, NSWindowDelegate {
    @Published var isVisible: Bool = false
    /// When true, the window is set to `.canJoinAllSpaces` so it stays visible
    /// as the user switches Spaces (Mission Control desktops). Default off so
    /// the window behaves like a normal floating panel; persisted across
    /// launches under `youtube-audio-widget.videoWindow.pinned`.
    @Published private(set) var isPinned: Bool = false
    /// True while the window is in macOS native full-screen. Driven by the
    /// `windowDid{Enter,Exit}FullScreen` delegate callbacks so the HUD icon
    /// reflects the system state even if the user used Esc or green button.
    @Published private(set) var isFullScreen: Bool = false
    /// Current aspect-ratio lock. Persisted under
    /// `youtube-audio-widget.videoWindow.orientation`.
    @Published private(set) var orientation: VideoOrientation = .landscape
    private static let pinnedDefaultsKey = "youtube-audio-widget.videoWindow.pinned"
    private static let orientationDefaultsKey = "youtube-audio-widget.videoWindow.orientation"
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
        // Keep the chromeless titled style for the window's whole life. The
        // titled+fullSizeContentView combo (hidden buttons, transparent
        // titlebar) is what gives the resizable/draggable-but-chromeless look;
        // we used to swap to `.borderless` while parked off-screen and back to
        // titled on every show, but that styleMask swap reparents the hosted
        // WKWebView and forces a WebKit relayout — the visible flash on toggle.
        // Parked windows are simply moved to (-3000,-3000) and `orderOut`, so
        // the titlebar is never on screen anyway.
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 270),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true   // drag from anywhere, not just the title strip
        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true

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
        // Briefly order in then back out so the WKWebView attaches and
        // WebKit initializes its media session against a real window — the
        // CLAUDE.md note about "detached views suspend playback" applies at
        // first attach, not at every visibility toggle. `orderOut` keeps the
        // window/view binding intact so audio continues playing, but
        // removes the window from Mission Control / App Exposé / Spaces
        // gathering (which was rendering the off-screen ghost as a blank
        // screen on a three-finger swipe up).
        window.orderBack(nil)
        window.orderOut(nil)
        super.init()
        window.delegate = self

        // Restore pin preference (default off if unset) and apply to the window
        // when the user toggles video on. While hidden, collectionBehavior is
        // cleared so the parked window doesn't appear in any Spaces gathering.
        isPinned = UserDefaults.standard.bool(forKey: Self.pinnedDefaultsKey)
        applyCollectionBehavior()
        if let raw = UserDefaults.standard.string(forKey: Self.orientationDefaultsKey),
           let saved = VideoOrientation(rawValue: raw) {
            orientation = saved
        }

        // Mount the SwiftUI HUD inside the visual-effect container. The HUD
        // holds an @ObservedObject reference to self so its pin button stays
        // in sync with `isPinned` and its close button calls `setVisible(false)`.
        let hudView = VideoControlsHUD(controller: controller, videoWindow: self, clock: controller.clock)
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

    func togglePinned() { setPinned(!isPinned) }

    func toggleOrientation() {
        setOrientation(orientation == .landscape ? .portrait : .landscape)
    }

    /// Swap aspect-ratio lock. Done in this exact order to avoid the
    /// content-aspect clamp fighting the resize:
    ///   1. clear the aspect lock,
    ///   2. update min size + content size,
    ///   3. re-apply the new aspect.
    /// The current frame's longer edge is preserved so the user doesn't end
    /// up with a window much smaller (or bigger) than what they had.
    func setOrientation(_ newOrientation: VideoOrientation) {
        guard newOrientation != orientation else { return }
        orientation = newOrientation
        UserDefaults.standard.set(newOrientation.rawValue, forKey: Self.orientationDefaultsKey)

        guard isVisible, !isFullScreen else { return }

        let current = window.frame
        window.contentAspectRatio = NSSize(width: 0, height: 0)
        window.minSize = newOrientation.minSize

        let aspect = newOrientation.aspect
        let aspectRatio = aspect.width / aspect.height
        // Preserve the larger of current width/height as the new "long edge"
        // so the window stays roughly the same visual size.
        let longEdge = max(current.width, current.height)
        let newSize: NSSize
        switch newOrientation {
        case .landscape:
            newSize = NSSize(width: longEdge, height: longEdge / aspectRatio)
        case .portrait:
            newSize = NSSize(width: longEdge * aspectRatio, height: longEdge)
        }
        // Re-anchor around the current center so the window doesn't jump.
        let newOrigin = NSPoint(
            x: current.midX - newSize.width / 2,
            y: current.midY - newSize.height / 2
        )
        window.setFrame(NSRect(origin: newOrigin, size: newSize), display: true, animate: true)
        window.contentAspectRatio = aspect
    }

    /// Enter or exit a borderless full-screen on the window's current screen.
    /// We deliberately avoid AppKit's native `toggleFullScreen(_:)` because
    /// it creates a dedicated Space, and for `.accessory` (menubar-only) apps
    /// the exit transition can leave the window deactivated or stranded on a
    /// non-current Space — the user perceives the app as closed.
    ///
    /// Manual fullscreen: stash the current frame and 16:9 aspect lock, drop
    /// the window's resize increments, lift it above the menu bar, and snap
    /// to `screen.frame`. Exit restores everything. The WKWebView stays
    /// attached to the same window throughout, so audio never glitches.
    func toggleFullScreen() {
        guard isVisible else { return }
        if isFullScreen {
            exitManualFullScreen()
        } else {
            enterManualFullScreen()
        }
    }

    private var preFullScreenFrame: NSRect?
    private var preFullScreenLevel: NSWindow.Level?
    private var preFullScreenStyleMask: NSWindow.StyleMask?
    private var preFullScreenMinSize: NSSize?

    private func enterManualFullScreen() {
        guard let screen = window.screen ?? NSScreen.main else { return }
        preFullScreenFrame = window.frame
        preFullScreenLevel = window.level
        preFullScreenStyleMask = window.styleMask
        preFullScreenMinSize = window.minSize

        // Clear all sizing constraints BEFORE the frame change. The 16:9
        // `contentAspectRatio` would otherwise clamp `setFrame(screen.frame)`
        // back to a 16:9 letterbox; the 240×135 `minSize` is fine but
        // tidiest to drop here too.
        window.contentAspectRatio = NSSize(width: 0, height: 0)
        window.resizeIncrements = NSSize(width: 1, height: 1)
        window.minSize = NSSize(width: 1, height: 1)

        // Switch to borderless so there's no titlebar competing with the
        // menu bar — the existing CLAUDE.md contract already documents
        // swapping styleMask between borderless and titled at runtime.
        window.styleMask = [.borderless, .resizable]
        window.setFrame(screen.frame, display: true)
        // `.popUpMenu` (101) sits above `.statusBar` (25, the menu bar's
        // level), so the video covers the menu bar. `CGShieldingWindowLevel`
        // is too aggressive — it blocks system overlays (volume, brightness).
        window.level = .popUpMenu
        window.makeKeyAndOrderFront(nil)

        isFullScreen = true
    }

    private func exitManualFullScreen() {
        window.level = preFullScreenLevel ?? .floating

        if let mask = preFullScreenStyleMask {
            window.styleMask = mask
            // Re-apply the chromeless titlebar setup that the original
            // `setVisible(true)` configured.
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isMovableByWindowBackground = true
            window.standardWindowButton(.closeButton)?.isHidden = true
            window.standardWindowButton(.miniaturizeButton)?.isHidden = true
            window.standardWindowButton(.zoomButton)?.isHidden = true
        }

        window.minSize = preFullScreenMinSize ?? orientation.minSize
        window.contentAspectRatio = orientation.aspect

        if let frame = preFullScreenFrame {
            window.setFrame(frame, display: true, animate: true)
        }

        preFullScreenFrame = nil
        preFullScreenLevel = nil
        preFullScreenStyleMask = nil
        preFullScreenMinSize = nil
        isFullScreen = false
    }

    func setPinned(_ pinned: Bool) {
        guard pinned != isPinned else { return }
        isPinned = pinned
        UserDefaults.standard.set(pinned, forKey: Self.pinnedDefaultsKey)
        applyCollectionBehavior()
    }

    /// Pinned: window joins every Space and stays put when the user switches
    /// desktops via Mission Control (and follows into full-screen apps via
    /// `.fullScreenAuxiliary`). Unpinned: default behavior — visible only on
    /// the Space it was created on.
    ///
    /// While the window is parked off-screen at (-3000, -3000) — the "audio
    /// only" state — we deliberately clear the collection behavior. Leaving
    /// `.fullScreenAuxiliary` set on the parked ghost was making Mission
    /// Control / App Exposé treat the off-screen window as a utility palette
    /// in fullscreen Spaces; gesture-triggered window gathering then
    /// rendered other apps' windows incorrectly or hid them. With an empty
    /// `collectionBehavior` while parked, the window stays alive (WebKit
    /// needs the host NSWindow to keep audio playing) but it no longer
    /// participates in any window-management gesture.
    private func applyCollectionBehavior() {
        if !isVisible {
            window.collectionBehavior = []
            return
        }
        if isPinned {
            window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        } else {
            window.collectionBehavior = [.fullScreenAuxiliary]
        }
    }

    func setVisible(_ visible: Bool) {
        guard visible != isVisible else { return }
        // Close button in fullscreen should restore to windowed before
        // hiding so the user lands back in a normal floating window next
        // time they reopen the video.
        if !visible && isFullScreen {
            exitManualFullScreen()
        }
        isVisible = visible
        if visible {
            // styleMask + chromeless config are set once in init and never
            // swapped (see the note there) — here we only re-apply the aspect
            // lock for the current orientation, lift the window on-screen, and
            // order it front. No `NSApp.activate(ignoringOtherApps:)`: the
            // toggle is driven from Murmur's own panel, so the app is already
            // active, and activating yanked focus from the frontmost app for
            // no benefit (the window is `.floating` and orders above anyway).
            window.contentAspectRatio = orientation.aspect
            window.minSize = orientation.minSize
            window.level = .floating
            if let f = savedFrame {
                window.setFrame(f, display: true)
            } else {
                window.setContentSize(orientation.defaultContentSize)
                window.center()
            }
            applyCollectionBehavior()
            window.makeKeyAndOrderFront(nil)
        } else {
            savedFrame = window.frame
            window.level = .normal
            window.setFrameOrigin(NSPoint(x: -3000, y: -3000))
            applyCollectionBehavior()
            // `orderOut` instead of `orderBack` so Mission Control / App
            // Exposé / three-finger-swipe-up never see this window at all.
            // The off-screen-but-orderedBack ghost was apparently confusing
            // macOS's window gathering — Mission Control collapsed to a
            // blank desktop when invoked while Murmur was running. The
            // WKWebView keeps the audio session alive as long as the view
            // is attached to its host NSWindow (which `orderOut` preserves;
            // only the window's appearance in the on-screen list changes).
            window.orderOut(nil)
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
