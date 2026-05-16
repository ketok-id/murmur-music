import AppKit
import SwiftUI

/// Displays album art from a `LibraryIndex.artworkDirectory` filename, with a
/// fallback gradient placeholder when no art is available.
struct AlbumArtView: View {
    /// Filename in `LibraryIndex.artworkDirectory`. Empty string = no art.
    let artworkPath: String
    var size: CGFloat = 44

    var body: some View {
        Group {
            if let img = loadImage() {
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
    }

    private func loadImage() -> NSImage? {
        guard !artworkPath.isEmpty else { return nil }
        let url = LibraryIndex.artworkDirectory.appendingPathComponent(artworkPath)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return NSImage(contentsOf: url)
    }
}
