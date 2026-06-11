import Combine
import Foundation

/// One playhead observer, two consumers: accumulates real listened seconds
/// into `ListeningStatsStore`, and decides when a track counts as a
/// ListenBrainz "listen" (the standard half-track-or-4-minutes rule).
///
/// Listened time is measured from `PlaybackClock` deltas — only small forward
/// steps while playing count, so seeks and stalls don't inflate the totals.
/// Scrobbles only fire for music-classified tracks whose title splits into
/// "Artist - Track" (`TrackQuery`), since ListenBrainz requires both fields.
///
/// AppDelegate-owned (constructor dependency on PlayerController).
final class ListeningRecorder {
    private let controller: PlayerController
    private let stats = ListeningStatsStore.shared
    private let listenBrainz = ListenBrainzStore.shared
    private var cancellables = Set<AnyCancellable>()

    private var lastTime: Double = 0
    private var accumulated: Double = 0
    private var scrobbled = false
    private var sentPlayingNow = false

    init(controller: PlayerController) {
        self.controller = controller

        controller.$currentVideoID
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.trackChanged() }
            .store(in: &cancellables)

        // The category hint lands after the title arrives, which is after the
        // videoID changes — playing_now waits for it.
        controller.$categoryHint
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.maybeSendPlayingNow() }
            .store(in: &cancellables)

        controller.clock.$currentTime
            .receive(on: DispatchQueue.main)
            .sink { [weak self] time in self?.tick(at: time) }
            .store(in: &cancellables)
    }

    private func trackChanged() {
        lastTime = 0
        accumulated = 0
        scrobbled = false
        sentPlayingNow = false
    }

    private func maybeSendPlayingNow() {
        guard !sentPlayingNow,
              listenBrainz.isEnabled,
              controller.categoryHint == .music,
              let split = TrackQuery.split(TrackQuery.clean(controller.title))
        else { return }
        sentPlayingNow = true
        listenBrainz.submitPlayingNow(artist: split.artist, track: split.track)
    }

    private func tick(at time: Double) {
        defer { lastTime = time }
        let delta = time - lastTime
        // Normal progression only: forward, and no bigger than a couple of
        // seconds even at 2x playback. Seeks/reloads fall outside and are
        // ignored (lastTime resyncs via the defer).
        guard controller.isPlaying, delta > 0, delta <= 2.5 else { return }

        accumulated += delta
        stats.add(seconds: delta, videoID: controller.currentVideoID, title: controller.title)

        // ListenBrainz rule: half the track or 4 minutes, whichever is less.
        // Live streams (duration 0) never produce listens, only playing_now.
        let duration = controller.duration
        guard !scrobbled,
              listenBrainz.isEnabled,
              duration > 30,
              accumulated >= min(duration / 2, 240),
              controller.categoryHint == .music,
              let split = TrackQuery.split(TrackQuery.clean(controller.title))
        else { return }
        scrobbled = true
        listenBrainz.submitListen(artist: split.artist, track: split.track, listenedAt: Date())
    }
}
