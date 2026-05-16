import SwiftUI

/// Per-deck effects strip: ECHO section (on + wet + divider) and REVERB section (on + wet).
struct FXControlsView: View {
    @ObservedObject var state: DeckState
    var tint: Color

    var body: some View {
        HStack(spacing: 10) {
            echoSection
            Divider().frame(height: 36).background(Color.white.opacity(0.08))
            reverbSection
            Spacer()
        }
    }

    private var echoSection: some View {
        HStack(spacing: 6) {
            toggle(label: "ECHO", on: $state.echoEnabled)
            KnobView(value: $state.echoWet, range: 0...1, defaultValue: 0.3,
                     label: "WET", tint: tint, diameter: 28)
            dividerPicker
        }
    }

    private var reverbSection: some View {
        HStack(spacing: 6) {
            toggle(label: "REV", on: $state.reverbEnabled)
            KnobView(value: $state.reverbWet, range: 0...1, defaultValue: 0.3,
                     label: "WET", tint: tint, diameter: 28)
        }
    }

    private var dividerPicker: some View {
        VStack(spacing: 2) {
            HStack(spacing: 2) {
                divButton(4, "¼")
                divButton(8, "⅛")
                divButton(16, "16")
            }
            Text("BEAT")
                .font(.system(size: 7, weight: .medium, design: .monospaced))
                .tracking(0.5)
                .foregroundColor(.white.opacity(0.4))
        }
    }

    private func divButton(_ value: Int, _ label: String) -> some View {
        let isOn = state.echoDivider == value
        return Button(action: { state.echoDivider = value }) {
            Text(label)
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundColor(isOn ? tint : .white.opacity(0.4))
                .frame(width: 18, height: 16)
                .background(isOn ? tint.opacity(0.15) : Color.white.opacity(0.03))
                .cornerRadius(2)
        }
        .buttonStyle(.plain)
    }

    private func toggle(label: String, on: Binding<Bool>) -> some View {
        Button(action: { on.wrappedValue.toggle() }) {
            Text(label)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .tracking(0.5)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .foregroundColor(on.wrappedValue ? tint : .white.opacity(0.4))
                .background(on.wrappedValue ? tint.opacity(0.15) : Color.white.opacity(0.03))
                .overlay(RoundedRectangle(cornerRadius: 3).stroke(on.wrappedValue ? tint.opacity(0.5) : Color.white.opacity(0.08), lineWidth: 1))
                .cornerRadius(3)
        }
        .buttonStyle(.plain)
    }
}
