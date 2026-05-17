import Foundation

struct YTSearchResult: Identifiable, Equatable {
    let videoID: String
    let title: String
    let channelTitle: String
    let thumbnailURL: URL?
    /// Filled in by `YouTubeSearchAPI.fetchVideoDetails` after search.
    var duration: TimeInterval? = nil
    var categoryHint: VideoCategoryHint? = nil

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

    /// Search YouTube for channels matching the query.
    static func searchChannels(query: String, apiKey: String, maxResults: Int = 10) async throws -> [YTChannelResult] {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedQuery = query.trimmingCharacters(in: .whitespaces)
        guard !trimmedKey.isEmpty else { throw SearchError.noAPIKey }
        guard !trimmedQuery.isEmpty else { return [] }

        var components = URLComponents(string: "https://www.googleapis.com/youtube/v3/search")!
        components.queryItems = [
            URLQueryItem(name: "part", value: "snippet"),
            URLQueryItem(name: "q", value: trimmedQuery),
            URLQueryItem(name: "type", value: "channel"),
            URLQueryItem(name: "maxResults", value: String(maxResults)),
            URLQueryItem(name: "key", value: trimmedKey),
        ]
        guard let url = components.url else { throw SearchError.network("Failed to build URL") }

        let (data, response) = try await safeGET(url: url)
        try checkHTTPStatus(response: response, data: data)

        do {
            let decoded = try JSONDecoder().decode(YouTubeChannelSearchResponse.self, from: data)
            return decoded.items.compactMap { item -> YTChannelResult? in
                guard let channelId = item.id.channelId else { return nil }
                let thumbURL = item.snippet.thumbnails.medium.flatMap { URL(string: $0.url) }
                return YTChannelResult(
                    channelId: channelId,
                    title: item.snippet.title,
                    thumbnailURL: thumbURL
                )
            }
        } catch {
            throw SearchError.decode(error.localizedDescription)
        }
    }

    /// Fetch a channel's title, thumbnail, and uploadsPlaylistId.
    static func fetchChannelDetails(channelId: String, apiKey: String) async throws -> (title: String, thumbnailURL: URL?, uploadsPlaylistId: String) {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else { throw SearchError.noAPIKey }

        var components = URLComponents(string: "https://www.googleapis.com/youtube/v3/channels")!
        components.queryItems = [
            URLQueryItem(name: "part", value: "snippet,contentDetails"),
            URLQueryItem(name: "id", value: channelId),
            URLQueryItem(name: "key", value: trimmedKey),
        ]
        guard let url = components.url else { throw SearchError.network("Failed to build URL") }

        let (data, response) = try await safeGET(url: url)
        try checkHTTPStatus(response: response, data: data)

        do {
            let decoded = try JSONDecoder().decode(YouTubeChannelsListResponse.self, from: data)
            guard let item = decoded.items.first else {
                throw SearchError.decode("Channel not found")
            }
            let thumb = item.snippet.thumbnails.medium.flatMap { URL(string: $0.url) }
            return (
                title: item.snippet.title,
                thumbnailURL: thumb,
                uploadsPlaylistId: item.contentDetails.relatedPlaylists.uploads
            )
        } catch let err as SearchError {
            throw err
        } catch {
            throw SearchError.decode(error.localizedDescription)
        }
    }

    /// Resolve a YouTube handle (e.g. "@lofigirl") to channel info.
    /// 1 quota unit (same as fetchChannelDetails).
    static func fetchChannelByHandle(handle: String, apiKey: String) async throws -> (channelId: String, title: String, thumbnailURL: URL?, uploadsPlaylistId: String) {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else { throw SearchError.noAPIKey }
        let cleanHandle = handle.hasPrefix("@") ? handle : "@" + handle

        var components = URLComponents(string: "https://www.googleapis.com/youtube/v3/channels")!
        components.queryItems = [
            URLQueryItem(name: "part", value: "snippet,contentDetails"),
            URLQueryItem(name: "forHandle", value: cleanHandle),
            URLQueryItem(name: "key", value: trimmedKey),
        ]
        guard let url = components.url else { throw SearchError.network("Failed to build URL") }

        let (data, response) = try await safeGET(url: url)
        try checkHTTPStatus(response: response, data: data)

        do {
            let decoded = try JSONDecoder().decode(YouTubeChannelsListWithIdResponse.self, from: data)
            guard let item = decoded.items.first else {
                throw SearchError.decode("Channel not found for \(cleanHandle)")
            }
            let thumb = item.snippet.thumbnails.medium.flatMap { URL(string: $0.url) }
            return (
                channelId: item.id,
                title: item.snippet.title,
                thumbnailURL: thumb,
                uploadsPlaylistId: item.contentDetails.relatedPlaylists.uploads
            )
        } catch let err as SearchError {
            throw err
        } catch {
            throw SearchError.decode(error.localizedDescription)
        }
    }

