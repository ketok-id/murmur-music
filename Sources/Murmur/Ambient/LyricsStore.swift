import Combine
import Foundation

struct LyricsLine: Equatable {
    let start: Double
    let text: String
}

enum LyricsResult: Equatable {
    case idle
    case loading
    case synced([LyricsLine])
    case plain(String)
    case missing(reason: String)
}

@MainActor
final class LyricsStore: ObservableObject {
    static let shared = LyricsStore()

    @Published private(set) var current: LyricsResult = .idle

    private var cache: [String: LyricsResult] = [:]
    private var inflight: Task<Void, Never>?
    private var activeVideoID: String = ""

    private init() {}

    func clear() {
        inflight?.cancel(); inflight = nil
        activeVideoID = ""
        current = .idle
    }

    func fetch(videoID: String, title: String, duration: Double) {
        guard !videoID.isEmpty else { clear(); return }
        if videoID == activeVideoID, case .loading = current { return }
        activeVideoID = videoID

        if let cached = cache[videoID] {
            current = cached
            return
        }

        inflight?.cancel()
        current = .loading

        guard let (artist, track) = TrackQuery.split(TrackQuery.clean(title)) else {
            let result = LyricsResult.missing(reason: "Couldn't parse artist/track from title")
            cache[videoID] = result
            current = result
            return
        }

        inflight = Task { [weak self] in
            let result = await Self.fetchLRCLIB(artist: artist, track: track, duration: duration)
            guard let self = self else { return }
            await MainActor.run {
                guard !Task.isCancelled, self.activeVideoID == videoID else { return }
                self.cache[videoID] = result
                self.current = result
            }
        }
    }

    // MARK: - LRCLIB

    private struct LRCLIBResponse: Decodable {
        let syncedLyrics: String?
        let plainLyrics: String?
    }

    private static func fetchLRCLIB(artist: String, track: String, duration: Double) async -> LyricsResult {
        var comps = URLComponents(string: "https://lrclib.net/api/get")!
        var items: [URLQueryItem] = [
            URLQueryItem(name: "artist_name", value: artist),
            URLQueryItem(name: "track_name", value: track),
        ]
        if duration > 0 {
            items.append(URLQueryItem(name: "duration", value: String(Int(duration.rounded()))))
        }
        comps.queryItems = items
        guard let url = comps.url else {
            return .missing(reason: "Bad URL")
        }
        var req = URLRequest(url: url)
        req.setValue("Murmur/macOS (https://github.com/ketok-id/murmur-music)",
                     forHTTPHeaderField: "User-Agent")
        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            if let http = response as? HTTPURLResponse, http.statusCode == 404 {
                return .missing(reason: "Not found on LRCLIB")
            }
            let decoded = try JSONDecoder().decode(LRCLIBResponse.self, from: data)
            if let synced = decoded.syncedLyrics, !synced.isEmpty,
               let lines = parseLRC(synced), !lines.isEmpty {
                return .synced(lines)
            }
            if let plain = decoded.plainLyrics, !plain.isEmpty {
                return .plain(plain)
            }
            return .missing(reason: "No lyrics in LRCLIB response")
        } catch is CancellationError {
            return .missing(reason: "Cancelled")
        } catch {
            return .missing(reason: "Network error: \(error.localizedDescription)")
        }
    }

    static func parseLRC(_ source: String) -> [LyricsLine]? {
        guard let regex = try? NSRegularExpression(
            pattern: #"\[(\d{1,2}):(\d{2})(?:\.(\d{1,3}))?\]"#
        ) else { return nil }

        var out: [LyricsLine] = []
        for raw in source.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(raw)
            let nsLine = line as NSString
            let matches = regex.matches(in: line, range: NSRange(location: 0, length: nsLine.length))
            guard !matches.isEmpty else { continue }

            let lastEnd = matches.last!.range.upperBound
            let text = nsLine
                .substring(from: lastEnd)
                .trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty else { continue }

            for m in matches {
                let mm = Int(nsLine.substring(with: m.range(at: 1))) ?? 0
                let ss = Int(nsLine.substring(with: m.range(at: 2))) ?? 0
                let frac: Double = {
                    let r = m.range(at: 3)
                    guard r.location != NSNotFound else { return 0 }
                    let raw = nsLine.substring(with: r)
                    let n = Double(raw) ?? 0
                    let divisor = pow(10.0, Double(raw.count))
                    return n / divisor
                }()
                out.append(LyricsLine(
                    start: Double(mm * 60 + ss) + frac,
                    text: text
                ))
            }
        }
        out.sort { $0.start < $1.start }
        return out.isEmpty ? nil : out
    }
}
