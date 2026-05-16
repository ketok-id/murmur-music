import SwiftUI

/// Sheet presented from the main popover for searching YouTube and picking a
/// result to load on the main player.
struct YouTubeSearchSheet: View {
    /// Called with the chosen result's video ID. Parent should dismiss + load.
    var onPick: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var apiKeyStore = APIKeyStore.shared

    @State private var draftQuery: String = ""
    @State private var activeQuery: String = ""
    @FocusState private var searchFocused: Bool

    enum Mode: String, CaseIterable, Identifiable {
        case videos, channels
        var id: String { rawValue }
        var label: String {
            switch self {
            case .videos: return "Videos"
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
            searchRow
            Divider().background(Color.white.opacity(0.06))
            content
        }
        .frame(width: 420, height: 540)
        .background(Color(white: 0.05))
        .onAppear { searchFocused = true }
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

    private var placeholderState: some View {
        VStack(spacing: 6) {
            Image(systemName: "play.rectangle.on.rectangle")
                .font(.system(size: 22))
                .foregroundColor(.white.opacity(0.25))
            Text("Type a query and press Return.")
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.45))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
