import AppKit
import SwiftUI

struct ContentView: View {
    @EnvironmentObject var controller: PlayerController
    @EnvironmentObject var favorites: FavoritesStore
    @EnvironmentObject var videoWindow: VideoWindowController
    @State private var urlInput: String = ""

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
                header
                urlRow
                dancerRow
                controlsRow
                statusFooter
            }
            .padding(outerPad)
        }
        .frame(width: 300, height: 250)
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
        HStack(spacing: 8) {
            Text("♪")
                .foregroundColor(accent)
            Text("—")
                .foregroundColor(fgDim)
            Text(headerLabel)
                .foregroundColor(fg)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer()
            Button(action: { videoWindow.toggle() }) {
                Text(videoWindow.isVisible ? "Video On" : "Video")
                    .foregroundColor(videoWindow.isVisible ? accent : fgDim)
            }
            .buttonStyle(.plain)
            .help("Show/hide floating video window")
            Button(action: { controller.reload() }) {
                Text("Reload").foregroundColor(fgDim)
            }
            .buttonStyle(.plain)
            .help("Reload current stream")
        }
        .font(.system(size: 11, weight: .medium, design: .monospaced))
    }

    private var headerLabel: String {
        let title = controller.title.trimmingCharacters(in: .whitespaces)
        return title.isEmpty ? "Murmur" : title
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
        }
    }

    private var statusFooter: some View {
        HStack(spacing: 6) {
            Text(controller.isPlaying ? "●" : "○")
                .foregroundColor(controller.isPlaying ? accent : fgDim)
            Text(controller.status.lowercased())
                .foregroundColor(fgDim)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 8)
            Button(action: { NSApp.terminate(nil) }) {
                Text("Quit")
                    .foregroundColor(fgDim)
            }
            .buttonStyle(.plain)
            .help("Quit Murmur")
        }
        .font(.system(size: 9, design: .monospaced))
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
