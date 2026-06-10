import AppKit
import Combine

/// Live score in the menu bar: while any World Cup match is in play (and
/// the ticker setting is on), the status item shows a compact scoreline
/// next to the brand icon — `MEX 1–0 RSA 67'` — rotating between
/// simultaneous matches every few seconds. Clears back to icon-only when
/// nothing is live.
///
/// Owns no AppKit resources itself: AppDelegate hands over its existing
/// `NSStatusItem` via `attach(_:)` after creating it.
final class WorldCupTicker {
    static let shared = WorldCupTicker()

    private weak var statusItem: NSStatusItem?
    private var cancellables = Set<AnyCancellable>()
    private var rotateTimer: Timer?
    private var rotateIndex = 0

    private var liveMatches: [WorldCupMatch] = []

    func attach(_ item: NSStatusItem) {
        statusItem = item
        guard cancellables.isEmpty else { render(); return }

        WorldCupStore.shared.$matches
            .receive(on: DispatchQueue.main)
            .sink { [weak self] matches in
                self?.liveMatches = matches.filter { $0.state == .live }
                self?.render()
            }
            .store(in: &cancellables)

        WorldCupAlertSettings.shared.$tickerEnabled
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                // Setting flips don't change liveMatches; just re-render.
                DispatchQueue.main.async { self?.render() }
            }
            .store(in: &cancellables)
    }

    private func render() {
        guard let button = statusItem?.button else { return }

        let shown = WorldCupAlertSettings.shared.tickerEnabled ? liveMatches : []
        guard !shown.isEmpty else {
            button.attributedTitle = NSAttributedString(string: "")
            button.imagePosition = .imageOnly
            stopRotation()
            return
        }

        if rotateIndex >= shown.count { rotateIndex = 0 }
        let match = shown[rotateIndex]
        let clock = match.clock.isEmpty ? "LIVE" : match.clock
        let text = " \(match.home.abbrev) \(match.home.score ?? "0")–\(match.away.score ?? "0") \(match.away.abbrev) \(clock)"

        let title = NSMutableAttributedString(
            string: text,
            attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold),
                .baselineOffset: 0.5,
            ])
        // Tint the clock segment so "67'" reads as live at a glance.
        if let range = text.range(of: clock, options: .backwards) {
            title.addAttribute(.foregroundColor,
                               value: NSColor.systemRed,
                               range: NSRange(range, in: text))
        }
        button.attributedTitle = title
        button.imagePosition = .imageLeft

        shown.count > 1 ? startRotation() : stopRotation()
    }

    private func startRotation() {
        guard rotateTimer == nil else { return }
        rotateTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.rotateIndex += 1
            self.render()
        }
    }

    private func stopRotation() {
        rotateTimer?.invalidate()
        rotateTimer = nil
        rotateIndex = 0
    }
}
