import SwiftUI

/// Shows the currently-loaded YouTube playlist (`PL…`) with the active video
/// highlighted. Tapping an entry jumps the player to that video. Mixes
/// (`RD…`) are not enumerable so the sheet is empty for those.
/// Restyled with the DesignKit primitives.
struct PlaylistSheet: View {
    @EnvironmentObject var controller: PlayerController
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = PlaylistStore.shared
    @ObservedObject private var userPlaylists = UserPlaylistsStore.shared

    /// Brief "Saved" affordance shown after a successful Save-as-local action.
    /// Resets after a couple of seconds so the button is reusable.
    @State private var savedFeedback: Bool = false

    var body: some View {
        PopoverShell {
            header
        } content: {
            content
        }
        .frame(width: 480, height: 540)
        .padding(8)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "play.square.stack.fill")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.cyan.opacity(0.9))
            Text("Now Playing")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(MurmurColor.textPrimary)
            if !store.items.isEmpty {
                Text(progressLabel)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(MurmurColor.textMuted)
            }
            Spacer()
            if !store.items.isEmpty {
                saveAsLocalButton
            }
            CloseButton(action: { dismiss() })
        }
        .padding(.horizontal, 16)
        .frame(height: 44)
    }

    /// Local playlist previously created from this same YouTube playlist, if
    /// any. Drives the button into its "already saved" state so the user
    /// doesn't silently create duplicates each time they reopen the sheet.
    private var existingLocal: UserPlaylist? {
        userPlaylists.existingSaved(forSourcePlaylistID: store.playlistID)
    }

    /// Copy every entry in the currently-loaded YouTube playlist into a new
    /// `UserPlaylist`. The button label briefly flips to "Saved ✓" so the
    /// user sees the action took. The new playlist appears in the My
    /// Playlists sheet — they can rename it from there. When this YouTube
    /// playlist was already saved locally, the button stays in its saved
    /// state across sheet opens (`existingLocal != nil`).
    private var saveAsLocalButton: some View {
        let isSaved = savedFeedback || existingLocal != nil
        return Button(action: saveAsLocal) {
            HStack(spacing: 4) {
                Image(systemName: isSaved ? "checkmark" : "tray.and.arrow.down")
                    .font(.system(size: 10, weight: .bold))
                Text(isSaved ? "Saved" : "Save as local")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
            }
            .foregroundStyle(isSaved ? MurmurColor.accentLight : MurmurColor.accent)
            .padding(.horizontal, 9)
            .frame(height: 22)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(MurmurColor.accent.opacity(isSaved ? 0.22 : 0.12))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(MurmurColor.accent.opacity(0.45), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(isSaved)
        .help(existingLocal.map { "Already saved as \"\($0.name)\" in My Playlists." }
              ?? "Copy this YouTube playlist into a new local playlist.")
    }

    private func saveAsLocal() {
        guard !store.items.isEmpty, existingLocal == nil else { return }
        // Default name: prefer the most common channel title; fall back to a
        // short, identifiable ID-based label. The user can rename later.
        let name = defaultLocalName()
        let id = userPlaylists.create(name: name, sourcePlaylistID: store.playlistID)
        for entry in store.items {
            userPlaylists.addItem(
                to: id,
                videoID: entry.videoID,
                title: entry.title,
                thumbnailURL: entry.thumbnailURL?.absoluteString ?? ""
            )
        }
        savedFeedback = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            savedFeedback = false
        }
    }

    private func defaultLocalName() -> String {
        // Pick the channel title that shows up most often — typical for a
        // single-creator playlist this is just "Lofi Girl" / "Channel Name".
        // For mixed playlists fall back to the playlist ID prefix.
        var counts: [String: Int] = [:]
        for item in store.items where !item.channelTitle.isEmpty {
            counts[item.channelTitle, default: 0] += 1
        }
        if let top = counts.max(by: { $0.value < $1.value })?.key, !top.isEmpty {
            return top
        }
        let suffix = store.playlistID.isEmpty
            ? ""
            : " · \(String(store.playlistID.prefix(8)))"
        return "YouTube playlist\(suffix)"
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
            VStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text("Loading playlist…")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(MurmurColor.textSecondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let err = store.errorMessage {
            VStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 18))
                    .foregroundStyle(.yellow.opacity(0.75))
                Text(err)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(MurmurColor.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if store.items.isEmpty {
            EmptyStateView(
                systemImage: "music.note.list",
                title: "No playlist loaded.",
                helper: "Paste a YouTube playlist URL (list=PL…) into the input."
            )
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(Array(store.items.enumerated()), id: \.element.id) { idx, entry in
                            row(entry, index: idx).id(entry.id)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
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
        return VideoResultRow(
            thumbURL: entry.thumbnailURL,
            title: entry.title.isEmpty ? entry.videoID : entry.title,
            subtitle: entry.channelTitle.isEmpty ? "Track \(index + 1)" : entry.channelTitle,
            isCurrent: isCurrent,
            onPlay: {
                // Preserve playlist context so YouTube keeps auto-advancing after
                // the picked video, and so the load(input:) parser keeps the
                // PlaylistStore alive instead of clearing it.
                let input: String
                if !store.playlistID.isEmpty {
                    input = "https://www.youtube.com/watch?v=\(entry.videoID)&list=\(store.playlistID)"
                } else {
                    input = entry.videoID
                }
                _ = controller.load(input: input)
                dismiss()
            },
            trailing: AnyView(
                Text("\(index + 1)")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(MurmurColor.textMuted)
                    .frame(width: 24)
            )
        )
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
