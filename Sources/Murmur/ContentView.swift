import AppKit
import SwiftUI

// MARK: - Design system
//
// Mirrors the palette + tokens defined in DESIGN.md so the redesign stays
// in sync with the spec. Keeping it inline here (rather than splitting into
// a DesignSystem/ folder) preserves the repo's flat layout — Murmur is a
// single executable target and this file is the only place that consumes
// these tokens.

enum MurmurColor {
    static let background    = Color.murmurHex("#070707")

    static let shellTop      = Color.murmurHex("#181818")
    static let shellBottom   = Color.murmurHex("#0D0D0D")

    static let panel         = Color.murmurHex("#141414")
    static let raisedPanel   = Color.murmurHex("#1A1A1A")
    static let pressedPanel  = Color.murmurHex("#0B0B0B")

    static let border        = Color.murmurHex("#2C2C2C")
    static let borderSoft    = Color.white.opacity(0.06)

    static let textPrimary   = Color.murmurHex("#F4E8DC")
    static let textSecondary = Color.murmurHex("#A39A91")
    static let textMuted     = Color.murmurHex("#6F6A65")

    static let accent        = Color.murmurHex("#FF9F6E")
    static let accentLight   = Color.murmurHex("#FFC19C")
    static let copper        = Color.murmurHex("#C9784D")
    static let glow          = Color.murmurHex("#FF9F6E").opacity(0.35)
}

extension Color {
    /// Local hex parser. Named `murmurHex` (not just `hex`) to avoid clashing
    /// with the SDK's failable `Color(hex:)` initializer, which returns
    /// `Color?` and broke type inference inside `LinearGradient(colors: …)`.
    static func murmurHex(_ hex: String) -> Color {
        let stripped = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: stripped).scanHexInt64(&int)
        let r = (int >> 16) & 0xff
        let g = (int >> 8)  & 0xff
        let b =  int        & 0xff
        return Color(.sRGB,
                     red:   Double(r) / 255,
                     green: Double(g) / 255,
                     blue:  Double(b) / 255,
                     opacity: 1)
    }
}

// MARK: - Content shell

struct ContentView: View {
    @EnvironmentObject var controller: PlayerController
    @EnvironmentObject var videoWindow: VideoWindowController
    @EnvironmentObject var booth: BoothLauncher
    @ObservedObject private var playbackQueue = PlaybackQueue.shared
    @ObservedObject private var playlistStore = PlaylistStore.shared
    @ObservedObject private var userPlaylists = UserPlaylistsStore.shared
    @State private var urlInput: String = ""
    @ObservedObject private var apiKeyStore = APIKeyStore.shared
    @ObservedObject private var updateChecker = UpdateChecker.shared

    /// Opens the Window-scene sheets (queue, playlist, search, settings,
    /// my-playlists). Replaces the prior `.sheet(isPresented:)` bindings
    /// that lived inside MenuBarExtra — those caused the sheet's
    /// `dismiss()` to bubble up and close the menu-bar panel itself,
    /// which looked to users like the whole app quitting on close. Window
    /// scenes also let the sheets sit side-by-side with the panel (the
    /// CleanMyMac layout).
    @Environment(\.openWindow) private var openWindow

    /// Open a sheet window and bring it to the front. As an `LSUIElement`
    /// accessory app, Murmur isn't normally the active app when the user
    /// clicks a menu-bar control — so a raw `openWindow(id:)` creates the
    /// window but it lands behind whatever app currently has focus.
    /// Activating before opening fixes that: the new window comes up as
    /// key and frontmost.
    private func openSheet(id: String) {
        NSApp.activate(ignoringOtherApps: true)
        openWindow(id: id)
    }

