import SwiftUI

/// Loop controls strip: IN, OUT, ½, ×2, ON/OFF.
struct LoopControlsView: View {
    @ObservedObject var loop: LoopState
    var tint: Color
    var onSetIn: () -> Void
    var onSetOut: () -> Void
    var onHalve: () -> Void
    var onDouble: () -> Void
    var onToggle: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            button("IN", active: loop.inSeconds != nil, action: onSetIn)
            button("OUT", active: loop.outSeconds != nil, action: onSetOut)
            button("½", active: false, action: onHalve)
                .disabled(!loop.isArmed)
                .opacity(loop.isArmed ? 1 : 0.4)
            button("×2", active: false, action: onDouble)
                .disabled(!loop.isArmed)
                .opacity(loop.isArmed ? 1 : 0.4)
            button(loop.isActive ? "LOOP" : "LOOP", active: loop.isActive, action: onToggle)
                .disabled(!loop.isArmed)
                .opacity(loop.isArmed ? 1 : 0.4)
            Spacer()
        }
    }

    private func button(_ label: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .tracking(0.5)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .foregroundColor(active ? tint : .white.opacity(0.55))
                .background(active ? tint.opacity(0.15) : Color.white.opacity(0.03))
                .overlay(RoundedRectangle(cornerRadius: 3).stroke(active ? tint.opacity(0.5) : Color.white.opacity(0.08), lineWidth: 1))
                .cornerRadius(3)
        }
        .buttonStyle(.plain)
    }
}
