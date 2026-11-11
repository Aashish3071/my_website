import SwiftUI

struct SettingsView: View {
    @AppStorage(StorageKey.hasCompletedOnboarding) private var hasCompletedOnboarding = true
    @Environment(\.dismiss) private var dismiss

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "–"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Version", value: appVersion)
                } header: {
                    Text("About")
                }

                Section {
                    Text("This version of the app controls a built-in demo diffuser. Support for real diffusers over Bluetooth will be added in a later version.")
                        .font(AppFont.callout)
                        .foregroundStyle(AppColor.textPrimary)
                } header: {
                    Text("Demo mode")
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
}

#Preview {
    SettingsView()
}
