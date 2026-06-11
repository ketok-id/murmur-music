import AppKit
import Combine
import SwiftUI

/// Tiny always-on-top "now playing" pill — thumbnail, marquee title, elapsed
/// time, play/pause/next — parked in a corner while you work. Same
/// non-activating NSPanel recipe as `ScoreboardPanel` (clicking it never
/// steals focus; joins all Spaces incl. full-screen apps).
///
/// `.shared` singleton with the controller injected post-init by AppDelegate
/// (the `SleepTimer` pattern). Visibility persists so the pill comes back on
/// relaunch.
final class MiniPillPanel: NSObject, ObservableObject {
    static let shared = MiniPillPanel()

    private static let visibleKey = "youtube-audio-widget.miniPill.visible"

    /// Injected by AppDelegate before `restoreIfWanted()` runs.
    weak var controller: PlayerController?

    @Published private(set) var visible = false

    private var panel: NSPanel?

    func toggle() { visible ? hide() : show() }

    func show() {
        guard let panel = ensurePanel() else { return }
        panel.orderFrontRegardless()
        visible = true
        UserDefaults.standard.set(true, forKey: Self.visibleKey)
    }

    func hide() {
        panel?.orderOut(nil)
        visible = false
        UserDefaults.standard.set(false, forKey: Self.visibleKey)
    }

    /// Called once at launch, after the controller is injected.
    func restoreIfWanted() {
        if UserDefaults.standard.bool(forKey: Self.visibleKey) { show() }
    }

    private func ensurePanel() -> NSPanel? {
        if let panel { return panel }
        guard let controller else { return nil }

        let p = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 56),
            styleMask: [.titled, .closable, .fullSizeContentView, .nonactivatingPanel, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        p.title = "Murmur"
        p.titleVisibility = .hidden
        p.titlebarAppearsTransparent = true
        p.standardWindowButton(.miniaturizeButton)?.isHidden = true
        p.standardWindowButton(.zoomButton)?.isHidden = true
        p.isReleasedWhenClosed = false
        p.level = .floating
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.isMovableByWindowBackground = true
        p.backgroundColor = .clear
        p.isOpaque = false
        p.hasShadow = true
        p.setFrameAutosaveName("murmur.minipill")
        p.delegate = self

        let host = NSHostingView(rootView: MiniPillView(controller: controller, clock: controller.clock))
        host.frame = p.contentView?.bounds ?? .zero
        host.autoresizingMask = [.width, .height]
        p.contentView?.addSubview(host)

        if p.frame.origin == .zero, let screen = NSScreen.main {
            let f = screen.visibleFrame
            p.setFrameOrigin(NSPoint(x: f.maxX - 340, y: f.minY + 24))
        }
        panel = p
        return p
    }
}

extension MiniPillPanel: NSWindowDelegate {
    /// The titlebar close button hides (and remembers) instead of closing —
    /// the panel object survives for frame persistence.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        hide()
        return false
    }
}

private struct MiniPillView: View {
    @ObservedObject var controller: PlayerController
    @ObservedObject var clock: PlaybackClock

    var body: some View {
        HStack(spacing: 8) {
            AsyncImage(url: URL(string: "https://i.ytimg.com/vi/\(controller.currentVideoID)/mqdefault.jpg")) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Rectangle().fill(Color.white.opacity(0.08))
                    .overlay(Image(systemName: "music.note")
                        .font(.system(size: 9))
                        .foregroundStyle(MurmurColor.textMuted))
            }
            .frame(width: 38, height: 26)
            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))

            VStack(alignment: .leading, spacing: 1) {
                MarqueeText(
                    text: controller.title,
                    font: .system(size: 10, weight: .semibold),
                    foregroundColor: MurmurColor.textPrimary
                )
                .frame(height: 13)
                Text(timeLabel)
                    .font(.system(size: 8, weight: .medium, design: .monospaced))
                    .foregroundStyle(controller.isPlaying ? MurmurColor.accent : MurmurColor.textMuted)
            }

            PillButton(systemName: controller.isPlaying ? "pause.fill" : "play.fill") {
                controller.isPlaying ? controller.pause() : controller.play()
            }
            PillButton(systemName: "forward.fill") { controller.playNext() }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.murmurHex("#101013").opacity(0.96))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(MurmurColor.border.opacity(0.8), lineWidth: 1)
        )
        .padding(6)
    }

    private var timeLabel: String {
        guard clock.duration > 0 else { return controller.isPlaying ? "LIVE" : "paused" }
        return "\(format(clock.currentTime)) / \(format(clock.duration))"
    }

    private func format(_ t: Double) -> String {
        let s = Int(t.rounded())
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec)
                     : String(format: "%d:%02d", m, sec)
    }
}

private struct PillButton: View {
    let systemName: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(hovering ? MurmurColor.accentLight : MurmurColor.textSecondary)
                .frame(width: 22, height: 22)
                .background(Circle().fill(Color.white.opacity(hovering ? 0.10 : 0.05)))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
