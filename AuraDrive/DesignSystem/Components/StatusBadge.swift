import SwiftUI

/// Small status pill. It always shows an icon and text together, so the status
/// never depends on colour alone (WCAG 1.4.1). VoiceOver reads it as one element.
struct StatusBadge: View {
    enum Kind {
        case success, warning, critical, neutral

        var color: Color {
            switch self {
            case .success: AppColor.success
            case .warning: AppColor.warning
            case .critical: AppColor.critical
            case .neutral: AppColor.textSecondary
            }
        }

        var symbolName: String {
            switch self {
            case .success: "checkmark.circle.fill"
            case .warning: "exclamationmark.triangle.fill"
            case .critical: "xmark.octagon.fill"
            case .neutral: "info.circle.fill"
            }
        }
    }

    let kind: Kind
    let text: LocalizedStringKey

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.xxs) {
            Image(systemName: kind.symbolName)
                .accessibilityHidden(true)
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(AppFont.caption.weight(.semibold))
        .foregroundStyle(kind.color)
        .padding(.horizontal, Spacing.xs)
        .padding(.vertical, Spacing.xxs)
        .background(kind.color.opacity(0.1), in: RoundedRectangle(cornerRadius: Spacing.s, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}
