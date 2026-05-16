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

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().background(Color.white.opacity(0.08))
            searchRow
            Divider().background(Color.white.opacity(0.06))
            content
        }
        .frame(width: 420, height: 480)
        .background(Color(white: 0.05))
        .onAppear { searchFocused = true }
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
            TextField("e.g. lofi study, synthwave radio, ocean waves…", text: $draftQuery)
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
        } else if activeQuery.isEmpty {
            placeholderState
        } else {
            YouTubeResultsView(
                query: activeQuery,
                onPick: { result in
                    onPick(result.videoID)
                    dismiss()
                },
                onBack: {
                    activeQuery = ""
                }
            )
            .frame(maxWidth: .infinity)
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
        activeQuery = draftQuery.trimmingCharacters(in: .whitespaces)
    }
}
