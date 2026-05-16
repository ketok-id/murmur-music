import Combine
import Foundation

/// Owns the two Ambient Layer channels — backing webviews + observable state.
///
/// The layer wires `AmbientChannelState` mutations to the underlying
/// `AmbientPlayer`. A `moodBias` (0…1) is applied as a multiplier on top of
/// each channel's `volume`, so the Mood Dial can scale the whole layer
/// without overwriting per-channel levels.
final class AmbientLayer: ObservableObject {
    let channel1 = AmbientChannelState()
    let channel2 = AmbientChannelState()

    private let player1 = AmbientPlayer()
    private let player2 = AmbientPlayer()

    private var cancellables = Set<AnyCancellable>()

    /// 0…1 scalar applied to all ambient channel volumes (Mood Dial input).
    @Published var moodBias: Float = 0.7 {
        didSet { applyVolumes() }
    }

    init() {
        channel1.$source.dropFirst().sink { [weak self] src in self?.applySource(src, to: self?.player1) }
            .store(in: &cancellables)
        channel2.$source.dropFirst().sink { [weak self] src in self?.applySource(src, to: self?.player2) }
            .store(in: &cancellables)
        channel1.$volume.sink { [weak self] _ in self?.applyVolumes() }.store(in: &cancellables)
        channel2.$volume.sink { [weak self] _ in self?.applyVolumes() }.store(in: &cancellables)
        channel1.$muted.sink { [weak self] _ in self?.applyVolumes() }.store(in: &cancellables)
        channel2.$muted.sink { [weak self] _ in self?.applyVolumes() }.store(in: &cancellables)
    }

    private func applySource(_ source: AmbientSource?, to player: AmbientPlayer?) {
        guard let player = player else { return }
        if let src = source {
            player.loadAndPlay(videoID: src.id)
        } else {
            player.stop()
        }
        applyVolumes()
    }

    private func applyVolumes() {
        let v1 = channel1.baseGain * moodBias
        let v2 = channel2.baseGain * moodBias
        player1.setVolume(Int(v1 * 100))
        player2.setVolume(Int(v2 * 100))
    }
}
