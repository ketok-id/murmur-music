import AVFoundation

/// Plays a local audio file via `AVAudioPlayerNode` + `AVAudioFile`.
///
/// Connect `outputNode` to a `ChannelStrip` input. The player node is attached
/// to the engine in `init`; it stays attached for the lifetime of the player.
final class LocalFilePlayer: SourcePlayer {
    private let engine: AVAudioEngine
    private let player = AVAudioPlayerNode()
    private var file: AVAudioFile?
    private var loadedURL: URL?

    /// Sample-frame offset of where playback was last started in the file.
    /// Combined with `player.lastRenderTime` to compute `currentTimeSeconds`.
    private var startFrame: AVAudioFramePosition = 0

    var outputNode: AVAudioNode { player }

    var displayName: String {
        loadedURL?.deletingPathExtension().lastPathComponent ?? "—"
    }

    var isLoaded: Bool { file != nil }
    var isPlaying: Bool { player.isPlaying }

    var currentTimeSeconds: Double {
        guard let file = file,
              let nodeTime = player.lastRenderTime,
              let playerTime = player.playerTime(forNodeTime: nodeTime) else {
            return 0
        }
        let frames = startFrame + playerTime.sampleTime
        return Double(frames) / file.processingFormat.sampleRate
    }

    var durationSeconds: Double {
        guard let file = file else { return 0 }
        return Double(file.length) / file.processingFormat.sampleRate
    }

    init(engine: AVAudioEngine) {
        self.engine = engine
        engine.attach(player)
    }

    func load(url: URL) throws {
        let file = try AVAudioFile(forReading: url)
        if player.isPlaying { player.stop() }
        self.file = file
        self.loadedURL = url
        self.startFrame = 0
        player.scheduleFile(file, at: nil, completionHandler: nil)
    }

    func play() {
        guard isLoaded, !player.isPlaying else { return }
        if !engine.isRunning {
            try? engine.start()
        }
        player.play()
    }

    func pause() {
        guard player.isPlaying else { return }
        player.pause()
    }

    func seek(toSeconds seconds: Double) {
        guard let file = file else { return }
        let sampleRate = file.processingFormat.sampleRate
        let frame = AVAudioFramePosition(max(0, seconds) * sampleRate)
        let clampedFrame = min(frame, file.length - 1)
        let framesToPlay = AVAudioFrameCount(max(0, file.length - clampedFrame))
        guard framesToPlay > 0 else { return }

        let wasPlaying = player.isPlaying
        player.stop()
        startFrame = clampedFrame
        player.scheduleSegment(file,
                               startingFrame: clampedFrame,
                               frameCount: framesToPlay,
                               at: nil,
                               completionHandler: nil)
        if wasPlaying { player.play() }
    }
}
