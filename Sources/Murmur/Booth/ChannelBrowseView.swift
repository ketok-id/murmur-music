import SwiftUI

/// Browses one channel's recent uploads. Fetches uploadsPlaylistId on first
/// load (if not already cached on the channel favorite), then lists videos.
struct ChannelBrowseView: View {
    let channel: ChannelFavorite
    var onPickVideo: (YTSearchResult) -> Void
    var onBack: () -> Void

    @ObservedObject private var apiKeyStore = APIKeyStore.shared
    @ObservedObject private var favorites = ChannelFavoritesStore.shared

    @State private var videos: [YTSearchResult] = []
    @State private var nextPageToken: String? = nil
    @State private var loading: Bool = true
    @State private var loadingMore: Bool = false
    @State private var errorMessage: String? = nil
    @State private var uploadsPlaylistId: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.6))
                }
                .buttonStyle(.plain)
                AsyncImage(url: URL(string: channel.thumbnailURL)) { phase in
                    switch phase {
                    case .success(let image): image.resizable().aspectRatio(contentMode: .fill)
                    default: Rectangle().fill(Color.white.opacity(0.05))
                    }
                }
                .frame(width: 22, height: 22)
                .clipShape(Circle())
                Text(channel.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white.opacity(0.92))
                    .lineLimit(1)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color.white.opacity(0.03))
            Divider().background(Color.white.opacity(0.06))

            content
        }
        .task {
            await initialLoad()
        }
    }

    @ViewBuilder
    private var content: some View {
        if loading {
            VStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Loading channel uploads…")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.5))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let err = errorMessage {
            VStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 18))
                    .foregroundColor(.yellow.opacity(0.7))
                Text(err)
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if videos.isEmpty {
            Text("No uploads found.")
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.4))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(videos) { video in
                        videoRow(video)
                        if video.id != videos.last?.id {
                            Divider().background(Color.white.opacity(0.04)).padding(.leading, 104)
                        }
                    }
                    if nextPageToken != nil {
                        loadMoreButton
                    }
                }
            }
        }
    }

    private func videoRow(_ video: YTSearchResult) -> some View {
        Button(action: { onPickVideo(video) }) {
            HStack(alignment: .top, spacing: 12) {
                AsyncImage(url: video.thumbnailURL) { phase in
                    switch phase {
                    case .empty: Rectangle().fill(Color.white.opacity(0.05))
                    case .success(let image): image.resizable().aspectRatio(contentMode: .fill)
                    case .failure:
                        ZStack {
                            Rectangle().fill(Color.white.opacity(0.04))
                            Image(systemName: "play.rectangle").foregroundColor(.white.opacity(0.3))
                        }
                    @unknown default: Color.clear
                    }
                }
                .frame(width: 80, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.white.opacity(0.06), lineWidth: 0.5))

                Text(decodeHTMLEntities(video.title))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white.opacity(0.92))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Play next") {
                PlaybackQueue.shared.enqueueNext(
                    videoID: video.videoID,
                    title: video.title,
                    thumbnailURL: video.thumbnailURL?.absoluteString ?? ""
                )
            }
            Button("Add to queue") {
                PlaybackQueue.shared.enqueue(
                    videoID: video.videoID,
                    title: video.title,
                    thumbnailURL: video.thumbnailURL?.absoluteString ?? ""
                )
            }
        }
    }

    private var loadMoreButton: some View {
        Button(action: { Task { await loadMore() } }) {
            HStack(spacing: 6) {
                if loadingMore {
                    ProgressView().controlSize(.small)
                }
                Text(loadingMore ? "Loading…" : "Load more")
                    .font(.system(size: 11, weight: .medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .foregroundColor(.cyan.opacity(0.8))
        }
        .buttonStyle(.plain)
        .disabled(loadingMore)
    }

    private func initialLoad() async {
        loading = true
        errorMessage = nil

        var playlistId = channel.uploadsPlaylistId
        if playlistId.isEmpty {
            do {
                let details = try await YouTubeSearchAPI.fetchChannelDetails(
                    channelId: channel.channelId, apiKey: apiKeyStore.youtubeKey
                )
                playlistId = details.uploadsPlaylistId
                if favorites.contains(channelId: channel.channelId) {
                    favorites.setUploadsPlaylistId(playlistId, forChannelId: channel.channelId)
                }
            } catch let err as YouTubeSearchAPI.SearchError {
                errorMessage = err.errorDescription
                loading = false
                return
            } catch {
                errorMessage = error.localizedDescription
                loading = false
                return
            }
        }
        uploadsPlaylistId = playlistId

        do {
            let page = try await YouTubeSearchAPI.listChannelUploads(
                uploadsPlaylistId: playlistId, apiKey: apiKeyStore.youtubeKey
            )
            videos = page.videos
            nextPageToken = page.nextPageToken
        } catch let err as YouTubeSearchAPI.SearchError {
            errorMessage = err.errorDescription
        } catch {
            errorMessage = error.localizedDescription
        }
        loading = false
    }

    private func loadMore() async {
        guard let token = nextPageToken, !loadingMore else { return }
        loadingMore = true
        do {
            let page = try await YouTubeSearchAPI.listChannelUploads(
                uploadsPlaylistId: uploadsPlaylistId,
                apiKey: apiKeyStore.youtubeKey,
                pageToken: token
            )
            videos.append(contentsOf: page.videos)
            nextPageToken = page.nextPageToken
        } catch {
            // Silent fail on pagination.
        }
        loadingMore = false
    }

    private func decodeHTMLEntities(_ s: String) -> String {
        guard let data = s.data(using: .utf8) else { return s }
        if let attributed = try? NSAttributedString(
            data: data,
            options: [.documentType: NSAttributedString.DocumentType.html,
                      .characterEncoding: String.Encoding.utf8.rawValue],
            documentAttributes: nil
        ) {
            return attributed.string
        }
        return s
    }
}
