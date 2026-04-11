import SwiftUI

extension Animation {
    /// Fast feedback: button presses, toggles, pill selection (100-160ms)
    static let spokeFeedback = Animation.easeOut(duration: 0.12)

    /// Standard transition: toasts, state changes, sheet content (200-250ms)
    static let spokeTransition = Animation.spring(response: 0.25, dampingFraction: 0.82)

    /// Emphasis: onboarding reveals, first-time animations (400-500ms)
    static let spokeEmphasis = Animation.easeInOut(duration: 0.45)
}

/// Press-scale feedback for buttons. Scales down on press, springs back on release.
struct PressScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.spokeFeedback, value: configuration.isPressed)
    }
}
