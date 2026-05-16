import SwiftUI

struct CrossfaderView: View {
    @Binding var position: Float   // -1…+1

    var body: some View {
        VStack(spacing: 4) {
            HStack {
                Text("A").font(.system(size: 9, design: .monospaced)).foregroundColor(.white.opacity(0.5))
                Spacer()
                Text("B").font(.system(size: 9, design: .monospaced)).foregroundColor(.white.opacity(0.5))
            }
            Slider(value: Binding(
                get: { Double(position) },
                set: { position = Float($0) }
            ), in: -1...1)
            .onTapGesture(count: 2) { position = 0 }
        }
        .padding(.horizontal, 12)
    }
}
