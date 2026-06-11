import Foundation
import ServiceManagement

/// `SMAppService` wrapper behind the Settings toggle. Only meaningful in the
/// bundled .app — the `swift run` dev binary has no bundle identifier, so the
/// toggle hides itself there (`isAvailable`).
enum LaunchAtLogin {
    static var isAvailable: Bool { Bundle.main.bundleIdentifier != nil }

    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    /// Returns false when registration fails (e.g. the user denied it in
    /// System Settings); callers should re-read `isEnabled` to resync UI.
    @discardableResult
    static func set(_ enabled: Bool) -> Bool {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            return true
        } catch {
            return false
        }
    }
}
