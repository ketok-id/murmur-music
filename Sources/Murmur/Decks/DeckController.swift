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
            // Reset analysis-derived state until we have new results.
            state.bpm = 0
            state.firstBeat = 0
            state.peaks = []

            AnalysisService.shared.analyze(url: url) { [weak self] result in
                guard let self = self, let result = result else { return }
                // Guard: only apply if the user hasn't loaded a different track
                // in the meantime.
                guard self.player.isLoaded,
                      self.state.displayName == result.url.deletingPathExtension().lastPathComponent
                else { return }
                self.state.bpm = result.metadata.bpm
                self.state.firstBeat = result.metadata.firstBeat
                self.state.peaks = result.peaks
            }
        } catch {
            NSLog("DeckController load error: \(error)")
            player.pause()
            state.isLoaded = false
            state.displayName = "Load failed"
            state.durationSeconds = 0
            state.currentTimeSeconds = 0
            state.isPlaying = false
            state.bpm = 0
            state.firstBeat = 0
            state.peaks = []
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

        // Tempo + key-lock: combineLatest so a change to either re-applies both.
        state.$tempoRate
            .combineLatest(state.$keyLock)
            .sink { [weak self] (rate, keyLock) in
                guard let self = self else { return }
                self.strip.rate = rate
                // Varispeed: pitch shift = 1200 * log2(rate). Key-lock: pitch = 0.
                self.strip.pitch = keyLock ? 0 : 1200 * log2(rate)
            }
            .store(in: &cancellables)

        // Persist user-adjusted firstBeat.
        state.$firstBeat
            .dropFirst() // skip the initial 0 emitted on assignment
            .sink { [weak self] firstBeat in
                guard let player = self?.player, let url = player.loadedURL else { return }
                LibraryIndex.shared.setFirstBeat(firstBeat, forPath: url.path)
            }
            .store(in: &cancellables)
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
