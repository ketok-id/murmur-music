import SwiftUI

// MARK: - DesignKit
//
// SwiftUI primitives shared by the four sheet surfaces (Up Next, Playlists,
// YouTube playlist, Search YouTube). Built from the visual vocabulary in
// `murmur_swiftui_macos_design_updated.md`'s "Integrated Popover System"
// section: dark cassette-deck panels, copper accents, soft shadows, rounded
// corners.
//
// We don't ship the doc's "overlay-over-shell with dim + blur" model
// (`PopoverOverlay`, `PopoverTopNotch`) because the main app is an
// `NSPopover`, not a regular window — these sheets stay as SwiftUI `.sheet`
// presentations (separate modal windows) and inherit only the *look*, not
// the overlay architecture. Sizes here are scaled to ~60% of the doc's
// 720-wide spec so the primitives feel proportional in our 420–460-wide
// sheets.

// MARK: - Popover shell

/// Wraps a sheet's body in the dark gradient + border + shadow chrome that
/// the design doc calls `IntegratedPopover`. The caller supplies the
/// header, content, and (optional) footer as view builders.
struct PopoverShell<Header: View, Content: View, Footer: View>: View {
    let header: Header
    let content: Content
    let footer: Footer

    init(
        @ViewBuilder header: () -> Header,
        @ViewBuilder content: () -> Content,
        @ViewBuilder footer: () -> Footer = { EmptyView() }
    ) {
        self.header = header()
        self.content = content()
        self.footer = footer()
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().background(MurmurColor.border.opacity(0.8))
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            footer
        }
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(LinearGradient(colors: [Color.murmurHex("#171717"),
                                              Color.murmurHex("#0B0B0B")],
                                     startPoint: .top, endPoint: .bottom))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(MurmurColor.border.opacity(0.9), lineWidth: 1)
        )
    }
}

// MARK: - Header

/// Sheet title row. Title (left) + optional subtitle/count chip + close (right).
struct PopoverHeader: View {
    let title: String
    var count: Int? = nil
    var leadingSystemImage: String? = nil
    var onClose: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            if let leading = leadingSystemImage {
                Image(systemName: leading)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(MurmurColor.accent)
            }
            Text(title)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(MurmurColor.textPrimary)
            if let count = count {
                Text("(\(count))")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(MurmurColor.textMuted)
            }
            Spacer()
            CloseButton(action: onClose)
        }
        .padding(.horizontal, 16)
        .frame(height: 44)
    }
}

/// Small circular close button — used in PopoverHeader and similar.
struct CloseButton: View {
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(hovering ? MurmurColor.textPrimary : MurmurColor.textSecondary)
                .frame(width: 20, height: 20)
                .background(Circle().fill(Color.white.opacity(hovering ? 0.12 : 0.08)))
                .overlay(Circle().stroke(Color.white.opacity(0.08), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

// MARK: - Segmented tabs

/// Three-tab segmented control with a sliding accent highlight. Used by
/// the YouTube search sheet (Videos / Trending / Channels).
struct MurmurSegmentedTabs<T: Hashable & RawRepresentable>: View where T.RawValue == String {
    let tabs: [T]
    @Binding var selectedTab: T
    @Namespace private var ns

    var body: some View {
        HStack(spacing: 0) {
            ForEach(tabs, id: \.self) { tab in
                Button { selectedTab = tab } label: {
                    Text(tab.rawValue.capitalized)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(selectedTab == tab
                                         ? MurmurColor.textPrimary
                                         : MurmurColor.textSecondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 28)
                        .background {
                            if selectedTab == tab {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(LinearGradient(
                                        colors: [MurmurColor.accent.opacity(0.72),
                                                 MurmurColor.copper.opacity(0.52)],
                                        startPoint: .top, endPoint: .bottom))
                                    .matchedGeometryEffect(id: "tab", in: ns)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(MurmurColor.border, lineWidth: 1)
        )
        .animation(.spring(response: 0.28, dampingFraction: 0.85), value: selectedTab)
    }
}

// MARK: - Search field

/// Inset search bar with magnifier + monospaced field + primary action.
struct PopoverSearchField: View {
    let placeholder: String
    @Binding var text: String
    var onSearch: () -> Void
    var canSearch: Bool = true
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(focused ? MurmurColor.accent : MurmurColor.textSecondary)

            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .focused($focused)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(MurmurColor.textPrimary)
                .tint(MurmurColor.accent)
                .onSubmit(onSearch)

            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(MurmurColor.textMuted)
                }
                .buttonStyle(.plain)
            }

            Button(action: onSearch) {
                Text("Search")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(canSearch ? MurmurColor.accentLight : MurmurColor.textMuted)
                    .padding(.horizontal, 12)
                    .frame(height: 24)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(LinearGradient(
                                colors: [Color.murmurHex("#7A432D"), Color.murmurHex("#3A2118")],
                                startPoint: .top, endPoint: .bottom))
                    )
            }
            .buttonStyle(.plain)
            .disabled(!canSearch)
        }
        .padding(.horizontal, 12)
        .frame(height: 38)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.black.opacity(0.25))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(focused ? MurmurColor.accent.opacity(0.55) : MurmurColor.border,
                        lineWidth: 1)
        )
        .shadow(color: focused ? MurmurColor.glow : .clear, radius: 8)
    }
}

