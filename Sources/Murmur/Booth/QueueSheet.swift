import SwiftUI

/// Standalone window showing the playback queue with reorder/remove/play-now.
/// Opened as a side-by-side `Window` scene from the main menu-bar panel
/// (not a `.sheet`), so it lives in its own NSWindow and the close button
/// dismisses just this window — not the menu-bar panel behind it. Styled
/// with the DesignKit primitives so it visually matches the cassette-deck
/// aesthetic (PopoverShell + PopoverHeader + VideoResultRow + ToggleFooter).
struct QueueSheet: View {
    @EnvironmentObject var controller: PlayerController
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var queue = PlaybackQueue.shared
    @ObservedObject private var trending = TrendingRegionStore.shared

    var body: some View {
        PopoverShell {
            header
        } content: {
            content
        } footer: {
            ToggleFooter(
                systemImage: "flame.fill",
                label: "Auto-fill from Trending",
                isOn: $trending.autoFillFromTrending,
                trailingLabel: "\(trending.regionCode) · \(trending.categoryLabel(for: trending.categoryId))",
                help: "When the queue runs out, automatically refill with trending videos for your region/category."
            )
        }
        .frame(width: 460, height: 520)
        .padding(8)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("Up Next")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(MurmurColor.textPrimary)
            Text("(\(queue.count))")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(MurmurColor.textMuted)
            Spacer()
            if !queue.isEmpty {
                Button("Clear all") { queue.clear() }
                    .buttonStyle(.plain)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.red.opacity(0.75))
            }
            CloseButton(action: { dismiss() })
        }
        .padding(.horizontal, 16)
        .frame(height: 44)
    }

    @ViewBuilder
    private var content: some View {
        if queue.isEmpty {
            EmptyStateView(
                systemImage: "list.bullet",
                title: "Queue is empty.",
                helper: "Right-click a search result → Add to queue."
            )
        } else {
            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(queue.items) { item in
                        VideoResultRow(
                            thumbURL: item.thumb,
                            title: item.title.isEmpty ? item.videoID : item.title,
                            subtitle: item.videoID,
                            onPlay: {
                                _ = controller.load(input: item.videoID)
                                dismiss()
                            },
                            trailing: AnyView(
                                Button {
                                    queue.remove(itemID: item.id)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 13))
                                        .foregroundStyle(MurmurColor.textMuted)
                                }
                                .buttonStyle(.plain)
                                .help("Remove from queue")
                            )
                        )
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
        }
    }
}
