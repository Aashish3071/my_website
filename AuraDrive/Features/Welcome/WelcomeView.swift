import SwiftUI

/// First screen, shown until the user taps Get Started.
struct WelcomeView: View {
    var onGetStarted: () -> Void

    @ScaledMetric(relativeTo: .largeTitle) private var heroIconSize: CGFloat = 72

    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.l) {
                Image(systemName: "wind")
                    .font(.system(size: heroIconSize))
                    .foregroundStyle(AppColor.brandPrimary)
                    .padding(.top, Spacing.xl)
                    .accessibilityHidden(true)

                VStack(spacing: Spacing.xs) {
                    Text("Welcome to AuraDrive")
                        .font(AppFont.largeTitle)
                        .foregroundStyle(AppColor.textPrimary)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier(AccessibilityID.Welcome.title)

                    Text("Control your car fragrance diffuser from your iPhone.")
                        .font(AppFont.body)
                        .foregroundStyle(AppColor.textSecondary)
                }
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

                Card {
                    VStack(alignment: .leading, spacing: Spacing.m) {
                        FeatureRow(
                            symbolName: "dial.medium",
                            title: "Adjust intensity",
                            detail: "Choose how strong the fragrance is."
                        )
                        FeatureRow(
                            symbolName: "clock",
                            title: "Set schedules",
                            detail: "Run the diffuser on a timer or in cycles."
                        )
                        FeatureRow(
                            symbolName: "drop",
                            title: "Track fragrance level",
                            detail: "See how much fragrance is left."
                        )
                    }
                }
            }
            .padding(.horizontal, Spacing.m)
            .padding(.bottom, Spacing.l)
            .frame(maxWidth: Layout.readableContentWidth)
            .frame(maxWidth: .infinity)
        }
        .background(AppColor.groupedBackground)
        .safeAreaInset(edge: .bottom) {
            Button("Get Started", action: onGetStarted)
            .buttonStyle(.primary)
            .accessibilityHint("Starts setting up your diffuser.")
            .accessibilityIdentifier(AccessibilityID.Welcome.getStartedButton)
            .padding(.horizontal, Spacing.m)
            .padding(.vertical, Spacing.s)
            .frame(maxWidth: Layout.readableContentWidth)
            .frame(maxWidth: .infinity)
            .background(.bar)
        }
        .toolbar(.hidden, for: .navigationBar)
    }
}

private struct FeatureRow: View {
    let symbolName: String
    let title: LocalizedStringKey
    let detail: LocalizedStringKey

    @ScaledMetric(relativeTo: .headline) private var iconWidth: CGFloat = 28

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.s) {
            Image(systemName: symbolName)
                .font(AppFont.headline)
                .foregroundStyle(AppColor.brandPrimary)
                .frame(width: iconWidth)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(title)
                    .font(AppFont.headline)
                    .foregroundStyle(AppColor.textPrimary)
                Text(detail)
                    .font(AppFont.callout)
                    .foregroundStyle(AppColor.textSecondary)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview("Light") {
    NavigationStack { WelcomeView {} }
}

#Preview("Dark, largest text") {
    NavigationStack { WelcomeView {} }
        .preferredColorScheme(.dark)
        .dynamicTypeSize(.accessibility5)
}
