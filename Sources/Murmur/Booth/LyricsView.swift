import SwiftUI

/// Standalone window showing time-synced lyrics for the current music video.
/// Opened as a `Window` scene from the main menu-bar panel; uses the same
/// DesignKit primitives as the other auxiliary sheets so it visually matches
/// the cassette-deck aesthetic.
struct LyricsView: View {
    @EnvironmentObject var controller: PlayerController
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = LyricsStore.shared

    var body: some View {
        PopoverShell {
            header
        } content: {
            content
        } footer: {
            footer
        }
        .frame(width: 380, height: 540)
        .padding(8)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("Lyrics")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(MurmurColor.textPrimary)
            if case .synced(let lines) = store.current {
                Text("(\(lines.count) lines)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(MurmurColor.textMuted)
            }
            Spacer()
            CloseButton(action: { dismiss() })
        }
        .padding(.horizontal, 16)
        .frame(height: 44)
    }

    @ViewBuilder
    private var content: some View {
        switch store.current {
        case .idle:
            EmptyStateView(
                systemImage: "text.quote",
                title: "No lyrics yet.",
                helper: "Lyrics will appear when a music track plays."
            )
        case .loading:
            VStack(spacing: 10) {
                ProgressView()
                Text("Looking up lyrics on LRCLIB…")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(MurmurColor.textMuted)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .missing(let reason):
            EmptyStateView(
                systemImage: "text.quote",
                title: "No lyrics found.",
                helper: reason
            )
        case .plain(let text):
            ScrollView {
                Text(text)
                    .font(.system(size: 13))
                    .foregroundStyle(MurmurColor.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
            }
        case .synced(let lines):
            syncedView(lines: lines)
        }
    }

    @ViewBuilder
    private func syncedView(lines: [LyricsLine]) -> some View {
        let activeIdx = activeIndex(in: lines, at: controller.currentTime)
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { idx, line in
                        Text(line.text)
                            .font(.system(size: 14))
                            .fontWeight(idx == activeIdx ? .semibold : .regular)
                            .foregroundStyle(idx == activeIdx
                                             ? MurmurColor.textPrimary
                                             : MurmurColor.textMuted)
                            .id(idx)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(16)
            }
            .onChange(of: activeIdx) { newIdx in
                guard let i = newIdx else { return }
                withAnimation(.easeOut(duration: 0.25)) {
                    proxy.scrollTo(i, anchor: .center)
                }
            }
        }
    }

    @ViewBuilder
    private var footer: some View {
        HStack(spacing: 6) {
            Text("via lrclib.net")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(MurmurColor.textMuted.opacity(0.7))
            Spacer()
            if case .synced = store.current {
                Text(timeLabel(controller.currentTime))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(MurmurColor.textMuted)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 28)
    }

    private func activeIndex(in lines: [LyricsLine], at t: Double) -> Int? {
        guard !lines.isEmpty, t >= lines[0].start else { return nil }
        var lo = 0, hi = lines.count - 1
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            if lines[mid].start <= t { lo = mid } else { hi = mid - 1 }
        }
        return lo
    }

    private func timeLabel(_ seconds: Double) -> String {
        let s = Int(seconds.rounded())
        return String(format: "%02d:%02d", s / 60, s % 60)
    }
}
