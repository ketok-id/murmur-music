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

    /// The deck currently designated as sync master. nil = no master.
    @Published private(set) var masterDeckId: Int? = nil
    let phaseAnalyzer = PhaseAnalyzer()

    init() {
        self.deck1 = DeckController(engine: graph.engine)
        self.deck2 = DeckController(engine: graph.engine)
        self.crossfader = Crossfader(submixA: graph.submixA, submixB: graph.submixB)
        self.recorder = MasterRecorder(engine: graph.engine)

        // Route deck1 → A submix, deck2 → B submix.
        deck1.connect(to: graph.submixA, in: graph.engine)
        deck2.connect(to: graph.submixB, in: graph.engine)

        phaseAnalyzer.attach(deck1: deck1, deck2: deck2) { [weak self] in
            self?.masterDeckId
        }
    }

    func start() throws {
        try graph.start()
    }

    /// Make a deck the sync master. Pass nil to clear.
    func setMaster(_ deckId: Int?) {
        masterDeckId = deckId
        deck1.state.isMaster = (deckId == 1)
        deck2.state.isMaster = (deckId == 2)
    }

    /// Sync `slave` to whichever deck is currently master.
    ///
    /// 1) Reads master's *effective* BPM = master.bpm * master.tempoRate
    /// 2) Reads slave's BPM
    /// 3) Sets slave.tempoRate so its effective BPM matches the master's
    ///
    /// Does nothing if either deck lacks a BPM or if `slave` IS the master.
    func sync(slave: DeckController) {
        guard let masterId = masterDeckId else { return }
        let master = (masterId == 1) ? deck1 : deck2
        if slave === master { return }
        let masterBPM = master.state.bpm
        let slaveBPM = slave.state.bpm
        guard masterBPM > 0, slaveBPM > 0 else { return }
        let masterEffective = masterBPM * Double(master.state.tempoRate)
        let newRate = Float(masterEffective / slaveBPM)
        // Clamp to the ±8% the slider allows so the UI stays in range.
        slave.state.tempoRate = max(0.92, min(1.08, newRate))
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
