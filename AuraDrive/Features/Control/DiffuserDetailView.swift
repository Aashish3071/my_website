import SwiftUI

/// Rename a diffuser, see its details, or remove it from the app.
struct DiffuserDetailView: View {
    let diffuserID: UUID

    @Environment(DiffuserStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var isConfirmingForget = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                        .submitLabel(.done)
                        .onSubmit(saveName)
                        .accessibilityIdentifier(AccessibilityID.Details.nameField)
                } header: {
            SectionHeader("Name")
        }

                if let diffuser = store.diffuser(withID: diffuserID) {
                    Section {
                        LabeledContent("Firmware version", value: diffuser.firmwareVersion)
                        LabeledContent("Status") {
                            Text(store.connectionState(for: diffuserID).title)
                        }
                    } header: {
            SectionHeader("About")
        }
                }

                Section {
                    Button("Forget This Diffuser") {
                        isConfirmingForget = true
                    }
                    .foregroundStyle(AppColor.critical)
                    .accessibilityIdentifier(AccessibilityID.Details.forgetButton)
                    .confirmationDialog(
                        "Forget this diffuser?",
                        isPresented: $isConfirmingForget,
                        titleVisibility: .visible
                    ) {
                        Button("Forget Diffuser", role: .destructive) {
                            store.remove(diffuserID)
                            dismiss()
                        }
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text("It will be removed from this app. You can add it again later.")
                    }
                }
            }
            .navigationTitle("Diffuser Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        saveName()
                        dismiss()
                    }
                    .accessibilityIdentifier(AccessibilityID.Details.doneButton)
                }
            }
            .onAppear {
                name = store.diffuser(withID: diffuserID)?.name ?? ""
            }
        }
    }

    private func saveName() {
        store.rename(diffuserID, to: name)
    }
}

#Preview {
    DiffuserDetailView(diffuserID: SimulatedDiffuserService.demoDiffuser.id)
        .environment(DiffuserStore.preview())
}
