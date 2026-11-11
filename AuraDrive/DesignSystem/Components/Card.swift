import SwiftUI

/// Rounded container for grouping related content on a grouped background.
struct Card<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Spacing.m)
            .background(
                AppColor.surface,
                in: RoundedRectangle(cornerRadius: Layout.cornerRadius, style: .continuous)
            )
    }
}
