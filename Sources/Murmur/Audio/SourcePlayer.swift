import AVFoundation

/// Abstract audio source — Phase 1 only ships `LocalFilePlayer`. Future phases
/// add `AppleMusicPlayer` and `YouTubeAmbientPlayer` (see design spec §7.1).
///
/// A `SourcePlayer` exposes a single `outputNode` that the channel strip
/// connects into. It must not call `engine.connect` itself.
protocol SourcePlayer: AnyObject {
    /// The node a `ChannelStrip` should connect *from*. Must be attached to the engine.
    var outputNode: AVAudioNode { get }
    /// Human-readable label for UI ("Bonobo — Cirrus", or "—" when nothing loaded).
    var displayName: String { get }
    /// True after a successful `load` and the player is playable.
    var isLoaded: Bool { get }
    /// Whether the player is currently playing.
    var isPlaying: Bool { get }
    /// Current playhead in seconds, valid only when `isLoaded`.
    var currentTimeSeconds: Double { get }
    /// Total duration in seconds, valid only when `isLoaded`.
    var durationSeconds: Double { get }

    func load(url: URL) throws
    func play()
    func pause()
    func seek(toSeconds seconds: Double)
}
