import SwiftUI

struct MasterControlsView: View {
    @ObservedObject var mixer: MixerEngine

    var body: some View {
        VStack(spacing: 10) {
            Text("MASTER")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .tracking(2)
                .foregroundColor(.white.opacity(0.6))

            KnobView(value: $mixer.masterVolume, range: 0...1.5, defaultValue: 1.0,
                     label: "VOL", tint: .cyan, diameter: 50)

            Button(action: { mixer.toggleRecording() }) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(mixer.isRecording ? Color.red : Color.red.opacity(0.4))
                        .frame(width: 8, height: 8)
                    Text(mixer.isRecording ? "REC ON" : "REC")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .tracking(1)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(mixer.isRecording ? Color.red.opacity(0.18) : Color.white.opacity(0.05))
                .foregroundColor(mixer.isRecording ? .red : .white.opacity(0.7))
                .cornerRadius(4)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(Color(white: 0.04))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.06), lineWidth: 1))
        .cornerRadius(8)
    }
}