    var body: some View {
        ZStack {
            // Shell background — soft top/bottom gradient. No outer rounded
            // stroke because NSPopover already supplies its own chrome (and
            // double-rounding would clip awkwardly at the corners).
            LinearGradient(colors: [MurmurColor.shellTop, MurmurColor.shellBottom],
                           startPoint: .top, endPoint: .bottom)

            VStack(spacing: 12) {
                HeaderBarView(
                    videoOn: videoWindow.isVisible,
                    onToggleVideo: { videoWindow.toggle() },
                    onReload: { controller.reload() },
                    share: shareMenu,
                    queueCount: playbackQueue.count,
                    onOpenQueue: { openSheet(id:"queue") },
                    userPlaylistActive: userPlaylists.hasActivePlaylist,
                    userPlaylistTooltip: userPlaylists.hasActivePlaylist
                        ? "Playing from \"\(userPlaylists.activePlaylist?.name ?? "")\""
                        : "My playlists",
                    onOpenUserPlaylists: { openSheet(id:"user-playlists") },
                    ytPlaylistActive: playlistStore.hasActivePlaylist,
                    ytPlaylistLabel: ytPlaylistLabel,
                    onOpenPlaylistSheet: { openSheet(id:"playlist") },
                    lyricsAvailable: controller.categoryHint == .music,
                    onOpenLyrics: { openSheet(id:"lyrics") },
                    apiKeyConfigured: apiKeyStore.hasYouTubeKey,
                    onOpenSettings: { openSheet(id:"api-key") }
                )

                URLInputBarView(
                    text: $urlInput,
                    onCommit: submitURL,
                    canSubmit: canSubmit,
                    favoritesButton: NativeFavoritesMenuButton(
                        controller: controller,
                        tint: NSColor(MurmurColor.accent)
                    ),
                    onSearch: {
                        YouTubeSearchState.shared.mode = .videos
                        YouTubeSearchState.shared.query = ""
                        openSheet(id:"search")
                    }
                )

                CassettePlayerCardView(
                    title: cardTitle,
                    subtitle: cardSubtitle,
                    badge: cardBadge,
                    isPlaying: controller.isPlaying,
                    isReady: controller.isReady,
                    onPlayPause: { controller.toggle() },
                    onStop: { controller.pause(); controller.seek(to: 0) },
                    onPrev: { controller.playPrev() },
                    onNext: { controller.playNext() }
                )

                FooterControlsView(
                    volume: Binding(get: { controller.volume },
                                    set: { newVal in
                                        controller.volume = newVal
                                        controller.setVolume(Int(newVal))
                                    }),
                    rate: controller.playbackRate,
                    onPickRate: { controller.setPlaybackRate($0) },
                    statusText: controller.status,
                    isLive: controller.isPlaying,
                    versionLabel: AnyView(versionLabel),
                    mixHint: controller.mixHint,
                    onQuit: { NSApp.terminate(nil) }
                )
            }
            .padding(14)
        }
        .frame(width: 500, height: 370)
        // No `.sheet(isPresented:)` modifiers — every former sheet is now
        // a top-level `Window` scene in `MurmurApp.body`, opened by
        // `openWindow(id:)` from the toggle sites above. Each window's
        // close button dismisses just that window (fixes the prior
        // "pressing close on a sheet closed the menu-bar panel" bug) and
        // they can sit side-by-side with the panel.
    }

    // MARK: - Computed bindings

    /// Track title for the cassette card label — `controller.title` is the
    /// truth, but blank during the initial load so we fall back to "Murmur".
    private var cardTitle: String {
        let t = controller.title.trimmingCharacters(in: .whitespaces)
        return t.isEmpty ? "Murmur" : t
    }

    /// Secondary line on the cassette label. Surfaces the user-playlist or
    /// YouTube-playlist context when active so users can tell "what set is
    /// this part of"; otherwise echoes the engine status line ("Loading…",
    /// "Playing", "Paused") in lowercase to match the retro aesthetic.
    private var cardSubtitle: String {
        if userPlaylists.hasActivePlaylist,
           let idx = userPlaylists.activeIndex,
           let p = userPlaylists.activePlaylist {
            return "\(p.name.lowercased()) • \(idx + 1)/\(p.items.count)"
        }
        if playlistStore.hasActivePlaylist, let idx = playlistStore.currentIndex {
            return "youtube playlist • \(idx + 1)/\(playlistStore.items.count)"
        }
        return controller.status.lowercased()
    }

    /// TYPE pill on the right of the track header. "LIVE" while playing
    /// (most Murmur streams are live radio); falls back to TAPE otherwise so
    /// the pill always has copy.
    private var cardBadge: String {
        controller.isPlaying ? "LIVE" : "TAPE"
    }

    private var ytPlaylistLabel: String {
        guard playlistStore.hasActivePlaylist else { return "" }
        if let i = playlistStore.currentIndex {
            return "\(i + 1)/\(playlistStore.items.count)"
        }
        return "\(playlistStore.items.count)"
    }

    // MARK: - Share (preserved from earlier fix)

    private var shareMenu: NativeShareMenuButton {
        NativeShareMenuButton(
            shareURL: shareURL,
            murmurLink: murmurLink,
            shareTitle: shareTitle,
            tint: NSColor(MurmurColor.textSecondary)
        )
    }

    private var shareURL: URL {
        let videoID = controller.currentVideoID
        let playlistID = playlistStore.hasActivePlaylist ? playlistStore.playlistID : ""
        let raw: String
        if !playlistID.isEmpty {
            raw = "https://www.youtube.com/watch?v=\(videoID)&list=\(playlistID)"
        } else {
            raw = "https://youtu.be/\(videoID)"
        }
        return URL(string: raw)!
    }

