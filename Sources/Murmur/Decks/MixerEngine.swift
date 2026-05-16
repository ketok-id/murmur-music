import AVFoundation
import Combine
import Foundation

/// Top-level coordinator for the DJ surface.
///
/// Owns the `AudioGraph`, two `DeckController`s, the `Crossfader`, and the
/// `MasterRecorder`. UI talks to this object; this object talks to the audio
/// nodes.
final class MixerEngine: ObservableObject {
    let graph = AudioGraph()
    let deck1: DeckController
    let deck2: DeckController
    let crossfader: Crossfader
    let recorder: MasterRecorder

    /// Master output volume 0…1.5. 1.0 = unity.
    @Published var masterVolume: Float = 1.0 {
        didSet { graph.engine.mainMixerNode.outputVolume = max(0, min(1.5, masterVolume)) }
    }

    /// -1…+1, drives the crossfader.
    @Published var crossfadePosition: Float = 0 {
        didSet { crossfader.position = crossfadePosition }
    }

    @Published private(set) var isRecording: Bool = false
    @Published private(set) var lastRecordingURL: URL?

    init() {
        self.deck1 = DeckController(engine: graph.engine)
        self.deck2 = DeckController(engine: graph.engine)
        self.crossfader = Crossfader(submixA: graph.submixA, submixB: graph.submixB)
        self.recorder = MasterRecorder(engine: graph.engine)

        // Route deck1 → A submix, deck2 → B submix.
        deck1.connect(to: graph.submixA, in: graph.engine)
        deck2.connect(to: graph.submixB, in: graph.engine)
    }

    func start() throws {
        try graph.start()
    }

    func toggleRecording() {
        if recorder.isRecording {
            let url = recorder.stop()
            isRecording = false
            lastRecordingURL = url
        } else {
            let url = recorder.start()
            isRecording = recorder.isRecording
            lastRecordingURL = url
        }
    }
}
