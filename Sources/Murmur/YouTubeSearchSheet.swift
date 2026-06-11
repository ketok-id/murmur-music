import SwiftUI

/// Standalone window (Window scene) for searching YouTube and picking a
/// result to load on the main player. Seed mode / query come from the
/// `YouTubeSearchState.shared` singleton — the caller mutates it before
/// invoking `openWindow(id: "search")` so the window opens in the right
/// mode (videos / trending / channels) with the right initial query.
/// Replacing the previous `initialMode` / `initialQuery` constructor params
/// is the cost of using a parameterless `Window` scene; the alternative
/// (`WindowGroup(id:for:)`) is macOS 14+ only.
struct YouTubeSearchSheet: View {
    @EnvironmentObject var controller: PlayerController
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var apiKeyStore = APIKeyStore.shared
    @ObservedObject private var history = SearchHistoryStore.shared
    @ObservedObject private var played = PlayedVideoHistoryStore.shared
    @ObservedObject private var seed = YouTubeSearchState.shared

    @State private var draftQuery: String = ""
    @State private var activeQuery: String = ""
    @FocusState private var searchFocused: Bool

    enum Mode: String, CaseIterable, Identifiable {
        case videos, trending, channels
        var id: String { rawValue }
        var label: String {
            switch self {
            case .videos: return "Videos"
            case .trending: return "Trending"
            case .channels: return "Channels"
            }
        }
    }

    @State private var mode: Mode = .videos
    @State private var browsing: ChannelFavorite? = nil

    var body: some View {
        PopoverShell {
            header
        } content: {
            VStack(spacing: 12) {
                MurmurSegmentedTabs(tabs: Mode.allCases, selectedTab: $mode)
                    .onChange(of: mode) { _ in
                        activeQuery = ""
                        browsing = nil
                    }

                if mode != .trending {
                    PopoverSearchField(
                        placeholder: mode == .videos
                            ? "e.g. lofi study, synthwave radio, ocean waves…"
                            : "Channel name (e.g. lofi girl)",
                        text: $draftQuery,
                        onSearch: activate,
                        canSearch: canSearch
                    )
                }

                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 10)
        }
        .frame(width: 480, height: 560)
        .padding(8)
        .onAppear {
            searchFocused = true
            // Seed mode + query from the shared state set by whoever called
            // `openWindow(id: "search")`. Clearing the seed on consume so
            // the next open without an explicit seed lands on default state
            // (videos mode, empty query) instead of replaying the previous.
            mode = seed.mode
            if !seed.query.isEmpty {
                draftQuery = seed.query
                activeQuery = seed.query
                SearchHistoryStore.shared.record(
                    query: seed.query,
                    mode: seed.mode == .videos ? .videos : .channels
                )
            }
            seed.consume()
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("Search YouTube")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(MurmurColor.textPrimary)
            Spacer()
            CloseButton(action: { dismiss() })
        }
        .padding(.horizontal, 16)
        .frame(height: 44)
    }

