import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// One deck's UI: file picker → display → transport → EQ + filter + volume knobs.
struct DeckView: View {
    @ObservedObject var state: DeckState
    var deckNumber: Int
    var tint: Color
    var onLoad: (URL) -> Void
    var onTogglePlay: () -> Void
    var hasMaster: Bool
    var onSync: () -> Void
    var onToggleMaster: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("DECK \(deckNumber)")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .tracking(2)
                    .foregroundColor(tint)
                Spacer()
                if state.isLoaded {
                    Text(timeString(state.currentTimeSeconds) + " / " + timeString(state.durationSeconds))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.white.opacity(0.5))
                }
            }

            Text(state.displayName)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white)
                .lineLimit(1)

            HStack {
                if state.bpm > 0 {
                    Text(String(format: "%.1f BPM", state.bpm))
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundColor(tint)
                } else if state.isLoaded {
                    Text("analyzing…")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.white.opacity(0.4))
                }
                Spacer()
            }

            ZStack {
                WaveformView(
                    peaks: state.peaks,
                    progress: state.durationSeconds > 0 ? state.currentTimeSeconds / state.durationSeconds : 0,
                    tint: tint
                )
                BeatGridOverlay(
                    bpm: state.bpm,
                    duration: state.durationSeconds,
                    firstBeat: $state.firstBeat,
                    tint: tint
                )
            }
            .frame(height: 50)

            SyncControlsView(
                state: state,
                tint: tint,
                hasMaster: hasMaster,
                onSync: onSync,
                onToggleMaster: onToggleMaster
            )

            HStack(spacing: 8) {
                Button(action: pickFile) {
                    Image(systemName: "folder")
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .background(Color.white.opacity(0.05))
                .cornerRadius(4)

                Button(action: onTogglePlay) {
                    Image(systemName: state.isPlaying ? "pause.fill" : "play.fill")
                        .frame(width: 28, height: 28)
                        .foregroundColor(state.isPlaying ? tint : .white.opacity(0.7))
                }
                .disabled(!state.isLoaded)
                .buttonStyle(.plain)
                .background(Color.white.opacity(0.05))
                .cornerRadius(4)

                Spacer()
            }

            HStack(spacing: 10) {
                KnobView(value: $state.highGain, range: -24...24, defaultValue: 0,
                         label: "HI", tint: tint)
                KnobView(value: $state.midGain, range: -24...24, defaultValue: 0,
                         label: "MID", tint: tint)
                KnobView(value: $state.lowGain, range: -24...24, defaultValue: 0,
                         label: "LO", tint: tint)
                KnobView(value: $state.filter, range: -1...1, defaultValue: 0,
                         label: "FILT", tint: .purple)
                KnobView(value: $state.volume, range: 0...1.5, defaultValue: 1.0,
                         label: "VOL", tint: tint)
                TempoSliderView(rate: $state.tempoRate, tint: tint)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(white: 0.06))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.08), lineWidth: 1))
        .cornerRadius(8)
    }

    private func pickFile() {
        let panel = NSOpenPanel()
        panel.title = "Load track on Deck \(deckNumber)"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.audio]
        if panel.runModal() == .OK, let url = panel.url {
            onLoad(url)
        }
    }

    private func timeString(_ seconds: Double) -> String {
        let s = Int(seconds)
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}