// MARK: - Discover card

/// Emoji + label card used by the Search Videos discover grid.
struct DiscoverCategoryCard: View {
    let icon: String
    let title: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Text(icon).font(.system(size: 16))
                Text(title)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(MurmurColor.textPrimary)
                Spacer()
            }
            .padding(.horizontal, 12)
            .frame(height: 36)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(hovering ? 0.075 : 0.045))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(hovering ? MurmurColor.accent.opacity(0.45)
                                     : MurmurColor.border.opacity(0.7),
                            lineWidth: 1)
            )
            .offset(y: hovering ? -1 : 0)
            .shadow(color: hovering ? MurmurColor.glow.opacity(0.45) : .clear, radius: 9)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.spring(response: 0.24, dampingFraction: 0.82), value: hovering)
    }
}

// MARK: - Playlist row

/// Generic playlist row: leading icon tile + name + subtitle + optional
/// active indicator. Used by the user-playlists list.
struct PlaylistRowView: View {
    let title: String
    let subtitle: String
    let isActive: Bool
    let onSelect: () -> Void
    var trailing: AnyView? = nil
    @State private var hovering = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(0.055))
                    .frame(width: 40, height: 40)
                    .overlay {
                        Image(systemName: "music.note.list")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(MurmurColor.textSecondary)
                    }

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(title)
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(MurmurColor.textPrimary)
                            .lineLimit(1)
                        if isActive {
                            Text("PLAYING")
                                .font(.system(size: 7, weight: .bold, design: .monospaced))
                                .tracking(1)
                                .foregroundStyle(MurmurColor.accent)
                        }
                    }
                    Text(subtitle)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(MurmurColor.textMuted)
                }

                Spacer()

                if let trailing = trailing {
                    trailing
                } else if isActive {
                    Image(systemName: "play.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(MurmurColor.accent)
                }
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(hovering ? 0.07 : 0.045))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(isActive ? MurmurColor.accent.opacity(0.6)
                                     : MurmurColor.border.opacity(0.8),
                            lineWidth: 1)
            )
            .shadow(color: isActive ? MurmurColor.glow.opacity(0.55) : .clear, radius: 9)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.spring(response: 0.26, dampingFraction: 0.86), value: isActive)
    }
}

// MARK: - New playlist input

/// Standalone create-a-playlist input with leading plus, focus glow, and
/// keyboard-submit handling.
struct NewPlaylistInput: View {
    @Binding var text: String
    var onCommit: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "plus.circle")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(focused ? MurmurColor.accent : MurmurColor.textSecondary)

            TextField("New playlist name", text: $text, onCommit: onCommit)
                .textFieldStyle(.plain)
                .focused($focused)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(MurmurColor.textPrimary)
                .tint(MurmurColor.accent)

            if !text.isEmpty {
                Button("Create", action: onCommit)
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(MurmurColor.accentLight)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 40)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.black.opacity(0.22))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(focused ? MurmurColor.accent.opacity(0.55) : MurmurColor.border,
                        lineWidth: 1)
        )
        .shadow(color: focused ? MurmurColor.glow : .clear, radius: 8)
    }
}

// MARK: - Video result row

