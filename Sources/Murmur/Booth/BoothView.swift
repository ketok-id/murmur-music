import SwiftUI

/// Top-level booth UI: two decks flanking a center strip (crossfader + master).
struct BoothView: View {
    @ObservedObject var mixer: MixerEngine
    @ObservedObject var deck1State: DeckState
    @ObservedObject var deck2State: DeckState

    var body: some View {
        VStack(spacing: 10) {
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
                    }
                )
                MasterControlsView(mixer: mixer)
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
                    }
                )
            }

            CrossfaderView(position: $mixer.crossfadePosition)
                .frame(height: 36)
                .background(Color(white: 0.04))
                .cornerRadius(8)
        }
        .padding(14)
        .frame(minWidth: 760, minHeight: 460)
        .background(Color(white: 0.02))
    }
}
