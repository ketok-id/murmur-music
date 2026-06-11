import SwiftUI

/// The search sheet's Radio mode — browse/search radio-browser.info and play
/// stations through `RadioPlayer`. Empty query = browse: genre/country chips
/// over the world's most-clicked stations; a typed query searches by name.
struct RadioBrowseView: View {
    let query: String

    @ObservedObject private var radio = RadioPlayer.shared
    @State private var stations: [RadioStation] = []
    @State private var loading = false
    @State private var errorText: String? = nil
    @State private var selectedChip: Chip? = nil

    private struct Chip: Equatable {
        let label: String
        var tag: String? = nil
        var country: String? = nil
    }

    private static let chips: [Chip] = [
        Chip(label: "Lofi", tag: "lofi"),
        Chip(label: "Jazz", tag: "jazz"),
        Chip(label: "Classical", tag: "classical"),
        Chip(label: "Electronic", tag: "electronic"),
        Chip(label: "News", tag: "news"),
        Chip(label: "Indonesia", country: "ID"),
    ]

    var body: some View {
        VStack(spacing: 8) {
            if query.isEmpty { chipRow }
            content
        }
        // Reload whenever the search query or the selected chip changes.
        .task(id: "\(query)|\(selectedChip?.label ?? "")") { await load() }
    }

    private var chipRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(Self.chips, id: \.label) { chip in
                    let selected = selectedChip == chip
                    Button {
                        selectedChip = selected ? nil : chip
                    } label: {
                        Text(chip.label)
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .foregroundStyle(selected ? MurmurColor.textPrimary : MurmurColor.textMuted)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(
                                Capsule().fill(selected ? MurmurColor.accent.opacity(0.25)
                                                        : Color.white.opacity(0.04))
                            )
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
            .padding(.horizontal, 16)
        }
    }

    @ViewBuilder
    private var content: some View {
        if loading && stations.isEmpty {
            VStack { Spacer(); ProgressView(); Spacer() }
        } else if let errorText, stations.isEmpty {
            EmptyStateView(
                systemImage: "dot.radiowaves.left.and.right",
                title: errorText,
                helper: "radio-browser.info is a community service — try again in a moment."
            )
        } else if stations.isEmpty {
            EmptyStateView(
                systemImage: "dot.radiowaves.left.and.right",
                title: "No stations found.",
                helper: "Try another name, or browse by genre above."
            )
        } else {
            ScrollView {
                LazyVStack(spacing: 5) {
                    ForEach(stations) { station in
                        StationRow(
                            station: station,
                            isCurrent: radio.station?.uuid == station.uuid,
                            isPlaying: radio.station?.uuid == station.uuid && radio.isPlaying,
                            isBuffering: radio.station?.uuid == station.uuid && radio.isBuffering
                        ) {
                            if radio.station?.uuid == station.uuid {
                                radio.stop()
                            } else {
                                radio.play(station)
                            }
                        }
                    }
                    Text("Directory: radio-browser.info — community-maintained, no account, no key.")
                        .font(.system(size: 9))
                        .foregroundStyle(MurmurColor.textMuted)
                        .padding(.top, 6)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }
        }
    }

    private func load() async {
        loading = true
        errorText = nil
        do {
            stations = try await RadioBrowserAPI.search(
                name: query.isEmpty ? nil : query,
                tag: query.isEmpty ? selectedChip?.tag : nil,
                countryCode: query.isEmpty ? selectedChip?.country : nil
            )
        } catch {
            errorText = "Couldn't reach the station directory."
        }
        loading = false
    }
}

private struct StationRow: View {
    let station: RadioStation
    let isCurrent: Bool
    let isPlaying: Bool
    let isBuffering: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                AsyncImage(url: station.faviconURL) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Rectangle().fill(Color.white.opacity(0.06))
                        .overlay(Image(systemName: "radio")
                            .font(.system(size: 10))
                            .foregroundStyle(MurmurColor.textMuted))
                }
                .frame(width: 30, height: 30)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(station.name)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(isCurrent ? MurmurColor.accentLight
                                                   : (hovering ? MurmurColor.textPrimary : MurmurColor.textSecondary))
                        .lineLimit(1)
                    Text(station.subtitle)
                        .font(.system(size: 9))
                        .foregroundStyle(MurmurColor.textMuted)
                        .lineLimit(1)
                }
                Spacer()
                if isBuffering {
                    ProgressView().controlSize(.mini).scaleEffect(0.6)
                } else {
                    Image(systemName: isPlaying ? "stop.fill"
                                                : (isCurrent ? "play.fill" : "play.fill"))
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(isPlaying ? MurmurColor.accent
                                                   : MurmurColor.textMuted.opacity(hovering ? 1 : 0.4))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isCurrent ? MurmurColor.accent.opacity(0.08)
                                    : Color.white.opacity(hovering ? 0.04 : 0.02))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(isCurrent ? MurmurColor.accent.opacity(0.4) : MurmurColor.borderSoft, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(isPlaying ? "Stop" : "Play in Murmur")
    }
}
