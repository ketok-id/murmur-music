import SwiftUI

/// Sheet presented from the main popover for searching YouTube and picking a
/// result to load on the main player.
struct YouTubeSearchSheet: View {
    /// Seed mode when the sheet opens. Default: videos.
    var initialMode: Mode = .videos
    /// Seed query when the sheet opens. If non-empty, the sheet activates
    /// the search immediately on appear.
    var initialQuery: String = ""
    /// Called with the chosen result's video ID. Parent should dismiss + load.
    var onPick: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var apiKeyStore = APIKeyStore.shared
    @ObservedObject private var history = SearchHistoryStore.shared
    @ObservedObject private var played = PlayedVideoHistoryStore.shared

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
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().background(Color.white.opacity(0.08))
            modePicker
            if mode != .trending {
                searchRow
            }
            Divider().background(Color.white.opacity(0.06))
            content
        }
        .frame(width: 420, height: 540)
        .background(Color(white: 0.05))
        .onAppear {
            searchFocused = true
            if !initialQuery.isEmpty {
                mode = initialMode
                draftQuery = initialQuery
                activeQuery = initialQuery
                SearchHistoryStore.shared.record(
                    query: initialQuery,
                    mode: initialMode == .videos ? .videos : .channels
                )
            }
        }
    }

    private var modePicker: some View {
        Picker("", selection: $mode) {
            ForEach(Mode.allCases) { mode in
                Text(mode.label).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .padding(.horizontal, 14)
        .padding(.top, 8)
        .padding(.bottom, 2)
        .onChange(of: mode) { _ in
            activeQuery = ""
            browsing = nil
        }
    }

    private var header: some View {
        HStack {
            Text("Search YouTube")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white)
            Spacer()
            Button(action: { dismiss() }) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.white.opacity(0.4))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var searchRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.5))
            TextField(mode == .videos
                      ? "e.g. lofi study, synthwave radio, ocean waves…"
                      : "Channel name (e.g. lofi girl)", text: $draftQuery)
                .textFieldStyle(.plain)
                .font(.system(size: 12, design: .monospaced))
                .focused($searchFocused)
                .onSubmit { activate() }
            if !draftQuery.isEmpty {
                Button(action: {
                    draftQuery = ""
                    activeQuery = ""
                }) {
                    Image(systemName: "xmark.circle")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.4))
                }
                .buttonStyle(.plain)
            }
            Button("Search") { activate() }
                .keyboardShortcut(.defaultAction)
                .disabled(!canSearch)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var content: some View {
        if !apiKeyStore.hasYouTubeKey {
            noKeyState
        } else if let channel = browsing {
            ChannelBrowseView(
                channel: channel,
                onPickVideo: { video in
                    onPick(video.videoID)
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
                            onPick(result.videoID)
                            dismiss()
                        },
                        onBack: { activeQuery = "" },
                        showHeader: false
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            case .trending:
                TrendingView(onPick: { result in
                    onPick(result.videoID)
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

    private var noKeyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "key.slash")
                .font(.system(size: 22))
                .foregroundColor(.white.opacity(0.3))
            Text("No YouTube API key configured.")
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.6))
            Text("Open the gear in the popover header to add one.")
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.45))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var placeholderState: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if mode == .videos {
                    discoverSection
                }
                if !played.entries.isEmpty && mode == .videos {
                    Divider().background(Color.white.opacity(0.04))
                    recentVideosSection
                }
                if !history.entries.isEmpty {
                    Divider().background(Color.white.opacity(0.04))
                    recentSearchesSection
                }
                if mode == .channels && history.entries.isEmpty && played.entries.isEmpty {
                    VStack(spacing: 6) {
                        Image(systemName: "person.crop.circle")
                            .font(.system(size: 22))
                            .foregroundColor(.white.opacity(0.25))
                        Text("Type a channel name, paste a URL, or @handle.")
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.45))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private var discoverSection: some View {
        HStack {
            Text("DISCOVER")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .tracking(1.5)
                .foregroundColor(.white.opacity(0.4))
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
                .foregroundColor(.white.opacity(0.4))
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
                .foregroundColor(.white.opacity(0.4))
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
            Button(action: { onPick(entry.videoID); dismiss() }) {
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
        apiKeyStore.hasYouTubeKey &&
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
