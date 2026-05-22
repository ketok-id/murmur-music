import AppKit
import SwiftUI

/// Displays album art from a `LibraryIndex.artworkDirectory` filename, with a
/// fallback gradient placeholder when no art is available.
struct AlbumArtView: View {
    /// Filename in `LibraryIndex.artworkDirectory`. Empty string = no art.
    let artworkPath: String
    var size: CGFloat = 44

    /// Decoded image cached in view state. Re-decoded only when `artworkPath`
    /// changes — without this, every body re-evaluation (e.g. parent's
    /// TimelineView ticks) repeats the disk read + image decode.
    @State private var cached: NSImage?

    var body: some View {
        Group {
            if let img = cached {
                Image(nsImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                LinearGradient(
                    colors: [Color(white: 0.18), Color(white: 0.10)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .overlay(
                    Image(systemName: "music.note")
                        .font(.system(size: size * 0.4, weight: .regular))
                        .foregroundColor(.white.opacity(0.2))
                )
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .task(id: artworkPath) {
            cached = Self.decode(path: artworkPath)
        }
    }

    private static func decode(path: String) -> NSImage? {
        guard !path.isEmpty else { return nil }
        let url = LibraryIndex.artworkDirectory.appendingPathComponent(path)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return NSImage(contentsOf: url)
    }
}
