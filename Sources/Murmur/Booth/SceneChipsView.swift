import SwiftUI

/// Horizontal row of scene chips along the top of the booth.
struct SceneChipsView: View {
    @ObservedObject var store: SceneStore
    var onRecall: (Scene) -> Void
    var onCapture: (String) -> Void

    @State private var promptingName = false
    @State private var draftName: String = ""

    var body: some View {
        HStack(spacing: 6) {
            Text("SCENES")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .tracking(2)
                .foregroundColor(.white.opacity(0.45))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(store.scenes) { scene in
                        chip(scene: scene)
                    }
                    captureChip
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
    }

    private func chip(scene: Scene) -> some View {
        Button(action: { onRecall(scene) }) {
            Text(scene.name)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .foregroundColor(.white.opacity(0.85))
                .background(Color.white.opacity(0.06))
                .overlay(RoundedRectangle(cornerRadius: 999).stroke(Color.white.opacity(0.12), lineWidth: 1))
                .cornerRadius(999)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Delete scene", role: .destructive) {
                store.remove(id: scene.id)
            }
        }
    }

    private var captureChip: some View {
        Button(action: { promptingName = true; draftName = "" }) {
            Text("+ save scene")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .foregroundColor(.cyan.opacity(0.85))
                .background(Color.cyan.opacity(0.08))
                .overlay(RoundedRectangle(cornerRadius: 999).stroke(Color.cyan.opacity(0.4), lineWidth: 1))
                .cornerRadius(999)
        }
        .buttonStyle(.plain)
        .alert("Save scene", isPresented: $promptingName) {
            TextField("Scene name", text: $draftName)
            Button("Save") {
                let name = draftName.trimmingCharacters(in: .whitespaces)
                if !name.isEmpty { onCapture(name) }
            }
            Button("Cancel", role: .cancel) {}
        }
    }
}
