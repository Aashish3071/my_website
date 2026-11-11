import SwiftUI

/// Home screen: the diffusers the user has added.
struct DiffuserListView: View {
    @Environment(DiffuserStore.self) private var store
    @State private var isAddingDiffuser = false
    @State private var isShowingSettings = false

    var body: some View {
        Group {
            if store.diffusers.isEmpty {
                emptyState
            } else {
                list
            }
        }
        .background(AppColor.groupedBackground)
        .navigationTitle("My Diffusers")
        .navigationDestination(for: UUID.self) { id in
            DiffuserControlView(diffuserID: id)
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Settings", systemImage: "gearshape") {
                    isShowingSettings = true
                }
                .accessibilityIdentifier(AccessibilityID.DiffuserList.settingsButton)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Add Diffuser", systemImage: "plus") {
                    isAddingDiffuser = true
                }
                .accessibilityIdentifier(AccessibilityID.DiffuserList.addButton)
            }
        }
        .sheet(isPresented: $isAddingDiffuser) {
            AddDiffuserView()
        }
        .sheet(isPresented: $isShowingSettings) {
            SettingsView()
        }
    }

    private var emptyState: some View {
        ScrollView {
            VStack(spacing: Spacing.l) {
                ContentUnavailableView {
                    Label("No diffusers yet", systemImage: "wind")
                } description: {
                    Text("Add your car fragrance diffuser to start controlling it.")
                        .foregroundStyle(AppColor.textSecondary)
                }

                Button("Add Diffuser") {
                    isAddingDiffuser = true
                }
                .buttonStyle(.primary)
                .accessibilityIdentifier(AccessibilityID.DiffuserList.emptyAddButton)
            }
            .padding(Spacing.m)
            .frame(maxWidth: Layout.readableContentWidth)
            .frame(maxWidth: .infinity)
        }
    }

    private var list: some View {
        List {
            ForEach(store.diffusers) { diffuser in
                NavigationLink(value: diffuser.id) {
                    DiffuserRow(diffuser: diffuser, connectionState: store.connectionState(for: diffuser.id))
                }
                .accessibilityIdentifier(AccessibilityID.DiffuserList.row)
            }
        }
    }
}

private struct DiffuserRow: View {
    let diffuser: Diffuser
    let connectionState: ConnectionState

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(diffuser.name)
                .font(AppFont.headline)
                .foregroundStyle(AppColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            StatusBadge(kind: connectionState.badgeKind, text: connectionState.title)

            Text("Fragrance \(diffuser.fragrancePercent)%")
                .font(AppFont.callout)
                .foregroundStyle(AppColor.textSecondary)

            if diffuser.isFragranceLow {
                StatusBadge(kind: .warning, text: "Fragrance low")
            }
        }
        .padding(.vertical, Spacing.xxs)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens the controls for this diffuser.")
    }
}

#Preview("With diffuser") {
    NavigationStack { DiffuserListView() }
        .environment(DiffuserStore.preview())
}

#Preview("Empty") {
    NavigationStack { DiffuserListView() }
        .environment(DiffuserStore.preview(withDemoDiffuser: false))
}
