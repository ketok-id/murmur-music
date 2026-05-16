import SwiftUI

/// Searchable picker for ambient sources. Filters the curated catalog locally,
/// and offers a "Search YouTube" path that hits the live API when the user
/// wants results beyond the curated list.
struct AmbientPickerView: View {
    /// Receives the user's choice (nil = clear / off).
    var onPick: (AmbientSource?) -> Void

    @State private var query: String = ""
    @State private var showingYouTube: Bool = false
    @FocusState private var searchFocused: Bool

    @ObservedObject private var apiKeyStore = APIKeyStore.shared

    private var filtered: [AmbientSource] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        if q.isEmpty { return AmbientSource.catalog }
        return AmbientSource.catalog.filter { src in
            src.name.lowercased().contains(q) ||
            src.kindLabel.lowercased().contains(q)
        }
    }

    var body: some View {
        if showingYouTube {
            YouTubeResultsView(
                query: query,
                onPick: { result in
                    let source = AmbientSource(id: result.videoID, name: result.title, kind: .beats)
                    onPick(source)
                },
                onBack: { showingYouTube = false }
            )
            .frame(width: 280, height: 380)
            .background(Color(white: 0.06))
        } else {
            catalogView
        }
    }

    private var catalogView: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.5))
                TextField("Search ambient…", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, design: .monospaced))
                    .focused($searchFocused)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color.white.opacity(0.04))
            Divider().background(Color.white.opacity(0.06))

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    row(label: "— Off —", kindLabel: "", isOff: true) {
                        onPick(nil)
                    }
                    Divider().background(Color.white.opacity(0.04))
                    if filtered.isEmpty {
                        Text("No matches in catalog.")
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.4))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 12)
                            .frame(maxWidth: .infinity, alignment: .center)
                    } else {
                        ForEach(filtered) { src in
                            row(label: src.name, kindLabel: src.kindLabel, isOff: false) {
                                onPick(src)
                            }
                        }
                    }
                }
            }
            .frame(maxHeight: 280)

            Divider().background(Color.white.opacity(0.08))
            ytSearchButton
        }
        .frame(width: 280)
        .background(Color(white: 0.06))
        .onAppear { searchFocused = true }
    }

    private var ytSearchLabel: String {
        let q = query.trimmingCharacters(in: .whitespaces)
        if q.isEmpty { return "Type to search YouTube" }
        if !apiKeyStore.hasYouTubeKey { return "Set API key to search YouTube →" }
        return "Search YouTube for \"\(q)\""
    }

    private var ytSearchForeground: Color {
        let q = query.trimmingCharacters(in: .whitespaces)
        if q.isEmpty { return .white.opacity(0.35) }
        if !apiKeyStore.hasYouTubeKey { return .white.opacity(0.45) }
        return .cyan
    }

    private var ytSearchDisabled: Bool {
        let q = query.trimmingCharacters(in: .whitespaces)
        return q.isEmpty || !apiKeyStore.hasYouTubeKey
    }

    private var ytSearchButton: some View {
        Button(action: {
            if !ytSearchDisabled { showingYouTube = true }
        }) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass.circle")
                Text(ytSearchLabel).lineLimit(1)
            }
            .font(.system(size: 11, design: .monospaced))
            .foregroundColor(ytSearchForeground)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .disabled(ytSearchDisabled)
    }

    private func row(label: String, kindLabel: String, isOff: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if !kindLabel.isEmpty {
                    Text(kindLabel)
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .tracking(0.5)
                        .foregroundColor(.cyan.opacity(0.75))
                        .frame(width: 50, alignment: .leading)
                } else {
                    Color.clear.frame(width: 50)
                }
                Text(label)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(isOff ? .white.opacity(0.45) : .white.opacity(0.9))
                    .lineLimit(1)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(Color.clear)
    }
}
