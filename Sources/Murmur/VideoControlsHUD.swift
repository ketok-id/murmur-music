import SwiftUI
import AppKit

/// QuickTime-style HUD overlaid on the floating video window. Native vibrancy
/// background is provided by an NSVisualEffectView mounted around the
/// NSHostingView; this SwiftUI view paints only the controls themselves.
struct VideoControlsHUD: View {
    @ObservedObject var controller: PlayerController
    @ObservedObject var videoWindow: VideoWindowController
    /// Playhead/duration observed separately from `controller` so the frequent
    /// time ticks re-render only this HUD, not the whole menu-bar panel.
    @ObservedObject var clock: PlaybackClock

    @State private var draggingScrubber: Bool = false
    @State private var scrubValue: Double = 0

    var body: some View {
        GeometryReader { proxy in
            // Reference HUD height is 44pt; everything scales relative to that
            // so a larger video gets a larger control bar without going
            // overboard on a 4K-fullscreen window.
            let scale = max(0.85, min(1.6, proxy.size.height / 44))
            HStack(spacing: 12 * scale) {
                playPauseButton(scale: scale)
                timeLabel(elapsed, scale: scale)
                scrubber
                timeLabel(remaining, monospaced: true, scale: scale)
                volumeControl(scale: scale)
                orientationButton(scale: scale)
                pinButton(scale: scale)
                fullScreenButton(scale: scale)
                closeButton(scale: scale)
            }
            .padding(.horizontal, 14 * scale)
            .padding(.vertical, 8 * scale)
            .foregroundColor(.white)
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .center)
        }
    }

    // MARK: - Subviews

    private func playPauseButton(scale: CGFloat) -> some View {
        Button(action: { controller.toggle() }) {
            Image(systemName: controller.isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: 18 * scale, weight: .medium))
                .frame(width: 28 * scale, height: 28 * scale)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(controller.isPlaying ? "Pause" : "Play")
    }

    private var scrubber: some View {
        Slider(
            value: Binding(
                get: { draggingScrubber ? scrubValue : clock.currentTime },
                set: { newValue in
                    scrubValue = newValue
                    draggingScrubber = true
                }
            ),
            in: 0...max(clock.duration, 1),
            onEditingChanged: { editing in
                if !editing {
                    controller.seek(to: scrubValue)
                    draggingScrubber = false
                }
            }
        )
        .controlSize(.small)
        .disabled(clock.duration <= 0)
    }

    private func timeLabel(_ seconds: Double, monospaced: Bool = false, scale: CGFloat) -> some View {
        Text(formatTime(seconds))
            .font(.system(size: 11 * scale, weight: .medium, design: .monospaced))
            .foregroundColor(.white.opacity(0.85))
            .frame(minWidth: 42 * scale, alignment: monospaced ? .trailing : .leading)
    }

    private func volumeControl(scale: CGFloat) -> some View {
        HStack(spacing: 6 * scale) {
            Image(systemName: volumeIcon)
                .font(.system(size: 11 * scale))
                .foregroundColor(.white.opacity(0.85))
                .frame(width: 14 * scale)
            Slider(
                value: Binding(
                    get: { controller.volume },
                    set: { newValue in
                        controller.volume = newValue
                        controller.setVolume(Int(newValue))
                    }
                ),
                in: 0...100
            )
            .controlSize(.small)
            .frame(width: 70 * scale)
        }
    }

    private func pinButton(scale: CGFloat) -> some View {
        Button(action: { videoWindow.togglePinned() }) {
            Image(systemName: videoWindow.isPinned ? "pin.fill" : "pin")
                .rotationEffect(.degrees(videoWindow.isPinned ? 0 : 45))
                .font(.system(size: 12 * scale, weight: .medium))
                .frame(width: 22 * scale, height: 22 * scale)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(videoWindow.isPinned
              ? "Pinned: follows you across Spaces — click to unpin"
              : "Pin to all Spaces")
    }

    private func orientationButton(scale: CGFloat) -> some View {
        Button(action: { videoWindow.toggleOrientation() }) {
            Image(systemName: videoWindow.orientation == .landscape
                  ? "rectangle.portrait"
                  : "rectangle")
                .font(.system(size: 12 * scale, weight: .medium))
                .frame(width: 22 * scale, height: 22 * scale)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(videoWindow.orientation == .landscape
              ? "Switch to portrait (9:16)"
              : "Switch to landscape (16:9)")
    }

    private func fullScreenButton(scale: CGFloat) -> some View {
        Button(action: { videoWindow.toggleFullScreen() }) {
            Image(systemName: videoWindow.isFullScreen
                  ? "arrow.down.right.and.arrow.up.left"
                  : "arrow.up.left.and.arrow.down.right")
                .font(.system(size: 12 * scale, weight: .medium))
                .frame(width: 22 * scale, height: 22 * scale)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(videoWindow.isFullScreen ? "Exit full screen" : "Enter full screen")
    }

    private func closeButton(scale: CGFloat) -> some View {
        Button(action: { videoWindow.setVisible(false) }) {
            Image(systemName: "xmark")
                .font(.system(size: 11 * scale, weight: .bold))
                .frame(width: 22 * scale, height: 22 * scale)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Hide video window")
    }

    // MARK: - Derived values

    private var elapsed: Double {
        draggingScrubber ? scrubValue : clock.currentTime
    }

    private var remaining: Double {
        guard clock.duration > 0 else { return 0 }
        return max(0, clock.duration - elapsed)
    }

    private var volumeIcon: String {
        switch controller.volume {
        case 0:        return "speaker.slash.fill"
        case ..<33:    return "speaker.fill"
        case ..<66:    return "speaker.wave.1.fill"
        default:       return "speaker.wave.2.fill"
        }
    }

    private func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        } else {
            return String(format: "%d:%02d", m, s)
        }
    }
}
