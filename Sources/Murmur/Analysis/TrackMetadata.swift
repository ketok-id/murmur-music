import Foundation

/// Cached analysis output for a single file.
/// `peaksPath` references a sidecar binary file written by `PeakExtractor`.
struct TrackMetadata: Codable, Equatable {
    let bpm: Double
    let duration: Double
    /// Seconds offset to the first downbeat. Defaults to 0; user-adjustable.
    var firstBeat: Double
    /// Filename (not full path) of the peaks sidecar inside the peaks directory.
    let peaksPath: String
    var hotCues: [HotCue] = []
    var keyName: String = ""
    var camelot: String = ""
    var title: String = ""
    var artist: String = ""
    var album: String = ""
    var artworkPath: String = ""
    var bandPeaksPath: String = ""
}
