import SwiftUI

/// Modal sheet for browsing, creating, and playing locally-composed playlists.
/// Top level shows the list of playlists; tapping one drills into a detail
/// view with the playlist's items (reorder + remove + play-from-here).
struct UserPlaylistsSheet: View {
    /// Called to actually start a video — typically `controller.load(input:)`.
    var onPlay: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = UserPlaylistsStore.shared

    @State private var selectedID: UUID? = nil
    @State private var draftName: String = ""
    @State private var renamingID: UUID? = nil
    @State private var renameDraft: String = ""
    @State private var pendingDelete: UUID? = nil
    @FocusState private var newNameFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().background(Color.white.opacity(0.08))
            content
        }
        .frame(width: 420, height: 520)
        .background(Color(white: 0.05))
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
        HStack {
            Text("Playlists")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white)
            Text("(\(store.playlists.count))")
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.white.opacity(0.4))
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

    private func detailHeader(_ playlist: UserPlaylist) -> some View {
        HStack(spacing: 8) {
            Button(action: { selectedID = nil; renamingID = nil }) {
                Image(systemName: "chevron.left")
                    .foregroundColor(.white.opacity(0.6))
            }
            .buttonStyle(.plain)
            .help("Back to playlists")

            if renamingID == playlist.id {
                TextField("Playlist name", text: $renameDraft, onCommit: { commitRename(playlist.id) })
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                Button("Save") { commitRename(playlist.id) }
                Button("Cancel") { renamingID = nil }
            } else {
                Text(playlist.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                Text("(\(playlist.items.count))")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.white.opacity(0.4))
                Button(action: {
                    renameDraft = playlist.name
                    renamingID = playlist.id
                }) {
                    Image(systemName: "pencil")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.5))
                }
                .buttonStyle(.plain)
                .help("Rename")
                Button(action: { pendingDelete = playlist.id }) {
                    Image(systemName: "trash")
                        .font(.system(size: 11))
                        .foregroundColor(.red.opacity(0.7))
                }
                .buttonStyle(.plain)
                .help("Delete playlist")
            }
            Spacer()
            if !playlist.items.isEmpty {
                Button(action: { play(playlist: playlist, at: 0) }) {
                    HStack(spacing: 4) {
                        Image(systemName: "play.fill")
                        Text("Play").font(.system(size: 11, weight: .medium))
                    }
                    .foregroundColor(Color(red: 0.96, green: 0.65, blue: 0.45))
                }
                .buttonStyle(.plain)
                .help("Play from the top")
            }
            Button(action: { dismiss() }) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.white.opacity(0.4))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
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
        VStack(spacing: 0) {
            newPlaylistRow
            Divider().background(Color.white.opacity(0.06))
            if store.playlists.isEmpty {
                emptyState
            } else {
                List {
                    ForEach(store.playlists) { playlist in
                        playlistRow(playlist)
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
    }

    private var newPlaylistRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "plus.circle")
                .foregroundColor(.white.opacity(0.5))
            // TextField's onCommit already fires on Return. A Button with
            // .keyboardShortcut(.defaultAction) would ALSO fire on Return,
            // causing createDraft() to run twice — so the explicit Create
            // button has no keyboard shortcut, just a click affordance.
            TextField("New playlist name", text: $draftName, onCommit: createDraft)
                .textFieldStyle(.plain)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(.white.opacity(0.9))
                .focused($newNameFocused)
            if !draftName.isEmpty {
                Button("Create") { createDraft() }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "music.note.list")
                .font(.system(size: 24))
                .foregroundColor(.white.opacity(0.25))
            Text("No playlists yet.")
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.45))
            Text("Create one above, then right-click any video → \"Add to playlist…\".")
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.35))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 30)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func playlistRow(_ playlist: UserPlaylist) -> some View {
        let isActive = store.activeID == playlist.id
        return HStack(spacing: 10) {
            Button(action: { selectedID = playlist.id }) {
                HStack(spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.white.opacity(0.05))
                            .frame(width: 36, height: 36)
                        Image(systemName: "music.note.list")
                            .font(.system(size: 14))
                            .foregroundColor(.white.opacity(0.5))
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(playlist.name)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.white.opacity(0.9))
                                .lineLimit(1)
                            if isActive {
                                Text("PLAYING")
                                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                                    .tracking(1)
                                    .foregroundColor(Color(red: 0.96, green: 0.65, blue: 0.45))
                            }
                        }
                        Text("\(playlist.items.count) item\(playlist.items.count == 1 ? "" : "s")")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.white.opacity(0.4))
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if !playlist.items.isEmpty {
                Button(action: { play(playlist: playlist, at: 0) }) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 11))
                        .foregroundColor(Color(red: 0.96, green: 0.65, blue: 0.45).opacity(0.85))
                }
                .buttonStyle(.plain)
                .help("Play from the top")
            }
        }
        .padding(.vertical, 3)
    }

    // MARK: Detail body

    @ViewBuilder
    private func detailBody(_ playlist: UserPlaylist) -> some View {
        if playlist.items.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "tray")
                    .font(.system(size: 24))
                    .foregroundColor(.white.opacity(0.25))
                Text("This playlist is empty.")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.45))
                Text("Right-click any video → \"Add to playlist…\" → \"\(playlist.name)\".")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.35))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 30)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List {
                ForEach(Array(playlist.items.enumerated()), id: \.element.id) { offset, item in
                    itemRow(playlist: playlist, item: item, index: offset)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
                .onMove { src, dest in store.moveItem(playlistID: playlist.id, from: src, to: dest) }
                .onDelete { offsets in
                    for i in offsets {
                        store.removeItem(playlistID: playlist.id, itemID: playlist.items[i].id)
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }

    private func itemRow(playlist: UserPlaylist, item: UserPlaylistItem, index: Int) -> some View {
        let isCurrent = store.activeID == playlist.id && store.activeIndex == index
        return HStack(spacing: 10) {
            Button(action: { play(playlist: playlist, at: index) }) {
                HStack(spacing: 10) {
                    AsyncImage(url: item.thumb) { phase in
                        switch phase {
                        case .success(let image): image.resizable().aspectRatio(contentMode: .fill)
                        default: Rectangle().fill(Color.white.opacity(0.05))
                        }
                    }
                    .frame(width: 64, height: 36)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                    .overlay(RoundedRectangle(cornerRadius: 3).stroke(Color.white.opacity(0.06), lineWidth: 0.5))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title.isEmpty ? item.videoID : item.title)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(isCurrent
                                             ? Color(red: 0.96, green: 0.65, blue: 0.45)
                                             : .white.opacity(0.9))
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        if isCurrent {
                            Text("Now playing")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .tracking(1)
                                .foregroundColor(Color(red: 0.96, green: 0.65, blue: 0.45).opacity(0.85))
                        }
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button(action: { store.removeItem(playlistID: playlist.id, itemID: item.id) }) {
                Image(systemName: "xmark.circle")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.35))
            }
            .buttonStyle(.plain)
            .help("Remove from playlist")
        }
        .padding(.vertical, 3)
    }

    // MARK: - Actions

    private func createDraft() {
        let trimmed = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let id = store.create(name: trimmed)
        draftName = ""
        newNameFocused = false
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
        onPlay(item.videoID)
        dismiss()
    }
}
