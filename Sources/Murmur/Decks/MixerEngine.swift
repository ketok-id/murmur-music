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

    // ── Phase 4: Murmur identity layer ────────────────────────────────────

    let ambient = AmbientLayer()
    let mood = MoodDial()
    let scenes = SceneStore()

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

        // Mood Dial → Ambient Layer volume bias.
        mood.$ambientBias.assign(to: &ambient.$moodBias)
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

    // MARK: - Scenes

    /// Capture the current state as a Scene with the given name.
    func captureScene(named name: String) -> Scene {
        let s = Scene(
            id: UUID(),
            name: name,
            crossfade: crossfadePosition,
            masterVolume: masterVolume,
            deck1: snapshot(of: deck1.state),
            deck2: snapshot(of: deck2.state),
            ambient1Source: ambient.channel1.source?.id,
            ambient1Volume: ambient.channel1.volume,
            ambient1Muted: ambient.channel1.muted,
            ambient2Source: ambient.channel2.source?.id,
            ambient2Volume: ambient.channel2.volume,
            ambient2Muted: ambient.channel2.muted,
            moodAngle: mood.angle
        )
        scenes.add(s)
        return s
    }

    /// Apply a scene: restores mixer levels + ambient + mood. Does NOT load tracks.
    func recallScene(_ scene: Scene) {
        crossfadePosition = scene.crossfade
        masterVolume = scene.masterVolume
        apply(scene.deck1, to: deck1.state)
        apply(scene.deck2, to: deck2.state)
        let cat = AmbientSource.catalog
        ambient.channel1.source = scene.ambient1Source.flatMap { id in cat.first(where: { $0.id == id }) }
        ambient.channel1.volume = scene.ambient1Volume
        ambient.channel1.muted = scene.ambient1Muted
        ambient.channel2.source = scene.ambient2Source.flatMap { id in cat.first(where: { $0.id == id }) }
        ambient.channel2.volume = scene.ambient2Volume
        ambient.channel2.muted = scene.ambient2Muted
        mood.angle = scene.moodAngle
    }

    private func snapshot(of state: DeckState) -> DeckSnapshot {
        DeckSnapshot(
            volume: state.volume,
            lowGain: state.lowGain,
            midGain: state.midGain,
            highGain: state.highGain,
            filter: state.filter,
            tempoRate: state.tempoRate,
            keyLock: state.keyLock,
            echoEnabled: state.echoEnabled,
            echoWet: state.echoWet,
            echoDivider: state.echoDivider,
            reverbEnabled: state.reverbEnabled,
            reverbWet: state.reverbWet
        )
    }

    private func apply(_ snapshot: DeckSnapshot, to state: DeckState) {
        state.volume = snapshot.volume
        state.lowGain = snapshot.lowGain
        state.midGain = snapshot.midGain
        state.highGain = snapshot.highGain
        state.filter = snapshot.filter
        state.tempoRate = snapshot.tempoRate
        state.keyLock = snapshot.keyLock
        state.echoEnabled = snapshot.echoEnabled
        state.echoWet = snapshot.echoWet
        state.echoDivider = snapshot.echoDivider
        state.reverbEnabled = snapshot.reverbEnabled
        state.reverbWet = snapshot.reverbWet
    }
}
