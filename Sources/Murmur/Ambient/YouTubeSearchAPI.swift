import Foundation

struct YTSearchResult: Identifiable, Equatable {
    let videoID: String
    let title: String
    let channelTitle: String
    let thumbnailURL: URL?

    var id: String { videoID }
}

enum YouTubeSearchAPI {
    enum SearchError: Error, LocalizedError {
        case noAPIKey
        case quotaExceeded
        case invalidKey
        case network(String)
        case decode(String)

        var errorDescription: String? {
            switch self {
            case .noAPIKey:        return "No YouTube API key configured."
            case .quotaExceeded:   return "Daily search quota exceeded. Try again tomorrow."
            case .invalidKey:      return "API key rejected by YouTube. Check it in Settings."
            case .network(let m):  return "Network error: \(m)"
            case .decode(let m):   return "Couldn't read YouTube's response: \(m)"
            }
        }
    }

    static func search(query: String, apiKey: String, maxResults: Int = 10) async throws -> [YTSearchResult] {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedQuery = query.trimmingCharacters(in: .whitespaces)
        guard !trimmedKey.isEmpty else { throw SearchError.noAPIKey }
        guard !trimmedQuery.isEmpty else { return [] }

        var components = URLComponents(string: "https://www.googleapis.com/youtube/v3/search")!
        components.queryItems = [
            URLQueryItem(name: "part", value: "snippet"),
            URLQueryItem(name: "q", value: trimmedQuery),
            URLQueryItem(name: "type", value: "video"),
            URLQueryItem(name: "maxResults", value: String(maxResults)),
            URLQueryItem(name: "key", value: trimmedKey),
        ]
        guard let url = components.url else {
            throw SearchError.network("Failed to build URL")
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(from: url)
        } catch {
            throw SearchError.network(error.localizedDescription)
        }

        if let http = response as? HTTPURLResponse {
            switch http.statusCode {
            case 200: break
            case 400: throw SearchError.invalidKey
            case 403:
                let body = String(data: data, encoding: .utf8) ?? ""
                if body.contains("quotaExceeded") || body.contains("dailyLimitExceeded") {
                    throw SearchError.quotaExceeded
                } else {
                    throw SearchError.invalidKey
                }
            default:
                throw SearchError.network("HTTP \(http.statusCode)")
            }
        }

        do {
            let decoded = try JSONDecoder().decode(YouTubeSearchResponse.self, from: data)
            return decoded.items.compactMap { item -> YTSearchResult? in
                guard let videoID = item.id.videoId else { return nil }
                let thumbURL = item.snippet.thumbnails.medium.map { URL(string: $0.url) } ?? nil
                return YTSearchResult(
                    videoID: videoID,
                    title: item.snippet.title,
                    channelTitle: item.snippet.channelTitle,
                    thumbnailURL: thumbURL ?? nil
                )
            }
        } catch {
            throw SearchError.decode(error.localizedDescription)
        }
    }
}

private struct YouTubeSearchResponse: Decodable {
    let items: [Item]

    struct Item: Decodable {
        let id: IdBlock
        let snippet: Snippet
    }
    struct IdBlock: Decodable {
        let videoId: String?
    }
    struct Snippet: Decodable {
        let title: String
        let channelTitle: String
        let thumbnails: Thumbnails
    }
    struct Thumbnails: Decodable {
        let medium: Thumb?
    }
    struct Thumb: Decodable {
        let url: String
    }
}
