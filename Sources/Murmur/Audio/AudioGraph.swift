import AVFoundation

/// Owns the single AVAudioEngine that drives the DJ surface.
///
/// Phase 1 only wires the engine lifecycle + two submix nodes (A group, B group)
/// connected to `mainMixerNode`. Decks and recording are bolted on by later tasks.
final class AudioGraph {
    let engine = AVAudioEngine()
    let submixA = AVAudioMixerNode()
    let submixB = AVAudioMixerNode()

    init() {
        engine.attach(submixA)
        engine.attach(submixB)
        // Connect both submixers to the main mixer at the engine's default format.
        let mainFormat = engine.mainMixerNode.outputFormat(forBus: 0)
        engine.connect(submixA, to: engine.mainMixerNode, format: mainFormat)
        engine.connect(submixB, to: engine.mainMixerNode, format: mainFormat)
    }

    func start() throws {
        guard !engine.isRunning else { return }
        engine.prepare()
        try engine.start()
    }

    func stop() {
        engine.stop()
    }
}