/// Video-list row: thumbnail + title + channel/duration. Used by Up Next,
/// trending results, and user-playlist detail.
struct VideoResultRow: View {
    let thumbURL: URL?
    let title: String
    let subtitle: String
    var duration: String? = nil
    var isCurrent: Bool = false
    let onPlay: () -> Void
    var trailing: AnyView? = nil
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onPlay) {
                HStack(spacing: 10) {
                    thumbnail
                    VStack(alignment: .leading, spacing: 3) {
                        Text(title.isEmpty ? "—" : title)
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(isCurrent ? MurmurColor.accent : MurmurColor.textPrimary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        Text(subtitle)
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(MurmurColor.textMuted)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if let trailing = trailing {
                trailing
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(hovering ? MurmurColor.accent.opacity(0.06) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(hovering ? MurmurColor.accent.opacity(0.4) : Color.clear,
                        lineWidth: 1)
        )
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
    }

    private var thumbnail: some View {
        ZStack(alignment: .bottomTrailing) {
            AsyncImage(url: thumbURL) { phase in
                switch phase {
                case .success(let image): image.resizable().aspectRatio(contentMode: .fill)
                default:
                    LinearGradient(colors: [Color.murmurHex("#34231F"), Color.murmurHex("#101010")],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                }
            }
            .frame(width: 84, height: 48)
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(MurmurColor.border.opacity(0.7), lineWidth: 1)
            )

            if let duration = duration, !duration.isEmpty {
                Text(duration)
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.black.opacity(0.7)))
                    .foregroundStyle(MurmurColor.textPrimary)
                    .padding(4)
            }
        }
    }
}

// MARK: - Saved channel row

/// Avatar circle + name + favorite star (with pulse on toggle). Used by
/// the YouTube channels tab.
struct SavedChannelRow: View {
    let name: String
    var subtitle: String? = nil
    let isFavorite: Bool
    let onSelect: () -> Void
    let onFavorite: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                Circle()
                    .fill(LinearGradient(colors: [Color.murmurHex("#2B2B2B"), Color.murmurHex("#111111")],
                                         startPoint: .top, endPoint: .bottom))
                    .frame(width: 36, height: 36)
                    .overlay {
                        Image(systemName: "person.fill")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(MurmurColor.textSecondary)
                    }
                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(MurmurColor.textPrimary)
                        .lineLimit(1)
                    if let subtitle = subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(MurmurColor.textMuted)
                            .lineLimit(1)
                    }
                }
                Spacer()
                Button(action: onFavorite) {
                    // `.symbolEffect(.pulse, value:)` requires macOS 14+; our
                    // deployment target is macOS 13. A scale toggle reads as
                    // a similar acknowledgement and works everywhere.
                    Image(systemName: isFavorite ? "star.fill" : "star")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(MurmurColor.accent)
                        .scaleEffect(isFavorite ? 1.0 : 0.92)
                        .animation(.spring(response: 0.28, dampingFraction: 0.6), value: isFavorite)
                }
                .buttonStyle(.plain)
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(hovering ? 0.065 : 0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(hovering ? MurmurColor.accent.opacity(0.35)
                                     : MurmurColor.border.opacity(0.7),
                            lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.spring(response: 0.24, dampingFraction: 0.86), value: hovering)
    }
}

// MARK: - Empty state

/// Centered empty-state block — circle-bordered icon + headline + helper.
struct EmptyStateView: View {
    let systemImage: String
    let title: String
    let helper: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(MurmurColor.accent.opacity(0.7))
                .frame(width: 64, height: 64)
                .background(Circle().fill(Color.white.opacity(0.035)))
                .overlay(Circle().stroke(MurmurColor.border.opacity(0.7), lineWidth: 1))

            Text(title)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(MurmurColor.textPrimary)

            Text(helper)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(MurmurColor.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Footer toggle bar

/// "Auto-fill from Trending" style footer with leading icon + label + switch.
struct ToggleFooter: View {
    let systemImage: String
    let label: String
    @Binding var isOn: Bool
    var trailingLabel: String? = nil
    var help: String = ""

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(isOn ? MurmurColor.accent : MurmurColor.textSecondary)
            Text(label)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(MurmurColor.textPrimary)
            Spacer()
            if let t = trailingLabel, isOn {
                Text(t)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(MurmurColor.textMuted)
            }
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
        }
        .padding(.horizontal, 16)
        .frame(height: 44)
        .background(Color.black.opacity(0.18))
        .overlay(alignment: .top) {
            Divider().background(MurmurColor.border.opacity(0.7))
        }
        .help(help)
    }
}
