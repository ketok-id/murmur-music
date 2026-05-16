import Combine
import Foundation

/// Computes the phase offset between two beat-locked decks at ~30Hz.
///
/// Phase offset is the difference between each deck's position within its beat,
/// modulo a beat interval. -0.5 to +0.5 beats. 0 = locked.
///
/// Publishes via `@Published var offsetBeats: Double` — UI binds to this.
final class PhaseAnalyzer: ObservableObject {
    /// Phase offset in beats, range -0.5…+0.5. 0 = master and slave beats aligned.
    /// Positive = slave is ahead of master.
    @Published var offsetBeats: Double = 0

    private var timer: Timer?
    private weak var deck1: DeckController?
    private weak var deck2: DeckController?
    private var getMasterId: () -> Int? = { nil }

    deinit {
        timer?.invalidate()
    }

    func attach(deck1: DeckController, deck2: DeckController, getMasterId: @escaping () -> Int?) {
        self.deck1 = deck1
        self.deck2 = deck2
        self.getMasterId = getMasterId
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    private func tick() {
        guard let d1 = deck1, let d2 = deck2 else { return }
        guard let masterId = getMasterId() else {
            if offsetBeats != 0 { offsetBeats = 0 }
            return
        }
        let master = (masterId == 1) ? d1 : d2
        let slave = (masterId == 1) ? d2 : d1

        guard master.state.bpm > 0, slave.state.bpm > 0,
              master.state.isPlaying, slave.state.isPlaying else {
            if offsetBeats != 0 { offsetBeats = 0 }
            return
        }

        let masterBeatInterval = 60.0 / (master.state.bpm * Double(master.state.tempoRate))
        let slaveBeatInterval = 60.0 / (slave.state.bpm * Double(slave.state.tempoRate))

        let masterPhase = phaseWithinBeat(time: master.state.currentTimeSeconds,
                                          firstBeat: master.state.firstBeat,
                                          beatInterval: masterBeatInterval)
        let slavePhase = phaseWithinBeat(time: slave.state.currentTimeSeconds,
                                         firstBeat: slave.state.firstBeat,
                                         beatInterval: slaveBeatInterval)

        var delta = slavePhase - masterPhase
        if delta > 0.5 { delta -= 1 }
        if delta < -0.5 { delta += 1 }
        offsetBeats = delta
    }

    /// Normalized phase 0..1 within the current beat.
    private func phaseWithinBeat(time: Double, firstBeat: Double, beatInterval: Double) -> Double {
        let offset = time - firstBeat
        let normalized = (offset / beatInterval).truncatingRemainder(dividingBy: 1)
        return normalized < 0 ? normalized + 1 : normalized
    }
}
