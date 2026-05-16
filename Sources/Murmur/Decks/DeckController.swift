import AVFoundation
import Combine
import Foundation

/// Owns one deck's source player + channel strip and mirrors observable state.
///
/// Wires `DeckState.@Published` properties to the strip via Combine. The UI
/// mutates `DeckState`; the controller's sinks push the values into the audio
/// graph.
final class DeckController {
    let state = DeckState()
    let strip: ChannelStrip
    let player: LocalFilePlayer

    private var cancellables = Set<AnyCancellable>()
    private var positionTimer: Timer?

    deinit {
        positionTimer?.invalidate()
    }

    init(engine: AVAudioEngine) {
        self.player = LocalFilePlayer(engine: engine)
        self.strip = ChannelStrip(engine: engine)
        strip.connectSource(player)
        wireStateBindings()
        startPositionPolling()
    }

    /// Connect this strip's volume node to a downstream submix.
    func connect(to submix: AVAudioMixerNode, in engine: AVAudioEngine) {
        engine.connect(strip.volume, to: submix, format: nil)
    }

    func load(url: URL) {
        do {
            try player.load(url: url)
            state.displayName = player.displayName
            state.isLoaded = true
            state.durationSeconds = player.durationSeconds
            state.currentTimeSeconds = 0
            state.isPlaying = false
        } catch {
            NSLog("DeckController load error: \(error)")
            // Stop any existing playback and clear stale state so the deck
            // shows an empty slot rather than a contradictory half-loaded state.
            player.pause()
            state.isLoaded = false
            state.displayName = "Load failed"
            state.durationSeconds = 0
            state.currentTimeSeconds = 0
            state.isPlaying = false
        }
    }

    func togglePlay() {
        if player.isPlaying {
            player.pause()
        } else {
            player.play()
        }
        state.isPlaying = player.isPlaying
    }

    private func wireStateBindings() {
        state.$volume.sink { [weak self] v in self?.strip.fader = v }.store(in: &cancellables)
        state.$lowGain.sink { [weak self] v in self?.strip.lowGain = v }.store(in: &cancellables)
        state.$midGain.sink { [weak self] v in self?.strip.midGain = v }.store(in: &cancellables)
        state.$highGain.sink { [weak self] v in self?.strip.highGain = v }.store(in: &cancellables)
        state.$filter.sink { [weak self] v in self?.strip.filterPosition = v }.store(in: &cancellables)
    }

    private func startPositionPolling() {
        positionTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self = self, self.player.isLoaded else { return }
            let raw = self.player.currentTimeSeconds
            let duration = self.player.durationSeconds
            self.state.currentTimeSeconds = max(0, min(raw, duration))
            let nowPlaying = self.player.isPlaying
            if self.state.isPlaying != nowPlaying {
                self.state.isPlaying = nowPlaying
            }
        }
    }
}
