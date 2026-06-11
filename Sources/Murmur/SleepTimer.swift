import Foundation

/// Fade-out-and-pause timer for falling asleep to a stream. The last
/// `fadeWindow` seconds ramp the player volume toward zero, then playback
/// pauses and the volume is restored (so the next manual play isn't silent).
///
/// `.shared` singleton per the store rule — no constructor dependencies; the
/// `PlayerController` hook is injected by AppDelegate at launch, the same
/// post-init pattern as `WindowOpenerBridge`'s captured closure.
final class SleepTimer: ObservableObject {
    static let shared = SleepTimer()

    /// Seconds left; 0 when the timer is off.
    @Published private(set) var remaining: Int = 0
    var isActive: Bool { remaining > 0 }

    /// Injected by AppDelegate (the controller is AppDelegate-owned).
    weak var controller: PlayerController?

    /// Seconds over which volume ramps down before the pause.
    private static let fadeWindow = 30

    private var timer: Timer?
    private var preFadeVolume: Int? = nil

    private init() {}

    func start(minutes: Int) {
        restoreVolumeIfNeeded()   // restarting mid-fade resets cleanly
        remaining = minutes * 60
        guard timer == nil else { return }
        let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.tick() }
        // `.common` keeps the countdown running while menus are open.
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func cancel() {
        timer?.invalidate()
        timer = nil
        remaining = 0
        restoreVolumeIfNeeded()
    }

    /// "12:34" / "1:05:00" for the footer chip.
    var remainingLabel: String {
        let h = remaining / 3600, m = (remaining % 3600) / 60, s = remaining % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s)
                     : String(format: "%d:%02d", m, s)
    }

    private func tick() {
        guard remaining > 0 else { return }
        remaining -= 1

        if remaining == 0 {
            timer?.invalidate()
            timer = nil
            controller?.pause()
            RadioPlayer.shared.pause()
            // Restore after the pause lands — the iframe accepts setVolume
            // while paused, and the saved level greets the next play.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.restoreVolumeIfNeeded()
            }
            return
        }

        if remaining <= Self.fadeWindow, let controller {
            if preFadeVolume == nil { preFadeVolume = Int(controller.volume) }
            if let base = preFadeVolume {
                let faded = Int(Double(base) * Double(remaining) / Double(Self.fadeWindow))
                controller.setVolume(faded)
                RadioPlayer.shared.setVolume(faded)
            }
        }
    }

    private func restoreVolumeIfNeeded() {
        if let v = preFadeVolume {
            controller?.setVolume(v)
            RadioPlayer.shared.setVolume(v)
            preFadeVolume = nil
        }
    }
}
