import SwiftUI

/// Searches for nearby diffusers and lets the user add one.
struct AddDiffuserView: View {
    @Environment(DiffuserStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var results: [DiscoveredDiffuser]?

    var body: some View {
        NavigationStack {
            List {
                if let results {
                    if results.isEmpty {
                        noResults
                    } else {
                        found(results)
                    }
                } else {
                    searching
                }
            }
            .navigationTitle("Add Diffuser")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .accessibilityIdentifier(AccessibilityID.AddDiffuser.cancelButton)
                }
            }
            .task {
                await search()
            }
        }
    }

    private var searching: some View {
        Section {
            HStack(spacing: Spacing.s) {
                ProgressView()
                Text("Searching for diffusers…")
                    .font(AppFont.body)
                    .foregroundStyle(AppColor.textPrimary)
            }
            .accessibilityElement(children: .combine)
        } footer: {
            SectionFooter("Make sure your diffuser is switched on and close to your iPhone.")
        }
    }

    private func found(_ results: [DiscoveredDiffuser]) -> some View {
        Section {
            ForEach(results) { discovered in
                Button {
                    store.add(discovered)
                    dismiss()
                } label: {
                    HStack(spacing: Spacing.s) {
                        Image(systemName: "wind")
                            .foregroundStyle(AppColor.brandPrimary)
                            .accessibilityHidden(true)
                        Text(discovered.name)
                            .font(AppFont.body)
                            .foregroundStyle(AppColor.textPrimary)
                        Spacer()
                        Text("Add")
                            .font(AppFont.headline)
                            .foregroundStyle(AppColor.brandPrimary)
                    }
                    .frame(minHeight: Layout.minimumTapTarget)
                    .contentShape(Rectangle())
                }
                .accessibilityLabel("Add \(discovered.name)")
                .accessibilityIdentifier(AccessibilityID.AddDiffuser.result)
            }
        } header: {
            SectionHeader("Nearby diffusers")
        } footer: {
            SectionFooter("This version of the app works with a built-in demo diffuser.")
        }
    }

    private var noResults: some View {
        Section {
            VStack(alignment: .leading, spacing: Spacing.s) {
                Text("No new diffusers found")
                    .font(AppFont.headline)
                    .foregroundStyle(AppColor.textPrimary)
                Text("Diffusers you have already added are not shown here.")
                    .font(AppFont.callout)
                    .foregroundStyle(AppColor.textSecondary)
                Button("Search Again") {
                    Task { await search() }
                }
                .buttonStyle(.secondary)
            }
            .padding(.vertical, Spacing.xs)
        }
    }

    private func search() async {
        results = nil
        let found = await store.discover()
        guard !Task.isCancelled else { return }
        results = found
        if found.isEmpty {
            AccessibilityNotification.Announcement("No new diffusers found").post()
        }
    }
}

#Preview {
    AddDiffuserView()
        .environment(DiffuserStore.preview(withDemoDiffuser: false))
}
