import AppKit
import SwiftUI

/// Reusable context-menu fragment for "Add to playlist".
///
/// **Flat, not nested.** A `Menu("Add to playlist")` inside `.contextMenu`
/// looks tidy but glitches on hover — the submenu's floating window competes
/// with the parent context menu's hover tracking, causing visible flicker as
/// the cursor crosses the boundary. Flat `Button` items in the same menu
/// don't have that problem, and one click adds — faster than navigating a
/// submenu. "New playlist…" still falls through to an NSAlert prompt because
/// `NSAlert.runModal` works above presented SwiftUI sheets.
@ViewBuilder
func addToPlaylistMenuItems(videoID: String, title: String, thumbnailURL: String = "") -> some View {
    let playlists = UserPlaylistsStore.shared.playlists
    ForEach(playlists) { p in
        Button(menuLabel(for: p, videoID: videoID)) {
            UserPlaylistsStore.shared.addItem(
                to: p.id, videoID: videoID, title: title, thumbnailURL: thumbnailURL
            )
        }
    }
    Button("Add to new playlist…") {
        promptCreateAndAddToPlaylist(videoID: videoID, title: title, thumbnailURL: thumbnailURL)
    }
}

private func menuLabel(for playlist: UserPlaylist, videoID: String) -> String {
    let already = playlist.items.contains(where: { $0.videoID == videoID })
    return already ? "Add to \(playlist.name) ✓" : "Add to \(playlist.name)"
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
