import AppKit
import SwiftUI

/// A circular platter that rotates at the deck's beat rate, with album art
/// on its center label, a beat-pulse halo ring, and a subtle 3D tilt.
///
/// Rotation rate: one revolution per bar (4 beats) — a deliberate slow rate
/// that reads as "playing" without being dizzying.
struct JogWheelView: View {
    @ObservedObject var state: DeckState
    var tint: Color = .cyan
    var size: CGFloat = 100

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            let now = timeline.date.timeIntervalSinceReferenceDate
            let rotation = currentRotation(at: now)
            let pulse = beatPulse(at: now)

            ZStack {
                // Halo ring (audio-reactive on beat).
                Circle()
                    .stroke(tint, lineWidth: 2)
                    .blur(radius: 1.5)
                    .opacity(0.25 + 0.55 * pulse)
                    .scaleEffect(1.0 + 0.04 * pulse)

                // Platter base.
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color(white: 0.18), Color(white: 0.05)],
                            center: .center, startRadius: size * 0.05, endRadius: size * 0.55
                        )
                    )
                    .overlay(
                        Circle().stroke(Color.white.opacity(0.08), lineWidth: 1)
                    )

                // Grooves — concentric rings that imply vinyl.
                ForEach(0..<6, id: \.self) { i in
                    Circle()
                        .stroke(Color.white.opacity(0.04), lineWidth: 0.5)
                        .frame(width: size * (0.55 + CGFloat(i) * 0.07),
                               height: size * (0.55 + CGFloat(i) * 0.07))
                }

                // Album art on the center label.
                centerLabel
                    .rotationEffect(.radians(rotation))

                // Cue marker — a tiny notch at the top of the platter (does NOT rotate).
                Circle()
                    .fill(tint)
                    .frame(width: 4, height: 4)
                    .shadow(color: tint.opacity(0.8), radius: 2)
                    .offset(y: -size * 0.46)
            }
            .frame(width: size, height: size)
            .rotation3DEffect(.degrees(18), axis: (x: 1, y: 0, z: 0), perspective: 0.6)
            .shadow(color: .black.opacity(0.6), radius: 10, x: 0, y: 4)
        }
    }

    /// Album art on the platter's center, sized to ~45% of platter diameter,
    /// with a small dark ring around it.
    private var centerLabel: some View {
        let labelSize = size * 0.45
        return ZStack {
            Group {
                if let img = loadArtwork() {
                    Image(nsImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    LinearGradient(
                        colors: [tint.opacity(0.4), Color(white: 0.1)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                    .overlay(
                        Image(systemName: "music.note")
                            .font(.system(size: labelSize * 0.4))
                            .foregroundColor(.white.opacity(0.4))
                    )
                }
            }
            .frame(width: labelSize, height: labelSize)
            .clipShape(Circle())
            .overlay(Circle().stroke(Color.white.opacity(0.15), lineWidth: 1))
            .overlay(
                // Spindle hole.
                Circle().fill(Color.black)
                    .frame(width: labelSize * 0.08, height: labelSize * 0.08)
            )
        }
    }

    /// Current rotation angle in radians.
    private func currentRotation(at wallTime: Double) -> Double {
        guard state.bpm > 0 else { return 0 }
        return rotation(forPlayhead: state.currentTimeSeconds)
    }

    private func rotation(forPlayhead t: Double) -> Double {
        let effectiveBPM = state.bpm * Double(state.tempoRate)
        let beatsPerSecond = effectiveBPM / 60.0
        // 1 revolution per 4 beats.
        return t * (beatsPerSecond / 4.0) * (2 * .pi)
    }

    /// Beat-pulse intensity 0…1, peaking on each beat and decaying.
    private func beatPulse(at wallTime: Double) -> Double {
        guard state.bpm > 0, state.isPlaying else { return 0 }
        let effectiveBPM = state.bpm * Double(state.tempoRate)
        let beatInterval = 60.0 / effectiveBPM
        let offsetFromFirst = state.currentTimeSeconds - state.firstBeat
        let phase = (offsetFromFirst / beatInterval).truncatingRemainder(dividingBy: 1)
        let phaseInBeat = phase < 0 ? phase + 1 : phase
        let decay = max(0, 1.0 - phaseInBeat * 20.0)
        return decay
    }

    private func loadArtwork() -> NSImage? {
        guard !state.artworkPath.isEmpty else { return nil }
        let url = LibraryIndex.artworkDirectory.appendingPathComponent(state.artworkPath)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return NSImage(contentsOf: url)
    }
}