    private var murmurLink: URL {
        var comp = URLComponents()
        comp.scheme = "murmur"
        comp.host = "play"
        var items = [URLQueryItem(name: "v", value: controller.currentVideoID)]
        if playlistStore.hasActivePlaylist {
            items.append(URLQueryItem(name: "list", value: playlistStore.playlistID))
        }
        comp.queryItems = items
        return comp.url ?? URL(string: "murmur://play?v=\(controller.currentVideoID)")!
    }

    private var shareTitle: String {
        let title = controller.title.trimmingCharacters(in: .whitespaces)
        return title.isEmpty ? "Murmur" : title
    }

    // MARK: - Version label (with update badge)

    @ViewBuilder
    private var versionLabel: some View {
        if updateChecker.hasUpdate, let url = updateChecker.releaseURL,
           let latest = updateChecker.latestVersion {
            Button(action: { NSWorkspace.shared.open(url) }) {
                HStack(spacing: 3) {
                    Image(systemName: "arrow.up.circle.fill")
                    Text("v\(latest)")
                }
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(MurmurColor.accent)
            }
            .buttonStyle(.plain)
            .help("Update available — v\(updateChecker.currentVersion) → v\(latest). Click to view on GitHub.")
        } else {
            Text("v\(updateChecker.currentVersion)")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(MurmurColor.textMuted)
                .help(updateChecker.lastCheckedAt.map {
                    "Murmur v\(updateChecker.currentVersion) — checked for updates \(formatRelativeTime($0))"
                } ?? "Murmur v\(updateChecker.currentVersion)")
                .onTapGesture(count: 2) { updateChecker.check() }
        }
    }

    private func formatRelativeTime(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    // MARK: - Discover catalog
    //
    // The favorites + discover dropdown itself is built by
    // `NativeFavoritesMenuButton` (AppKit-backed `NSMenu`), which reads
    // this catalog directly.

    struct CatalogGroup { let category: String; let items: [CatalogItem] }
    struct CatalogItem  { let name: String; let videoID: String }
    static let catalog: [CatalogGroup] = [
        CatalogGroup(category: "Featured", items: [
            CatalogItem(name: "Claude FM", videoID: kDefaultVideoID),
        ]),
        CatalogGroup(category: "Lofi & Chill", items: [
            CatalogItem(name: "Lofi Girl — beats to relax/study", videoID: "jfKfPfyJRdk"),
            CatalogItem(name: "Lofi Girl — sleepy lofi",          videoID: "rUxyKA_-grg"),
            CatalogItem(name: "Chillhop Music — lofi jazz",       videoID: "5yx6BWlEVcY"),
        ]),
        CatalogGroup(category: "Synthwave & Retro", items: [
            CatalogItem(name: "Lofi Girl — synthwave radio",      videoID: "4xDzrJKXOOY"),
            CatalogItem(name: "ChillSynth FM — synthwave",        videoID: "S_MOd40zlYU"),
        ]),
        CatalogGroup(category: "Jazz & Cafe", items: [
            CatalogItem(name: "Cafe Music BGM — jazz cafe",       videoID: "Dx5qFachd3A"),
        ]),
        CatalogGroup(category: "Classical", items: [
            CatalogItem(name: "Halidon Music — classical",        videoID: "jgpJVI3tDbY"),
        ]),
        CatalogGroup(category: "Electronic", items: [
            CatalogItem(name: "Monstercat — Uncaged",             videoID: "MVPTGNGiI-4"),
        ]),
    ]

    // MARK: - Submit / save actions

    private var canSubmit: Bool {
        !urlInput.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func submitURL() {
        let trimmed = urlInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if YouTubeChannelURL.parse(trimmed) != nil {
            YouTubeSearchState.shared.mode = .channels
            YouTubeSearchState.shared.query = trimmed
            openSheet(id:"search")
            urlInput = ""
            return
        }
        if controller.load(input: trimmed) {
            urlInput = ""
        }
    }

}

// MARK: - Header bar

private struct HeaderBarView: View {
    let videoOn: Bool
    let onToggleVideo: () -> Void
    let onReload: () -> Void
    let share: NativeShareMenuButton
    let queueCount: Int
    let onOpenQueue: () -> Void
    let userPlaylistActive: Bool
    let userPlaylistTooltip: String
    let onOpenUserPlaylists: () -> Void
    let ytPlaylistActive: Bool
    let ytPlaylistLabel: String
    let onOpenPlaylistSheet: () -> Void
    let lyricsAvailable: Bool
    let onOpenLyrics: () -> Void
    let apiKeyConfigured: Bool
    let onOpenSettings: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            // Primary window controls.
            HStack(spacing: 8) {
                IconButton(systemName: videoOn ? "tv.fill" : "tv",
                           tint: videoOn ? MurmurColor.accent : nil,
                           help: videoOn ? "Hide floating video window"
                                         : "Show floating video window",
                           action: onToggleVideo)
                IconButton(systemName: "arrow.clockwise",
                           help: "Reload current stream",
                           action: onReload)
                // Native share button — sized to match IconButton's 36×28 chrome.
                shareChrome
            }

            Spacer()

            // Brand mark. Tracked, with soft accent glow per DESIGN.md typography.
            // `minimumScaleFactor` keeps the wordmark fully readable instead
            // of truncating to "M U R …" when the right-side cluster widens
            // (YT-playlist "1/37" pill, queue count, etc.). Avoid `fixedSize`
            // here — it pushes the HStack's intrinsic width past 500 and the
            // whole popover grows to fit, overflowing the .frame(width: 500).
            Text("MURMUR")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .tracking(8)
                .foregroundStyle(MurmurColor.textPrimary)
                .shadow(color: MurmurColor.glow, radius: 8)
                .lineLimit(1)
                .minimumScaleFactor(0.6)

            Spacer()

            // Library / settings cluster.
            HStack(spacing: 8) {
                if ytPlaylistActive {
                    IconButton(systemName: "play.square.stack.fill",
                               trailingLabel: ytPlaylistLabel,
                               tint: Color.cyan.opacity(0.9),
                               help: "Open YouTube playlist",
                               action: onOpenPlaylistSheet)
                }
                IconButton(systemName: "list.bullet",
                           trailingLabel: queueCount > 0 ? "\(queueCount)" : nil,
                           tint: queueCount > 0 ? MurmurColor.accent : nil,
                           help: queueCount > 0
                                ? "Playback queue — \(queueCount) up next"
                                : "Playback queue (empty)",
                           action: onOpenQueue)
                IconButton(systemName: "music.note.list",
                           tint: userPlaylistActive ? MurmurColor.accent : nil,
                           help: userPlaylistTooltip,
                           action: onOpenUserPlaylists)
                if lyricsAvailable {
                    IconButton(systemName: "text.quote",
                               tint: MurmurColor.accent,
                               help: "Lyrics",
                               action: onOpenLyrics)
                }
                IconButton(systemName: "gearshape",
                           tint: apiKeyConfigured ? MurmurColor.accent : nil,
                           help: apiKeyConfigured ? "YouTube API key configured"
                                                  : "Configure YouTube API key",
                           action: onOpenSettings)
            }
        }
        .frame(height: 28)
    }

