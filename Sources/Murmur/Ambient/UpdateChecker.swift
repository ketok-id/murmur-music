import Foundation

/// Polls the GitHub Releases API for the latest published Murmur release and
/// compares the tag against the running app's `CFBundleShortVersionString`.
///
/// Best-effort — silent on network failure, rate limiting, or private-repo
/// responses. The `swift run` dev build has no Info.plist, so `currentVersion`
/// reports `dev` in that case and `hasUpdate` always returns false (you can't
/// meaningfully compare "dev" against a tag).
final class UpdateChecker: ObservableObject {
    static let shared = UpdateChecker()

    /// GitHub Releases endpoint for this project. Tied to the repo configured
    /// in `git remote`. If the repo moves, update both this URL and the
    /// `ketok-id/murmur-music` string in the README / CLAUDE.md.
    static let releasesAPI = URL(string:
        "https://api.github.com/repos/ketok-id/murmur-music/releases/latest")!

    /// How often to re-check while the app is running. GitHub's unauthenticated
    /// API allows ~60 requests/hour per IP, so 6h is generous.
    static let recheckInterval: TimeInterval = 6 * 3600

    /// Progress of an in-app self-update (download → unpack → relaunch).
    enum InstallState: Equatable {
        case idle
        case working
        case failed(String)
    }

    @Published private(set) var currentVersion: String
    @Published private(set) var latestVersion: String? = nil
    @Published private(set) var releaseURL: URL? = nil
    /// Direct download URL of the release's `Murmur.zip` asset, used by the
    /// in-app updater. Nil if the release published no zip asset.
    @Published private(set) var downloadURL: URL? = nil
    @Published private(set) var releaseNotes: String = ""
    @Published private(set) var lastCheckedAt: Date? = nil
    @Published private(set) var isChecking: Bool = false
    @Published var installState: InstallState = .idle

    var hasUpdate: Bool {
        guard let latest = latestVersion, currentVersion != "dev" else { return false }
        return Self.compare(current: currentVersion, latest: latest) == .orderedAscending
    }

    /// True when an update exists and we have a zip asset to install from —
    /// i.e. the "Update & Restart" button can actually self-install rather
    /// than just opening the release page.
    var canSelfUpdate: Bool { hasUpdate && downloadURL != nil }

    /// Download the latest `Murmur.zip` and swap-and-relaunch in place. On
    /// success the app terminates (the helper finishes the install); failures
    /// surface in `installState` and leave the running app untouched.
    @MainActor
    func downloadAndInstall() {
        guard installState != .working, let url = downloadURL else { return }
        installState = .working
        Task { @MainActor in
            do {
                try await SelfUpdater.downloadAndInstall(zipURL: url)
            } catch {
                installState = .failed(error.localizedDescription)
            }
        }
    }

    private var checkTask: Task<Void, Never>?
    private var loopTask: Task<Void, Never>?

    private init() {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        currentVersion = (v?.isEmpty == false) ? v! : "dev"
    }

    /// Kick off an immediate check and start a background re-check loop.
    /// Called once from `AppDelegate.applicationDidFinishLaunching`.
    func startBackgroundChecks() {
        check()
        loopTask?.cancel()
        loopTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(Self.recheckInterval * 1_000_000_000))
                if Task.isCancelled { return }
                self?.check()
            }
        }
    }

    /// Manual one-shot check, idempotent while a check is in flight.
    func check() {
        guard checkTask == nil else { return }
        isChecking = true
        checkTask = Task { [weak self] in
            await self?.performCheck()
            guard let self else { return }
            await MainActor.run {
                self.checkTask = nil
                self.isChecking = false
                self.lastCheckedAt = Date()
            }
        }
    }

    private func performCheck() async {
        var req = URLRequest(url: Self.releasesAPI)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.cachePolicy = .reloadIgnoringLocalCacheData
        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return }
            struct Release: Decodable {
                let tag_name: String
                let html_url: String
                let body: String?
                let assets: [Asset]
                struct Asset: Decodable { let name: String; let browser_download_url: String }
            }
            let release = try JSONDecoder().decode(Release.self, from: data)
            let stripped = release.tag_name.trimmingCharacters(in: CharacterSet(charactersIn: "vV "))
            // The in-app updater installs from the ditto-built `Murmur.zip`
            // asset (not the DMG — a zip is trivial to unpack programmatically).
            let zipURL = release.assets
                .first { $0.name.hasSuffix(".zip") }
                .flatMap { URL(string: $0.browser_download_url) }
            await MainActor.run {
                self.latestVersion = stripped
                self.releaseURL = URL(string: release.html_url)
                self.downloadURL = zipURL
                self.releaseNotes = release.body ?? ""
            }
        } catch {
            // Best-effort: swallow. The UI just won't surface an update badge.
        }
    }

    /// Compare two dotted-numeric version strings (e.g. `2026.05.20.3` vs
    /// `2026.05.20.4`). Missing components on either side are treated as 0.
    /// Non-numeric components compare as 0 — release tags should be pure
    /// dotted integers (matching `build-app.sh`'s `VERSION`).
    static func compare(current: String, latest: String) -> ComparisonResult {
        let a = current.split(separator: ".").map { Int($0) ?? 0 }
        let b = latest.split(separator: ".").map { Int($0) ?? 0 }
        let len = max(a.count, b.count)
        for i in 0..<len {
            let av = i < a.count ? a[i] : 0
            let bv = i < b.count ? b[i] : 0
            if av < bv { return .orderedAscending }
            if av > bv { return .orderedDescending }
        }
        return .orderedSame
    }
}
