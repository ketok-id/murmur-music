import AppKit
import Combine
import UserNotifications

// MARK: - Settings

/// User-facing switches for the live-update machinery, persisted to
/// UserDefaults. Surfaced in the World Cup window's bell popover.
final class WorldCupAlertSettings: ObservableObject {
    static let shared = WorldCupAlertSettings()

    enum GoalScope: String, CaseIterable {
        case all = "All matches"
        case followed = "Followed"
        case off = "Off"
    }

    @Published var goalScope: GoalScope {
        didSet { UserDefaults.standard.set(goalScope.rawValue, forKey: Self.kScope) }
    }
    @Published var kickoffReminders: Bool {
        didSet { UserDefaults.standard.set(kickoffReminders, forKey: Self.kReminders) }
    }
    @Published var tickerEnabled: Bool {
        didSet { UserDefaults.standard.set(tickerEnabled, forKey: Self.kTicker) }
    }
    @Published var autoTuneRadio: Bool {
        didSet { UserDefaults.standard.set(autoTuneRadio, forKey: Self.kAutoTune) }
    }
    @Published var dailyDigest: Bool {
        didSet { UserDefaults.standard.set(dailyDigest, forKey: Self.kDigest) }
    }

    private static let kScope     = "youtube-audio-widget.worldcup.goalScope"
    private static let kReminders = "youtube-audio-widget.worldcup.kickoffReminders"
    private static let kTicker    = "youtube-audio-widget.worldcup.ticker"
    private static let kAutoTune  = "youtube-audio-widget.worldcup.autoTune"
    private static let kDigest    = "youtube-audio-widget.worldcup.dailyDigest"

    private init() {
        let d = UserDefaults.standard
        goalScope = GoalScope(rawValue: d.string(forKey: Self.kScope) ?? "") ?? .all
        kickoffReminders = d.object(forKey: Self.kReminders) as? Bool ?? true
        tickerEnabled = d.object(forKey: Self.kTicker) as? Bool ?? true
        autoTuneRadio = d.object(forKey: Self.kAutoTune) as? Bool ?? false
        dailyDigest = d.object(forKey: Self.kDigest) as? Bool ?? true
    }
}

// MARK: - Notifier

/// Watches `WorldCupStore.matches` and turns state changes into macOS
/// notifications + side effects:
///   - score change while live  → "⚽ 23' — Mexico 1–0 South Africa"
///   - scheduled → live         → kickoff notification (+ optional
///                                auto-tune: load talkSPORT into the player)
///   - live → finished          → full-time notification
///   - T-15min for followed     → kickoff reminder
///
/// Detection rides the store's existing poll, so timing is as fresh as the
/// poll cadence (60s during live windows). The very first snapshot after
/// launch is recorded but never notified — otherwise starting Murmur
/// mid-match would replay the whole scoreline.
///
/// UNUserNotificationCenter requires a real bundle: `swift run` binaries
/// have none and would crash on `.current()`, so everything no-ops there
/// (`notificationsAvailable`).
final class WorldCupNotifier: NSObject {
    static let shared = WorldCupNotifier()

    private weak var controller: PlayerController?
    private var cancellable: AnyCancellable?
    private var previous: [String: WorldCupMatch] = [:]
    private var hasSnapshot = false
    private var remindedKickoffs = Set<String>()
    private var authRequested = false

    private var notificationsAvailable: Bool { Bundle.main.bundleIdentifier != nil }
    private var settings: WorldCupAlertSettings { .shared }

    /// Called once from AppDelegate after the player exists. Starting the
    /// sink here (not in init) keeps singleton init free of side effects.
    func attach(controller: PlayerController) {
        self.controller = controller
        guard cancellable == nil else { return }
        if notificationsAvailable {
            UNUserNotificationCenter.current().delegate = self
        }
        cancellable = WorldCupStore.shared.$matches
            .receive(on: DispatchQueue.main)
            .sink { [weak self] matches in self?.process(matches) }
    }

    private func process(_ matches: [WorldCupMatch]) {
        defer {
            previous = Dictionary(uniqueKeysWithValues: matches.map { ($0.id, $0) })
            hasSnapshot = true
        }
        guard hasSnapshot else { return }
        checkDailyDigest(matches)

        for match in matches {
            let old = previous[match.id]
            checkKickoffReminder(match)
            guard let old else { continue }

            if old.state == .scheduled && match.state == .live {
                kickedOff(match)
            }
            if match.state == .live, let oldHome = old.home.score, let oldAway = old.away.score,
               let newHome = match.home.score, let newAway = match.away.score,
               (oldHome != newHome || oldAway != newAway) {
                scoreChanged(match, old: old)
            }
            if old.state == .live && match.state == .finished {
                fullTime(match)
            }
        }
    }

    // MARK: Triggers

    private func scoreChanged(_ match: WorldCupMatch, old: WorldCupMatch) {
        guard inScope(match) else { return }
        // A total that went DOWN is a goal taken off the board (VAR/correction),
        // not a goal — say so instead of celebrating.
        let oldTotal = (Int(old.home.score ?? "") ?? 0) + (Int(old.away.score ?? "") ?? 0)
        let newTotal = (Int(match.home.score ?? "") ?? 0) + (Int(match.away.score ?? "") ?? 0)
        let prefix = newTotal < oldTotal
            ? "🚫 Goal disallowed — "
            : "⚽ \(match.clock.isEmpty ? "Goal" : match.clock) — "
        notify(id: "goal-\(match.id)-\(match.home.score ?? "")-\(match.away.score ?? "")",
               title: prefix + scoreline(match),
               body: "\(match.stage) · \(match.venue)",
               matchID: match.id)
    }

