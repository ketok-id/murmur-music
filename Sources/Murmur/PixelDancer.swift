import SwiftUI

// MARK: - Cassette
//
// Pixel-art cassette tape rendered procedurally on a Canvas. The reels spin
// while audio is playing and freeze the moment it's paused. Volume modulates
// the rotation speed (very subtly — a real cassette doesn't speed up).
// The play / pause button is overlaid in the gap between the two reels so
// the cassette doubles as the transport control.

struct CassetteTape: View {
    @ObservedObject var controller: PlayerController
    @ObservedObject private var playlist = PlaylistStore.shared
    @ObservedObject private var queue = PlaybackQueue.shared
    @ObservedObject private var trending = TrendingRegionStore.shared
    @ObservedObject private var userPlaylists = UserPlaylistsStore.shared

    private static let onColor   = Color(red: 0.96, green: 0.65, blue: 0.45)   // peach (playing)
    private static let idleColor = Color(red: 0.91, green: 0.87, blue: 0.78)   // cream (paused)
    private static let dimColor  = Color(red: 0.91, green: 0.87, blue: 0.78).opacity(0.30)
    private static let bgColor   = Color(red: 0.05, green: 0.05, blue: 0.06)   // matches popover background

    var body: some View {
        GeometryReader { geo in
            ZStack {
                TimelineView(.animation(paused: !controller.isPlaying)) { context in
                    Canvas { ctx, size in
                        draw(in: ctx, size: size, time: context.date.timeIntervalSinceReferenceDate)
                    }
                }
                labelOverlay(geo: geo)
                transportControls(geo: geo)
            }
        }
        .aspectRatio(2.4, contentMode: .fit)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Cassette label (title + context)

    /// Overlay positioned inside the cassette's drawn label rectangle. Houses
    /// the now-playing title (marquee'd when overflowing) and an optional
    /// context line (playlist name + index). Geometry mirrors the rect drawn
    /// in `draw(in:size:time:)` so they stay aligned at any size.
    private func labelOverlay(geo: GeometryProxy) -> some View {
        let inset: CGFloat = 1.5
        let bodyWidth = geo.size.width - inset * 2
        let bodyHeight = geo.size.height - inset * 2
        let labelMinX = inset + 10
        let labelMinY = inset + 8
        let labelWidth = bodyWidth - 20
        let labelHeight = bodyHeight * 0.28
        let textPad: CGFloat = 5
        let titleColor = controller.isPlaying ? Self.onColor : Self.idleColor

        return VStack(alignment: .leading, spacing: 1) {
            MarqueeText(
                text: displayTitle,
                font: .system(size: max(8, labelHeight * 0.32), weight: .semibold, design: .monospaced),
                foregroundColor: titleColor
            )
            if let sub = subtitleText {
                Text(sub)
                    .font(.system(size: max(7, labelHeight * 0.22), weight: .regular, design: .monospaced))
                    .foregroundColor(Self.dimColor)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(width: labelWidth - textPad * 2,
               height: labelHeight - textPad,
               alignment: .leading)
        .position(x: labelMinX + labelWidth / 2,
                  y: labelMinY + labelHeight / 2)
    }

    private var displayTitle: String {
        let t = controller.title.trimmingCharacters(in: .whitespaces)
        return t.isEmpty ? "Murmur" : t
    }

    private var subtitleText: String? {
        if userPlaylists.hasActivePlaylist,
           let p = userPlaylists.activePlaylist,
           let idx = userPlaylists.activeIndex {
            return "\(p.name) · \(idx + 1)/\(p.items.count)"
        }
        if playlist.hasActivePlaylist {
            let total = playlist.items.count
            if let i = playlist.currentIndex {
                return "playlist · \(i + 1)/\(total)"
            }
            return "playlist · \(total) tracks"
        }
        return nil
    }

    // MARK: - Transport controls overlay

    private var canPlayPrev: Bool {
        playlist.hasActivePlaylist
            && (playlist.currentIndex ?? 0) > 0
    }

    private var canPlayNext: Bool {
        if playlist.hasActivePlaylist,
           let idx = playlist.currentIndex,
           idx + 1 < playlist.items.count {
            return true
        }
        if !queue.isEmpty { return true }
        if trending.autoFillFromTrending { return true }
        return false
    }

    private func transportControls(geo: GeometryProxy) -> some View {
        HStack(spacing: 6) {
            transportButton(symbol: "⏮", enabled: canPlayPrev, action: { controller.playPrev() })
            playButton
            transportButton(symbol: "⏭", enabled: canPlayNext, action: { controller.playNext() })
        }
        .position(x: geo.size.width / 2, y: geo.size.height * 0.62)
    }

    private var playButton: some View {
        let buttonColor: Color = controller.isReady
            ? (controller.isPlaying ? Self.onColor : Self.idleColor)
            : Self.idleColor.opacity(0.45)
        return Button(action: { controller.toggle() }) {
            Text(controller.isPlaying ? "❚❚" : "▶")
                .font(.system(size: 14, weight: .medium, design: .monospaced))
                .foregroundColor(buttonColor)
                .frame(width: 36, height: 26)
                .background(Self.bgColor)
                .overlay(Rectangle().stroke(buttonColor.opacity(0.7),
                                            style: StrokeStyle(lineWidth: 1, dash: [2, 2])))
        }
        .buttonStyle(.plain)
        .disabled(!controller.isReady)
    }

    private func transportButton(symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        let color: Color = enabled ? Self.idleColor : Self.idleColor.opacity(0.30)
        return Button(action: action) {
            Text(symbol)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(color)
                .frame(width: 26, height: 20)
                .background(Self.bgColor)
                .overlay(Rectangle().stroke(color.opacity(0.6),
                                            style: StrokeStyle(lineWidth: 1, dash: [2, 2])))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    // MARK: - Cassette drawing

    private func draw(in ctx: GraphicsContext, size: CGSize, time: TimeInterval) {
        let color = controller.isPlaying ? Self.onColor : Self.idleColor
        let dim   = color.opacity(0.45)

        // Cassette body
        let inset: CGFloat = 1.5
        let body = CGRect(x: inset, y: inset,
                          width: size.width - inset * 2,
                          height: size.height - inset * 2)
        ctx.stroke(Path(roundedRect: body, cornerRadius: 8), with: .color(color), lineWidth: 1.6)

        // Top label area — outline only; the live title + context lines are
        // rendered as a SwiftUI overlay on top (`labelOverlay`), aligned to
        // the same rect, so they replace what used to be hand-drawn ruling
        // lines and feel like writing on a real cassette label.
        let labelRect = CGRect(
            x: body.minX + 10, y: body.minY + 8,
            width: body.width - 20, height: body.height * 0.28
        )
        ctx.stroke(Path(roundedRect: labelRect, cornerRadius: 2), with: .color(dim), lineWidth: 1)

        // Reels
        let reelRadius = body.height * 0.20
        let reelY      = body.minY + body.height * 0.62
        let reelXLeft  = body.minX + body.width * 0.22
        let reelXRight = body.minX + body.width * 0.78

        // Tape strand drawn first so reels paint over its endpoints
        let tapeY = reelY - reelRadius - 2
        ctx.stroke(linePath(x1: reelXLeft, y1: tapeY, x2: reelXRight, y2: tapeY),
                   with: .color(dim), lineWidth: 0.9)

        // Slow rotation: ~5.5s/rev at vol 0, ~2.8s/rev at vol 100. Real cassettes
        // turn slowly — bumping speed with volume is just a tiny morale boost.
        let speed = 0.18 + (controller.volume / 100.0) * 0.17
        let baseAngle = time * speed * 2 * .pi

        for cx in [reelXLeft, reelXRight] {
            drawReel(ctx: ctx, center: CGPoint(x: cx, y: reelY),
                     radius: reelRadius, angle: baseAngle, color: color)
        }

        // Spindle holes (the small openings at the bottom of the cassette)
        let holeY = body.maxY - 6
        let holeR: CGFloat = 1.6
        for cx in [body.minX + body.width * 0.16, body.maxX - body.width * 0.16] {
            ctx.fill(Path(ellipseIn: CGRect(x: cx - holeR, y: holeY - holeR,
                                            width: holeR * 2, height: holeR * 2)),
                     with: .color(dim))
        }
    }

    private func drawReel(ctx: GraphicsContext, center: CGPoint, radius: CGFloat,
                          angle: Double, color: Color) {
        let outer = Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius,
                                           width: radius * 2, height: radius * 2))
        ctx.stroke(outer, with: .color(color), lineWidth: 1.3)

        let hubR: CGFloat = max(2, radius * 0.32)
        let hub = Path(ellipseIn: CGRect(x: center.x - hubR, y: center.y - hubR,
                                         width: hubR * 2, height: hubR * 2))
        ctx.stroke(hub, with: .color(color), lineWidth: 1)

        let spokeCount = 6
        for i in 0..<spokeCount {
            let theta = angle + Double(i) * (2 * .pi / Double(spokeCount))
            let cosT = CGFloat(cos(theta))
            let sinT = CGFloat(sin(theta))
            let inner = CGPoint(x: center.x + cosT * hubR, y: center.y + sinT * hubR)
            let outerPt = CGPoint(x: center.x + cosT * (radius - 0.6),
                                  y: center.y + sinT * (radius - 0.6))
            ctx.stroke(linePath(x1: inner.x, y1: inner.y, x2: outerPt.x, y2: outerPt.y),
                       with: .color(color), lineWidth: 1)
        }
    }

    private func linePath(x1: CGFloat, y1: CGFloat, x2: CGFloat, y2: CGFloat) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: x1, y: y1))
        p.addLine(to: CGPoint(x: x2, y: y2))
        return p
    }
}
