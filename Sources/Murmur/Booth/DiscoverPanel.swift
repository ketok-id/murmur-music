import SwiftUI

/// Grid of audio-focused discovery topics. Clicking a chip fires `onPick`
/// with the topic's query string.
struct DiscoverPanel: View {
    var onPick: (DiscoverTopic) -> Void

    private let columns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(DiscoverTopic.catalog) { topic in
                Button(action: { onPick(topic) }) {
                    HStack(spacing: 8) {
                        Text(topic.emoji)
                            .font(.system(size: 16))
                        Text(topic.title)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.white.opacity(0.85))
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                    )
                    .cornerRadius(6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 10)
    }
}
