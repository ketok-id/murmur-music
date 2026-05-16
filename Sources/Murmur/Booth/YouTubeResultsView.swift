import SwiftUI

struct YouTubeResultsView: View {
    let query: String
    var onPick: (YTSearchResult) -> Void
    var onBack: () -> Void

    @State private var results: [YTSearchResult] = []
    @State private var loading: Bool = true
    @State private var errorMessage: String? = nil

    @ObservedObject private var apiKeyStore = APIKeyStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
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

            content
        }
        .frame(width: 280)
        .background(Color(white: 0.06))
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
                    }
                }
            }
            .frame(maxHeight: 320)
        }
    }

    private func row(_ result: YTSearchResult) -> some View {
        Button(action: { onPick(result) }) {
            HStack(spacing: 10) {
                AsyncImage(url: result.thumbnailURL) { phase in
                    switch phase {
                    case .empty:
                        Rectangle().fill(Color.white.opacity(0.04))
                    case .success(let image):
                        image.resizable().aspectRatio(contentMode: .fill)
                    case .failure:
                        Image(systemName: "play.rectangle")
                            .foregroundColor(.white.opacity(0.3))
                    @unknown default:
                        Color.clear
                    }
                }
                .frame(width: 56, height: 32)
                .clipShape(RoundedRectangle(cornerRadius: 3))
                .overlay(RoundedRectangle(cornerRadius: 3).stroke(Color.white.opacity(0.08), lineWidth: 1))

                VStack(alignment: .leading, spacing: 2) {
                    Text(decodeHTMLEntities(result.title))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.white.opacity(0.9))
                        .lineLimit(2)
                    Text(result.channelTitle)
                        .font(.system(size: 9))
                        .foregroundColor(.cyan.opacity(0.7))
                        .lineLimit(1)
                }
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
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
