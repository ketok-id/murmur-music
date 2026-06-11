import SwiftUI

/// The "stats" Window scene — local listening totals from
/// `ListeningStatsStore`: today / 7 days / all time, a 14-day bar strip, and
/// the most-listened tracks (click to play). Entirely offline.
struct StatsSheet: View {
    @EnvironmentObject var controller: PlayerController
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var stats = ListeningStatsStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "chart.bar.fill")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(MurmurColor.accent)
                Text("Listening Stats")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(MurmurColor.textPrimary)
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.white.opacity(0.4))
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 10) {
                totalCard(label: "TODAY", seconds: stats.totalToday)
                totalCard(label: "LAST 7 DAYS", seconds: stats.totalLast7Days)
                totalCard(label: "ALL TIME", seconds: stats.totalAllTime)
            }

            barStrip

            VStack(alignment: .leading, spacing: 6) {
                Text("MOST LISTENED")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .tracking(1.5)
                    .foregroundStyle(MurmurColor.textMuted)
                if stats.topTracks(limit: 1).isEmpty {
                    Text("Play something — time starts counting from now.")
                        .font(.system(size: 11))
                        .foregroundStyle(MurmurColor.textSecondary)
                        .padding(.vertical, 12)
                } else {
                    ForEach(Array(stats.topTracks(limit: 10).enumerated()), id: \.element.id) { index, track in
                        TopTrackRow(rank: index + 1, track: track) {
                            _ = controller.load(input: track.videoID)
                        }
                    }
                }
            }

            Text("Counted locally from actual playback time — seeks and pauses don't inflate it. Nothing leaves your Mac.")
                .font(.system(size: 9))
                .foregroundStyle(MurmurColor.textMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(width: 420)
        .background(Color.murmurHex("#121212"))
    }

    private func totalCard(label: String, seconds: Double) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .tracking(1.2)
                .foregroundStyle(MurmurColor.textMuted)
            Text(Self.hours(seconds))
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(MurmurColor.accent)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(MurmurColor.borderSoft, lineWidth: 1)
        )
    }

    /// 14 days, oldest → newest; bars normalize to the busiest day.
    private var barStrip: some View {
        let days = stats.lastDays(14)
        let peak = max(days.map(\.seconds).max() ?? 0, 1)
        return VStack(alignment: .leading, spacing: 4) {
            Text("LAST 14 DAYS")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .tracking(1.5)
                .foregroundStyle(MurmurColor.textMuted)
            HStack(alignment: .bottom, spacing: 4) {
                ForEach(days, id: \.day) { entry in
                    VStack(spacing: 2) {
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(entry.seconds > 0 ? MurmurColor.accent.opacity(0.85)
                                                    : Color.white.opacity(0.06))
                            .frame(height: max(3, 42 * entry.seconds / peak))
                        Text(Self.weekday.string(from: entry.day))
                            .font(.system(size: 7, weight: .medium, design: .monospaced))
                            .foregroundStyle(MurmurColor.textMuted)
                    }
                    .frame(maxWidth: .infinity)
                    .help("\(Self.dayLabel.string(from: entry.day)) — \(Self.hours(entry.seconds))")
                }
            }
            .frame(height: 56, alignment: .bottom)
        }
    }

    private static func hours(_ seconds: Double) -> String {
        if seconds < 60 { return "0m" }
        let h = Int(seconds) / 3600, m = (Int(seconds) % 3600) / 60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }

    private static let weekday: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEEE"   // single-letter weekday
        return f
    }()

    private static let dayLabel: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        return f
    }()
}

private struct TopTrackRow: View {
    let rank: Int
    let track: TrackStat
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(String(format: "%02d", rank))
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(rank <= 3 ? MurmurColor.accent : MurmurColor.textMuted)
                Text(track.title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(hovering ? MurmurColor.textPrimary : MurmurColor.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer()
                Text(Self.listened(track.seconds))
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(MurmurColor.textMuted)
                Image(systemName: "play.fill")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(MurmurColor.accent.opacity(hovering ? 1 : 0))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(hovering ? 0.05 : 0.02))
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("Play again")
    }

    private static func listened(_ seconds: Double) -> String {
        let h = Int(seconds) / 3600, m = (Int(seconds) % 3600) / 60
        if h > 0 { return "\(h)h \(m)m" }
        if m > 0 { return "\(m)m" }
        return "<1m"
    }
}
