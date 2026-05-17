import SwiftUI

struct APIKeySetupSheet: View {
    @ObservedObject var store: APIKeyStore
    @ObservedObject private var quota = QuotaTracker.shared
    @Environment(\.dismiss) private var dismiss

    @State private var draftKey: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("YouTube API Key")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.white.opacity(0.4))
                }
                .buttonStyle(.plain)
            }

            Text("Required for live YouTube search. Free for up to ~100 searches/day on Google's free tier. Setup takes ~5 minutes — see the link below.")
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
        .onAppear { draftKey = store.youtubeKey }
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