    /// List a channel's uploads, newest first. Returns a page of ~50 results +
    /// an optional nextPageToken for further pagination.
    static func listChannelUploads(uploadsPlaylistId: String, apiKey: String, pageToken: String? = nil) async throws -> (videos: [YTSearchResult], nextPageToken: String?) {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else { throw SearchError.noAPIKey }
        guard !uploadsPlaylistId.isEmpty else { return ([], nil) }

        var components = URLComponents(string: "https://www.googleapis.com/youtube/v3/playlistItems")!
        var items = [
            URLQueryItem(name: "part", value: "snippet"),
            URLQueryItem(name: "playlistId", value: uploadsPlaylistId),
            URLQueryItem(name: "maxResults", value: "50"),
            URLQueryItem(name: "key", value: trimmedKey),
        ]
        if let pageToken = pageToken, !pageToken.isEmpty {
            items.append(URLQueryItem(name: "pageToken", value: pageToken))
        }
        components.queryItems = items
        guard let url = components.url else { throw SearchError.network("Failed to build URL") }

        let (data, response) = try await safeGET(url: url)
        try checkHTTPStatus(response: response, data: data)

        do {
            let decoded = try JSONDecoder().decode(YouTubePlaylistItemsResponse.self, from: data)
            let videos = decoded.items.compactMap { item -> YTSearchResult? in
                guard let videoId = item.snippet.resourceId.videoId else { return nil }
                let thumb = item.snippet.thumbnails.medium.flatMap { URL(string: $0.url) }
                return YTSearchResult(
                    videoID: videoId,
                    title: item.snippet.title,
                    channelTitle: item.snippet.channelTitle,
                    thumbnailURL: thumb
                )
            }
            return (videos: videos, nextPageToken: decoded.nextPageToken)
        } catch {
            throw SearchError.decode(error.localizedDescription)
        }
    }

    static func fetchVideoDetails(ids: [String], apiKey: String) async throws -> [String: (duration: TimeInterval, categoryId: String)] {
        guard !ids.isEmpty else { return [:] }
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else { throw SearchError.noAPIKey }

        var components = URLComponents(string: "https://www.googleapis.com/youtube/v3/videos")!
        components.queryItems = [
            URLQueryItem(name: "part", value: "contentDetails,snippet"),
            URLQueryItem(name: "id", value: ids.joined(separator: ",")),
            URLQueryItem(name: "key", value: trimmedKey),
        ]
        guard let url = components.url else { throw SearchError.network("Failed to build URL") }

        let (data, response) = try await safeGET(url: url)
        try checkHTTPStatus(response: response, data: data)

        let decoded = try JSONDecoder().decode(YouTubeVideoDetailsResponse.self, from: data)
        var dict: [String: (duration: TimeInterval, categoryId: String)] = [:]
        for item in decoded.items {
            let duration = parseISO8601Duration(item.contentDetails.duration) ?? 0
            dict[item.id] = (duration: duration, categoryId: item.snippet.categoryId)
        }
        return dict
    }

    static func parseISO8601Duration(_ s: String) -> TimeInterval? {
        guard s.hasPrefix("PT") else { return nil }
        var remaining = Substring(s.dropFirst(2))
        var total: TimeInterval = 0
        while !remaining.isEmpty {
            guard let unitIdx = remaining.firstIndex(where: { !$0.isNumber && $0 != "." }) else { return nil }
            let numStr = String(remaining[..<unitIdx])
            guard let num = Double(numStr) else { return nil }
            let unit = remaining[unitIdx]
            switch unit {
            case "H": total += num * 3600
            case "M": total += num * 60
            case "S": total += num
            default: return nil
            }
            remaining = remaining[remaining.index(after: unitIdx)...]
        }
        return total
    }

    // MARK: - Shared HTTP helpers

    private static func safeGET(url: URL) async throws -> (Data, URLResponse) {
        do {
            return try await URLSession.shared.data(from: url)
        } catch {
            throw SearchError.network(error.localizedDescription)
        }
    }

    private static func checkHTTPStatus(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }
        switch http.statusCode {
        case 200: return
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

private struct YouTubeChannelSearchResponse: Decodable {
    let items: [Item]

    struct Item: Decodable {
        let id: IdBlock
        let snippet: Snippet
    }
    struct IdBlock: Decodable {
        let channelId: String?
    }
    struct Snippet: Decodable {
        let title: String
        let thumbnails: Thumbnails
    }
    struct Thumbnails: Decodable {
        let medium: Thumb?
    }
    struct Thumb: Decodable {
        let url: String
    }
}

private struct YouTubeChannelsListResponse: Decodable {
    let items: [Item]

    struct Item: Decodable {
        let snippet: Snippet
        let contentDetails: ContentDetails
    }
    struct Snippet: Decodable {
        let title: String
        let thumbnails: Thumbnails
    }
    struct Thumbnails: Decodable {
        let medium: Thumb?
    }
    struct Thumb: Decodable {
        let url: String
    }
    struct ContentDetails: Decodable {
        let relatedPlaylists: RelatedPlaylists
    }
    struct RelatedPlaylists: Decodable {
        let uploads: String
    }
}

private struct YouTubePlaylistItemsResponse: Decodable {
    let items: [Item]
    let nextPageToken: String?

    struct Item: Decodable {
        let snippet: Snippet
    }
    struct Snippet: Decodable {
        let title: String
        let channelTitle: String
        let thumbnails: Thumbnails
        let resourceId: ResourceId
    }
    struct Thumbnails: Decodable {
        let medium: Thumb?
    }
    struct Thumb: Decodable {
        let url: String
    }
    struct ResourceId: Decodable {
        let videoId: String?
    }
}

private struct YouTubeChannelsListWithIdResponse: Decodable {
    let items: [Item]

    struct Item: Decodable {
        let id: String
        let snippet: Snippet
        let contentDetails: ContentDetails
    }
    struct Snippet: Decodable {
        let title: String
        let thumbnails: Thumbnails
    }
    struct Thumbnails: Decodable {
        let medium: Thumb?
    }
    struct Thumb: Decodable {
        let url: String
    }
    struct ContentDetails: Decodable {
        let relatedPlaylists: RelatedPlaylists
    }
    struct RelatedPlaylists: Decodable {
        let uploads: String
    }
}

private struct YouTubeVideoDetailsResponse: Decodable {
    let items: [Item]

    struct Item: Decodable {
        let id: String
        let snippet: Snippet
        let contentDetails: ContentDetails
    }
    struct Snippet: Decodable {
        let categoryId: String
    }
    struct ContentDetails: Decodable {
        let duration: String
    }
}
