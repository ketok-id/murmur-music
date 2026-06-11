import Foundation

/// ListenBrainz scrobbling client. Key-less in the app sense — the credential
/// is the user's own free token from listenbrainz.org/settings, pasted into
/// Murmur's Settings (the same user-owned-credential model as the optional
/// YouTube API key). Empty token = scrobbling off.
///
/// Submission timing lives in `ListeningRecorder`; this store just persists
/// the token and talks HTTP. Rate limits are dynamic (X-RateLimit-* headers);
/// at Murmur's one-listen-per-track volume they're unreachable, so failures
/// are dropped silently after surfacing in `lastStatus`.
final class ListenBrainzStore: ObservableObject {
    static let shared = ListenBrainzStore()

    private static let tokenKey = "youtube-audio-widget.listenbrainz.token"

    @Published var token: String {
        didSet { UserDefaults.standard.set(token, forKey: Self.tokenKey) }
    }
    /// Last submit/validate outcome, shown in Settings ("Scrobbling as ketok").
    @Published private(set) var lastStatus: String? = nil

    var isEnabled: Bool { !token.trimmingCharacters(in: .whitespaces).isEmpty }

    private init() {
        token = UserDefaults.standard.string(forKey: Self.tokenKey) ?? ""
    }

    /// Returns the account's username, or nil if the token is rejected.
    func validate(_ candidate: String) async -> String? {
        guard let url = URL(string: "https://api.listenbrainz.org/1/validate-token") else { return nil }
        var request = URLRequest(url: url)
        request.setValue("Token \(candidate.trimmingCharacters(in: .whitespaces))", forHTTPHeaderField: "Authorization")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let decoded = try? JSONDecoder().decode(ValidateResponse.self, from: data),
              decoded.valid
        else { return nil }
        return decoded.user_name
    }

    func submitPlayingNow(artist: String, track: String) {
        submit(listenType: "playing_now", payload: [
            ["track_metadata": ["artist_name": artist, "track_name": track]]
        ])
    }

    func submitListen(artist: String, track: String, listenedAt: Date) {
        submit(listenType: "single", payload: [
            [
                "listened_at": Int(listenedAt.timeIntervalSince1970),
                "track_metadata": ["artist_name": artist, "track_name": track],
            ]
        ])
    }

    private func submit(listenType: String, payload: [[String: Any]]) {
        let trimmed = token.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty,
              let url = URL(string: "https://api.listenbrainz.org/1/submit-listens")
        else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Token \(trimmed)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "listen_type": listenType,
            "payload": payload,
        ])
        // Strong self is fine — the store is a process-lifetime singleton.
        Task { @MainActor in
            guard let (_, response) = try? await URLSession.shared.data(for: request) else { return }
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            self.lastStatus = code == 200
                ? nil
                : "ListenBrainz rejected the last submit (HTTP \(code))."
        }
    }

    private struct ValidateResponse: Decodable {
        let valid: Bool
        let user_name: String?
    }
}
