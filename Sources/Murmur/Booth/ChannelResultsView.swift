import SwiftUI

/// Channels-mode results view. Shows live channel-search results plus saved
/// favorites. Picking a channel (search result or favorite) calls `onPick`.
struct ChannelResultsView: View {
    let query: String      // Empty = show only favorites; non-empty = run search
    var onPick: (ChannelFavorite) -> Void

    @ObservedObject private var apiKeyStore = APIKeyStore.shared
    @ObservedObject private var favorites = ChannelFavoritesStore.shared

    @State private var results: [YTChannelResult] = []
    @State private var loading: Bool = false
    @State private var errorMessage: String? = nil

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if !query.isEmpty {
                    searchSection
                }
                if !favorites.channels.isEmpty {
                    if !query.isEmpty {
                        Divider().background(Color.white.opacity(0.06)).padding(.vertical, 4)
                    }
                    savedSection
                }
                if query.isEmpty && favorites.channels.isEmpty {
                    emptyState
                }
            }
        }
        .task(id: query) {
            await runSearch()
        }
    }

    @ViewBuilder
    private var searchSection: some View {
        sectionHeader("Search results")
        if loading {
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Searching channels…")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.5))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
        } else if let err = errorMessage {
            Text(err)
                .font(.system(size: 11))
                .foregroundColor(.yellow.opacity(0.8))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
        } else if results.isEmpty {
            Text("No channels found.")
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.4))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
        } else {
            ForEach(results) { result in
                channelRow(
                    title: result.title,
                    thumbnailURL: result.thumbnailURL,
                    isFavorited: favorites.contains(channelId: result.channelId),
                    onTap: {
                        let fav = ChannelFavorite(
                            channelId: result.channelId,
                            title: result.title,
                            thumbnailURL: result.thumbnailURL?.absoluteString ?? "",
                            uploadsPlaylistId: ""
                        )
                        onPick(fav)
                    },
                    onToggleFavorite: {
                        if favorites.contains(channelId: result.channelId) {
                            favorites.remove(channelId: result.channelId)
                        } else {
                            let fav = ChannelFavorite(
                                channelId: result.channelId,
                                title: result.title,
                                thumbnailURL: result.thumbnailURL?.absoluteString ?? "",
                                uploadsPlaylistId: ""
                            )
                            favorites.add(fav)
                        }
                    }
                )
            }
        }
    }

    @ViewBuilder
    private var savedSection: some View {
        sectionHeader("Saved channels")
        ForEach(favorites.channels) { fav in
            channelRow(
                title: fav.title,
                thumbnailURL: URL(string: fav.thumbnailURL),
                isFavorited: true,
                onTap: { onPick(fav) },
                onToggleFavorite: {
                    favorites.remove(channelId: fav.channelId)
                }
            )
        }
    }

    private func sectionHeader(_ label: String) -> some View {
        Text(label.uppercased())
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .tracking(1.5)
            .foregroundColor(.white.opacity(0.4))
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 4)
    }

    private func channelRow(
        title: String,
        thumbnailURL: URL?,
        isFavorited: Bool,
        onTap: @escaping () -> Void,
        onToggleFavorite: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 12) {
            Button(action: onTap) {
                HStack(spacing: 12) {
                    AsyncImage(url: thumbnailURL) { phase in
                        switch phase {
                        case .empty: Rectangle().fill(Color.white.opacity(0.04))
                        case .success(let image): image.resizable().aspectRatio(contentMode: .fill)
                        case .failure:
                            ZStack {
                                Rectangle().fill(Color.white.opacity(0.04))
                                Image(systemName: "person.crop.circle")
                                    .foregroundColor(.white.opacity(0.3))
                            }
                        @unknown default: Color.clear
                        }
                    }
                    .frame(width: 40, height: 40)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color.white.opacity(0.08), lineWidth: 0.5))

                    Text(title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white.opacity(0.92))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button(action: onToggleFavorite) {
                Image(systemName: isFavorited ? "star.fill" : "star")
                    .font(.system(size: 13))
                    .foregroundColor(isFavorited ? .yellow : .white.opacity(0.4))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "person.crop.circle")
                .font(.system(size: 22))
                .foregroundColor(.white.opacity(0.25))
            Text("Search to find channels.")
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.45))
            Text("Saved channels appear here for quick access.")
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.35))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
    }

    private func runSearch() async {
        guard !query.isEmpty else {
            results = []
            errorMessage = nil
            loading = false
            return
        }
        loading = true
        errorMessage = nil
        do {
            results = try await YouTubeSearchAPI.searchChannels(
                query: query, apiKey: apiKeyStore.youtubeKey
            )
        } catch let err as YouTubeSearchAPI.SearchError {
            errorMessage = err.errorDescription
        } catch {
            errorMessage = error.localizedDescription
        }
        loading = false
    }
}
