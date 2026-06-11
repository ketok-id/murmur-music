import Combine
import Foundation

/// Watches the playhead and seeks past SponsorBlock segments. Segment data +
/// settings live in `SponsorBlockStore`; this is just the position loop,
/// riding the same `PlaybackClock` ticks the lyrics highlight uses — no extra
/// timers, no iframe changes (the skip is a normal `seek(to:)`).
///
/// AppDelegate-owned (constructor dependency on PlayerController).
final class SponsorSkipper {
    private let controller: PlayerController
    private let store = SponsorBlockStore.shared
    private var cancellables = Set<AnyCancellable>()
    private var segments: [SponsorSegment] = []
    private var fetchTask: Task<Void, Never>?
    private var lastSkipTarget: Double = -1

    init(controller: PlayerController) {
        self.controller = controller

        controller.$currentVideoID
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] videoID in self?.reload(for: videoID) }
            .store(in: &cancellables)

        // Toggling the feature on mid-video must fetch for the current track.
        store.$enabled
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] enabled in
                guard let self, enabled else { return }
                self.reload(for: self.controller.currentVideoID)
            }
            .store(in: &cancellables)

        controller.clock.$currentTime
            .receive(on: DispatchQueue.main)
            .sink { [weak self] time in self?.checkSkip(at: time) }
            .store(in: &cancellables)
    }

    private func reload(for videoID: String) {
        segments = []
        lastSkipTarget = -1
        fetchTask?.cancel()
        guard store.enabled, !videoID.isEmpty else { return }
        fetchTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let fetched = await self.store.segments(for: videoID)
            guard !Task.isCancelled, self.controller.currentVideoID == videoID else { return }
            self.segments = fetched
        }
    }

    private func checkSkip(at time: Double) {
        guard store.enabled, controller.isPlaying, !segments.isEmpty else { return }
        guard let hit = segments.first(where: {
            store.categories.contains($0.category) && time >= $0.start && time < $0.end - 0.3
        }) else { return }
        // The iframe sometimes lands a hair before the seek target — don't
        // re-skip the segment we just jumped out of.
        guard abs(hit.end - lastSkipTarget) > 0.5 else { return }
        lastSkipTarget = hit.end
        controller.seek(to: hit.end + 0.05)
    }
}
