import SwiftUI

/// Filled, full-width button for the main action on a screen.
struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: Layout.cornerRadius, style: .continuous)
        configuration.label
            .font(AppFont.headline)
            .multilineTextAlignment(.center)
            .foregroundStyle(AppColor.onBrandPrimary)
            .padding(.horizontal, Spacing.m)
            .padding(.vertical, Spacing.s)
            .frame(maxWidth: .infinity, minHeight: Layout.minimumTapTarget)
            .background(AppColor.brandPrimary, in: shape)
            .contentShape(shape)
            .opacity(isEnabled ? (configuration.isPressed ? 0.85 : 1) : 0.45)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .motionSafeAnimation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

/// Outlined, full-width button for secondary actions.
struct SecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: Layout.cornerRadius, style: .continuous)
        configuration.label
            .font(AppFont.headline)
            .multilineTextAlignment(.center)
            .foregroundStyle(AppColor.brandPrimary)
            .padding(.horizontal, Spacing.m)
            .padding(.vertical, Spacing.s)
            .frame(maxWidth: .infinity, minHeight: Layout.minimumTapTarget)
            .background(AppColor.surface, in: shape)
            .overlay(shape.strokeBorder(AppColor.brandPrimary, lineWidth: 1.5))
            .contentShape(shape)
            .opacity(isEnabled ? (configuration.isPressed ? 0.7 : 1) : 0.45)
            .motionSafeAnimation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    static var primary: PrimaryButtonStyle { PrimaryButtonStyle() }
}

extension ButtonStyle where Self == SecondaryButtonStyle {
    static var secondary: SecondaryButtonStyle { SecondaryButtonStyle() }
}
