import AppKit
import SwiftUI

/// Reusable context-menu fragment for "Add to playlist". Shows a submenu with
/// existing playlists (instant-add) plus "New playlist…" which falls through
/// to an NSAlert prompt — `NSAlert.runModal` works above presented SwiftUI
/// sheets, sidestepping the nested-`.sheet(item:)` mess that would otherwise
/// be required to present a SwiftUI picker on top of `YouTubeSearchSheet`.
@ViewBuilder
func addToPlaylistMenuItems(videoID: String, title: String, thumbnailURL: String = "") -> some View {
    let playlists = UserPlaylistsStore.shared.playlists
    if playlists.isEmpty {
        Button("Add to new playlist…") {
            promptCreateAndAddToPlaylist(videoID: videoID, title: title, thumbnailURL: thumbnailURL)
        }
    } else {
        Menu("Add to playlist") {
            ForEach(playlists) { p in
                Button(menuLabel(for: p, videoID: videoID)) {
                    UserPlaylistsStore.shared.addItem(
                        to: p.id, videoID: videoID, title: title, thumbnailURL: thumbnailURL
                    )
                }
            }
            Divider()
            Button("New playlist…") {
                promptCreateAndAddToPlaylist(videoID: videoID, title: title, thumbnailURL: thumbnailURL)
            }
        }
    }
}

private func menuLabel(for playlist: UserPlaylist, videoID: String) -> String {
    playlist.items.contains(where: { $0.videoID == videoID })
        ? "\(playlist.name) ✓"
        : playlist.name
}

private func promptCreateAndAddToPlaylist(videoID: String, title: String, thumbnailURL: String) {
    let alert = NSAlert()
    alert.messageText = "New playlist"
    alert.informativeText = "Name your new playlist."
    let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 220, height: 24))
    field.placeholderString = "Playlist name"
    alert.accessoryView = field
    alert.addButton(withTitle: "Create & add")
    alert.addButton(withTitle: "Cancel")
    NSApp.activate(ignoringOtherApps: true)
    if alert.runModal() == .alertFirstButtonReturn {
        let name = field.stringValue.trimmingCharacters(in: .whitespaces)
        let finalName = name.isEmpty ? "Untitled" : name
        let id = UserPlaylistsStore.shared.create(name: finalName)
        UserPlaylistsStore.shared.addItem(
            to: id, videoID: videoID, title: title, thumbnailURL: thumbnailURL
        )
    }
}
