import SwiftUI

struct APIKeySetupSheet: View {
    @ObservedObject private var store = APIKeyStore.shared
    @ObservedObject private var quota = QuotaTracker.shared
    @Environment(\.dismiss) private var dismiss

    @State private var draftKey: String = ""
    @State private var launchAtLogin = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Settings")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.white.opacity(0.4))
                }
                .buttonStyle(.plain)
            }

            // Launch-at-login only exists for the bundled .app — the
            // `swift run` dev binary has no bundle to register.
            if LaunchAtLogin.isAvailable {
                Toggle("Launch Murmur at login", isOn: $launchAtLogin)
                    .font(.system(size: 11))
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .onChange(of: launchAtLogin) { enabled in
                        guard enabled != LaunchAtLogin.isEnabled else { return }
                        if !LaunchAtLogin.set(enabled) {
                            // Registration denied/failed — resync the switch.
                            launchAtLogin = LaunchAtLogin.isEnabled
                        }
                    }

                Divider().background(Color.white.opacity(0.1))
            }

            sponsorBlockSection

            Divider().background(Color.white.opacity(0.1))

            Text("YouTube API Key")
                .font(.system(size: 12, weight: .semibold))

            Text("Optional — search, channels and playlists work without a key via Murmur's built-in scraper. A key adds YouTube's Trending charts, result pagination, and richer metadata. Free for ~100 searches/day on Google's free tier.")
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.6))
                .fixedSize(horizontal: false, vertical: true)

            Link(destination: URL(string: "https://console.cloud.google.com/apis/library/youtube.googleapis.com")!) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.up.right.square")
                    Text("Open Google Cloud Console")
                }
                .font(.system(size: 11))
                .foregroundColor(.cyan)
            }

            Divider().background(Color.white.opacity(0.1))

            VStack(alignment: .leading, spacing: 4) {
                Text("Paste your API key")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .tracking(0.5)
                    .foregroundColor(.white.opacity(0.5))
                SecureField("AIzaSy…", text: $draftKey)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, design: .monospaced))
                    .padding(8)
                    .background(Color.white.opacity(0.05))
                    .cornerRadius(4)
            }


            Divider().background(Color.white.opacity(0.1))
            quotaSection

            HStack(spacing: 8) {
                if store.hasYouTubeKey {
                    Button("Clear saved key") {
                        store.setYouTubeKey("")
                        draftKey = ""
                    }
                    .foregroundColor(.red.opacity(0.7))
                    .buttonStyle(.plain)
                }
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(.plain)
                Button("Save") {
                    store.setYouTubeKey(draftKey)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(draftKey.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(18)
        .frame(width: 380)
        .background(Color(white: 0.05))
        .onAppear {
            draftKey = store.youtubeKey
            launchAtLogin = LaunchAtLogin.isEnabled
        }
    }

    @ObservedObject private var sponsorBlock = SponsorBlockStore.shared

    private var sponsorBlockSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle("Auto-skip sponsored segments", isOn: $sponsorBlock.enabled)
                .font(.system(size: 11))
                .toggleStyle(.switch)
                .controlSize(.mini)

            if sponsorBlock.enabled {
                ForEach(SponsorBlockStore.allCategories, id: \.id) { category in
                    Toggle(category.label, isOn: Binding(
                        get: { sponsorBlock.categories.contains(category.id) },
                        set: { _ in sponsorBlock.toggleCategory(category.id) }
                    ))
                    .font(.system(size: 10))
                    .toggleStyle(.checkbox)
                    .padding(.leading, 8)
                }
            }

            Link(destination: URL(string: "https://sponsor.ajay.app")!) {
                Text("Crowd-sourced timestamps from SponsorBlock (CC BY-NC-SA 4.0)")
                    .font(.system(size: 9))
                    .foregroundColor(.white.opacity(0.4))
                    .underline()
            }
        }
    }

    private var quotaSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("QUOTA TODAY")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .tracking(1.5)
                    .foregroundColor(.white.opacity(0.4))
                Spacer()
                Text("\(quota.usedToday) / \(QuotaTracker.dailyLimit)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(quota.fractionUsed >= 0.9 ? .red.opacity(0.85) : .white.opacity(0.7))
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color.white.opacity(0.06))
                    Rectangle()
                        .fill(quota.fractionUsed >= 0.9 ? Color.red.opacity(0.8) :
                              quota.fractionUsed >= 0.7 ? Color.orange.opacity(0.8) :
                              Color.cyan.opacity(0.7))
                        .frame(width: geo.size.width * CGFloat(quota.fractionUsed))
                }
            }
            .frame(height: 4)
            .cornerRadius(2)

            Text("Resets at midnight Pacific. Murmur estimates client-side — actual quota may differ if you use the same key elsewhere.")
                .font(.system(size: 9))
                .foregroundColor(.white.opacity(0.4))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
