import AVFoundation
import Foundation

/// Drives seamless looping on an `AVAudioPlayerNode` by repeatedly scheduling
/// the same beat-quantized segment.
///
/// When `engage(player:file:inSeconds:outSeconds:)` is called, the engine stops
/// the player, reschedules a segment for the loop region, and registers a
/// completion callback that immediately re-queues the same segment so playback
/// continues into the next loop iteration with no audible gap.
///
/// Call `disengage()` to stop looping; the player will play out the current
/// loop iteration to completion (no clicks) and then schedule the rest of the
/// file from the loop's out-point onward.
final class LoopEngine {
    private weak var player: AVAudioPlayerNode?
    private var file: AVAudioFile?
    private var inFrame: AVAudioFramePosition = 0
    private var outFrame: AVAudioFramePosition = 0
    private var active: Bool = false

    /// True when looping is currently engaged.
    var isEngaged: Bool { active }

    /// Engage a loop on the given player. Stops current playback, schedules
    /// the loop segment, and arranges seamless re-scheduling.
    func engage(player: AVAudioPlayerNode, file: AVAudioFile, inSeconds: Double, outSeconds: Double) {
        let sr = file.processingFormat.sampleRate
        let inFrame = AVAudioFramePosition(max(0, inSeconds) * sr)
        let outFrame = AVAudioFramePosition(min(Double(file.length), outSeconds * sr))
        guard outFrame > inFrame else { return }

        self.player = player
        self.file = file
        self.inFrame = inFrame
        self.outFrame = outFrame
        self.active = true

        let wasPlaying = player.isPlaying
        player.stop()
        scheduleLoopSegment()
        if wasPlaying { player.play() }
    }

    /// Stop looping. Subsequent playback continues from the loop out-point
    /// to the end of the file.
    func disengage() {
        guard active, let player = player, let file = file else {
            active = false
            return
        }
        active = false
        let remaining = file.length - outFrame
        guard remaining > 0 else { return }
        player.scheduleSegment(file,
                               startingFrame: outFrame,
                               frameCount: AVAudioFrameCount(remaining),
                               at: nil,
                               completionHandler: nil)
    }

    private func scheduleLoopSegment() {
        guard let player = player, let file = file, active else { return }
        let frameCount = AVAudioFrameCount(outFrame - inFrame)
        player.scheduleSegment(file,
                               startingFrame: inFrame,
                               frameCount: frameCount,
                               at: nil) { [weak self] in
            guard let self = self, self.active else { return }
            self.scheduleLoopSegment()
        }
    }
}
