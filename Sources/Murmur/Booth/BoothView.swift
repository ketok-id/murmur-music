import SwiftUI

/// Top-level booth UI: two decks flanking a center strip (crossfader + master).
struct BoothView: View {
    @ObservedObject var mixer: MixerEngine
    @ObservedObject var deck1State: DeckState
    @ObservedObject var deck2State: DeckState

    var body: some View {
        VStack(spacing: 6) {
            SceneChipsView(
                store: mixer.scenes,
                onRecall: { mixer.recallScene($0) },
                onCapture: { name in _ = mixer.captureScene(named: name) }
            )

            AmbientStripView(
                channel1: mixer.ambient.channel1,
                channel2: mixer.ambient.channel2
            )

            HStack(alignment: .top, spacing: 12) {
                DeckView(
                    state: deck1State,
                    deckNumber: 1,
                    tint: .cyan,
                    onLoad: { mixer.deck1.load(url: $0) },
                    onTogglePlay: { mixer.deck1.togglePlay() },
                    hasMaster: mixer.masterDeckId != nil,
                    onSync: { mixer.sync(slave: mixer.deck1) },
                    onToggleMaster: {
                        mixer.setMaster(deck1State.isMaster ? nil : 1)
                    },
                    onSetOrJumpCue: { id in
                        if deck1State.hotCues.contains(where: { $0.id == id }) {
                            mixer.deck1.jumpHotCue(id: id)
                        } else {
                            mixer.deck1.setHotCue(id: id)
                        }
                    },
                    onDeleteCue: { mixer.deck1.deleteHotCue(id: $0) },
                    onSetLoopIn: { mixer.deck1.setLoopIn() },
                    onSetLoopOut: { mixer.deck1.setLoopOut() },
                    onHalveLoop: { mixer.deck1.halveLoop() },
                    onDoubleLoop: { mixer.deck1.doubleLoop() },
                    onToggleLoop: { mixer.deck1.toggleLoop() },
                    onScrubBegan: { mixer.deck1.beginScrub() },
                    onScrub: { mixer.deck1.scrub(toSeconds: $0) },
                    onScrubEnded: { mixer.deck1.endScrub() }
                )
                VStack(spacing: 8) {
                    MasterControlsView(mixer: mixer)
                    LivePhaseMeter(analyzer: mixer.phaseAnalyzer)
                        .frame(height: 30)
                    MoodDialView(mood: mixer.mood)
                }
                .frame(width: 110)
                DeckView(
                    state: deck2State,
                    deckNumber: 2,
                    tint: .orange,
                    onLoad: { mixer.deck2.load(url: $0) },
                    onTogglePlay: { mixer.deck2.togglePlay() },
                    hasMaster: mixer.masterDeckId != nil,
                    onSync: { mixer.sync(slave: mixer.deck2) },
                    onToggleMaster: {
                        mixer.setMaster(deck2State.isMaster ? nil : 2)
                    },
                    onSetOrJumpCue: { id in
                        if deck2State.hotCues.contains(where: { $0.id == id }) {
                            mixer.deck2.jumpHotCue(id: id)
                        } else {
                            mixer.deck2.setHotCue(id: id)
                        }
                    },
                    onDeleteCue: { mixer.deck2.deleteHotCue(id: $0) },
                    onSetLoopIn: { mixer.deck2.setLoopIn() },
                    onSetLoopOut: { mixer.deck2.setLoopOut() },
                    onHalveLoop: { mixer.deck2.halveLoop() },
                    onDoubleLoop: { mixer.deck2.doubleLoop() },
                    onToggleLoop: { mixer.deck2.toggleLoop() },
                    onScrubBegan: { mixer.deck2.beginScrub() },
                    onScrub: { mixer.deck2.scrub(toSeconds: $0) },
                    onScrubEnded: { mixer.deck2.endScrub() }
                )
            }

            CrossfaderView(position: $mixer.crossfadePosition)
                .frame(height: 36)
                .background(Color(white: 0.04))
                .cornerRadius(8)
        }
        .padding(14)
        .frame(minWidth: 1000, minHeight: 900)
        .background(Color(white: 0.02))
    }
}

/// Tiny wrapper so SwiftUI observes `PhaseAnalyzer.@Published`.
private struct LivePhaseMeter: View {
    @ObservedObject var analyzer: PhaseAnalyzer
    var body: some View { PhaseMeterView(offsetBeats: analyzer.offsetBeats) }
}
