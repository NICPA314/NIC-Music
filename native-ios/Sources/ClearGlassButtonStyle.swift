import SwiftUI

struct ClearGlassButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 22)
            .frame(minHeight: 50)
            .contentShape(Capsule())
            .glassEffect(.clear.interactive(), in: .capsule)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
    }
}
