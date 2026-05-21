import AppKit
import SwiftUI

/// Single-line text that scrolls horizontally when it overflows its container.
/// If the text fits, it renders statically. Otherwise the same text is drawn
/// twice with a gap and a TimelineView drives a linear offset that loops
/// seamlessly. A short pause at the start of each cycle gives the user time
/// to read the beginning before the scroll kicks in.
///
/// Sizing: the view adopts the natural line height of `font` (because a
/// hidden, naturally-sized Text acts as the layout host) and takes whatever
/// horizontal space the parent grants it.
///
/// Animation is paused while no Murmur window is visible to the user —
/// otherwise Mission Control / Stage Manager would capture the marquee
/// mid-cycle and show garbled wrap-around text in the overview snapshot.
/// Driven by `NSApplication.didResignActiveNotification` / `didBecomeActive`
/// rather than `NSWindow.occlusionState` because the menu-bar panel can
/// stay "visible" (occlusionState == .visible) while Mission Control is up.
struct MarqueeText: View {
    let text: String
    var font: Font = .system(size: 12)
    /// Scroll speed in points per second.
    var speed: CGFloat = 28
    /// Pause (in seconds) at the start of each scroll cycle.
    var startPause: TimeInterval = 1.4
    /// Gap (in points) between the end of the first copy of the text and the
    /// start of the second — wide enough that the seam isn't jarring.
    var gap: CGFloat = 40
    var foregroundColor: Color = .primary

    @State private var textWidth: CGFloat = 0
    @State private var isAppActive: Bool = NSApp?.isActive ?? true

    var body: some View {
        // Hidden host: defines the natural line height. Truncation mode + the
        // outer .clipped() means it won't push the parent layout wider than
        // the available space.
        Text(text)
            .font(font)
            .lineLimit(1)
            .truncationMode(.tail)
            .opacity(0)
            .overlay(
                GeometryReader { proxy in
                    overlayContent(containerWidth: proxy.size.width)
                }
            )
            .clipped()
            .background(
                // Measure the natural (un-truncated) text width so we know
                // whether to scroll. Sits in the background of the host so
                // it doesn't take layout space of its own.
                Text(text)
                    .font(font)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .hidden()
                    .background(
                        GeometryReader { g in
                            Color.clear.preference(key: WidthKey.self, value: g.size.width)
                        }
                    )
                    .onPreferenceChange(WidthKey.self) { textWidth = $0 }
            )
            .onReceive(NotificationCenter.default.publisher(
                for: NSApplication.didBecomeActiveNotification
            )) { _ in isAppActive = true }
            .onReceive(NotificationCenter.default.publisher(
                for: NSApplication.didResignActiveNotification
            )) { _ in isAppActive = false }
    }

    @ViewBuilder
    private func overlayContent(containerWidth: CGFloat) -> some View {
        let needsScroll = textWidth > containerWidth + 0.5 && textWidth > 0
        if needsScroll {
            // `paused: !isAppActive` freezes the timeline (and the marquee
            // offset) whenever the user isn't focused on Murmur — primarily
            // while Mission Control / Stage Manager is up. Without this the
            // overview captures the panel mid-scroll and shows wrap-around
            // junction text in the snapshot ("...AU + KENAL..." → looks
            // garbled). On resume, the timeline picks up from its frozen
            // offset, so a long title doesn't restart on every refocus.
            TimelineView(.animation(paused: !isAppActive)) { timeline in
                scrollingBody(now: timeline.date, containerWidth: containerWidth)
            }
        } else {
            Text(text)
                .font(font)
                .lineLimit(1)
                .foregroundColor(foregroundColor)
                .frame(width: containerWidth, alignment: .leading)
        }
    }

    private func scrollingBody(now: Date, containerWidth: CGFloat) -> some View {
        let elapsed = now.timeIntervalSinceReferenceDate
        let distance = textWidth + gap
        let scrollDuration = max(0.001, TimeInterval(distance / speed))
        let cycle = scrollDuration + startPause
        var phase = elapsed.truncatingRemainder(dividingBy: cycle)
        if phase < 0 { phase += cycle }
        let offset: CGFloat
        if phase < startPause {
            offset = 0
        } else {
            let progress = (phase - startPause) / scrollDuration
            offset = -CGFloat(progress) * distance
        }
        return HStack(spacing: gap) {
            Text(text)
                .font(font)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
            Text(text)
                .font(font)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
        .foregroundColor(foregroundColor)
        .offset(x: offset)
        .frame(width: containerWidth, alignment: .leading)
    }

    private struct WidthKey: PreferenceKey {
        static var defaultValue: CGFloat = 0
        static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
            value = nextValue()
        }
    }
}
