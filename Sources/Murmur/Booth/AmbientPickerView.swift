import SwiftUI

/// Searchable picker for ambient sources. Replaces the simple `Menu` in
/// `AmbientStripView` so the user can filter the catalog by typed text.
struct AmbientPickerView: View {
    /// Receives the user's choice (nil = clear / off).
    var onPick: (AmbientSource?) -> Void

    @State private var query: String = ""
    @FocusState private var searchFocused: Bool

    private var filtered: [AmbientSource] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        if q.isEmpty { return AmbientSource.catalog }
        return AmbientSource.catalog.filter { src in
            src.name.lowercased().contains(q) ||
            src.kindLabel.lowercased().contains(q)
        }
    }

    var body: some View {
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
                        Text("No matches")
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.4))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 16)
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
            .frame(maxHeight: 320)
        }
        .frame(width: 280)
        .background(Color(white: 0.06))
        .onAppear { searchFocused = true }
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