    /// Wraps the AppKit share button in the same gradient/border chrome the
    /// SwiftUI IconButton uses so it doesn't look out of place in the row.
    private var shareChrome: some View {
        share
            .frame(width: 36, height: 28)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(LinearGradient(colors: [Color.murmurHex("#242424"), Color.murmurHex("#111111")],
                                         startPoint: .top, endPoint: .bottom))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(MurmurColor.border, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.4), radius: 6, x: 0, y: 3)
    }
}

// MARK: - Icon button

private struct IconButton: View {
    let systemName: String
    var trailingLabel: String? = nil
    var tint: Color? = nil
    let help: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 3) {
                Image(systemName: systemName)
                    .font(.system(size: 12, weight: .medium))
                if let trailing = trailingLabel {
                    Text(trailing)
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                }
            }
            .foregroundStyle(currentTint)
            .frame(minWidth: 36, maxWidth: .infinity)
            .frame(height: 28)
            .padding(.horizontal, 4)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(LinearGradient(colors: [Color.murmurHex("#242424"), Color.murmurHex("#111111")],
                                         startPoint: .top, endPoint: .bottom))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(hovering ? MurmurColor.accent.opacity(0.45) : MurmurColor.border,
                            lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.4), radius: 6, x: 0, y: 3)
        }
        .buttonStyle(.plain)
        .fixedSize()
        .onHover { hovering = $0 }
        .help(help)
    }

    private var currentTint: Color {
        if let tint = tint { return tint }
        return hovering ? MurmurColor.accent : MurmurColor.textSecondary
    }
}

// MARK: - URL input bar

