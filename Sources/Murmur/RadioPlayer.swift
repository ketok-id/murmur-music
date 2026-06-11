import AVFoundation
import Combine
import Foundation

/// Native internet-radio playback — a second audio path beside the YouTube
/// webview, because radio streams are plain HTTP(S)/HLS audio that AVPlayer
/// eats directly (the booth's AVAudioEngine already proves native audio
/// coexists with the player webview).
///
/// Mutual exclusion with the YouTube player is two-way:
///   - `play(_:)` pauses the YouTube iframe first;
///   - a sink on `controller.$isPlaying` stops the radio the moment YouTube
///     starts playing again.
/// The footer volume slider drives both — a sink mirrors `controller.$volume`
/// into the AVPlayer.
///
/// `.shared` singleton with the controller injected post-init by AppDelegate
/// (the SleepTimer / MiniPillPanel pattern).
///
/// Note: many directory streams are plain `http://`. The bundled app carries
/// the media-only ATS exception (`NSAllowsArbitraryLoadsForMedia`) in
/// Info.plist; under `swift run` (no Info.plist) those http stations won't
/// load — https ones still do.
final class RadioPlayer: ObservableObject {
    static let shared = RadioPlayer()

    @Published private(set) var station: RadioStation? = nil
    @Published private(set) var isPlaying = false
    @Published private(set) var isBuffering = false

    /// Injected by AppDelegate.
    weak var controller: PlayerController? {
        didSet { installSinks() }
    }

    private let player = AVPlayer()
    private var statusCancellable: AnyCancellable?
    private var controllerCancellables = Set<AnyCancellable>()

    private init() {
        statusCancellable = player.publisher(for: \.timeControlStatus)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                self?.isPlaying = status == .playing
                self?.isBuffering = status == .waitingToPlayAtSpecifiedRate
            }
    }

    func play(_ s: RadioStation) {
        controller?.pause()
        station = s
        player.replaceCurrentItem(with: AVPlayerItem(url: s.streamURL))
        player.volume = Float((controller?.volume ?? 70) / 100)
        player.play()
        RadioBrowserAPI.reportClick(uuid: s.uuid)
    }

    /// Resume after `pause()` — rejoins the live edge.
    func resume() {
        guard station != nil else { return }
        player.play()
    }

    func pause() { player.pause() }

    /// Stop and tear the stream down (close button / YouTube takeover).
    func stop() {
        player.pause()
        player.replaceCurrentItem(with: nil)
        station = nil
    }

    /// Sleep-timer fade hook (the slider mirror covers normal volume).
    func setVolume(_ v: Int) {
        player.volume = Float(max(0, min(100, v))) / 100
    }

    private func installSinks() {
        controllerCancellables.removeAll()
        guard let controller else { return }

        // YouTube starting means the user moved on — kill the radio.
        controller.$isPlaying
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] ytPlaying in
                guard let self, ytPlaying, self.station != nil else { return }
                self.stop()
            }
            .store(in: &controllerCancellables)

        controller.$volume
            .receive(on: DispatchQueue.main)
            .sink { [weak self] volume in
                self?.player.volume = Float(volume / 100)
            }
            .store(in: &controllerCancellables)
    }
}
