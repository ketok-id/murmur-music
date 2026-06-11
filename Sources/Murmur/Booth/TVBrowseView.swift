import SwiftUI

/// The search sheet's TV mode — iptv-org's community directory of publicly
/// available TV streams, browsed by country (Indonesia first), filtered by
/// the sheet's search field, played in the floating `LiveTVWindow`.
struct TVBrowseView: View {
    /// Sheet search text — used as a client-side name filter.
    let query: String

    @AppStorage("youtube-audio-widget.iptv.country") private var countryCode = "ID"
    @ObservedObject private var tv = LiveTVWindow.shared
    @State private var countries: [IPTVCountry] = []
    @State private var channels: [IPTVChannel] = []
    @State private var loading = false
    @State private var errorText: String? = nil

    private var filtered: [IPTVChannel] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return channels }
        return channels.filter {
            $0.name.localizedCaseInsensitiveContains(trimmed)
                || $0.group.localizedCaseInsensitiveContains(trimmed)
        }
    }

    private var countryLabel: String {
        countries.first { $0.code == countryCode }
            .map { "\($0.flag) \($0.name)" } ?? countryCode
    }

    var body: some View {
        VStack(spacing: 8) {
            header
            content
        }
        .task { countries = (try? await IPTVDirectoryAPI.countries()) ?? [] }
        .task(id: countryCode) { await load() }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Menu {
                ForEach(countries) { country in
                    Button {
                        countryCode = country.code
                    } label: {
                        if country.code == countryCode {
                            Label("\(country.flag) \(country.name)", systemImage: "checkmark")
                        } else {
                            Text("\(country.flag) \(country.name)")
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(countryLabel)
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 7, weight: .bold))
                }
                .foregroundStyle(MurmurColor.textSecondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color.white.opacity(0.04)))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Country — channels come from iptv-org's community directory")

            if !channels.isEmpty {
                Text("\(filtered.count) channels")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(MurmurColor.textMuted)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
    }

    @ViewBuilder
    private var content: some View {
        if loading && channels.isEmpty {
            VStack { Spacer(); ProgressView(); Spacer() }
        } else if let errorText, channels.isEmpty {
            EmptyStateView(
                systemImage: "tv",
                title: errorText,
                helper: "iptv-org is a community index — try another country or retry."
            )
        } else if filtered.isEmpty {
            EmptyStateView(
                systemImage: "tv",
                title: channels.isEmpty ? "No channels listed for this country."
                                        : "Nothing matches that filter.",
                helper: "Type in the search field to filter by name or genre."
            )
        } else {
            ScrollView {
                LazyVStack(spacing: 5) {
                    ForEach(filtered) { channel in
                        TVChannelRow(
                            channel: channel,
                            isCurrent: tv.currentID == channel.id
                        ) {
                            LiveTVWindow.shared.show(channel: channel)
                        }
                    }
                    Text("Directory: iptv-org — community-indexed public streams; some are geo-locked or off-air.")
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
            channels = try await IPTVDirectoryAPI.channels(country: countryCode)
        } catch {
            channels = []
            errorText = "Couldn't load the channel list."
        }
        loading = false
    }
}

private struct TVChannelRow: View {
    let channel: IPTVChannel
    let isCurrent: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                AsyncImage(url: channel.logoURL) { image in
                    image.resizable().scaledToFit()
                } placeholder: {
                    Image(systemName: "tv")
                        .font(.system(size: 10))
                        .foregroundStyle(MurmurColor.textMuted)
                }
                .frame(width: 34, height: 24)
                .background(Color.white.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(channel.name)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(isCurrent ? MurmurColor.accentLight
                                                   : (hovering ? MurmurColor.textPrimary : MurmurColor.textSecondary))
                        .lineLimit(1)
                    if !channel.subtitle.isEmpty {
                        Text(channel.subtitle)
                            .font(.system(size: 9))
                            .foregroundStyle(MurmurColor.textMuted)
                            .lineLimit(1)
                    }
                }
                Spacer()
                Image(systemName: isCurrent ? "tv.fill" : "play.fill")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(isCurrent ? MurmurColor.accent
                                               : MurmurColor.textMuted.opacity(hovering ? 1 : 0.4))
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
        .help("Watch in a floating window")
    }
}