private struct URLInputBarView: View {
    @Binding var text: String
    let onCommit: () -> Void
    let canSubmit: Bool
    let favoritesButton: NativeFavoritesMenuButton
    let onSearch: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "link")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(MurmurColor.accent)

            TextField("paste url or video id", text: $text, onCommit: onCommit)
                .textFieldStyle(.plain)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(MurmurColor.textPrimary)
                .tint(MurmurColor.accent)

            // Favorites star — AppKit NSMenu instead of SwiftUI `Menu` so the
            // "Discover live music" / "Remove" submenus track hover correctly.
            // SwiftUI's submenu tracking window doesn't become key here,
            // leaving highlights stuck and the cursor unable to traverse
            // submenu items.
            favoritesButton
                .frame(width: 20, height: 20)

            Button(action: onSearch) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(MurmurColor.textSecondary)
            }
            .buttonStyle(.plain)
            .help("Search YouTube")

            Button(action: onCommit) {
                Text("GO")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(canSubmit ? MurmurColor.accentLight : MurmurColor.textMuted)
                    .frame(width: 40, height: 24)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(LinearGradient(colors: [Color.murmurHex("#2A211C"), Color.murmurHex("#15110F")],
                                                 startPoint: .top, endPoint: .bottom))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(canSubmit ? MurmurColor.accent.opacity(0.55)
                                              : MurmurColor.border,
                                    lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .disabled(!canSubmit)
        }
        .padding(.horizontal, 10)
        .frame(height: 36)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(LinearGradient(colors: [Color.murmurHex("#181818"), Color.murmurHex("#0E0E0E")],
                                     startPoint: .top, endPoint: .bottom))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(hovering ? MurmurColor.accent.opacity(0.35) : MurmurColor.border,
                        lineWidth: 1)
        )
        .onHover { hovering = $0 }
    }
}

// MARK: - Cassette player card

private struct CassettePlayerCardView: View {
    let title: String
    let subtitle: String
    let badge: String
    let isPlaying: Bool
    let isReady: Bool
    let onPlayPause: () -> Void
    let onStop: () -> Void
    let onPrev: () -> Void
    let onNext: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            TrackInfoHeaderView(title: title, subtitle: subtitle, badge: badge)
            TapeVisualizerView(isPlaying: isPlaying)
            PlaybackControlsView(isPlaying: isPlaying,
                                 isReady: isReady,
                                 onPlayPause: onPlayPause,
                                 onStop: onStop,
                                 onPrev: onPrev,
                                 onNext: onNext)
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(LinearGradient(colors: [Color.murmurHex("#1A1A1A"), Color.murmurHex("#101010")],
                                     startPoint: .top, endPoint: .bottom))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(MurmurColor.accent.opacity(0.45), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.45), radius: 18, x: 0, y: 10)
    }
}

// MARK: - Track info header

private struct TrackInfoHeaderView: View {
    let title: String
    let subtitle: String
    let badge: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                MarqueeText(
                    text: title,
                    font: .system(size: 14, weight: .semibold, design: .monospaced),
                    foregroundColor: MurmurColor.accent
                )
                Text(subtitle)
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(MurmurColor.textMuted)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer(minLength: 6)
            Text(badge)
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .tracking(1)
                .foregroundStyle(MurmurColor.textSecondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.black.opacity(0.25))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(MurmurColor.border, lineWidth: 1)
                )
        }
    }
}

// MARK: - Tape visualizer (reels + tape line)

private struct TapeVisualizerView: View {
    let isPlaying: Bool

    var body: some View {
        HStack(spacing: 16) {
            TapeReelView(isPlaying: isPlaying)
            TapeLineView()
            TapeReelView(isPlaying: isPlaying)
        }
        .padding(.horizontal, 14)
        .frame(height: 76)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(LinearGradient(colors: [Color.murmurHex("#0B0B0B"), Color.murmurHex("#151515")],
                                     startPoint: .top, endPoint: .bottom))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.murmurHex("#292929"), lineWidth: 1)
        )
    }
}

// MARK: - Tape reel
//
// Driven by `TimelineView(.animation(paused:))` rather than the
// `withAnimation { … repeatForever }` pattern in DESIGN.md — the timeline
// approach freezes instantly on pause and resumes from the exact same
// angle, with no inertia / wind-down artefact. The visual is identical: an
// `AngularGradient` ring with a center hub and accent stroke.

private struct TapeReelView: View {
    let isPlaying: Bool
    private static let secondsPerRev: Double = 2

    var body: some View {
        TimelineView(.animation(paused: !isPlaying)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            let angle = (t.truncatingRemainder(dividingBy: Self.secondsPerRev)
                         / Self.secondsPerRev) * 360

            ZStack {
                Circle()
                    .fill(AngularGradient(
                        colors: [MurmurColor.accent,
                                 Color.murmurHex("#222222"),
                                 Color.murmurHex("#222222"),
                                 MurmurColor.accent,
                                 Color.murmurHex("#222222"),
                                 Color.murmurHex("#222222"),
                                 MurmurColor.accent],
                        center: .center))
                Circle().fill(Color.murmurHex("#101010")).frame(width: 16, height: 16)
                Circle().stroke(MurmurColor.accent.opacity(0.8), lineWidth: 1.5)
            }
            .frame(width: 50, height: 50)
            .rotationEffect(.degrees(angle))
            .shadow(color: MurmurColor.glow, radius: 7)
        }
    }
}

