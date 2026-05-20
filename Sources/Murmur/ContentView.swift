import AppKit
import SwiftUI

struct ContentView: View {
    @EnvironmentObject var controller: PlayerController
    @EnvironmentObject var favorites: FavoritesStore
    @EnvironmentObject var videoWindow: VideoWindowController
    @EnvironmentObject var booth: BoothLauncher
    @EnvironmentObject var queueLauncher: QueueLauncher
    @ObservedObject private var playbackQueue = PlaybackQueue.shared
    @ObservedObject private var playlistStore = PlaylistStore.shared
    @ObservedObject private var userPlaylistsLauncher = UserPlaylistsLauncher.shared
    @ObservedObject private var userPlaylists = UserPlaylistsStore.shared
    @State private var urlInput: String = ""
    @State private var showingAPIKeySheet: Bool = false
    @State private var showingPlaylistSheet: Bool = false
    @State private var showingYouTubeSearch: Bool = false
    @State private var ytInitialMode: YouTubeSearchSheet.Mode = .videos
    @State private var ytInitialQuery: String = ""
    @ObservedObject private var apiKeyStore = APIKeyStore.shared
    @ObservedObject private var updateChecker = UpdateChecker.shared

    // Cozy pixel-art palette: warm cream on near-black, peach accent for active states.
    private let bg     = Color(red: 0.05, green: 0.05, blue: 0.06)
    private let fg     = Color(red: 0.91, green: 0.87, blue: 0.78)
    private let fgDim  = Color(red: 0.91, green: 0.87, blue: 0.78).opacity(0.45)
    private let border = Color(red: 0.91, green: 0.87, blue: 0.78).opacity(0.30)
    private let accent = Color(red: 0.96, green: 0.65, blue: 0.45)
    private let dashStyle = StrokeStyle(lineWidth: 1, dash: [2, 2])

    // Spacing tokens — single source of truth so padding stays consistent.
    private let outerPad: CGFloat = 14
    private let rowGap:   CGFloat = 10

    var body: some View {
        ZStack {
            bg

            VStack(alignment: .leading, spacing: rowGap) {
                wordmark
                header
                urlRow
                dancerRow
                controlsRow
                statusFooter
            }
            .padding(outerPad)
        }
        .frame(width: 340, height: 296)
    }

