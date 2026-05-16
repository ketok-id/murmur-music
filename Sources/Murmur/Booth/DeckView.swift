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
    var onSetOrJumpCue: (Int) -> Void
    var onDeleteCue: (Int) -> Void
    var onSetLoopIn: () -> Void
    var onSetLoopOut: () -> Void
    var onHalveLoop: () -> Void
    var onDoubleLoop: () -> Void
    var onToggleLoop: () -> Void
    var onScrubBegan: () -> Void
    var onScrub: (Double) -> Void
    var onScrubEnded: () -> Void

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

            HStack(alignment: .center, spacing: 14) {
                JogWheelView(
                    state: state,
                    tint: tint,
                    size: 96,
                    onScrubBegan: onScrubBegan,
                    onScrub: onScrub,
                    onScrubEnded: onScrubEnded
                )
                VStack(alignment: .leading, spacing: 4) {
                    Text(displayTitle)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    if !state.artist.isEmpty {
                        Text(state.artist)
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.6))
                            .lineLimit(1)
                    }
                    if !state.album.isEmpty {
                        Text(state.album)
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.4))
                            .lineLimit(1)
                    }
                }
                Spacer()
            }
            .frame(height: 100)

            HStack(spacing: 12) {
                if state.bpm > 0 {
                    Text(String(format: "%.1f BPM", state.bpm))
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundColor(tint)
                } else if state.isLoaded {
                    Text("analyzing…")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.white.opacity(0.4))
                }
                if !state.keyName.isEmpty {
                    Text("\(state.keyName)  ·  \(state.camelot)")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundColor(.yellow.opacity(0.85))
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
                CueAndLoopOverlay(
                    hotCues: state.hotCues,
                    loop: state.loop,
                    duration: state.durationSeconds,
                    loopTint: tint
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

            HotCuePadsView(
                hotCues: state.hotCues,
                onSetOrJump: onSetOrJumpCue,
                onDelete: onDeleteCue
            )

            LoopControlsView(
                loop: state.loop,
                tint: tint,
                onSetIn: onSetLoopIn,
                onSetOut: onSetLoopOut,
                onHalve: onHalveLoop,
                onDouble: onDoubleLoop,
                onToggle: onToggleLoop
            )

            FXControlsView(state: state, tint: tint)

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

            HStack(spacing: 8) {
                KnobView(value: $state.highGain, range: -24...24, defaultValue: 0,
                         label: "HI", tint: tint, diameter: 36)
                KnobView(value: $state.midGain, range: -24...24, defaultValue: 0,
                         label: "MID", tint: tint, diameter: 36)
                KnobView(value: $state.lowGain, range: -24...24, defaultValue: 0,
                         label: "LO", tint: tint, diameter: 36)
                KnobView(value: $state.filter, range: -1...1, defaultValue: 0,
                         label: "FILT", tint: .purple, diameter: 36)
                KnobView(value: $state.volume, range: 0...1.5, defaultValue: 1.0,
                         label: "VOL", tint: tint, diameter: 36)
                TempoSliderView(rate: $state.tempoRate, tint: tint)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(white: 0.06))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.08), lineWidth: 1))
        .cornerRadius(8)
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url = url else { return }
                DispatchQueue.main.async {
                    onLoad(url)
                }
            }
            return true
        }
    }

    private var displayTitle: String {
        if !state.title.isEmpty { return state.title }
        return state.displayName
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
