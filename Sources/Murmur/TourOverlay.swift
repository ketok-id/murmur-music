import SwiftUI

/// Three-card first-launch tour shown once over the main panel (flag in
/// UserDefaults). No spotlight machinery — just the three things a new
/// user won't discover on their own, then out of the way forever.
struct TourOverlay: View {
    let onDone: () -> Void
    @State private var step = 0

    private struct Step {
        let icon: String
        let title: String
        let text: String
    }

    private static let steps: [Step] = [
        Step(
            icon: "magnifyingglass",
            title: "Search works out of the box",
            text: "Hit the search icon and type — videos, channels and playlists play with zero setup. No account, no API key."
        ),
        Step(
            icon: "dot.radiowaves.left.and.right",
            title: "Radio, TV & the World Cup",
            text: "The search window also has 58,000+ radio stations and live TV by country. The ⚽ button opens the World Cup hub — live scores, alerts and full-match video."
        ),
        Step(
            icon: "play.rectangle.on.rectangle",
            title: "Take it anywhere",
            text: "Toggle the floating video window with the TV button, pop the mini pill from the footer, and control everything with your keyboard's media keys."
        ),
    ]

    var body: some View {
        ZStack {
            Color.black.opacity(0.55)
                .onTapGesture {}   // swallow clicks behind the card

            VStack(spacing: 14) {
                Image(systemName: Self.steps[step].icon)
                    .font(.system(size: 26, weight: .medium))
                    .foregroundStyle(MurmurColor.accent)
                    .frame(height: 34)
                Text(Self.steps[step].title)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(MurmurColor.textPrimary)
                Text(Self.steps[step].text)
                    .font(.system(size: 11))
                    .foregroundStyle(MurmurColor.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 5) {
                    ForEach(0..<Self.steps.count, id: \.self) { i in
                        Circle()
                            .fill(i == step ? MurmurColor.accent : Color.white.opacity(0.15))
                            .frame(width: 5, height: 5)
                    }
                }
                .padding(.top, 2)

                HStack {
                    Button("Skip") { onDone() }
                        .buttonStyle(.plain)
                        .font(.system(size: 11))
                        .foregroundStyle(MurmurColor.textMuted)
                    Spacer()
                    Button(step == Self.steps.count - 1 ? "Start listening" : "Next") {
                        if step == Self.steps.count - 1 {
                            onDone()
                        } else {
                            withAnimation(.easeOut(duration: 0.18)) { step += 1 }
                        }
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(MurmurColor.accent)
                }
                .padding(.top, 4)
            }
            .padding(20)
            .frame(width: 300)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.murmurHex("#141417"))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(MurmurColor.accent.opacity(0.25), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.5), radius: 24, y: 8)
        }
    }
}
