import SwiftUI

/// The privacy policy, readable inside the app. Keep it in step with
/// `docs/PRIVACY_POLICY.md`, which is the version published on the web.
struct PrivacyPolicyView: View {
    private struct Topic: Identifiable {
        let title: String
        let text: String
        var id: String { title }
    }

    private let topics: [Topic] = [
        Topic(
            title: "What the app collects",
            text: "Nothing. AuraDrive has no accounts, no advertising and no analytics. It does not send any information about you or your diffuser to us or to anyone else."
        ),
        Topic(
            title: "What is stored on your iPhone",
            text: "The names and settings of the diffusers you add, and your choices in Settings. This stays on your iPhone and is removed when you delete the app."
        ),
        Topic(
            title: "Bluetooth",
            text: "Bluetooth is used only to find and control your diffuser. It is not used to work out your location."
        ),
        Topic(
            title: "Notifications",
            text: "If you turn on low fragrance alerts, the app shows a notification on this iPhone when a cartridge is running low. Notifications are created on your iPhone and are not sent through our servers."
        ),
        Topic(
            title: "Contact",
            text: "Questions about privacy can be sent to the support address in Settings."
        ),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.l) {
                ForEach(topics) { topic in
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text(topic.title)
                            .font(AppFont.headline)
                            .foregroundStyle(AppColor.textPrimary)
                            .accessibilityAddTraits(.isHeader)
                        Text(topic.text)
                            .font(AppFont.body)
                            .foregroundStyle(AppColor.textPrimary)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(Spacing.m)
            .frame(maxWidth: Layout.readableContentWidth, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(AppColor.groupedBackground)
        .navigationTitle("Privacy Policy")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack { PrivacyPolicyView() }
}
