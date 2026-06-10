import AppKit
import SwiftUI

/// World Cup 2026 board — the `world-cup` Window scene, opened from the
/// header's soccer-ball button, the favorites menu, `murmur://worldcup`, or
/// a notification click.
///
/// Four tabs:
///   Matches — day-grouped fixtures with live clocks/scores, expandable
///             per-match detail (events / stats / lineups), live audio
///             sources, per-match stream resolution, follow context menus.
///   Groups  — all 12 group tables, star-to-follow teams.
///   News    — ESPN World Cup headlines.
///   Bracket — knockout fixtures by round (empty until the draw exists).
///
/// The bell popover configures the live machinery (`WorldCupAlertSettings`):
/// goal/FT notifications, kickoff reminders, the menu-bar ticker, and
/// auto-tune radio. Those run app-wide via `WorldCupNotifier`/`WorldCupTicker`
/// — this window is just where they're switched on.
struct WorldCupSheet: View {
    @EnvironmentObject var controller: PlayerController
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openWindow) private var openWindow
    @ObservedObject private var store = WorldCupStore.shared
    @ObservedObject private var apiKeys = APIKeyStore.shared
    @ObservedObject private var follows = WorldCupFollowStore.shared
    @ObservedObject private var alerts = WorldCupAlertSettings.shared

    enum Tab: String, CaseIterable {
        case matches, groups, scorers, news, bracket
    }

    enum MatchScope: String, CaseIterable {
        case all = "All"
        case live = "Live"
        case followed = "★"
    }

    @State private var selectedTab: Tab
    @State private var hideFinished = false
    @State private var scope: MatchScope = .all
    @State private var resolvingSourceID: String? = nil
    @State private var sourceError: String? = nil
    @State private var didAutoScroll = false
    @State private var expandedMatchID: String? = nil
    @State private var showSettings = false
    @State private var showAddSource = false
    @State private var newSourceName = ""
    @State private var newSourceURL = ""

    init() {
        // Verification/debug affordance: MURMUR_WC_TAB=news (etc.) preselects
        // a tab at window creation. Defaults to Matches.
        let env = ProcessInfo.processInfo.environment["MURMUR_WC_TAB"] ?? ""
        _selectedTab = State(initialValue: Tab(rawValue: env) ?? .matches)
    }

    var body: some View {
        PopoverShell {
            header
        } content: {
            VStack(spacing: 0) {
                MurmurSegmentedTabs(tabs: Tab.allCases, selectedTab: $selectedTab)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                Divider().background(MurmurColor.border.opacity(0.6))
                switch selectedTab {
                case .matches: matchesTab
                case .groups:  groupsTab
                case .scorers: scorersTab
                case .news:    newsTab
                case .bracket: bracketTab
                }
            }
        } footer: {
            footer
        }
        .frame(width: 540, height: 700)
        .padding(8)
        .onAppear { store.sheetDidOpen() }
        .onDisappear { store.sheetDidClose() }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "soccerball")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(MurmurColor.accent)
            Text("World Cup 2026")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(MurmurColor.textPrimary)
            if store.liveCount > 0 {
                HStack(spacing: 4) {
                    PulsingDot()
                    Text("\(store.liveCount) LIVE")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.red.opacity(0.9))
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color.red.opacity(0.12)))
            }
            Spacer()
            Button { ScoreboardPanel.shared.toggle() } label: {
                Image(systemName: "rectangle.inset.topright.filled")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(MurmurColor.textSecondary)
            }
            .buttonStyle(.plain)
            .help("Floating mini-scoreboard — live scores in a corner, above every app")
            Button { showSettings.toggle() } label: {
                Image(systemName: "bell")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(alerts.goalScope == .off ? MurmurColor.textMuted
                                                              : MurmurColor.accent)
            }
            .buttonStyle(.plain)
            .help("Alerts & live updates — notifications, menu-bar ticker, auto-tune")
            .popover(isPresented: $showSettings, arrowEdge: .bottom) { settingsPopover }
            if store.isLoading {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.7)
            } else {
                Button { store.refresh(force: true) } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(MurmurColor.textSecondary)
                }
                .buttonStyle(.plain)
                .help("Refresh scores now")
            }
            CloseButton(action: { dismiss() })
        }
        .padding(.horizontal, 16)
        .frame(height: 44)
    }

    // MARK: Settings popover

    private var settingsPopover: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("LIVE UPDATES")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .tracking(1.4)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 5) {
                Text("Goal & full-time notifications")
                    .font(.system(size: 11, weight: .semibold))
                Picker("", selection: $alerts.goalScope) {
                    ForEach(WorldCupAlertSettings.GoalScope.allCases, id: \.self) { scope in
                        Text(scope.rawValue).tag(scope)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            Toggle("Kick-off reminders (followed teams)", isOn: $alerts.kickoffReminders)
                .font(.system(size: 11))
            Toggle("Morning fixtures digest (8 AM)", isOn: $alerts.dailyDigest)
                .font(.system(size: 11))
            Toggle("Live score in the menu bar", isOn: $alerts.tickerEnabled)
                .font(.system(size: 11))
            Toggle("Auto-play radio at kick-off (followed)", isOn: $alerts.autoTuneRadio)
                .font(.system(size: 11))

            Divider()

            Button {
                WorldCupCalendarExport.export(
                    store.matches.filter { $0.state == .scheduled && follows.involvesFollowedTeam($0) })
            } label: {
                Label("Add followed fixtures to Calendar…", systemImage: "calendar.badge.plus")
                    .font(.system(size: 11))
            }
            .disabled(!store.matches.contains { $0.state == .scheduled && follows.involvesFollowedTeam($0) })

            Text("Scores poll every minute while matches are live; alerts only arrive while Murmur is running. Follow teams via right-click on a match or the ☆ in Groups.")
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(width: 270)
    }

    // MARK: Matches tab

    private var matchesTab: some View {
        VStack(spacing: 0) {
            sourcesStrip
            filterRow
            Divider().background(MurmurColor.border.opacity(0.6))
            scheduleList
        }
    }

    /// Scope chips (All / Live / ★) + the next-followed-match countdown.
    private var filterRow: some View {
        HStack(spacing: 6) {
            ForEach(MatchScope.allCases, id: \.self) { s in
                Button { scope = s } label: {
                    Text(s.rawValue)
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundStyle(scope == s ? MurmurColor.textPrimary : MurmurColor.textMuted)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            Capsule().fill(scope == s ? MurmurColor.accent.opacity(0.25)
                                                      : Color.white.opacity(0.04))
                        )
                }
                .buttonStyle(.plain)
                .help(s == .live ? "Live matches only" : (s == .followed ? "Followed teams only" : "All matches"))
            }
            Spacer()
            if let next = nextFollowedMatch {
                Image(systemName: "star.fill")
                    .font(.system(size: 7))
                    .foregroundStyle(MurmurColor.accent)
                Text("\(next.home.abbrev) vs \(next.away.abbrev) in")
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .foregroundStyle(MurmurColor.textSecondary)
                Text(timerInterval: Date()...max(Date(), next.date), countsDown: true)
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(MurmurColor.accent)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    /// Next upcoming match of a followed team — the countdown target.
    private var nextFollowedMatch: WorldCupMatch? {
        store.matches
            .filter { $0.state == .scheduled && $0.date > Date() && follows.involvesFollowedTeam($0) }
            .min { $0.date < $1.date }
    }

    // MARK: Live sources strip

    private struct LiveSource: Identifiable {
        enum Kind {
            case youTubeLive(liveURL: URL, fallback: URL)
            case tvriEmbedded
        }
        let id: String
        let name: String
        let systemImage: String
        let help: String
        let kind: Kind
    }

    private static let sources: [LiveSource] = [
        LiveSource(
            id: "tvri",
            name: "TVRI",
            systemImage: "tv.fill",
            help: "TVRI — Indonesia's official 2026 World Cup broadcaster, all 104 matches free. Opens the live TVRI Klik stream in a floating Murmur window (full match video).",
            kind: .tvriEmbedded
        ),
        LiveSource(
            id: "fifa",
            name: "FIFA Official",
            systemImage: "trophy.fill",
            help: "FIFA's YouTube channel — live studio shows, watchalongs & highlights",
            kind: .youTubeLive(liveURL: URL(string: "https://www.youtube.com/@FIFA/live")!,
                               fallback: URL(string: "https://www.youtube.com/@FIFA")!)
        ),
        LiveSource(
            id: "talksport",
            name: "talkSPORT Radio",
            systemImage: "radio.fill",
            help: "UK sports radio — live World Cup match commentary, perfect for audio-only",
            kind: .youTubeLive(liveURL: URL(string: "https://www.youtube.com/@talkSPORT/live")!,
                               fallback: URL(string: "https://www.youtube.com/@talkSPORT")!)
        ),
    ]

    @ObservedObject private var customSources = WorldCupCustomSourcesStore.shared

    private var sourcesStrip: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Wraps via ScrollView when built-ins + custom chips outgrow the row.
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    Text("LIVE")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .tracking(1.4)
                        .foregroundStyle(MurmurColor.textMuted)
                    ForEach(Self.sources) { source in
                        SourceChip(
                            name: source.name,
                            systemImage: source.systemImage,
                            busy: resolvingSourceID == source.id,
                            help: source.help,
                            action: { listen(to: source) }
                        )
                        .contextMenu {
                            if case .tvriEmbedded = source.kind {
                                ForEach(TVRIWindow.Channel.allCases, id: \.self) { channel in
                                    Button("Open TVRI \(channel.label)") {
                                        TVRIWindow.shared.show(channel: channel)
                                    }
                                }
                            }
                        }
                    }
                    ForEach(customSources.items) { custom in
                        SourceChip(
                            name: custom.name,
                            systemImage: "dot.radiowaves.left.and.right",
                            busy: resolvingSourceID == custom.id.uuidString,
                            help: "Custom source — resolves \(custom.channelURL)/live and plays it in Murmur. Right-click to remove.",
                            action: { listenToCustom(custom) }
                        )
                        .contextMenu {
                            Button("Remove \"\(custom.name)\"") {
                                customSources.remove(id: custom.id)
                            }
                        }
                    }
                    Button { showAddSource.toggle() } label: {
                        Image(systemName: "plus.circle")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(MurmurColor.textMuted)
                    }
                    .buttonStyle(.plain)
                    .help("Add your own live source — any YouTube channel (e.g. a local commentary channel)")
                    .popover(isPresented: $showAddSource, arrowEdge: .bottom) { addSourcePopover }
                }
                .padding(.horizontal, 16)
            }
            if let sourceError {
                Text(sourceError)
                    .font(.system(size: 10))
                    .foregroundStyle(MurmurColor.textMuted)
                    .lineLimit(1)
                    .padding(.horizontal, 16)
            }
        }
        .padding(.vertical, 10)
    }

    private var addSourcePopover: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ADD LIVE SOURCE")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .tracking(1.4)
                .foregroundStyle(.secondary)
            TextField("Name (e.g. Local Commentary)", text: $newSourceName)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11))
            TextField("YouTube channel URL (youtube.com/@…)", text: $newSourceURL)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11))
            HStack {
                Text("The chip resolves the channel's /live stream at click time.")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Add") {
                    if customSources.add(name: newSourceName, channelURL: newSourceURL) {
                        newSourceName = ""
                        newSourceURL = ""
                        showAddSource = false
                    }
                }
                .disabled(newSourceName.trimmingCharacters(in: .whitespaces).isEmpty
                          || newSourceURL.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(12)
        .frame(width: 300)
    }

    private func listenToCustom(_ source: CustomLiveSource) {
        guard resolvingSourceID == nil, let liveURL = source.liveURL else { return }
        resolvingSourceID = source.id.uuidString
        sourceError = nil
        Task { @MainActor in
            do {
                let videoID = try await YouTubeLiveResolver.currentLiveVideoID(of: liveURL)
                _ = controller.load(input: videoID)
            } catch {
                sourceError = "\(source.name) isn't live right now — opened the channel in your browser."
                if let fallback = source.fallbackURL { NSWorkspace.shared.open(fallback) }
            }
            resolvingSourceID = nil
        }
    }

    /// YouTube sources: resolve the channel's current live stream and load it
    /// into the player (browser fallback when not live). TVRI: show the
    /// embedded floating window — full match video, no browser needed.
    private func listen(to source: LiveSource) {
        switch source.kind {
        case .tvriEmbedded:
            TVRIWindow.shared.show()
        case .youTubeLive(let liveURL, let fallback):
            guard resolvingSourceID == nil else { return }
            resolvingSourceID = source.id
            sourceError = nil
            Task { @MainActor in
                do {
                    let videoID = try await YouTubeLiveResolver.currentLiveVideoID(of: liveURL)
                    _ = controller.load(input: videoID)
                } catch {
                    sourceError = "\(source.name) isn't live right now — opened the channel in your browser."
                    NSWorkspace.shared.open(fallback)
                }
                resolvingSourceID = nil
            }
        }
    }

    // MARK: Schedule list

    private var visibleMatches: [WorldCupMatch] {
        store.matches.filter { match in
            if hideFinished && match.state == .finished { return false }
            switch scope {
            case .all: return true
            case .live: return match.state == .live
            case .followed: return follows.involvesFollowedTeam(match)
            }
        }
    }

    private var days: [(day: Date, matches: [WorldCupMatch])] {
        Dictionary(grouping: visibleMatches) { Calendar.current.startOfDay(for: $0.date) }
            .sorted { $0.key < $1.key }
            .map { (day: $0.key, matches: $0.value.sorted { $0.date < $1.date }) }
    }

    @ViewBuilder
    private var scheduleList: some View {
        if store.matches.isEmpty {
            if store.isLoading {
                VStack { Spacer(); ProgressView(); Spacer() }
            } else {
                EmptyStateView(
                    systemImage: "soccerball",
                    title: store.errorText ?? "No fixtures yet.",
                    helper: "The schedule appears once ESPN publishes it. Click ⟳ to retry."
                )
            }
        } else if visibleMatches.isEmpty {
            EmptyStateView(
                systemImage: scope == .followed ? "star" : "soccerball",
                title: scope == .live ? "No matches in play right now."
                     : (scope == .followed ? "No matches for followed teams." : "Nothing to show."),
                helper: scope == .followed
                    ? "Right-click any match (or use ☆ in Groups) to follow a team."
                    : "Adjust the filters above."
            )
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 6, pinnedViews: [.sectionHeaders]) {
                        ForEach(days, id: \.day) { group in
                            Section {
                                ForEach(group.matches) { match in
                                    matchCell(match)
                                        .id("match-\(match.id)")
                                }
                            } header: {
                                dayHeader(group.day)
                            }
                            .id(group.day)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 10)
                }
                .onChange(of: store.lastUpdated) { _ in
                    autoScrollToToday(proxy)
                    consumeNavTarget(proxy, target: WorldCupNavState.shared.targetMatchID)
                }
                // @Published emits on willSet — the singleton's property still
                // holds the OLD value inside this closure, so use the emitted
                // value, never re-read the store here.
                .onReceive(WorldCupNavState.shared.$targetMatchID) { emitted in
                    consumeNavTarget(proxy, target: emitted)
                }
                .onAppear {
                    autoScrollToToday(proxy)
                    consumeNavTarget(proxy, target: WorldCupNavState.shared.targetMatchID)
                }
            }
        }
    }

    /// Notification / deep-link landing: expand the targeted match and
    /// scroll it into view (clearing any filter that would hide it).
    private func consumeNavTarget(_ proxy: ScrollViewProxy, target: String?) {
        guard let target,
              store.matches.contains(where: { $0.id == target }) else { return }
        WorldCupNavState.shared.targetMatchID = nil
        selectedTab = .matches
        scope = .all
        hideFinished = false
        expandedMatchID = target
        didAutoScroll = true   // don't fight the today-autoscroll
        DispatchQueue.main.async {
            withAnimation(nil) { proxy.scrollTo("match-\(target)", anchor: .center) }
        }
    }

    /// A match row plus its expandable detail pane and follow context menu.
    private func matchCell(_ match: WorldCupMatch) -> some View {
        VStack(spacing: 0) {
            MatchRow(match: match,
                     isExpanded: expandedMatchID == match.id,
                     onFindStream: { findStream(for: match) })
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        expandedMatchID = (expandedMatchID == match.id) ? nil : match.id
                    }
                }
            if expandedMatchID == match.id {
                MatchDetailPane(match: match)
            }
        }
        .contextMenu {
            followToggleButton(match.home)
            followToggleButton(match.away)
            Divider()
            if match.state == .live {
                Button("Watch on TVRI (full match)") { TVRIWindow.shared.show() }
            }
            Button(match.state == .finished ? "Find highlights on YouTube"
                                            : "Find live stream") { findStream(for: match) }
            if match.state == .scheduled {
                Divider()
                Button("Add to Calendar…") { WorldCupCalendarExport.export([match]) }
            }
        }
    }

    @ViewBuilder
    private func followToggleButton(_ team: WorldCupTeam) -> some View {
        let isOn = follows.isFollowed(team.abbrev)
        Button {
            follows.toggle(team.abbrev)
        } label: {
            Label(isOn ? "Unfollow \(team.name)" : "Follow \(team.name)",
                  systemImage: isOn ? "star.fill" : "star")
        }
    }

    private func autoScrollToToday(_ proxy: ScrollViewProxy) {
        guard !didAutoScroll, !days.isEmpty else { return }
        let today = Calendar.current.startOfDay(for: Date())
        guard let target = days.first(where: { $0.day >= today })?.day else { return }
        didAutoScroll = true
        DispatchQueue.main.async {
            withAnimation(nil) { proxy.scrollTo(target, anchor: .top) }
        }
    }

    private func dayHeader(_ day: Date) -> some View {
        HStack(spacing: 6) {
            if Calendar.current.isDateInToday(day) {
                Text("TODAY")
                    .font(.system(size: 9, weight: .heavy, design: .monospaced))
                    .foregroundStyle(MurmurColor.accent)
            }
            Text(Self.dayFormatter.string(from: day).uppercased())
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .tracking(1.2)
                .foregroundStyle(MurmurColor.textMuted)
            Rectangle()
                .fill(MurmurColor.border.opacity(0.6))
                .frame(height: 1)
        }
        .padding(.top, 8)
        .padding(.bottom, 2)
        .background(Color.murmurHex("#121212"))
    }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE · MMM d"
        return f
    }()

    /// Match button = search, never auto-play. Resolving "the" stream for a
    /// match and loading it unprompted replaced whatever was playing with a
    /// best guess (often a watchalong, or pre-kickoff something merely
    /// related) — too aggressive for a single click. Auto-resolution only
    /// lives where it's explicit now: the LIVE chips and the opt-in
    /// auto-tune setting. Live/upcoming matches search for streams;
    /// finished ones search for highlights.
    private func findStream(for match: WorldCupMatch) {
        openSearch(query: match.searchQuery)
    }

    /// YouTube search fallback — in-app when a Data API key is configured,
    /// otherwise a browser search (the in-app sheet is useless without a key).
    private func openSearch(query: String) {
        if apiKeys.hasYouTubeKey {
            YouTubeSearchState.shared.mode = .videos
            YouTubeSearchState.shared.query = query
            NSApp.activate(ignoringOtherApps: true)
            openWindow(id: "search")
        } else {
            let escaped = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
            if let url = URL(string: "https://www.youtube.com/results?search_query=\(escaped)") {
                NSWorkspace.shared.open(url)
            }
        }
    }

    // MARK: Groups tab

    @ObservedObject private var standings = WorldCupStandingsStore.shared

    @ViewBuilder
    private var groupsTab: some View {
        if standings.groups.isEmpty {
            if standings.isLoading {
                VStack { Spacer(); ProgressView(); Spacer() }
                    .onAppear { standings.refresh() }
            } else {
                EmptyStateView(
                    systemImage: "tablecells",
                    title: standings.errorText ?? "No group tables yet.",
                    helper: "Tables appear once ESPN publishes the groups."
                )
                .onAppear { standings.refresh() }
            }
        } else {
            ScrollView {
                LazyVStack(spacing: 14) {
                    ForEach(standings.groups) { group in
                        GroupTable(group: group,
                                   thirdsQualified: thirdsQualified,
                                   allGroupsComplete: allGroupsComplete)
                    }
                    thirdPlaceRace
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
            .onAppear { standings.refresh() }
        }
    }

    /// 48-team format: the 8 best third-placed teams advance alongside each
    /// group's top two. This is the cross-group race no one can track by eye.
    private var thirdPlaceEntries: [WorldCupGroupEntry] {
        standings.groups
            .compactMap { $0.entries.first { $0.rank == 3 } }
            .sorted {
                ($0.points, $0.goalDiff, $0.goalsFor) > ($1.points, $1.goalDiff, $1.goalsFor)
            }
    }

    private var allGroupsComplete: Bool {
        !standings.groups.isEmpty
            && standings.groups.allSatisfy { $0.entries.allSatisfy { $0.played >= 3 } }
    }

    /// Decided only when every group has finished — before that, badges
    /// would be guesses.
    private var thirdsQualified: Set<String> {
        guard allGroupsComplete else { return [] }
        return Set(thirdPlaceEntries.prefix(8).map(\.abbrev))
    }

    @ViewBuilder
    private var thirdPlaceRace: some View {
        let thirds = thirdPlaceEntries
        if thirds.count == 12 {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text("BEST THIRD-PLACED — TOP 8 ADVANCE")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .tracking(1.2)
                        .foregroundStyle(MurmurColor.accent)
                    Rectangle()
                        .fill(MurmurColor.border.opacity(0.6))
                        .frame(height: 1)
                }
                VStack(spacing: 2) {
                    ForEach(Array(thirds.enumerated()), id: \.element.id) { idx, entry in
                        HStack(spacing: 6) {
                            Circle()
                                .fill(idx < 8 ? MurmurColor.accent.opacity(0.85) : Color.clear)
                                .frame(width: 4, height: 4)
                            Text("\(idx + 1)")
                                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                                .foregroundStyle(MurmurColor.textMuted)
                                .frame(width: 14, alignment: .trailing)
                            AsyncImage(url: entry.logoURL) { image in
                                image.resizable().scaledToFit()
                            } placeholder: {
                                Circle().fill(Color.white.opacity(0.08))
                            }
                            .frame(width: 14, height: 14)
                            Text(entry.name)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(idx < 8 ? MurmurColor.textSecondary
                                                         : MurmurColor.textMuted)
                                .lineLimit(1)
                            Spacer()
                            Text("\(entry.played)")
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(MurmurColor.textMuted)
                                .frame(width: 14, alignment: .trailing)
                            Text(entry.goalDiff > 0 ? "+\(entry.goalDiff)" : "\(entry.goalDiff)")
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(MurmurColor.textMuted)
                                .frame(width: 24, alignment: .trailing)
                            Text("\(entry.points)")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundStyle(MurmurColor.textPrimary)
                                .frame(width: 20, alignment: .trailing)
                        }
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(MurmurColor.accent.opacity(0.03))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(MurmurColor.accent.opacity(0.15), lineWidth: 1)
            )
        }
    }

    // MARK: Scorers tab

    @ObservedObject private var scorersStore = WorldCupScorersStore.shared

    @ViewBuilder
    private var scorersTab: some View {
        if scorersStore.scorers.isEmpty {
            EmptyStateView(
                systemImage: "shoe.2",
                title: "No goals scored yet.",
                helper: "The Golden Boot race builds up here as matches finish."
            )
        } else {
            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(Array(scorersStore.scorers.prefix(30).enumerated()),
                            id: \.element.id) { idx, scorer in
                        HStack(spacing: 8) {
                            Text("\(idx + 1)")
                                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                                .foregroundStyle(idx == 0 ? MurmurColor.accent : MurmurColor.textMuted)
                                .frame(width: 18, alignment: .trailing)
                            Text(scorer.name)
                                .font(.system(size: 11, weight: idx == 0 ? .bold : .medium))
                                .foregroundStyle(idx == 0 ? MurmurColor.textPrimary
                                                          : MurmurColor.textSecondary)
                                .lineLimit(1)
                            Text(scorer.teamAbbrev)
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundStyle(MurmurColor.textMuted)
                            Spacer()
                            Text("⚽ \(scorer.goals)")
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundStyle(idx == 0 ? MurmurColor.accent
                                                          : MurmurColor.textSecondary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(idx == 0 ? MurmurColor.accent.opacity(0.06)
                                               : Color.white.opacity(0.02))
                        )
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
        }
    }

    // MARK: News tab

    @ObservedObject private var news = WorldCupNewsStore.shared

    @ViewBuilder
    private var newsTab: some View {
        if news.articles.isEmpty {
            if news.isLoading {
                VStack { Spacer(); ProgressView(); Spacer() }
                    .onAppear { news.refresh() }
            } else {
                EmptyStateView(
                    systemImage: "newspaper",
                    title: news.errorText ?? "No headlines yet.",
                    helper: "ESPN's World Cup feed refreshes throughout the day."
                )
                .onAppear { news.refresh() }
            }
        } else {
            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(news.articles) { article in
                        NewsRow(article: article)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
            .onAppear { news.refresh() }
        }
    }

    // MARK: Bracket tab

    /// Knockout fixtures grouped by round, ordered by each round's first
    /// kickoff. Empty until the round-of-32 draw lands in the feed.
    private var knockoutRounds: [(stage: String, matches: [WorldCupMatch])] {
        let knockout = store.matches.filter { !$0.stage.isEmpty && $0.stage != "Group Stage" }
        return Dictionary(grouping: knockout) { $0.stage }
            .map { (stage: $0.key, matches: $0.value.sorted { $0.date < $1.date }) }
            .sorted { ($0.matches.first?.date ?? .distantFuture) < ($1.matches.first?.date ?? .distantFuture) }
    }

    @ViewBuilder
    private var bracketTab: some View {
        if knockoutRounds.isEmpty {
            EmptyStateView(
                systemImage: "trophy",
                title: "Knockout bracket isn't set yet.",
                helper: "The round of 32 appears here once the group stage wraps up (June 27)."
            )
        } else {
            ScrollView {
                LazyVStack(spacing: 6, pinnedViews: [.sectionHeaders]) {
                    ForEach(knockoutRounds, id: \.stage) { round in
                        Section {
                            ForEach(round.matches) { match in
                                matchCell(match)
                            }
                        } header: {
                            HStack(spacing: 6) {
                                Text(round.stage.uppercased())
                                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                                    .tracking(1.2)
                                    .foregroundStyle(MurmurColor.accent)
                                Rectangle()
                                    .fill(MurmurColor.border.opacity(0.6))
                                    .frame(height: 1)
                            }
                            .padding(.top, 8)
                            .padding(.bottom, 2)
                            .background(Color.murmurHex("#121212"))
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
        }
    }

    // MARK: Footer

    @ViewBuilder
    private var footer: some View {
        switch selectedTab {
        case .matches:
            ToggleFooter(
                systemImage: "flag.checkered",
                label: "Hide finished matches",
                isOn: $hideFinished,
                trailingLabel: footerStatus,
                help: "Collapse full-time results so today's and upcoming fixtures stay on top."
            )
        case .groups:
            thinFooter("Top 2 advance · best 8 third-placed teams join them")
        case .scorers:
            thinFooter("Golden Boot race · tallied from finished matches")
        case .news:
            thinFooter("Headlines from ESPN's World Cup feed")
        case .bracket:
            thinFooter("Round of 32 → Final · all times local")
        }
    }

    private func thinFooter(_ text: String) -> some View {
        HStack {
            Text(text)
                .font(.system(size: 9))
                .foregroundStyle(MurmurColor.textMuted)
            Spacer()
            Text(footerStatus)
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(MurmurColor.textMuted)
        }
        .padding(.horizontal, 16)
        .frame(height: 34)
    }

    private var footerStatus: String {
        guard let updated = store.lastUpdated else { return "" }
        return "updated \(Self.timeFormatter.string(from: updated))"
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.timeStyle = .short
        f.dateStyle = .none
        return f
    }()
}

// MARK: - Match row

private struct MatchRow: View {
    let match: WorldCupMatch
    let isExpanded: Bool
    let onFindStream: () -> Void
    @State private var hovering = false
    @ObservedObject private var follows = WorldCupFollowStore.shared

    var body: some View {
        HStack(spacing: 10) {
            statusColumn
                .frame(width: 52, alignment: .leading)

            teamLabel(match.home, logoLeading: false)
                .frame(maxWidth: .infinity, alignment: .trailing)
            scoreColumn
                .frame(width: 54)
            teamLabel(match.away, logoLeading: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Live matches: full match video via the embedded TVRI window.
            if match.state == .live {
                Button { TVRIWindow.shared.show() } label: {
                    Image(systemName: "tv")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(MurmurColor.accent.opacity(0.8))
                }
                .buttonStyle(.plain)
                .help("Watch on TVRI — full match video (official, free)")
            }

            Button(action: onFindStream) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(hovering ? MurmurColor.accent : MurmurColor.textMuted)
            }
            .buttonStyle(.plain)
            .help(match.state == .finished ? "Find highlights on YouTube"
                                           : "Find a live stream on YouTube")

            Image(systemName: "chevron.down")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(MurmurColor.textMuted.opacity(hovering || isExpanded ? 1 : 0.35))
                .rotationEffect(.degrees(isExpanded ? 180 : 0))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(match.state == .live ? Color.red.opacity(0.06)
                                           : Color.white.opacity(hovering ? 0.04 : 0.02))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(match.state == .live ? Color.red.opacity(0.25) : MurmurColor.borderSoft,
                        lineWidth: 1)
        )
        .onHover { hovering = $0 }
        .help("\(match.home.name) vs \(match.away.name)\n\(match.stage) · \(match.venue)\nClick to expand · right-click to follow")
    }

    @ViewBuilder
    private var statusColumn: some View {
        switch match.state {
        case .scheduled:
            Text(Self.kickoffFormatter.string(from: match.date))
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(MurmurColor.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        case .live:
            HStack(spacing: 3) {
                PulsingDot()
                Text(match.clock.isEmpty ? "LIVE" : match.clock)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.red.opacity(0.9))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        case .finished:
            Text("FT")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(MurmurColor.textMuted)
        }
    }

    private var scoreColumn: some View {
        Group {
            if match.state == .scheduled {
                Text("vs")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(MurmurColor.textMuted)
            } else {
                VStack(spacing: 0) {
                    Text("\(match.home.score ?? "0") – \(match.away.score ?? "0")")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundStyle(match.state == .live ? MurmurColor.textPrimary
                                                              : MurmurColor.textSecondary)
                    if let hp = match.home.shootoutScore, let ap = match.away.shootoutScore {
                        Text("(\(hp)–\(ap) p)")
                            .font(.system(size: 8, weight: .semibold, design: .monospaced))
                            .foregroundStyle(MurmurColor.textMuted)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func teamLabel(_ team: WorldCupTeam, logoLeading: Bool) -> some View {
        HStack(spacing: 5) {
            if logoLeading { teamLogo(team) }
            if follows.isFollowed(team.abbrev) {
                Image(systemName: "star.fill")
                    .font(.system(size: 6))
                    .foregroundStyle(MurmurColor.accent.opacity(0.9))
            }
            Text(team.abbrev)
                .font(.system(size: 11, weight: team.winner ? .bold : .semibold,
                              design: .rounded))
                .foregroundStyle(team.winner ? MurmurColor.textPrimary : MurmurColor.textSecondary)
            if !logoLeading { teamLogo(team) }
        }
        .help(team.name)
    }

    private func teamLogo(_ team: WorldCupTeam) -> some View {
        AsyncImage(url: team.logoURL) { image in
            image.resizable().scaledToFit()
        } placeholder: {
            Circle().fill(Color.white.opacity(0.08))
        }
        .frame(width: 16, height: 16)
    }

    private static let kickoffFormatter: DateFormatter = {
        let f = DateFormatter()
        f.timeStyle = .short
        f.dateStyle = .none
        return f
    }()
}

// MARK: - Match detail pane

/// Expanded content under a match row: events timeline, match stats, and
/// starting lineups. All sections are optional — ESPN fills them in as the
/// match approaches and plays out.
private struct MatchDetailPane: View {
    let match: WorldCupMatch
    @ObservedObject private var store = WorldCupMatchDetailStore.shared
    @State private var showLineups = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let detail = store.detail(for: match.id) {
                if detail.isEmpty {
                    Text(match.state == .scheduled
                         ? "Lineups and events appear closer to kick-off."
                         : "No detail available for this match.")
                        .font(.system(size: 10))
                        .foregroundStyle(MurmurColor.textMuted)
                } else {
                    if !detail.events.isEmpty {
                        eventsTimeline(detail.events)
                    }
                    if !detail.stats.isEmpty {
                        statsBlock(detail.stats)
                    }
                    if !detail.homeForm.isEmpty || !detail.awayForm.isEmpty {
                        formBlock(detail)
                    }
                    if !detail.headToHead.isEmpty {
                        h2hBlock(detail.headToHead)
                    }
                    if !detail.homeStarters.isEmpty || !detail.awayStarters.isEmpty {
                        lineupsBlock(detail)
                    }
                }
            } else if store.loading.contains(match.id) {
                HStack {
                    Spacer()
                    ProgressView().controlSize(.small).scaleEffect(0.7)
                    Spacer()
                }
                .padding(.vertical, 6)
            }
            HStack(spacing: 4) {
                Image(systemName: "mappin.and.ellipse")
                    .font(.system(size: 8))
                Text("\(match.stage) · \(match.venue)")
                    .font(.system(size: 9))
            }
            .foregroundStyle(MurmurColor.textMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.025))
        )
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2)
                .fill(MurmurColor.accent.opacity(0.5))
                .frame(width: 2)
                .padding(.vertical, 6)
                .padding(.leading, 1)
        }
        .padding(.top, 2)
        .onAppear { store.fetch(matchID: match.id) }
        .onChange(of: WorldCupStore.shared.lastUpdated) { _ in
            // Keep an expanded live match's events in step with the score poll.
            if match.state == .live { store.fetch(matchID: match.id) }
        }
    }

    private func eventsTimeline(_ events: [WorldCupMatchDetail.Event]) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(events) { event in
                HStack(spacing: 6) {
                    Text(event.minute)
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundStyle(MurmurColor.textMuted)
                        .frame(width: 34, alignment: .trailing)
                    Text(icon(for: event.kind))
                        .font(.system(size: 9))
                    Text(event.text)
                        .font(.system(size: 10, weight: event.kind == .goal ? .bold : .regular))
                        .foregroundStyle(event.kind == .goal ? MurmurColor.textPrimary
                                                             : MurmurColor.textSecondary)
                        .lineLimit(1)
                    Spacer()
                    if !event.teamAbbrev.isEmpty {
                        Text(event.teamAbbrev)
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .foregroundStyle(MurmurColor.textMuted)
                    }
                }
            }
        }
    }

    private func icon(for kind: WorldCupMatchDetail.Event.Kind) -> String {
        switch kind {
        case .goal: return "⚽"
        case .yellow: return "🟨"
        case .red: return "🟥"
        case .substitution: return "🔁"
        case .other: return "·"
        }
    }

    private func statsBlock(_ stats: [WorldCupMatchDetail.StatLine]) -> some View {
        VStack(spacing: 2) {
            ForEach(stats) { stat in
                HStack(spacing: 8) {
                    Text(stat.home)
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(MurmurColor.textSecondary)
                        .frame(width: 44, alignment: .trailing)
                    Text(stat.label)
                        .font(.system(size: 9))
                        .foregroundStyle(MurmurColor.textMuted)
                        .frame(maxWidth: .infinity)
                    Text(stat.away)
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(MurmurColor.textSecondary)
                        .frame(width: 44, alignment: .leading)
                }
            }
        }
        .padding(.vertical, 2)
    }

    /// "MEX  W W D L W" / "RSA  L D W W D" — last five, most recent first.
    private func formBlock(_ detail: WorldCupMatchDetail) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("FORM")
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .tracking(1)
                .foregroundStyle(MurmurColor.textMuted)
            formRow(abbrev: match.home.abbrev, games: detail.homeForm)
            formRow(abbrev: match.away.abbrev, games: detail.awayForm)
        }
    }

    private func formRow(abbrev: String, games: [WorldCupMatchDetail.FormGame]) -> some View {
        HStack(spacing: 4) {
            Text(abbrev)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(MurmurColor.textSecondary)
                .frame(width: 34, alignment: .leading)
            ForEach(games) { game in
                Text(game.result)
                    .font(.system(size: 8, weight: .heavy, design: .monospaced))
                    .foregroundStyle(formColor(game.result))
                    .frame(width: 14, height: 14)
                    .background(
                        RoundedRectangle(cornerRadius: 3)
                            .fill(formColor(game.result).opacity(0.15))
                    )
                    .help(game.summary)
            }
        }
    }

    private func formColor(_ result: String) -> Color {
        switch result {
        case "W": return Color.green.opacity(0.85)
        case "L": return Color.red.opacity(0.85)
        default:  return MurmurColor.textMuted
        }
    }

    private func h2hBlock(_ lines: [WorldCupMatchDetail.H2HLine]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("HEAD-TO-HEAD")
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .tracking(1)
                .foregroundStyle(MurmurColor.textMuted)
            ForEach(lines) { line in
                Text(line.text)
                    .font(.system(size: 9))
                    .foregroundStyle(MurmurColor.textSecondary)
                    .lineLimit(1)
            }
        }
    }

    private func lineupsBlock(_ detail: WorldCupMatchDetail) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) { showLineups.toggle() }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: showLineups ? "chevron.down" : "chevron.right")
                        .font(.system(size: 7, weight: .bold))
                    Text("Starting XI")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .tracking(1)
                }
                .foregroundStyle(MurmurColor.textMuted)
            }
            .buttonStyle(.plain)

            if showLineups {
                HStack(alignment: .top, spacing: 12) {
                    lineupColumn(title: match.home.abbrev, players: detail.homeStarters)
                    lineupColumn(title: match.away.abbrev, players: detail.awayStarters)
                }
            }
        }
    }

    private func lineupColumn(title: String, players: [WorldCupMatchDetail.Player]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundStyle(MurmurColor.accent.opacity(0.8))
            ForEach(players) { p in
                HStack(spacing: 4) {
                    Text(p.jersey)
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundStyle(MurmurColor.textMuted)
                        .frame(width: 16, alignment: .trailing)
                    Text(p.name)
                        .font(.system(size: 9))
                        .foregroundStyle(MurmurColor.textSecondary)
                        .lineLimit(1)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Group table

private struct GroupTable: View {
    let group: WorldCupGroup
    let thirdsQualified: Set<String>
    let allGroupsComplete: Bool
    @ObservedObject private var follows = WorldCupFollowStore.shared

    /// Badges only when they're facts, not forecasts: a group's top-2 "Q" /
    /// 4th-place "OUT" appear once that group has played out; the 3rd-place
    /// verdict additionally needs every group finished (best-8 rule).
    private var groupComplete: Bool {
        group.entries.allSatisfy { $0.played >= 3 }
    }

    @ViewBuilder
    private func badge(for entry: WorldCupGroupEntry) -> some View {
        if groupComplete {
            if entry.rank <= 2 {
                qBadge("Q", accent: true)
            } else if entry.rank == 4 {
                qBadge("OUT", accent: false)
            } else if allGroupsComplete {
                qBadge(thirdsQualified.contains(entry.abbrev) ? "Q" : "OUT",
                       accent: thirdsQualified.contains(entry.abbrev))
            }
        }
    }

    private func qBadge(_ text: String, accent: Bool) -> some View {
        Text(text)
            .font(.system(size: 7, weight: .heavy, design: .monospaced))
            .foregroundStyle(accent ? MurmurColor.accent : MurmurColor.textMuted)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(
                Capsule().fill(accent ? MurmurColor.accent.opacity(0.15)
                                      : Color.white.opacity(0.05))
            )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(group.name.uppercased())
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .tracking(1.2)
                    .foregroundStyle(MurmurColor.accent)
                Rectangle()
                    .fill(MurmurColor.border.opacity(0.6))
                    .frame(height: 1)
                Text("P   GD  PTS")
                    .font(.system(size: 8, weight: .semibold, design: .monospaced))
                    .foregroundStyle(MurmurColor.textMuted)
                    .padding(.trailing, 26)
            }
            VStack(spacing: 2) {
                ForEach(group.entries) { entry in
                    row(entry)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.02))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(MurmurColor.borderSoft, lineWidth: 1)
        )
    }

    private func row(_ entry: WorldCupGroupEntry) -> some View {
        HStack(spacing: 6) {
            // Qualification hint: top 2 go through (best thirds may too).
            Circle()
                .fill(entry.rank <= 2 ? MurmurColor.accent.opacity(0.85)
                      : (entry.rank == 3 ? MurmurColor.accent.opacity(0.3) : Color.clear))
                .frame(width: 4, height: 4)
            Text("\(entry.rank)")
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundStyle(MurmurColor.textMuted)
                .frame(width: 10, alignment: .trailing)
            AsyncImage(url: entry.logoURL) { image in
                image.resizable().scaledToFit()
            } placeholder: {
                Circle().fill(Color.white.opacity(0.08))
            }
            .frame(width: 14, height: 14)
            Text(entry.name)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(MurmurColor.textSecondary)
                .lineLimit(1)
            badge(for: entry)
            Spacer()
            Text("\(entry.played)")
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(MurmurColor.textMuted)
                .frame(width: 14, alignment: .trailing)
            Text(entry.goalDiff > 0 ? "+\(entry.goalDiff)" : "\(entry.goalDiff)")
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(MurmurColor.textMuted)
                .frame(width: 24, alignment: .trailing)
            Text("\(entry.points)")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(MurmurColor.textPrimary)
                .frame(width: 20, alignment: .trailing)
            Button { follows.toggle(entry.abbrev) } label: {
                Image(systemName: follows.isFollowed(entry.abbrev) ? "star.fill" : "star")
                    .font(.system(size: 9))
                    .foregroundStyle(follows.isFollowed(entry.abbrev)
                                     ? MurmurColor.accent : MurmurColor.textMuted.opacity(0.6))
            }
            .buttonStyle(.plain)
            .help(follows.isFollowed(entry.abbrev) ? "Unfollow \(entry.name)" : "Follow \(entry.name)")
        }
    }
}

// MARK: - News row

private struct NewsRow: View {
    let article: WorldCupArticle
    @State private var hovering = false

    var body: some View {
        Button {
            if let link = article.link { NSWorkspace.shared.open(link) }
        } label: {
            HStack(spacing: 10) {
                AsyncImage(url: article.imageURL) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Rectangle().fill(Color.white.opacity(0.06))
                        .overlay(Image(systemName: "newspaper")
                            .font(.system(size: 12))
                            .foregroundStyle(MurmurColor.textMuted))
                }
                .frame(width: 72, height: 42)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text(article.headline)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(hovering ? MurmurColor.textPrimary : MurmurColor.textSecondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    if let published = article.published {
                        Text(Self.relative.localizedString(for: published, relativeTo: Date()))
                            .font(.system(size: 9))
                            .foregroundStyle(MurmurColor.textMuted)
                    }
                }
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(MurmurColor.textMuted.opacity(hovering ? 1 : 0.4))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(hovering ? 0.04 : 0.02))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(MurmurColor.borderSoft, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("Open on espn.com")
    }

    private static let relative: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f
    }()
}

// MARK: - Bits

private struct SourceChip: View {
    let name: String
    let systemImage: String
    let busy: Bool
    let help: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if busy {
                    ProgressView().controlSize(.mini).scaleEffect(0.6)
                        .frame(width: 10, height: 10)
                } else {
                    Image(systemName: systemImage)
                        .font(.system(size: 9, weight: .medium))
                }
                Text(name)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(hovering ? MurmurColor.accentLight : MurmurColor.accent)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(
                Capsule().fill(MurmurColor.accent.opacity(hovering ? 0.16 : 0.10))
            )
            .overlay(
                Capsule().stroke(MurmurColor.accent.opacity(0.35), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
    }
}

private struct PulsingDot: View {
    @State private var dimmed = false

    var body: some View {
        Circle()
            .fill(Color.red)
            .frame(width: 6, height: 6)
            .opacity(dimmed ? 0.35 : 1)
            .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true),
                       value: dimmed)
            .onAppear { dimmed = true }
    }
}
