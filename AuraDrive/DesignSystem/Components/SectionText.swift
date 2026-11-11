import SwiftUI

/// Section heading for forms and lists. Replaces the system style, whose grey
/// falls short of 4.5:1 contrast and whose text does not scale fully.
struct SectionHeader: View {
    let title: LocalizedStringKey

    init(_ title: LocalizedStringKey) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(AppFont.caption.weight(.semibold))
            .foregroundStyle(AppColor.textSecondary)
            .textCase(nil)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
    }
}

/// Explanatory text under a form or list section.
struct SectionFooter: View {
    let text: LocalizedStringKey

    init(_ text: LocalizedStringKey) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(AppFont.caption)
            .foregroundStyle(AppColor.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
