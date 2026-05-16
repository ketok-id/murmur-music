import AVFoundation
import Combine
import Foundation

/// Single-source playback of one Recording.
final class RecordingPlayer: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published private(set) var nowPlayingURL: URL? = nil
    @Published private(set) var currentTime: Double = 0
    @Published private(set) var duration: Double = 0

    private var player: AVAudioPlayer?
    private var timer: Timer?

    var isPlaying: Bool { player?.isPlaying ?? false }

    deinit {
        timer?.invalidate()
    }

    func play(_ recording: Recording) {
        if nowPlayingURL == recording.url, let p = player {
            if p.isPlaying { p.pause() } else { p.play() }
            nowPlayingURL = nowPlayingURL
            return
        }
        stop()
        do {
            let p = try AVAudioPlayer(contentsOf: recording.url)
            p.delegate = self
            p.prepareToPlay()
            p.play()
            self.player = p
            self.nowPlayingURL = recording.url
            self.duration = p.duration
            startTimer()
        } catch {
            NSLog("[RecordingPlayer] failed to play \(recording.url.lastPathComponent): \(error)")
        }
    }

    func stop() {
        player?.stop()
        player = nil
        nowPlayingURL = nil
        currentTime = 0
        duration = 0
        timer?.invalidate()
        timer = nil
    }

    func isLoaded(_ recording: Recording) -> Bool {
        nowPlayingURL == recording.url
    }

    func isPlaying(_ recording: Recording) -> Bool {
        nowPlayingURL == recording.url && (player?.isPlaying ?? false)
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self = self, let p = self.player else { return }
            self.currentTime = p.currentTime
        }
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        stop()
    }
}