    private func kickedOff(_ match: WorldCupMatch) {
        if inScope(match) {
            notify(id: "ko-\(match.id)",
                   title: "🏟️ Kick-off — \(match.home.name) vs \(match.away.name)",
                   body: "\(match.stage) · \(match.venue)",
                   matchID: match.id)
        }
        // Auto-tune: load live radio commentary for followed kick-offs.
        if settings.autoTuneRadio,
           WorldCupFollowStore.shared.involvesFollowedTeam(match),
           let controller {
            Task { @MainActor in
                if let id = try? await YouTubeLiveResolver.topLiveVideoID(
                    matching: match.searchQuery) {
                    _ = controller.load(input: id)
                }
            }
        }
    }

    private func fullTime(_ match: WorldCupMatch) {
        guard inScope(match) else { return }
        // Knockout shootouts: surface the penalty score alongside the draw.
        var title = "FT — \(scoreline(match))"
        if let hp = match.home.shootoutScore, let ap = match.away.shootoutScore {
            title += " (\(hp)–\(ap) pens)"
        }
        notify(id: "ft-\(match.id)",
               title: title,
               body: "\(match.stage) · \(match.venue)",
               matchID: match.id)
    }

    /// Once per day after 08:00 local: today's remaining fixtures in one
    /// notification, followed teams starred.
    private func checkDailyDigest(_ matches: [WorldCupMatch]) {
        guard settings.dailyDigest else { return }
        guard Calendar.current.component(.hour, from: Date()) >= 8 else { return }
        let todayKey = Self.dayKey.string(from: Date())
        guard UserDefaults.standard.string(forKey: Self.kDigestSent) != todayKey else { return }

        let today = matches
            .filter { Calendar.current.isDateInToday($0.date) && $0.state != .finished }
            .sorted { $0.date < $1.date }
        guard !today.isEmpty else { return }

        UserDefaults.standard.set(todayKey, forKey: Self.kDigestSent)
        let lines = today.prefix(6).map { match -> String in
            let star = WorldCupFollowStore.shared.involvesFollowedTeam(match) ? " ⭐" : ""
            let when = match.state == .live ? "LIVE" : Self.digestTime.string(from: match.date)
            return "\(match.home.abbrev) vs \(match.away.abbrev) \(when)\(star)"
        }
        let extra = today.count > 6 ? " +\(today.count - 6) more" : ""
        notify(id: "digest-\(todayKey)",
               title: "⚽ Today at the World Cup — \(today.count) match\(today.count == 1 ? "" : "es")",
               body: lines.joined(separator: " · ") + extra)
    }

    private static let kDigestSent = "youtube-audio-widget.worldcup.digestSentDay"
    private static let dayKey: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
    private static let digestTime: DateFormatter = {
        let f = DateFormatter()
        f.timeStyle = .short
        f.dateStyle = .none
        return f
    }()

    private func checkKickoffReminder(_ match: WorldCupMatch) {
        guard settings.kickoffReminders,
              match.state == .scheduled,
              WorldCupFollowStore.shared.involvesFollowedTeam(match),
              !remindedKickoffs.contains(match.id) else { return }
        let lead = match.date.timeIntervalSinceNow
        guard lead > 0 && lead <= 15 * 60 else { return }
        remindedKickoffs.insert(match.id)
        notify(id: "remind-\(match.id)",
               title: "⏰ \(match.home.name) vs \(match.away.name) kicks off soon",
               body: "In about \(max(1, Int(lead / 60))) min · \(match.venue)",
               matchID: match.id)
    }

    // MARK: Helpers

    private func inScope(_ match: WorldCupMatch) -> Bool {
        switch settings.goalScope {
        case .all: return true
        case .followed: return WorldCupFollowStore.shared.involvesFollowedTeam(match)
        case .off: return false
        }
    }

    private func scoreline(_ match: WorldCupMatch) -> String {
        "\(match.home.name) \(match.home.score ?? "0")–\(match.away.score ?? "0") \(match.away.name)"
    }

    private func notify(id: String, title: String, body: String, matchID: String? = nil) {
        guard notificationsAvailable else { return }
        let center = UNUserNotificationCenter.current()
        let fire = {
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
            if let matchID { content.userInfo = ["matchID": matchID] }
            center.add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
        }
        if authRequested {
            fire()
        } else {
            authRequested = true
            center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
                if granted { fire() }
            }
        }
    }
}

extension WorldCupNotifier: UNUserNotificationCenterDelegate {
    /// Show banners even while Murmur is the active app.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    /// Clicking a notification opens the World Cup board (same path as the
    /// murmur://worldcup deep link), focused on the match that fired it.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let matchID = response.notification.request.content.userInfo["matchID"] as? String
        DispatchQueue.main.async {
            if let matchID { WorldCupNavState.shared.targetMatchID = matchID }
            NotificationCenter.default.post(name: .murmurOpenWorldCup, object: nil)
        }
        completionHandler()
    }
}
