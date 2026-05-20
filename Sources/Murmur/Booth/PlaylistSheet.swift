import SwiftUI

/// Shows the currently-loaded YouTube playlist (`PL…`) with the active video
/// highlighted. Tapping an entry jumps the player to that video. Mixes
/// (`RD…`) are not enumerable so the sheet is empty for those.
struct PlaylistSheet: View {
    /// Called with the chosen entry's videoID. Parent loads it on the player.
    var onPick: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = PlaylistStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().background(Color.white.opacity(0.08))
            content
        }
        .frame(width: 460, height: 540)
        .background(Color(white: 0.05))
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "music.note.list")
                .font(.system(size: 12))
                .foregroundColor(.cyan.opacity(0.85))
            Text("Now Playing")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white)
            if !store.items.isEmpty {
                Text(progressLabel)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.white.opacity(0.5))
            }
            Spacer()
            Button(action: { dismiss() }) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.white.opacity(0.4))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var progressLabel: String {
        if let i = store.currentIndex {
            return "(\(i + 1)/\(store.items.count))"
        }
        return "(\(store.items.count))"
    }

    @ViewBuilder
    private var content: some View {
        if store.isLoading && store.items.isEmpty {
            VStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Loading playlist…")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.5))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let err = store.errorMessage {
            VStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 18))
                    .foregroundColor(.yellow.opacity(0.7))
                Text(err)
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if store.items.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "music.note.list")
                    .font(.system(size: 22))
                    .foregroundColor(.white.opacity(0.25))
                Text("No playlist loaded.")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.45))
                Text("Paste a YouTube playlist URL (list=PL…) into the input.")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.35))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(store.items.enumerated()), id: \.element.id) { idx, entry in
                            row(entry, index: idx)
                                .id(entry.id)
                            if entry.id != store.items.last?.id {
                                Divider().background(Color.white.opacity(0.04)).padding(.leading, 92)
                            }
                        }
                    }
                }
                .onAppear {
                    if let i = store.currentIndex, i < store.items.count {
                        proxy.scrollTo(store.items[i].id, anchor: .center)
                    }
                }
                .onChange(of: store.currentIndex) { newIndex in
                    if let i = newIndex, i < store.items.count {
                        withAnimation { proxy.scrollTo(store.items[i].id, anchor: .center) }
                    }
                }
            }
        }
    }

    private func row(_ entry: PlaylistEntry, index: Int) -> some View {
        let isCurrent = (store.currentIndex == index)
        return Button(action: {
            onPick(entry.videoID)
            dismiss()
        }) {
            HStack(spacing: 10) {
                ZStack {
                    if isCurrent {
                        Image(systemName: "play.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.cyan)
                    } else {
                        Text("\(index + 1)")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.white.opacity(0.4))
                    }
                }
                .frame(width: 22)

                AsyncImage(url: entry.thumbnailURL) { phase in
                    switch phase {
                    case .success(let image): image.resizable().aspectRatio(contentMode: .fill)
                    default: Rectangle().fill(Color.white.opacity(0.05))
                    }
                }
                .frame(width: 56, height: 32)
                .clipShape(RoundedRectangle(cornerRadius: 3))
                .overlay(RoundedRectangle(cornerRadius: 3).stroke(Color.white.opacity(0.06), lineWidth: 0.5))

                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.title.isEmpty ? entry.videoID : entry.title)
                        .font(.system(size: 12, weight: isCurrent ? .semibold : .regular))
                        .foregroundColor(isCurrent ? .white : .white.opacity(0.88))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    if !entry.channelTitle.isEmpty {
                        Text(entry.channelTitle)
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.45))
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isCurrent ? Color.cyan.opacity(0.08) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Play next") {
                PlaybackQueue.shared.enqueueNext(
                    videoID: entry.videoID,
                    title: entry.title,
                    thumbnailURL: entry.thumbnailURL?.absoluteString ?? ""
                )
            }
            Button("Add to queue") {
                PlaybackQueue.shared.enqueue(
                    videoID: entry.videoID,
                    title: entry.title,
                    thumbnailURL: entry.thumbnailURL?.absoluteString ?? ""
                )
            }
        }
    }
}
