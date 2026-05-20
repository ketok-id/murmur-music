import SwiftUI

/// Modal sheet showing the playback queue with reorder/remove/play-now.
struct QueueSheet: View {
    var onPlayNow: (QueueItem) -> Void

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var queue = PlaybackQueue.shared
    @ObservedObject private var trending = TrendingRegionStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().background(Color.white.opacity(0.08))
            content
            Divider().background(Color.white.opacity(0.06))
            footer
        }
        .frame(width: 420, height: 500)
        .background(Color(white: 0.05))
    }

    private var header: some View {
        HStack {
            Text("Up Next")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white)
            Text("(\(queue.count))")
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.white.opacity(0.4))
            Spacer()
            if !queue.isEmpty {
                Button("Clear all") { queue.clear() }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.red.opacity(0.7))
            }
            Button(action: { dismiss() }) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.white.opacity(0.4))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var content: some View {
        if queue.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "list.bullet")
                    .font(.system(size: 24))
                    .foregroundColor(.white.opacity(0.25))
                Text("Queue is empty.")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.45))
                Text("Right-click a search result → \"Add to queue\".")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.35))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List {
                ForEach(queue.items) { item in
                    row(item)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
                .onMove { src, dest in queue.move(from: src, to: dest) }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Toggle(isOn: $trending.autoFillFromTrending) {
                HStack(spacing: 5) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.orange.opacity(0.75))
                    Text("Auto-fill from Trending")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.white.opacity(0.75))
                }
            }
            .toggleStyle(.switch)
            .controlSize(.mini)
            .help("When the queue runs out, automatically refill with trending videos for your region/category.")
            Spacer()
            if trending.autoFillFromTrending {
                Text("\(trending.regionCode) · \(trending.categoryLabel(for: trending.categoryId))")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.white.opacity(0.4))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private func row(_ item: QueueItem) -> some View {
        HStack(spacing: 10) {
            Button(action: { onPlayNow(item); dismiss() }) {
                HStack(spacing: 10) {
                    AsyncImage(url: item.thumb) { phase in
                        switch phase {
                        case .success(let image): image.resizable().aspectRatio(contentMode: .fill)
                        default: Rectangle().fill(Color.white.opacity(0.05))
                        }
                    }
                    .frame(width: 64, height: 36)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                    .overlay(RoundedRectangle(cornerRadius: 3).stroke(Color.white.opacity(0.06), lineWidth: 0.5))

                    Text(item.title.isEmpty ? item.videoID : item.title)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.9))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button(action: { queue.remove(itemID: item.id) }) {
                Image(systemName: "xmark.circle")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.35))
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 3)
    }
}
