import SwiftUI

/// 8 hot-cue pads in a 4x2 grid. Click sets-or-jumps; right-click deletes.
///
/// A pad shows colored when its cue is set, dim outline when empty.
struct HotCuePadsView: View {
    let hotCues: [HotCue]
    var onSetOrJump: (Int) -> Void
    var onDelete: (Int) -> Void

    var body: some View {
        let columns = [GridItem(.flexible(), spacing: 4),
                       GridItem(.flexible(), spacing: 4),
                       GridItem(.flexible(), spacing: 4),
                       GridItem(.flexible(), spacing: 4)]
        LazyVGrid(columns: columns, spacing: 4) {
            ForEach(0..<8, id: \.self) { id in
                pad(id: id)
            }
        }
    }

    private func pad(id: Int) -> some View {
        let cue = hotCues.first(where: { $0.id == id })
        let color = cue.flatMap { Color(hex: $0.colorHex) } ?? Color.white.opacity(0.06)
        return Button(action: { onSetOrJump(id) }) {
            Text("\(id + 1)")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(cue == nil ? .white.opacity(0.5) : .black)
                .frame(maxWidth: .infinity)
                .frame(height: 22)
                .background(color)
                .overlay(RoundedRectangle(cornerRadius: 3).stroke(Color.white.opacity(0.1), lineWidth: 1))
                .cornerRadius(3)
        }
        .buttonStyle(.plain)
        .contextMenu {
            if cue != nil {
                Button("Delete cue \(id + 1)", role: .destructive) { onDelete(id) }
            }
        }
    }
}

extension Color {
    /// Construct a `Color` from a 6-character hex string (no #). Returns nil on bad input.
    init?(hex: String) {
        var s = hex
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        let r = Double((v >> 16) & 0xff) / 255
        let g = Double((v >> 8) & 0xff) / 255
        let b = Double(v & 0xff) / 255
        self = Color(red: r, green: g, blue: b)
    }
}
