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
    let loopEngine = LoopEngine()

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
            state.hotCues = []
            state.loop.clear()
            loopEngine.disengage()

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
                self.state.hotCues = result.metadata.hotCues
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
            state.hotCues = []
            state.loop.clear()
            loopEngine.disengage()
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

    // MARK: - Hot cues

    /// Set the hot cue at pad index `id` to the current playhead position.
    func setHotCue(id: Int) {
        guard state.isLoaded else { return }
        let seconds = state.currentTimeSeconds
        var cues = state.hotCues
        let cue = HotCue(id: id, seconds: seconds, colorHex: HotCue.defaultColor(for: id))
        if let idx = cues.firstIndex(where: { $0.id == id }) {
            cues[idx] = cue
        } else {
            cues.append(cue)
            cues.sort { $0.id < $1.id }
        }
        state.hotCues = cues
        if let url = player.loadedURL {
            LibraryIndex.shared.setHotCues(cues, forPath: url.path)
        }
    }

    /// Jump playback to the cue at pad index `id`. No-op if the cue isn't set.
    func jumpHotCue(id: Int) {
        guard let cue = state.hotCues.first(where: { $0.id == id }) else { return }
        if loopEngine.isEngaged {
            state.loop.isActive = false
            loopEngine.disengage()
        }
        player.seek(toSeconds: cue.seconds)
    }

    /// Remove the cue at pad index `id`.
    func deleteHotCue(id: Int) {
        var cues = state.hotCues
        cues.removeAll { $0.id == id }
        state.hotCues = cues
        if let url = player.loadedURL {
            LibraryIndex.shared.setHotCues(cues, forPath: url.path)
        }
    }

    // MARK: - Loops

    /// Set the loop IN point at the current playhead, snapped to the nearest beat.
    func setLoopIn() {
        let t = beatSnap(state.currentTimeSeconds)
        state.loop.inSeconds = t
    }

    /// Set the loop OUT point at the current playhead, snapped to the nearest beat,
    /// and engage the loop.
    func setLoopOut() {
        let t = beatSnap(state.currentTimeSeconds)
        guard let inT = state.loop.inSeconds, t > inT else { return }
        state.loop.outSeconds = t
        engageLoopIfReady()
    }

    /// Halve the loop length (move OUT to half-distance from IN).
    func halveLoop() {
        guard let inT = state.loop.inSeconds, let outT = state.loop.outSeconds else { return }
        let length = outT - inT
        state.loop.outSeconds = inT + length / 2
        engageLoopIfReady()
    }

    /// Double the loop length (move OUT to twice-distance from IN).
    func doubleLoop() {
        guard let inT = state.loop.inSeconds, let outT = state.loop.outSeconds else { return }
        let length = outT - inT
        state.loop.outSeconds = inT + length * 2
        engageLoopIfReady()
    }

    /// Toggle loop on/off.
    func toggleLoop() {
        if state.loop.isActive {
            state.loop.isActive = false
            loopEngine.disengage()
        } else {
            engageLoopIfReady()
        }
    }

    private func engageLoopIfReady() {
        guard let inT = state.loop.inSeconds,
              let outT = state.loop.outSeconds,
              let file = player.file,
              outT > inT else { return }
        state.loop.isActive = true
        loopEngine.engage(player: player.player, file: file, inSeconds: inT, outSeconds: outT)
    }

    private func beatSnap(_ t: Double) -> Double {
        guard state.bpm > 0 else { return t }
        let beatInterval = 60.0 / state.bpm
        let firstBeat = state.firstBeat
        let offsetFromFirst = t - firstBeat
        let beatsFromFirst = (offsetFromFirst / beatInterval).rounded()
        return firstBeat + beatsFromFirst * beatInterval
    }
}