// MARK: - Tape line

private struct TapeLineView: View {
    var body: some View {
        VStack(spacing: 8) {
            Rectangle()
                .fill(LinearGradient(
                    colors: [MurmurColor.accent.opacity(0.15),
                             MurmurColor.accent.opacity(0.85),
                             MurmurColor.accent.opacity(0.15)],
                    startPoint: .leading, endPoint: .trailing))
                .frame(height: 1.5)

            HStack(spacing: 7) {
                ForEach(0..<12, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(MurmurColor.accent.opacity(0.45))
                        .frame(width: 1.5, height: 7)
                }
            }
        }
    }
}

// MARK: - Playback controls

private struct PlaybackControlsView: View {
    let isPlaying: Bool
    let isReady: Bool
    let onPlayPause: () -> Void
    let onStop: () -> Void
    let onPrev: () -> Void
    let onNext: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            PlayerControlButton(systemName: "backward.fill",
                                help: "Previous", action: onPrev)
            PlayerControlButton(systemName: "stop.fill",
                                help: "Stop", action: onStop)
            PlayerControlButton(systemName: isPlaying ? "pause.fill" : "play.fill",
                                isActive: true,
                                width: 62,
                                help: isPlaying ? "Pause" : "Play",
                                action: onPlayPause)
                .disabled(!isReady)
            PlayerControlButton(systemName: "forward.fill",
                                help: "Next", action: onNext)
        }
    }
}

private struct PlayerControlButton: View {
    let systemName: String
    var isActive: Bool = false
    var width: CGFloat = 46
    let help: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(foreground)
                .frame(width: width, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(LinearGradient(
                            colors: isActive
                                ? [Color.murmurHex("#3A251B"), Color.murmurHex("#17100C")]
                                : [Color.murmurHex("#242424"), Color.murmurHex("#111111")],
                            startPoint: .top, endPoint: .bottom))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(borderColor, lineWidth: 1)
                )
                .shadow(color: isActive ? MurmurColor.glow : .black.opacity(0.4),
                        radius: isActive ? 12 : 5, x: 0, y: isActive ? 0 : 2)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
    }

    private var foreground: Color {
        if isActive { return MurmurColor.accentLight }
        return hovering ? MurmurColor.textPrimary : MurmurColor.textSecondary
    }

    private var borderColor: Color {
        if isActive { return MurmurColor.accent.opacity(0.7) }
        return hovering ? MurmurColor.accent.opacity(0.35) : MurmurColor.border
    }
}

// MARK: - Footer

private struct FooterControlsView: View {
    @Binding var volume: Double
    let rate: Double
    let onPickRate: (Double) -> Void
    let statusText: String
    let isLive: Bool
    let versionLabel: AnyView
    let mixHint: String
    let onQuit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !mixHint.isEmpty {
                Text("⚠ \(mixHint.lowercased())")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.orange.opacity(0.85))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help("YouTube Mix playlists (list=RD…) are auto-generated by YouTube and the embedded player often won't chain to the next track. Try a saved PL… playlist instead.")
            }

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("VOLUME")
                        .font(.system(size: 8, weight: .semibold, design: .monospaced))
                        .tracking(1.5)
                        .foregroundStyle(MurmurColor.textSecondary)
                    Text(String(format: "%03d", Int(volume)))
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundStyle(MurmurColor.accent)
                }

                Slider(value: $volume, in: 0...100)
                    .tint(MurmurColor.accent)
                    .controlSize(.small)

                // Speed dropdown — small SwiftUI Menu. Same potential hover
                // bug as the favorites menu; can be swapped for NSMenu if it
                // bites in practice.
                Menu {
                    ForEach([0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0], id: \.self) { r in
                        Button(action: { onPickRate(r) }) {
                            if rate == r {
                                Label(String(format: "%.2fx", r), systemImage: "checkmark")
                            } else {
                                Text(String(format: "%.2fx", r))
                            }
                        }
                    }
                } label: {
                    Text(String(format: "%.2gx", rate))
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(rate == 1.0 ? MurmurColor.textSecondary : MurmurColor.accent)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Playback speed")
            }

            HStack(spacing: 6) {
                Circle()
                    .fill(isLive ? MurmurColor.accent : MurmurColor.textMuted)
                    .frame(width: 6, height: 6)
                    .shadow(color: isLive ? MurmurColor.accent : .clear, radius: 6)
                Text(statusText.lowercased())
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(MurmurColor.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 10)
                versionLabel
                Button(action: onQuit) {
                    Text("Quit")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(MurmurColor.textMuted)
                }
                .buttonStyle(.plain)
                .help("Quit Murmur")
            }
        }
    }
}

