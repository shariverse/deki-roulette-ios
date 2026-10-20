import SwiftUI

/// スピン・並べ替えの開始ボタン。`flare` はこの操作専用の色。
struct PrimaryActionButton: View {
    let title: String
    let busy: Bool
    let enabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(Theme.Typography.font(.title3, weight: .black))
                .tracking(0.5)
                .foregroundStyle(enabled ? Theme.onFlare : Theme.muted)
                .padding(.horizontal, 48)
                .padding(.vertical, 14)
                .background(enabled ? Theme.flare : Theme.ink700, in: .capsule)
                .shadow(color: enabled ? Theme.flareGlow : .clear, radius: 14, y: 8)
        }
        .buttonStyle(PressScaleStyle())
        .disabled(!enabled)
        .accessibilityAddTraits(busy ? .updatesFrequently : [])
    }
}

private struct PressScaleStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
