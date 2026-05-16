import AVFoundation
import AppKit

/// Extracts title/artist/album/artwork from an audio file via AVAsset metadata.
///
/// Artwork is persisted as a PNG sidecar in `LibraryIndex.artworkDirectory`,
/// keyed by a hash of the source path so re-loading the same file is a cache
/// hit. The returned `artworkPath` is a filename (not full path) — callers
/// resolve it against the artwork directory.
enum MetadataExtractor {
    struct Result {
        let title: String
        let artist: String
        let album: String
        /// Filename of the PNG sidecar in the artwork directory, or empty if no art was found.
        let artworkPath: String
    }

    /// Asynchronously extract metadata.
    static func extract(from url: URL) async -> Result {
        let asset = AVURLAsset(url: url)
        var title = ""
        var artist = ""
        var album = ""
        var artworkPath = ""

        do {
            let items = try await asset.load(.commonMetadata)
            for item in items {
                guard let commonKey = item.commonKey else { continue }
                switch commonKey {
                case .commonKeyTitle:
                    if let v = try? await item.load(.stringValue), !v.isEmpty { title = v }
                case .commonKeyArtist:
                    if let v = try? await item.load(.stringValue), !v.isEmpty { artist = v }
                case .commonKeyAlbumName:
                    if let v = try? await item.load(.stringValue), !v.isEmpty { album = v }
                case .commonKeyArtwork:
                    if let data = try? await item.load(.dataValue),
                       let image = NSImage(data: data) {
                        artworkPath = saveArtwork(image, sourcePath: url.path)
                    }
                default:
                    break
                }
            }
        } catch {
            NSLog("[Metadata] failed for \(url.lastPathComponent): \(error)")
        }

        if title.isEmpty {
            title = url.deletingPathExtension().lastPathComponent
        }
        return Result(title: title, artist: artist, album: album, artworkPath: artworkPath)
    }

    private static func saveArtwork(_ image: NSImage, sourcePath: String) -> String {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            return ""
        }
        let filename = "art-" + String(sourcePath.hashValue, radix: 16) + ".png"
        let url = LibraryIndex.artworkDirectory.appendingPathComponent(filename)
        do {
            try png.write(to: url, options: .atomic)
            return filename
        } catch {
            NSLog("[Metadata] artwork save failed: \(error)")
            return ""
        }
    }
}
