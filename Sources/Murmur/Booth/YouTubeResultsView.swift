import SwiftUI

struct YouTubeResultsView: View {
    let query: String
    var onPick: (YTSearchResult) -> Void
    var onBack: () -> Void
    /// When false, the inner "YouTube · query" header bar is hidden — useful
    /// when the parent already shows the query (e.g., the search sheet).
    var showHeader: Bool = true

    @State private var results: [YTSearchResult] = []
    @State private var loading: Bool = true
    @State private var errorMessage: String? = nil

    @ObservedObject private var apiKeyStore = APIKeyStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if showHeader {
                HStack(spacing: 8) {
                    Button(action: onBack) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.6))
                    }
                    .buttonStyle(.plain)
                    Text("YouTube · \"\(query)\"")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.white.opacity(0.8))
                        .lineLimit(1)
                    Spacer()
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Color.white.opacity(0.04))
                Divider().background(Color.white.opacity(0.06))
            }

            content
        }
        .task(id: query) {
            await runSearch()
        }
    }

    @ViewBuilder
    private var content: some View {
        if loading {
            VStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Searching YouTube…")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.5))
            }
            .frame(maxWidth: .infinity, maxHeight: 200)
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
            .frame(maxWidth: .infinity, maxHeight: 200)
        } else if results.isEmpty {
            Text("No results.")
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.4))
                .frame(maxWidth: .infinity, maxHeight: 200, alignment: .center)
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
                .frame(width: 80, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.white.opacity(0.06), lineWidth: 0.5))

                VStack(alignment: .leading, spacing: 3) {
                    Text(decodeHTMLEntities(result.title))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white.opacity(0.92))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
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
    }

    private func runSearch() async {
        loading = true
        errorMessage = nil
        do {
            let res = try await YouTubeSearchAPI.search(
                query: query,
                apiKey: apiKeyStore.youtubeKey
            )
            results = res
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
