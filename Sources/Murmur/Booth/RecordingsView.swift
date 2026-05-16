import SwiftUI

/// Lists recorded WAV files with per-row play/pause + delete.
struct RecordingsView: View {
    @ObservedObject var store: RecordingsStore
    @ObservedObject var player: RecordingPlayer

    @State private var deleteCandidate: Recording? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().background(Color.white.opacity(0.06))
            if store.recordings.isEmpty {
                emptyState
            } else {
                List {
                    ForEach(store.recordings) { rec in
                        row(rec)
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .frame(minWidth: 460, minHeight: 360)
        .background(Color(white: 0.04))
        .alert(item: $deleteCandidate) { rec in
            Alert(
                title: Text("Delete recording?"),
                message: Text("\(rec.url.lastPathComponent) — \(rec.sizeLabel)"),
                primaryButton: .destructive(Text("Delete")) {
                    if player.isLoaded(rec) { player.stop() }
                    store.delete(rec)
                },
                secondaryButton: .cancel()
            )
        }
    }

    private var header: some View {
        HStack {
            Text("Recordings")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)
            Spacer()
            Text("\(store.recordings.count) bounce\(store.recordings.count == 1 ? "" : "s")")
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.white.opacity(0.5))
            Button(action: { store.refresh() }) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.55))
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "waveform")
                .font(.system(size: 32))
                .foregroundColor(.white.opacity(0.2))
            Text("No recordings yet")
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(.white.opacity(0.4))
            Text("Hit REC in the booth to bounce a mix.")
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.3))
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func row(_ rec: Recording) -> some View {
        HStack(spacing: 10) {
            Button(action: { player.play(rec) }) {
                Image(systemName: player.isPlaying(rec) ? "pause.fill" : "play.fill")
                    .font(.system(size: 13))
                    .foregroundColor(player.isLoaded(rec) ? .cyan : .white.opacity(0.65))
                    .frame(width: 28, height: 28)
                    .background(player.isLoaded(rec) ? Color.cyan.opacity(0.12) : Color.white.opacity(0.04))
                    .cornerRadius(4)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                Text(rec.url.deletingPathExtension().lastPathComponent)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.white.opacity(0.9))
                    .lineLimit(1)
                HStack(spacing: 8) {
                    Text(rec.dateLabel)
                    Text("·")
                    Text(rec.durationLabel)
                    Text("·")
                    Text(rec.sizeLabel)
                }
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.white.opacity(0.45))
            }
            Spacer()
            Button(action: { deleteCandidate = rec }) {
                Image(systemName: "trash")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.4))
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
    }
}
