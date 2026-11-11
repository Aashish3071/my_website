import SwiftUI

/// Preview-only catalogue for checking components in light/dark mode and at large
/// text sizes. It isn't used in the app.
private struct DesignSystemCatalog: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.l) {
                Text("Typography").font(AppFont.title).accessibilityAddTraits(.isHeader)
                Text("Large title").font(AppFont.largeTitle)
                Text("Headline").font(AppFont.headline)
                Text("Body text that wraps across several lines when the text size is large.")
                    .font(AppFont.body)
                Text("Secondary text").font(AppFont.callout).foregroundStyle(AppColor.textSecondary)
                Text("72%").font(AppFont.readout).monospacedDigit()

                Text("Buttons").font(AppFont.title).accessibilityAddTraits(.isHeader)
                Button("Primary action") {}.buttonStyle(.primary)
                Button("Secondary action") {}.buttonStyle(.secondary)
                Button("Disabled") {}.buttonStyle(.primary).disabled(true)

                Text("Status").font(AppFont.title).accessibilityAddTraits(.isHeader)
                Card {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        StatusBadge(kind: .success, text: "Connected")
                        StatusBadge(kind: .warning, text: "Fragrance low")
                        StatusBadge(kind: .critical, text: "Disconnected")
                        StatusBadge(kind: .neutral, text: "Searching")
                    }
                }
            }
            .padding(Spacing.m)
        }
        .background(AppColor.groupedBackground)
    }
}

#Preview("Light") {
    DesignSystemCatalog()
}

#Preview("Dark") {
    DesignSystemCatalog().preferredColorScheme(.dark)
}

#Preview("Accessibility text size") {
    DesignSystemCatalog().dynamicTypeSize(.accessibility3)
}
