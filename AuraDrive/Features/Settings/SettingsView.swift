import SwiftUI

struct SettingsView: View {
    @AppStorage(StorageKey.hasCompletedOnboarding) private var hasCompletedOnboarding = true
    @AppStorage(LowFragranceNotifier.enabledKey) private var lowFragranceAlertsEnabled = false
    @Environment(\.dismiss) private var dismiss
    @State private var notificationsWereDenied = false

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "–"
    }

    var body: some View {
        NavigationStack {
            Form {
                alertsSection
                helpSection

                Section {
                    LabeledContent("Version", value: appVersion)
                } header: {
                    SectionHeader("About")
                }

                Section {
                    Text("This version of the app controls a built-in demo diffuser. Support for real diffusers over Bluetooth will be added in a later version.")
                        .font(AppFont.callout)
                        .foregroundStyle(AppColor.textPrimary)
                } header: {
                    SectionHeader("Demo mode")
                }

                Section {
                    Button("Show Welcome Screen Again") {
                        hasCompletedOnboarding = false
                        dismiss()
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier(AccessibilityID.Settings.doneButton)
                }
            }
        }
    }

    private var alertsSection: some View {
        Section {
            Toggle("Low fragrance alerts", isOn: alertsBinding)
                .accessibilityIdentifier(AccessibilityID.Settings.lowFragranceAlertsToggle)
            if notificationsWereDenied {
                StatusBadge(
                    kind: .warning,
                    text: "Notifications are turned off for AuraDrive. Turn them on in the iPhone Settings app."
                )
            }
        } header: {
            SectionHeader("Alerts")
        } footer: {
            SectionFooter("Get a notification when a cartridge has 15% or less left.")
        }
    }

    private var helpSection: some View {
        Section {
            if let supportURL = AppLinks.supportEmailURL {
                Link("Contact Support", destination: supportURL)
                    .accessibilityHint("Opens an email to \(AppLinks.supportEmail).")
            }
            NavigationLink("Privacy Policy") {
                PrivacyPolicyView()
            }
            .accessibilityIdentifier(AccessibilityID.Settings.privacyPolicyLink)
        } header: {
            SectionHeader("Help")
        }
    }

    /// Turning alerts on asks iOS for permission first, and stays off if refused.
    private var alertsBinding: Binding<Bool> {
        Binding(
            get: { lowFragranceAlertsEnabled },
            set: { isOn in
                guard isOn else {
                    lowFragranceAlertsEnabled = false
                    notificationsWereDenied = false
                    return
                }
                Task {
                    let granted = await LowFragranceNotifier.requestPermission()
                    lowFragranceAlertsEnabled = granted
                    notificationsWereDenied = !granted
                }
            }
        )
    }
}

#Preview {
    SettingsView()
}