    /// Centered "MURMUR" brand mark at the very top of the popover. Tracked
    /// letters + monospaced weight to match the cassette / pixel-art palette.
    private var wordmark: some View {
        HStack(spacing: 0) {
            Text("MURMUR")
                .font(.system(size: 11, weight: .heavy, design: .monospaced))
                .tracking(4)
                .foregroundColor(fg)
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private var dancerRow: some View {
        HStack {
            Spacer()
            CassetteTape(controller: controller)
            Spacer()
        }
    }

    // MARK: - Sections

    private var header: some View {
        // Title now lives on the cassette label below. The header is a pure
        // toolbar: window controls on the left, library indicators clustered
        // toward the right, settings at the far edge. Leading spacer keeps
        // the row breathing on small popover widths.
        HStack(spacing: 6) {
            // Window controls (primary).
            headerIconButton(
                systemName: videoWindow.isVisible ? "tv.fill" : "tv",
                tint: videoWindow.isVisible ? accent : fgDim,
                help: videoWindow.isVisible ? "Hide floating video window" : "Show floating video window",
                action: { videoWindow.toggle() }
            )
            headerIconButton(
                systemName: "arrow.clockwise",
                tint: fgDim,
                help: "Reload current stream",
                action: { controller.reload() }
            )
            shareMenu

            Spacer(minLength: 4)

            // Library indicators (counts surface only when there's something to count).
            if playlistStore.hasActivePlaylist {
                Button(action: { showingPlaylistSheet = true }) {
                    HStack(spacing: 3) {
                        Image(systemName: "play.square.stack.fill")
                        if let i = playlistStore.currentIndex {
                            Text("\(i + 1)/\(playlistStore.items.count)")
                                .font(.system(size: 9, design: .monospaced))
                        } else {
                            Text("\(playlistStore.items.count)")
                                .font(.system(size: 9, design: .monospaced))
                        }
                    }
                    .foregroundColor(.cyan.opacity(0.85))
                }
                .buttonStyle(.plain)
                .help("YouTube playlist — \(playlistStore.items.count) tracks")
            }
            Button(action: { queueLauncher.show() }) {
                HStack(spacing: 3) {
                    Image(systemName: "list.bullet")
                    if !playbackQueue.isEmpty {
                        Text("\(playbackQueue.count)")
                            .font(.system(size: 9, design: .monospaced))
                    }
                }
                .foregroundColor(playbackQueue.isEmpty ? fgDim : accent)
            }
            .buttonStyle(.plain)
            .help(playbackQueue.isEmpty
                  ? "Playback queue (empty)"
                  : "Playback queue — \(playbackQueue.count) up next")
            Button(action: { userPlaylistsLauncher.show() }) {
                HStack(spacing: 3) {
                    Image(systemName: "music.note.list")
                    if userPlaylists.hasActivePlaylist,
                       let idx = userPlaylists.activeIndex,
                       let p = userPlaylists.activePlaylist {
                        Text("\(idx + 1)/\(p.items.count)")
                            .font(.system(size: 9, design: .monospaced))
                    }
                }
                .foregroundColor(userPlaylists.hasActivePlaylist ? accent : fgDim)
            }
            .buttonStyle(.plain)
            .help(userPlaylists.hasActivePlaylist
                  ? "Playing from \"\(userPlaylists.activePlaylist?.name ?? "")\""
                  : "My playlists")

            headerSeparator

            headerIconButton(
                systemName: "gearshape",
                tint: apiKeyStore.hasYouTubeKey ? accent : fgDim,
                help: apiKeyStore.hasYouTubeKey ? "YouTube API key configured" : "Configure YouTube API key",
                action: { showingAPIKeySheet = true }
            )
        }
        .font(.system(size: 11, weight: .medium, design: .monospaced))
        .sheet(isPresented: $showingAPIKeySheet) {
            APIKeySetupSheet(store: apiKeyStore)
        }
        .sheet(isPresented: $queueLauncher.isShowing) {
            QueueSheet { item in
                _ = controller.load(input: item.videoID)
            }
        }
        .sheet(isPresented: $showingPlaylistSheet) {
            PlaylistSheet { videoID in
                _ = controller.load(input: videoID)
            }
        }
        .sheet(isPresented: $userPlaylistsLauncher.isShowing) {
            UserPlaylistsSheet { videoID in
                _ = controller.load(input: videoID)
            }
        }
    }

    /// Minimal SF-symbol button used across the header so all action buttons
    /// share the same hit target + tint behavior. Keeps the call sites short.
    private func headerIconButton(systemName: String, tint: Color, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .foregroundColor(tint)
                .frame(width: 16, height: 16)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    /// Thin vertical rule that splits the header into logical clusters:
    /// window controls / library indicators / app config.
    private var headerSeparator: some View {
        Rectangle()
            .fill(border)
            .frame(width: 1, height: 11)
            .padding(.horizontal, 1)
    }

    /// Share menu for the currently-playing track. `ShareLink` (macOS 13+)
    /// opens the system share sheet — Messages, Mail, AirDrop, Notes, and any
    /// installed share extensions. The Murmur-link variant uses the registered
    /// `murmur://` URL scheme (Info.plist `CFBundleURLTypes`) so recipients
    /// with Murmur installed open straight into playback. The Copy actions
    /// are the fast path for chat apps that auto-unfurl YouTube links.
    private var shareMenu: some View {
        Menu {
            ShareLink(item: shareURL,
                      subject: Text(shareTitle),
                      message: Text("\(shareTitle)\n\(murmurLink.absoluteString)")) {
                Label("Share (YouTube link)…", systemImage: "square.and.arrow.up")
            }
            ShareLink(item: murmurLink,
                      subject: Text("Open in Murmur — \(shareTitle)"),
                      message: Text("\(shareTitle)\nOpen with Murmur:")) {
                Label("Share Murmur link…", systemImage: "music.note")
            }
            Divider()
            Button {
                copyToPasteboard(shareURL.absoluteString)
            } label: {
                Label("Copy YouTube link", systemImage: "link")
            }
            Button {
                copyToPasteboard(murmurLink.absoluteString)
            } label: {
                Label("Copy Murmur link", systemImage: "music.note.list")
            }
            Button {
                copyToPasteboard(shareTitle)
            } label: {
                Label("Copy title", systemImage: "text.cursor")
            }
            Divider()
            Button {
                copyToPasteboard("\(shareTitle)\n\(shareURL.absoluteString)")
            } label: {
                Label("Copy title + YouTube link", systemImage: "doc.on.clipboard")
            }
            Button {
                copyToPasteboard("♪ \(shareTitle)\n\(shareURL.absoluteString)\nOpen in Murmur: \(murmurLink.absoluteString)")
            } label: {
                Label("Copy rich card", systemImage: "rectangle.on.rectangle")
            }
        } label: {
            Image(systemName: "square.and.arrow.up")
                .foregroundColor(fgDim)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Share what you're listening to")
    }

    /// Watch URL for the active video, with `&list=…` appended when a YouTube
    /// playlist is loaded so the recipient lands in the same playlist context.
    /// Falls back to the short `youtu.be` form for plain single-video shares.
    private var shareURL: URL {
        let videoID = controller.currentVideoID
        let playlistID = playlistStore.hasActivePlaylist ? playlistStore.playlistID : ""
        let raw: String
        if !playlistID.isEmpty {
            raw = "https://www.youtube.com/watch?v=\(videoID)&list=\(playlistID)"
        } else {
            raw = "https://youtu.be/\(videoID)"
        }
        // youtu.be / watch URLs above are always well-formed; the `!` is safe.
        return URL(string: raw)!
    }

    /// Deep link into the Murmur app for the currently-playing track. Format:
    /// `murmur://play?v=<id>[&list=<playlistID>]` — handled by
    /// `AppDelegate.application(_:open:)`. Recipients without Murmur installed
    /// will get a "no app to open" error from macOS, so this is paired with
    /// the YouTube link in the rich share variants.
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

    private func copyToPasteboard(_ s: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(s, forType: .string)
    }

    private var urlRow: some View {
        HStack(spacing: 8) {
            Text("›").foregroundColor(fgDim)
            TextField("paste url or video id", text: $urlInput, onCommit: submitURL)
                .textFieldStyle(.plain)
                .foregroundColor(fg)
                .tint(accent)

            Menu {
                favoritesMenu
            } label: {
                Text("★").foregroundColor(accent)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Favorites & discover")

            Button(action: {
                ytInitialMode = .videos
                ytInitialQuery = ""
                showingYouTubeSearch = true
            }) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(fgDim)
            }
            .buttonStyle(.plain)
            .help("Search YouTube")

            Button(action: submitURL) {
                Text("Go")
                    .foregroundColor(canSubmit ? accent : fgDim)
            }
            .buttonStyle(.plain)
            .disabled(!canSubmit)
        }
        .font(.system(size: 11, design: .monospaced))
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .overlay(Rectangle().stroke(border, style: dashStyle))
        .sheet(isPresented: $showingYouTubeSearch) {
            YouTubeSearchSheet(
                initialMode: ytInitialMode,
                initialQuery: ytInitialQuery
            ) { videoID in
                _ = controller.load(input: videoID)
            }
        }
    }

    private var controlsRow: some View {
        HStack(spacing: 8) {
            Text("vol")
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundColor(fgDim)
            Slider(value: $controller.volume, in: 0...100)
                .tint(accent)
                .controlSize(.mini)
                .onChange(of: controller.volume) { newVal in
                    controller.setVolume(Int(newVal))
                }
            Text(String(format: "%03d", Int(controller.volume)))
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundColor(fg)
            Menu {
                ForEach([0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0], id: \.self) { rate in
                    Button(action: { controller.setPlaybackRate(rate) }) {
                        if controller.playbackRate == rate {
                            Label(String(format: "%.2fx", rate), systemImage: "checkmark")
                        } else {
                            Text(String(format: "%.2fx", rate))
                        }
                    }
                }
            } label: {
                Text(String(format: "%.2gx", controller.playbackRate))
                    .foregroundColor(controller.playbackRate == 1.0 ? fgDim : accent)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .font(.system(size: 9, weight: .medium, design: .monospaced))
            .help("Playback speed")
        }
    }

    private var statusFooter: some View {
        VStack(alignment: .leading, spacing: 2) {
            if !controller.mixHint.isEmpty {
                Text("⚠ \(controller.mixHint.lowercased())")
                    .foregroundColor(.orange.opacity(0.85))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help("YouTube Mix playlists (list=RD…) are auto-generated by YouTube and the embedded player often won't chain to the next track. Try a saved PL… playlist instead.")
            }
            HStack(spacing: 6) {
                Text(controller.isPlaying ? "●" : "○")
                    .foregroundColor(controller.isPlaying ? accent : fgDim)
                Text(controller.status.lowercased())
                    .foregroundColor(fgDim)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 8)
                versionLabel
                Button(action: { NSApp.terminate(nil) }) {
                    Text("Quit")
                        .foregroundColor(fgDim)
                }
                .buttonStyle(.plain)
                .help("Quit Murmur")
            }
        }
        .font(.system(size: 9, design: .monospaced))
    }

    /// Version pill — dim "v…" by default; turns into a tappable accent
    /// badge ("v… → v…  ↑") when `UpdateChecker` finds a newer GitHub release.
    /// Clicking opens the release page in the default browser.
    @ViewBuilder
    private var versionLabel: some View {
        if updateChecker.hasUpdate, let url = updateChecker.releaseURL,
           let latest = updateChecker.latestVersion {
            Button(action: { NSWorkspace.shared.open(url) }) {
                HStack(spacing: 3) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 9))
                    Text("v\(latest)")
                }
                .foregroundColor(accent)
            }
            .buttonStyle(.plain)
            .help("Update available — v\(updateChecker.currentVersion) → v\(latest). Click to view on GitHub.")
        } else {
            Text("v\(updateChecker.currentVersion)")
                .foregroundColor(fgDim)
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

    private var boothButton: some View {
        Button(action: { booth.show() }) {
            Text("OPEN DJ BOOTH →")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .tracking(1.5)
                .foregroundColor(accent)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(accent.opacity(0.7), style: dashStyle)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Menus

    @ViewBuilder
    private var favoritesMenu: some View {
        if favorites.items.isEmpty {
            Text("No favorites yet")
        } else {
            ForEach(favorites.items) { fav in
                Button(menuLabel(name: fav.name, videoID: fav.videoID)) {
                    controller.load(input: fav.videoID)
                }
            }
            Divider()
            Menu("Remove") {
                ForEach(favorites.items) { fav in
                    Button(fav.name) { favorites.remove(fav) }
                }
            }
        }
        Divider()
        Menu("Discover live music") {
            discoverMenu
        }
        Divider()
        Button("Save current as favorite", action: saveCurrentFavorite)
            .disabled(controller.currentVideoID.isEmpty)
    }

    /// In-widget catalog of known live music streams, organized by genre.
    /// IDs may go stale if a stream restarts — when that happens, paste a
    /// fresh URL into the input field and Save Current to replace.
    @ViewBuilder
    private var discoverMenu: some View {
        ForEach(Self.catalog, id: \.category) { group in
            Section(group.category) {
                ForEach(group.items, id: \.videoID) { item in
                    Button(menuLabel(name: item.name, videoID: item.videoID)) {
                        controller.load(input: item.videoID)
                    }
                }
            }
        }
    }

    /// Prefix the active stream with a ● dot so the user can see what's playing.
    /// Two leading spaces on inactive items keep names vertically aligned.
    private func menuLabel(name: String, videoID: String) -> String {
        videoID == controller.currentVideoID ? "● \(name)" : "   \(name)"
    }

    private struct CatalogGroup {
        let category: String
        let items: [CatalogItem]
    }
    private struct CatalogItem {
        let name: String
        let videoID: String
    }

    private static let catalog: [CatalogGroup] = [
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

    // MARK: - Actions

    private var canSubmit: Bool {
        !urlInput.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func submitURL() {
        let trimmed = urlInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if YouTubeChannelURL.parse(trimmed) != nil {
            ytInitialMode = .channels
            ytInitialQuery = trimmed
            showingYouTubeSearch = true
            urlInput = ""
            return
        }

        // Pass the raw URL through so `controller.load` can pull out both the
        // video ID and any `list=…` playlist parameter.
        if controller.load(input: trimmed) {
            urlInput = ""
        }
    }

    private func saveCurrentFavorite() {
        let id = controller.currentVideoID
        guard !id.isEmpty else { return }
        let placeholder = "YouTube Live Stream"
        let name = (controller.title == placeholder || controller.title.isEmpty) ? id : controller.title
        favorites.add(name: name, videoID: id)
    }

}