    @ViewBuilder
    private var content: some View {
        if let channel = browsing {
            ChannelBrowseView(
                channel: channel,
                onPickVideo: { video in
                    _ = controller.load(input: video.videoID)
                    dismiss()
                },
                onBack: { browsing = nil }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            switch mode {
            case .videos:
                if activeQuery.isEmpty {
                    placeholderState
                } else {
                    YouTubeResultsView(
                        query: activeQuery,
                        onPick: { result in
                            _ = controller.load(input: result.videoID)
                            dismiss()
                        },
                        onBack: { activeQuery = "" },
                        showHeader: false
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            case .trending:
                TrendingView(onPick: { result in
                    _ = controller.load(input: result.videoID)
                    dismiss()
                })
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .channels:
                ChannelResultsView(
                    query: activeQuery,
                    onPick: { channel in
                        browsing = channel
                    }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    @ViewBuilder
    private var placeholderState: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if mode == .videos {
                    discoverSection
                }
                if !played.entries.isEmpty && mode == .videos {
                    sectionDivider
                    recentVideosSection
                }
                if !history.entries.isEmpty {
                    sectionDivider
                    recentSearchesSection
                }
                if mode == .channels && history.entries.isEmpty && played.entries.isEmpty {
                    EmptyStateView(
                        systemImage: "person.crop.circle",
                        title: "Find a channel.",
                        helper: "Type a channel name, paste a URL, or @handle."
                    )
                    .padding(.vertical, 24)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// Hairline between placeholder sections — matches the DesignKit border color.
    private var sectionDivider: some View {
        Rectangle()
            .fill(MurmurColor.border.opacity(0.5))
            .frame(height: 1)
            .padding(.vertical, 6)
    }

    @ViewBuilder
    private var discoverSection: some View {
        HStack {
            Text("DISCOVER")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .tracking(1.5)
                .foregroundStyle(MurmurColor.textSecondary)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 6)

        DiscoverPanel { topic in
            mode = .videos
            draftQuery = topic.query
            activeQuery = topic.query
            SearchHistoryStore.shared.record(query: topic.query, mode: .videos)
        }
    }

    @ViewBuilder
    private var recentVideosSection: some View {
        HStack {
            Text("RECENT VIDEOS")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .tracking(1.5)
                .foregroundStyle(MurmurColor.textSecondary)
            Spacer()
            Button("Clear") { played.clear() }
                .buttonStyle(.plain)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.white.opacity(0.4))
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 6)

        ForEach(played.entries.prefix(10)) { entry in
            playedRow(entry)
            if entry.id != played.entries.prefix(10).last?.id {
                Divider().background(Color.white.opacity(0.04)).padding(.leading, 104)
            }
        }
    }

    @ViewBuilder
    private var recentSearchesSection: some View {
        HStack {
            Text("RECENT SEARCHES")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .tracking(1.5)
                .foregroundStyle(MurmurColor.textSecondary)
            Spacer()
            Button("Clear") { history.clear() }
                .buttonStyle(.plain)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.white.opacity(0.4))
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 6)

        ForEach(history.entries) { entry in
            historyRow(entry)
            if entry.id != history.entries.last?.id {
                Divider().background(Color.white.opacity(0.04)).padding(.leading, 38)
            }
        }
    }

    private func historyRow(_ entry: SearchHistoryEntry) -> some View {
        HStack(spacing: 10) {
            Button(action: { reenter(entry) }) {
                HStack(spacing: 10) {
                    Image(systemName: entry.mode == .videos ? "play.rectangle" : "person.crop.circle")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.5))
                        .frame(width: 18)
                    Text(entry.query)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.white.opacity(0.85))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button(action: { history.remove(id: entry.id) }) {
                Image(systemName: "xmark.circle")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.3))
            }
            .buttonStyle(.plain)
            .help("Remove from history")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
    }

    private func playedRow(_ entry: PlayedVideoEntry) -> some View {
        HStack(spacing: 10) {
            Button(action: {
                _ = controller.load(input: entry.videoID)
                dismiss()
            }) {
                HStack(spacing: 12) {
                    AsyncImage(url: entry.thumbnailURL) { phase in
                        switch phase {
                        case .success(let image): image.resizable().aspectRatio(contentMode: .fill)
                        default: Rectangle().fill(Color.white.opacity(0.05))
                        }
                    }
                    .frame(width: 80, height: 48)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.white.opacity(0.06), lineWidth: 0.5))

                    VStack(alignment: .leading, spacing: 3) {
                        Text(entry.title.isEmpty ? entry.videoID : entry.title)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.white.opacity(0.9))
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                        if let pos = entry.lastPosition, pos > 5 {
                            HStack(spacing: 3) {
                                Image(systemName: "arrow.uturn.left.circle")
                                    .font(.system(size: 9))
                                Text("Resume \(formatResumeTime(pos))")
                                    .font(.system(size: 10, design: .monospaced))
                            }
                            .foregroundColor(.cyan.opacity(0.75))
                        }
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .contextMenu {
                Button("Play next") {
                    PlaybackQueue.shared.enqueueNext(
                        videoID: entry.videoID,
                        title: entry.title,
                        thumbnailURL: entry.thumbnailURL?.absoluteString ?? ""
                    )
                }
                Button("Add to queue") {
                    PlaybackQueue.shared.enqueue(
                        videoID: entry.videoID,
                        title: entry.title,
                        thumbnailURL: entry.thumbnailURL?.absoluteString ?? ""
                    )
                }
                Divider()
                addToPlaylistMenuItems(
                    videoID: entry.videoID,
                    title: entry.title,
                    thumbnailURL: entry.thumbnailURL?.absoluteString ?? ""
                )
            }

            Button(action: { played.remove(videoID: entry.videoID) }) {
                Image(systemName: "xmark.circle")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.3))
            }
            .buttonStyle(.plain)
            .help("Remove from history")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private func formatResumeTime(_ seconds: TimeInterval) -> String {
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

    private func reenter(_ entry: SearchHistoryEntry) {
        mode = (entry.mode == .videos) ? .videos : .channels
        draftQuery = entry.query
        activeQuery = entry.query
        history.record(query: entry.query, mode: entry.mode)
    }

    private var canSearch: Bool {
        // No key required — YouTubeSearchAPI falls back to the key-less
        // scraper when APIKeyStore is empty.
        !draftQuery.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func activate() {
        guard canSearch else { return }
        let trimmed = draftQuery.trimmingCharacters(in: .whitespaces)
        activeQuery = trimmed
        SearchHistoryStore.shared.record(
            query: trimmed,
            mode: mode == .videos ? .videos : .channels
        )
    }
}
