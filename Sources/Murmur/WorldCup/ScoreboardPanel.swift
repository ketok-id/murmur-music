import AppKit
import SwiftUI

/// Tiny always-on-top scoreboard — live matches only, parked in a corner
/// while you work. A non-activating NSPanel so clicking it never steals
/// focus from the frontmost app; joins all Spaces (incl. full-screen apps)
/// the same way the pinned video window does.
final class ScoreboardPanel {
    static let shared = ScoreboardPanel()

    private var panel: NSPanel?

    var isVisible: Bool { panel?.isVisible ?? false }

    func toggle() { isVisible ? hide() : show() }

    func show() {
        let panel = ensurePanel()
        panel.orderFrontRegardless()
    }

    func hide() { panel?.orderOut(nil) }

    private func ensurePanel() -> NSPanel {
        if let panel { return panel }

        let p = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 240, height: 120),
            styleMask: [.titled, .closable, .fullSizeContentView, .nonactivatingPanel, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        p.title = "Scores"
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
        p.setFrameAutosaveName("murmur.worldcup.scoreboard")

        let host = NSHostingView(rootView: ScoreboardView())
        host.frame = p.contentView?.bounds ?? .zero
        host.autoresizingMask = [.width, .height]
        p.contentView?.addSubview(host)

        if p.frame.origin == .zero {
            // Default to the top-right corner of the main screen.
            if let screen = NSScreen.main {
                let f = screen.visibleFrame
                p.setFrameOrigin(NSPoint(x: f.maxX - 260, y: f.maxY - 140))
            }
        }
        panel = p
        return p
    }
}

/// Content: live matches as compact rows; otherwise the next kickoff.
private struct ScoreboardView: View {
    @ObservedObject private var store = WorldCupStore.shared

    private var live: [WorldCupMatch] { store.matches.filter { $0.state == .live } }
    private var nextUp: WorldCupMatch? {
        store.matches.filter { $0.state == .scheduled && $0.date > Date() }
            .min { $0.date < $1.date }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                Image(systemName: "soccerball")
                    .font(.system(size: 9))
                    .foregroundStyle(MurmurColor.accent)
                Text("WORLD CUP")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .tracking(1.2)
                    .foregroundStyle(MurmurColor.textMuted)
                Spacer()
            }
            if live.isEmpty {
                if let next = nextUp {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(next.home.abbrev) vs \(next.away.abbrev)")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(MurmurColor.textPrimary)
                        Text("kicks off " + Self.kickoff.string(from: next.date))
                            .font(.system(size: 9))
                            .foregroundStyle(MurmurColor.textSecondary)
                    }
                } else {
                    Text("No matches today")
                        .font(.system(size: 10))
                        .foregroundStyle(MurmurColor.textMuted)
                }
            } else {
                ForEach(live) { match in
                    HStack(spacing: 6) {
                        Circle().fill(Color.red).frame(width: 5, height: 5)
                        Text("\(match.home.abbrev) \(match.home.score ?? "0")–\(match.away.score ?? "0") \(match.away.abbrev)")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundStyle(MurmurColor.textPrimary)
                        Spacer()
                        Text(match.clock.isEmpty ? "LIVE" : match.clock)
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Color.red.opacity(0.9))
                    }
                }
            }
        }
        .padding(10)
        .frame(minWidth: 220, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.murmurHex("#101013").opacity(0.96))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(MurmurColor.border.opacity(0.8), lineWidth: 1)
        )
        .padding(6)
    }

    private static let kickoff: DateFormatter = {
        let f = DateFormatter()
        f.timeStyle = .short
        f.dateStyle = .none
        return f
    }()
}
