import Foundation

/// JSON-backed cache of analysis results keyed by absolute file path.
///
/// The index is loaded on init from
/// `~/Library/Application Support/Murmur/library.json` and persisted on every
/// write. Reads are O(1); writes serialize the entire index (small enough at
/// this stage that incremental serialization isn't worth the complexity).
final class LibraryIndex {
    static let shared = LibraryIndex()

    private(set) var tracks: [String: TrackMetadata] = [:]
    private let url: URL
    private let queue = DispatchQueue(label: "murmur.library-index")

    private init() {
        let appSupport = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
            .appendingPathComponent("Murmur", isDirectory: true)
        try? FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
        self.url = appSupport.appendingPathComponent("library.json")
        load()
    }

    /// Where artwork PNG sidecars live.
    static var artworkDirectory: URL {
        let dir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
            .appendingPathComponent("Murmur", isDirectory: true)
            .appendingPathComponent("artwork", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Where peak sidecar files live.
    static var peaksDirectory: URL {
        let dir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
            .appendingPathComponent("Murmur", isDirectory: true)
            .appendingPathComponent("peaks", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func metadata(forPath path: String) -> TrackMetadata? {
        queue.sync { tracks[path] }
    }

    func setMetadata(_ metadata: TrackMetadata, forPath path: String) {
        queue.sync {
            tracks[path] = metadata
            save()
        }
    }

    /// Update only the firstBeat (user-adjusted downbeat).
    func setFirstBeat(_ firstBeat: Double, forPath path: String) {
        queue.sync {
            guard var existing = tracks[path] else { return }
            existing.firstBeat = firstBeat
            tracks[path] = existing
            save()
        }
    }

    /// Update only the hotCues array for a track.
    func setHotCues(_ hotCues: [HotCue], forPath path: String) {
        queue.sync {
            guard var existing = tracks[path] else { return }
            existing.hotCues = hotCues
            tracks[path] = existing
            save()
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([String: TrackMetadata].self, from: data) else {
            return
        }
        tracks = decoded
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(tracks)
            try data.write(to: url, options: .atomic)
        } catch {
            NSLog("LibraryIndex save error: \(error)")
        }
    }
}
