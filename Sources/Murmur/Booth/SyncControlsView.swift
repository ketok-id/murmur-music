import SwiftUI

/// Three small controls under each deck: SYNC button, KEY-LOCK toggle,
/// MASTER toggle.
///
/// - SYNC engages: pulls this deck to match the master deck's effective BPM.
///   Disabled when no master is set, or when this deck IS master.
/// - KEY-LOCK toggles whether tempo changes preserve pitch.
/// - MASTER assigns/clears this deck as the sync master.
struct SyncControlsView: View {
    @ObservedObject var state: DeckState
    var tint: Color
    /// True if any deck currently has master designation.
    var hasMaster: Bool
    var onSync: () -> Void
    var onToggleMaster: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Button(action: onSync) {
                Text("SYNC")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .tracking(1)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .foregroundColor(syncEnabled ? tint : .white.opacity(0.25))
                    .background(syncEnabled ? tint.opacity(0.15) : Color.white.opacity(0.03))
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(syncEnabled ? tint.opacity(0.6) : Color.white.opacity(0.08), lineWidth: 1))
                    .cornerRadius(4)
            }
            .buttonStyle(.plain)
            .disabled(!syncEnabled)

            Button(action: { state.keyLock.toggle() }) {
                Text("KEY-LOCK")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .tracking(1)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .foregroundColor(state.keyLock ? Color.green : .white.opacity(0.4))
                    .background(state.keyLock ? Color.green.opacity(0.12) : Color.white.opacity(0.03))
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(state.keyLock ? Color.green.opacity(0.5) : Color.white.opacity(0.08), lineWidth: 1))
                    .cornerRadius(4)
            }
            .buttonStyle(.plain)

            Button(action: onToggleMaster) {
                Text("MASTER")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .tracking(1)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .foregroundColor(state.isMaster ? Color.yellow : .white.opacity(0.4))
                    .background(state.isMaster ? Color.yellow.opacity(0.12) : Color.white.opacity(0.03))
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(state.isMaster ? Color.yellow.opacity(0.6) : Color.white.opacity(0.08), lineWidth: 1))
                    .cornerRadius(4)
            }
            .buttonStyle(.plain)

            Spacer()
        }
    }

    private var syncEnabled: Bool {
        hasMaster && !state.isMaster && state.bpm > 0
    }
}
