import AppKit
import Combine
import MediaPlayer

/// Murmur ↔ macOS "Now Playing" integration: hardware media keys, AirPods
/// taps, and the Control Center / Lock Screen tile.
///
/// Two halves:
///   - `MPRemoteCommandCenter` handlers route system transport commands into
///     `PlayerController` (which talks to the YouTube iframe over the JS
///     bridge — main-thread only, hence the dispatches).
///   - `MPNowPlayingInfoCenter` is fed title / artwork / position so the
///     system tile shows the current video. Artwork comes from the key-less
///     `i.ytimg.com` thumbnail for the playing videoID.
///
/// Elapsed time is pushed on state changes and a coarse 3s throttle — macOS
/// extrapolates between pushes from `playbackRate`, so per-tick writes are
/// unnecessary. `playbackState` (macOS-only API) is what marks Murmur as the
/// active "now playing" app so media keys reach us.
///
/// AppDelegate-owned (constructor dependency on PlayerController, per the
/// singleton-vs-env rule); constructed once in `applicationDidFinishLaunching`.
final class NowPlayingBridge {
    private let controller: PlayerController
    private var cancellables: Set<AnyCancellable> = []
    private var artwork: MPMediaItemArtwork?
    private var artworkVideoID: String?

    init(controller: PlayerController) {
        self.controller = controller
        installRemoteCommands()
        installSinks()
    }

    // MARK: - System → Murmur (remote commands)

    private func installRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()

        // When a radio station is loaded, transport commands act on the
        // RadioPlayer instead of the YouTube iframe.
        center.playCommand.addTarget { [weak self] _ in
            DispatchQueue.main.async {
                if RadioPlayer.shared.station != nil { RadioPlayer.shared.resume() }
                else { self?.controller.play() }
            }
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            DispatchQueue.main.async {
                if RadioPlayer.shared.station != nil { RadioPlayer.shared.pause() }
                else { self?.controller.pause() }
            }
            return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            DispatchQueue.main.async {
                let radio = RadioPlayer.shared
                if radio.station != nil {
                    radio.isPlaying ? radio.pause() : radio.resume()
                    return
                }
                guard let controller = self?.controller else { return }
                controller.isPlaying ? controller.pause() : controller.play()
            }
            return .success
        }
        center.nextTrackCommand.addTarget { [weak self] _ in
            DispatchQueue.main.async {
                guard RadioPlayer.shared.station == nil else { return }
                self?.controller.playNext()
            }
            return .success
        }
        center.previousTrackCommand.addTarget { [weak self] _ in
            DispatchQueue.main.async {
                guard RadioPlayer.shared.station == nil else { return }
                self?.controller.playPrev()
            }
            return .success
        }
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            DispatchQueue.main.async { self?.controller.seek(to: event.positionTime) }
            return .success
        }
    }

    // MARK: - Murmur → system (now-playing info)

    private func installSinks() {
        // `@Published` emits on willSet, so every sink hops through the main
        // queue — by the time it runs, the property holds the new value and
        // `pushInfo()` reads a consistent snapshot.
        controller.$isPlaying
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] playing in
                MPNowPlayingInfoCenter.default().playbackState = playing ? .playing : .paused
                self?.pushInfo()
            }
            .store(in: &cancellables)

        controller.$title
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.pushInfo() }
            .store(in: &cancellables)

        controller.$playbackRate
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.pushInfo() }
            .store(in: &cancellables)

        controller.$currentVideoID
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] videoID in self?.updateArtwork(for: videoID) }
            .store(in: &cancellables)

        controller.clock.$duration
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.pushInfo() }
            .store(in: &cancellables)

        // Coarse elapsed-time sync; also catches seeks from inside the app.
        controller.clock.$currentTime
            .throttle(for: .seconds(3), scheduler: DispatchQueue.main, latest: true)
            .sink { [weak self] _ in self?.pushInfo() }
            .store(in: &cancellables)

        // Radio takes over the tile while a station is loaded.
        RadioPlayer.shared.$station
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.pushInfo() }
            .store(in: &cancellables)
        RadioPlayer.shared.$isPlaying
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] playing in
                guard RadioPlayer.shared.station != nil else { return }
                MPNowPlayingInfoCenter.default().playbackState = playing ? .playing : .paused
                self?.pushInfo()
            }
            .store(in: &cancellables)
    }

    private func pushInfo() {
        // Radio mode: station name, live, no scrubbing.
        if let station = RadioPlayer.shared.station {
            var info: [String: Any] = [
                MPMediaItemPropertyTitle: station.name,
                MPMediaItemPropertyArtist: "Internet Radio",
                MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
                MPNowPlayingInfoPropertyIsLiveStream: true,
                MPNowPlayingInfoPropertyPlaybackRate: RadioPlayer.shared.isPlaying ? 1.0 : 0.0,
            ]
            if let artwork { info[MPMediaItemPropertyArtwork] = artwork }
            MPNowPlayingInfoCenter.default().nowPlayingInfo = info
            return
        }

        var info: [String: Any] = [
            MPMediaItemPropertyTitle: controller.title,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
            MPNowPlayingInfoPropertyPlaybackRate: controller.isPlaying ? controller.playbackRate : 0.0,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: controller.currentTime,
        ]
        let duration = controller.duration
        if duration > 0 {
            info[MPMediaItemPropertyPlaybackDuration] = duration
        } else {
            // Live streams report no duration; tell the tile not to render
            // a scrubber position out of nothing.
            info[MPNowPlayingInfoPropertyIsLiveStream] = true
        }
        if let artwork { info[MPMediaItemPropertyArtwork] = artwork }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func updateArtwork(for videoID: String) {
        guard videoID != artworkVideoID, !videoID.isEmpty else { return }
        artworkVideoID = videoID
        artwork = nil
        pushInfo()

        guard let url = URL(string: "https://i.ytimg.com/vi/\(videoID)/hqdefault.jpg") else { return }
        Task { @MainActor [weak self] in
            guard let (data, _) = try? await URLSession.shared.data(from: url),
                  let image = NSImage(data: data),
                  let self, self.artworkVideoID == videoID
            else { return }
            self.artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
            self.pushInfo()
        }
    }
}
