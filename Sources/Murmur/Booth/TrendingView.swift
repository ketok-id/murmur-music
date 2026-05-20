import SwiftUI

/// Renders YouTube's "Most Popular" chart for a given region. Single-call —
/// `YouTubeSearchAPI.fetchTrending` returns durations + category hints inline,
/// so no follow-up details fetch is needed (1 quota unit per refresh).
struct TrendingView: View {
    var onPick: (YTSearchResult) -> Void

    @State private var results: [YTSearchResult] = []
    @State private var loading: Bool = true
    @State private var errorMessage: String? = nil

    @ObservedObject private var apiKeyStore = APIKeyStore.shared
    @ObservedObject private var regionStore = TrendingRegionStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().background(Color.white.opacity(0.06))
            content
        }
        .task(id: "\(regionStore.regionCode)|\(regionStore.categoryId)") {
            await load()
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "flame.fill")
                .font(.system(size: 11))
                .foregroundColor(.orange.opacity(0.8))
            Text("TRENDING")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .tracking(1.2)
                .foregroundColor(.white.opacity(0.7))
            regionMenu
            categoryMenu
            Spacer()
            Button(action: { Task { await load() } }) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.5))
            }
            .buttonStyle(.plain)
            .disabled(loading)
            .help("Refresh trending")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.03))
    }

    private var regionMenu: some View {
        Menu {
            ForEach(TrendingRegionStore.supported) { region in
                Button(action: { regionStore.regionCode = region.code }) {
                    if regionStore.regionCode == region.code {
                        Label("\(region.name) (\(region.code))", systemImage: "checkmark")
                    } else {
                        Text("\(region.name) (\(region.code))")
                    }
                }
            }
        } label: {
            HStack(spacing: 3) {
                Text(regionStore.regionCode)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.85))
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundColor(.white.opacity(0.5))
            }
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Change region: \(regionStore.displayName(for: regionStore.regionCode))")
    }

    private var categoryMenu: some View {
        Menu {
            ForEach(TrendingRegionStore.categories) { cat in
                Button(action: { regionStore.categoryId = cat.id }) {
                    if regionStore.categoryId == cat.id {
                        Label("\(cat.emoji) \(cat.label)", systemImage: "checkmark")
                    } else {
                        Text("\(cat.emoji) \(cat.label)")
                    }
                }
            }
        } label: {
            HStack(spacing: 3) {
                let active = TrendingRegionStore.categories.first(where: { $0.id == regionStore.categoryId })
                    ?? TrendingRegionStore.categories[0]
                Text("\(active.emoji) \(active.label)")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.85))
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundColor(.white.opacity(0.5))
            }
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Filter by category")
    }

    @ViewBuilder
    private var content: some View {
        if loading && results.isEmpty {
            VStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Loading trending videos…")
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
        } else if results.isEmpty {
            Text("No trending videos returned.")
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.4))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(results) { result in
                        row(result)
                        if result.id != results.last?.id {
                            Divider().background(Color.white.opacity(0.04)).padding(.leading, 104)
                        }
                    }
                }
            }
        }
    }

    private func row(_ result: YTSearchResult) -> some View {
        Button(action: { onPick(result) }) {
            HStack(alignment: .top, spacing: 12) {
                ZStack(alignment: .bottomTrailing) {
                    AsyncImage(url: result.thumbnailURL) { phase in
                        switch phase {
                        case .empty:
                            Rectangle().fill(Color.white.opacity(0.05))
                        case .success(let image):
                            image.resizable().aspectRatio(contentMode: .fill)
                        case .failure:
                            ZStack {
                                Rectangle().fill(Color.white.opacity(0.04))
                                Image(systemName: "play.rectangle")
                                    .foregroundColor(.white.opacity(0.3))
                            }
                        @unknown default:
                            Color.clear
                        }
                    }
                    if let duration = result.duration, duration > 0 {
                        Text(formatDuration(duration))
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .foregroundColor(.white)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.black.opacity(0.75))
                            .cornerRadius(2)
                            .padding(3)
                    }
                }
                .frame(width: 80, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.white.opacity(0.06), lineWidth: 0.5))

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 4) {
                        if let hint = result.categoryHint, hint != .other, !hint.emoji.isEmpty {
                            Text(hint.emoji)
                                .font(.system(size: 11))
                        }
                        Text(decodeHTMLEntities(result.title))
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.white.opacity(0.92))
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Text(result.channelTitle)
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.5))
                        .lineLimit(1)
                }
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
                    videoID: result.videoID,
                    title: result.title,
                    thumbnailURL: result.thumbnailURL?.absoluteString ?? ""
                )
            }
            Button("Add to queue") {
                PlaybackQueue.shared.enqueue(
                    videoID: result.videoID,
                    title: result.title,
                    thumbnailURL: result.thumbnailURL?.absoluteString ?? ""
                )
            }
            Divider()
            addToPlaylistMenuItems(
                videoID: result.videoID,
                title: result.title,
                thumbnailURL: result.thumbnailURL?.absoluteString ?? ""
            )
        }
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        } else {
            return String(format: "%d:%02d", m, s)
        }
    }

    private func load() async {
        loading = true
        errorMessage = nil
        do {
            results = try await YouTubeSearchAPI.fetchTrending(
                regionCode: regionStore.regionCode,
                apiKey: apiKeyStore.youtubeKey,
                categoryId: regionStore.categoryId
            )
        } catch let err as YouTubeSearchAPI.SearchError {
            errorMessage = err.errorDescription
        } catch {
            errorMessage = error.localizedDescription
        }
        loading = false
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
