import SwiftUI

/// Thin strip showing two Ambient Layer channels with source picker + volume knob.
struct AmbientStripView: View {
    @ObservedObject var channel1: AmbientChannelState
    @ObservedObject var channel2: AmbientChannelState

    var body: some View {
        HStack(spacing: 12) {
            Text("AMBIENT")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .tracking(2)
                .foregroundColor(.cyan.opacity(0.7))
            channelControls(state: channel1, label: "1")
            channelControls(state: channel2, label: "2")
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.cyan.opacity(0.04))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.cyan.opacity(0.15), style: StrokeStyle(lineWidth: 1, dash: [3, 2])))
        .cornerRadius(6)
    }

    private func channelControls(state: AmbientChannelState, label: String) -> some View {
        HStack(spacing: 8) {
            Menu {
                Button("— Off —") { state.source = nil }
                Divider()
                ForEach(AmbientSource.catalog) { src in
                    Button("\(src.kindLabel) · \(src.name)") {
                        state.source = src
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Circle()
                        .fill(state.source != nil ? Color.cyan : Color.white.opacity(0.15))
                        .frame(width: 8, height: 8)
                    Text(state.source?.name ?? "Pick a bed…")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(state.source != nil ? .white : .white.opacity(0.4))
                        .lineLimit(1)
                }
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            Button(action: { state.muted.toggle() }) {
                Image(systemName: state.muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.system(size: 10))
                    .foregroundColor(state.muted ? .red.opacity(0.6) : .white.opacity(0.6))
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.plain)

            Slider(value: Binding(
                get: { Double(state.volume) },
                set: { state.volume = Float($0) }
            ), in: 0...1)
            .frame(width: 60)
        }
    }
}
