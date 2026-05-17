import Combine
import Foundation

/// Client-side estimate of YouTube Data API v3 quota usage.
final class QuotaTracker: ObservableObject {
    static let shared = QuotaTracker()

    static let dailyLimit = 10_000

    @Published private(set) var usedToday: Int = 0

    private let usedKey = "youtube-audio-widget.quota-used.v1"
    private let dayKey  = "youtube-audio-widget.quota-day.v1"

    private init() { load() }

    var remainingToday: Int { max(0, Self.dailyLimit - usedToday) }

    var fractionUsed: Double {
        min(1, Double(usedToday) / Double(Self.dailyLimit))
    }

    func record(cost: Int) {
        rolloverIfNeeded()
        usedToday += cost
        save()
    }

    func resetToday() {
        usedToday = 0
        save()
    }

    private func load() {
        rolloverIfNeeded()
        usedToday = UserDefaults.standard.integer(forKey: usedKey)
    }

    private func save() {
        UserDefaults.standard.set(usedToday, forKey: usedKey)
    }

    private func rolloverIfNeeded() {
        let today = currentPacificDay()
        let lastDay = UserDefaults.standard.string(forKey: dayKey) ?? ""
        if today != lastDay {
            usedToday = 0
            UserDefaults.standard.set(today, forKey: dayKey)
            UserDefaults.standard.set(0, forKey: usedKey)
        }
    }

    private func currentPacificDay() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "America/Los_Angeles")
        return formatter.string(from: Date())
    }
}
