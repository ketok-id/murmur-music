import SwiftUI

/// Modal sheet for browsing, creating, and playing locally-composed playlists.
/// Top level shows the list of playlists; tapping one drills into a detail
/// view with the playlist's items (reorder + remove + play-from-here).
/// Styled with the DesignKit primitives — `NewPlaylistInput`,
/// `PlaylistRowView`, `VideoResultRow`, `EmptyStateView`.
struct UserPlaylistsSheet: View {
    @EnvironmentObject var controller: PlayerController
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = UserPlaylistsStore.shared

    @State private var selectedID: UUID? = nil
    @State private var draftName: String = ""
    @State private var renamingID: UUID? = nil
    @State private var renameDraft: String = ""
    @State private var pendingDelete: UUID? = nil

    var body: some View {
        PopoverShell {
            header
        } content: {
            content
        }
        .frame(width: 460, height: 540)
        .padding(8)
    }

    // MARK: - Header

    @ViewBuilder
    private var header: some View {
        if let pid = selectedID, let playlist = store.playlists.first(where: { $0.id == pid }) {
            detailHeader(playlist)
        } else {
            listHeader
        }
    }

    private var listHeader: some View {
        HStack(spacing: 8) {
            Text("Playlists")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(MurmurColor.textPrimary)
            Text("(\(store.playlists.count))")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(MurmurColor.textMuted)
            Spacer()
            CloseButton(action: { dismiss() })
        }
        .padding(.horizontal, 16)
        .frame(height: 44)
    }

    private func detailHeader(_ playlist: UserPlaylist) -> some View {
        HStack(spacing: 8) {
            Button(action: { selectedID = nil; renamingID = nil }) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(MurmurColor.textSecondary)
            }
            .buttonStyle(.plain)
            .help("Back to playlists")

            if renamingID == playlist.id {
                TextField("Playlist name", text: $renameDraft, onCommit: { commitRename(playlist.id) })
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(MurmurColor.textPrimary)
                    .tint(MurmurColor.accent)
                Button("Save") { commitRename(playlist.id) }
                    .buttonStyle(.plain)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(MurmurColor.accentLight)
                Button("Cancel") { renamingID = nil }
                    .buttonStyle(.plain)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(MurmurColor.textMuted)
            } else {
                Text(playlist.name)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(MurmurColor.textPrimary)
                    .lineLimit(1)
                Text("(\(playlist.items.count))")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(MurmurColor.textMuted)
                Button(action: {
                    renameDraft = playlist.name
                    renamingID = playlist.id
                }) {
                    Image(systemName: "pencil")
                        .font(.system(size: 10))
                        .foregroundStyle(MurmurColor.textSecondary)
                }
                .buttonStyle(.plain)
                .help("Rename")
                Button(action: { pendingDelete = playlist.id }) {
                    Image(systemName: "trash")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.red.opacity(0.75))
                }
                .buttonStyle(.plain)
                .help("Delete playlist")
            }
            Spacer()
            if !playlist.items.isEmpty {
                Button(action: { play(playlist: playlist, at: 0) }) {
                    HStack(spacing: 4) {
                        Image(systemName: "play.fill")
                        Text("Play")
                    }
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(MurmurColor.accent)
                }
                .buttonStyle(.plain)
                .help("Play from the top")
            }
            CloseButton(action: { dismiss() })
        }
        .padding(.horizontal, 16)
        .frame(height: 44)
        .alert("Delete \"\(playlist.name)\"?",
               isPresented: Binding(get: { pendingDelete == playlist.id },
                                    set: { if !$0 { pendingDelete = nil } })) {
            Button("Cancel", role: .cancel) { pendingDelete = nil }
            Button("Delete", role: .destructive) {
                store.delete(id: playlist.id)
                selectedID = nil
                pendingDelete = nil
            }
        } message: {
            Text("Removes the playlist and its \(playlist.items.count) item\(playlist.items.count == 1 ? "" : "s"). The videos themselves stay on YouTube.")
        }
    }

    // MARK: - Body

    @ViewBuilder
    private var content: some View {
        if let pid = selectedID, let playlist = store.playlists.first(where: { $0.id == pid }) {
            detailBody(playlist)
        } else {
            listBody
        }
    }

    // MARK: List body

    @ViewBuilder
    private var listBody: some View {
        VStack(spacing: 12) {
            NewPlaylistInput(text: $draftName, onCommit: createDraft)

            if store.playlists.isEmpty {
                EmptyStateView(
                    systemImage: "music.note.list",
                    title: "No playlists yet.",
                    helper: "Create one above, then right-click any video → \"Add to playlist…\"."
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(store.playlists) { playlist in
                            PlaylistRowView(
                                title: playlist.name,
                                subtitle: "\(playlist.items.count) item\(playlist.items.count == 1 ? "" : "s")",
                                isActive: store.activeID == playlist.id,
                                onSelect: { selectedID = playlist.id },
                                trailing: playlist.items.isEmpty ? nil : AnyView(
                                    Button {
                                        play(playlist: playlist, at: 0)
                                    } label: {
                                        Image(systemName: "play.fill")
                                            .font(.system(size: 11, weight: .bold))
                                            .foregroundStyle(MurmurColor.accent.opacity(0.85))
                                    }
                                    .buttonStyle(.plain)
                                    .help("Play from the top")
                                )
                            )
                        }
                    }
                    .padding(.bottom, 8)
                }
            }
        }
        .padding(12)
    }

    // MARK: Detail body

    @ViewBuilder
    private func detailBody(_ playlist: UserPlaylist) -> some View {
        if playlist.items.isEmpty {
            EmptyStateView(
                systemImage: "tray",
                title: "This playlist is empty.",
                helper: "Right-click any video → \"Add to playlist…\" → \"\(playlist.name)\"."
            )
        } else {
            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(Array(playlist.items.enumerated()), id: \.element.id) { offset, item in
                        let isCurrent = store.activeID == playlist.id && store.activeIndex == offset
                        VideoResultRow(
                            thumbURL: item.thumb,
                            title: item.title.isEmpty ? item.videoID : item.title,
                            subtitle: isCurrent ? "Now playing" : item.videoID,
                            isCurrent: isCurrent,
                            onPlay: { play(playlist: playlist, at: offset) },
                            trailing: AnyView(
                                Button {
                                    store.removeItem(playlistID: playlist.id, itemID: item.id)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 13))
                                        .foregroundStyle(MurmurColor.textMuted)
                                }
                                .buttonStyle(.plain)
                                .help("Remove from playlist")
                            )
                        )
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
        }
    }

    // MARK: - Actions

    private func createDraft() {
        let trimmed = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let id = store.create(name: trimmed)
        draftName = ""
        selectedID = id
    }

    private func commitRename(_ id: UUID) {
        let trimmed = renameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { renamingID = nil; return }
        store.rename(id: id, to: trimmed)
        renamingID = nil
    }

    private func play(playlist: UserPlaylist, at index: Int) {
        guard let item = store.activate(playlistID: playlist.id, startAt: index) else { return }
        _ = controller.load(input: item.videoID)
        dismiss()
    }
}