// MARK: - Native share menu
//
// AppKit-backed share button. Replaces a SwiftUI `Menu` that suffered from
// a hover-tracking bug inside the NSPopover (the dropdown window wasn't
// becoming key, so highlights stuck on the first item and the cursor
// couldn't move them). Built directly on `NSMenu.popUp` and
// `NSSharingServicePicker`, both of which behave correctly from inside an
// `.applicationDefined` popover.

struct NativeShareMenuButton: NSViewRepresentable {
    let shareURL: URL
    let murmurLink: URL
    let shareTitle: String
    let tint: NSColor

    func makeCoordinator() -> Coordinator {
        Coordinator(shareURL: shareURL, murmurLink: murmurLink, shareTitle: shareTitle)
    }

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton()
        button.bezelStyle = .regularSquare
        button.isBordered = false
        button.imagePosition = .imageOnly
        // .scaleNone keeps the symbol at its configured point size — using
        // .scaleProportionallyUpOrDown would let it grow to fill the chrome
        // frame, making the share icon visibly larger than the neighboring
        // SwiftUI IconButtons (which render the symbol at its natural size).
        button.imageScaling = .scaleNone
        let cfg = NSImage.SymbolConfiguration(pointSize: 12, weight: .medium)
        let image = NSImage(systemSymbolName: "square.and.arrow.up", accessibilityDescription: "Share")?
            .withSymbolConfiguration(cfg)
        image?.isTemplate = true
        button.image = image
        button.contentTintColor = tint
        button.toolTip = "Share what you're listening to"
        button.target = context.coordinator
        button.action = #selector(Coordinator.onClick(_:))
        return button
    }

    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.shareURL = shareURL
        context.coordinator.murmurLink = murmurLink
        context.coordinator.shareTitle = shareTitle
        button.contentTintColor = tint
    }

    final class Coordinator: NSObject {
        var shareURL: URL
        var murmurLink: URL
        var shareTitle: String
        private weak var anchor: NSView?

        init(shareURL: URL, murmurLink: URL, shareTitle: String) {
            self.shareURL = shareURL
            self.murmurLink = murmurLink
            self.shareTitle = shareTitle
        }

        @objc func onClick(_ sender: NSButton) {
            anchor = sender
            let menu = NSMenu()
            menu.autoenablesItems = false
            menu.addItem(item("Share (YouTube link)…",   "square.and.arrow.up",   #selector(shareYouTube(_:))))
            menu.addItem(item("Share Murmur link…",      "music.note",            #selector(shareMurmur(_:))))
            menu.addItem(.separator())
            menu.addItem(item("Copy YouTube link",       "link",                  #selector(copyYouTube(_:))))
            menu.addItem(item("Copy Murmur link",        "music.note.list",       #selector(copyMurmur(_:))))
            menu.addItem(item("Copy title",              "text.cursor",           #selector(copyTitle(_:))))
            menu.addItem(.separator())
            menu.addItem(item("Copy title + YouTube link", "doc.on.clipboard",    #selector(copyTitleAndYouTube(_:))))
            menu.addItem(item("Copy rich card",          "rectangle.on.rectangle",#selector(copyRichCard(_:))))
            menu.popUp(positioning: nil,
                       at: NSPoint(x: 0, y: sender.bounds.height + 4),
                       in: sender)
        }

        private func item(_ title: String, _ systemImage: String, _ action: Selector) -> NSMenuItem {
            let i = NSMenuItem(title: title, action: action, keyEquivalent: "")
            i.target = self
            i.image = NSImage(systemSymbolName: systemImage, accessibilityDescription: nil)
            return i
        }

        @objc private func shareYouTube(_ s: Any) { share([shareURL as NSURL]) }
        @objc private func shareMurmur(_ s: Any)  { share([murmurLink as NSURL]) }
        @objc private func copyYouTube(_ s: Any)  { copy(shareURL.absoluteString) }
        @objc private func copyMurmur(_ s: Any)   { copy(murmurLink.absoluteString) }
        @objc private func copyTitle(_ s: Any)    { copy(shareTitle) }
        @objc private func copyTitleAndYouTube(_ s: Any) {
            copy("\(shareTitle)\n\(shareURL.absoluteString)")
        }
        @objc private func copyRichCard(_ s: Any) {
            copy("♪ \(shareTitle)\n\(shareURL.absoluteString)\nOpen in Murmur: \(murmurLink.absoluteString)")
        }

        private func share(_ items: [Any]) {
            guard let anchor = anchor else { return }
            let picker = NSSharingServicePicker(items: items)
            picker.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .minY)
        }

        private func copy(_ s: String) {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(s, forType: .string)
        }
    }
}

// MARK: - Native favorites + discover menu
//
// AppKit-backed star button. Replaces a SwiftUI `Menu` whose nested
// submenus ("Remove", "Discover live music") suffered the same hover-
// tracking bug as the old share menu: the submenu window didn't become
// key, leaving the highlight stuck on the first item and the cursor
// unable to traverse. `NSMenu` handles its own tracking correctly.

struct NativeFavoritesMenuButton: NSViewRepresentable {
    let controller: PlayerController
    let tint: NSColor

    func makeCoordinator() -> Coordinator { Coordinator(controller: controller) }

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton()
        button.bezelStyle = .regularSquare
        button.isBordered = false
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleNone
        let cfg = NSImage.SymbolConfiguration(pointSize: 12, weight: .medium)
        let image = NSImage(systemSymbolName: "star.fill", accessibilityDescription: "Favorites")?
            .withSymbolConfiguration(cfg)
        image?.isTemplate = true
        button.image = image
        button.contentTintColor = tint
        button.toolTip = "Favorites & discover"
        button.target = context.coordinator
        button.action = #selector(Coordinator.onClick(_:))
        return button
    }

    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.controller = controller
        button.contentTintColor = tint
    }

    final class Coordinator: NSObject {
        var controller: PlayerController

        init(controller: PlayerController) { self.controller = controller }

        @objc func onClick(_ sender: NSButton) {
            let menu = buildMenu()
            menu.popUp(positioning: nil,
                       at: NSPoint(x: 0, y: sender.bounds.height + 4),
                       in: sender)
        }

        private func buildMenu() -> NSMenu {
            let menu = NSMenu()
            menu.autoenablesItems = false

            let favorites = FavoritesStore.shared.items
            let currentID = controller.currentVideoID

            if favorites.isEmpty {
                let placeholder = NSMenuItem(title: "No favorites yet", action: nil, keyEquivalent: "")
                placeholder.isEnabled = false
                menu.addItem(placeholder)
            } else {
                for fav in favorites {
                    let item = NSMenuItem(title: label(name: fav.name, videoID: fav.videoID),
                                          action: #selector(loadFavorite(_:)),
                                          keyEquivalent: "")
                    item.target = self
                    item.representedObject = fav.videoID
                    menu.addItem(item)
                }
                menu.addItem(.separator())
                let removeRoot = NSMenuItem(title: "Remove", action: nil, keyEquivalent: "")
                let removeSub = NSMenu()
                for fav in favorites {
                    let r = NSMenuItem(title: fav.name,
                                       action: #selector(removeFavorite(_:)),
                                       keyEquivalent: "")
                    r.target = self
                    r.representedObject = fav.videoID
                    removeSub.addItem(r)
                }
                removeRoot.submenu = removeSub
                menu.addItem(removeRoot)
            }

            menu.addItem(.separator())

            let discoverRoot = NSMenuItem(title: "Discover live music", action: nil, keyEquivalent: "")
            let discoverSub = NSMenu()
            for group in ContentView.catalog {
                let header = NSMenuItem(title: group.category, action: nil, keyEquivalent: "")
                header.isEnabled = false
                discoverSub.addItem(header)
                for item in group.items {
                    let it = NSMenuItem(title: label(name: item.name, videoID: item.videoID),
                                        action: #selector(loadFavorite(_:)),
                                        keyEquivalent: "")
                    it.target = self
                    it.representedObject = item.videoID
                    discoverSub.addItem(it)
                }
            }
            discoverRoot.submenu = discoverSub
            menu.addItem(discoverRoot)

            menu.addItem(.separator())

            let save = NSMenuItem(title: "Save current as favorite",
                                  action: #selector(saveCurrent(_:)),
                                  keyEquivalent: "")
            save.target = self
            save.isEnabled = !currentID.isEmpty
            menu.addItem(save)

            return menu
        }

        private func label(name: String, videoID: String) -> String {
            videoID == controller.currentVideoID ? "● \(name)" : "   \(name)"
        }

        @objc private func loadFavorite(_ sender: NSMenuItem) {
            guard let videoID = sender.representedObject as? String else { return }
            _ = controller.load(input: videoID)
        }

        @objc private func removeFavorite(_ sender: NSMenuItem) {
            guard let videoID = sender.representedObject as? String,
                  let fav = FavoritesStore.shared.items.first(where: { $0.videoID == videoID })
            else { return }
            FavoritesStore.shared.remove(fav)
        }

        @objc private func saveCurrent(_ sender: NSMenuItem) {
            let id = controller.currentVideoID
            guard !id.isEmpty else { return }
            let placeholder = "YouTube Live Stream"
            let name = (controller.title == placeholder || controller.title.isEmpty) ? id : controller.title
            FavoritesStore.shared.add(name: name, videoID: id)
        }
    }
}
