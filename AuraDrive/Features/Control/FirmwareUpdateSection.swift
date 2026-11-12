import SwiftUI

/// Check for, install and follow a firmware update. Shown on the Details screen.
struct FirmwareUpdateSection: View {
    let diffuserID: UUID

    @Environment(DiffuserStore.self) private var store

    private var state: FirmwareUpdateState { store.firmwareUpdateState(for: diffuserID) }
    private var isConnected: Bool { store.connectionState(for: diffuserID) == .connected }

    var body: some View {
        Section {
            content
        } header: {
            SectionHeader("Firmware update")
        } footer: {
            SectionFooter(footerText)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .idle:
            checkButton("Check for Update")
        case .checking:
            progressRow("Checking for updates…")
        case .upToDate:
            status(.success, "Firmware is up to date.")
            checkButton("Check Again")
        case .available(let version):
            Text("Version \(version) is available.")
                .font(AppFont.body)
                .foregroundStyle(AppColor.textPrimary)
                .accessibilityIdentifier(AccessibilityID.Details.firmwareStatus)
            Button("Install Update") {
                store.installFirmwareUpdate(diffuserID)
            }
            .buttonStyle(.primary)
            .disabled(!isConnected)
            .accessibilityIdentifier(AccessibilityID.Details.installUpdateButton)
        case .preparing:
            progressRow("Preparing the diffuser…")
        case .transferring(let progress):
            transferProgress(progress)
            Button("Cancel Update") {
                store.cancelFirmwareUpdate(diffuserID)
            }
            .foregroundStyle(AppColor.critical)
            .accessibilityIdentifier(AccessibilityID.Details.cancelUpdateButton)
        case .verifying:
            progressRow("Finishing the update…")
        case .completed(let version):
            status(.success, "Updated to version \(version).")
        case .failed(let error):
            status(.warning, LocalizedStringKey(error.message))
            checkButton("Try Again")
        }
    }

    private var footerText: LocalizedStringKey {
        if state.isInProgress {
            "Keep your iPhone near the diffuser and AuraDrive open until the update finishes. The diffuser can't be controlled meanwhile."
        } else if !isConnected {
            "Connect to the diffuser to install updates."
        } else {
            "Updates can add features and fix problems."
        }
    }

    private func checkButton(_ title: LocalizedStringKey) -> some View {
        Button(title) {
            Task { await store.checkForFirmwareUpdate(diffuserID) }
        }
        .accessibilityIdentifier(AccessibilityID.Details.checkForUpdateButton)
    }

    private func status(_ kind: StatusBadge.Kind, _ text: LocalizedStringKey) -> some View {
        StatusBadge(kind: kind, text: text)
            .accessibilityIdentifier(AccessibilityID.Details.firmwareStatus)
    }

    private func progressRow(_ text: LocalizedStringKey) -> some View {
        HStack(spacing: Spacing.s) {
            ProgressView()
            Text(text)
                .font(AppFont.body)
                .foregroundStyle(AppColor.textPrimary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(AccessibilityID.Details.firmwareStatus)
    }

    private func transferProgress(_ progress: Double) -> some View {
        let percent = Int((progress * 100).rounded())
        return VStack(alignment: .leading, spacing: Spacing.s) {
            HStack(alignment: .firstTextBaseline) {
                Text("Installing update")
                    .font(AppFont.body)
                    .foregroundStyle(AppColor.textPrimary)
                Spacer(minLength: Spacing.s)
                Text("\(percent)%")
                    .font(AppFont.headline)
                    .foregroundStyle(AppColor.textPrimary)
                    .monospacedDigit()
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Installing update")
            .accessibilityValue("\(percent) percent")
            .accessibilityIdentifier(AccessibilityID.Details.firmwareStatus)

            // The bar repeats the percentage above, so VoiceOver skips it.
            ProgressView(value: progress)
                .tint(AppColor.brandPrimary)
                .accessibilityHidden(true)
        }
        .padding(.vertical, Spacing.xxs)
    }
}

#Preview {
    NavigationStack {
        Form {
            FirmwareUpdateSection(diffuserID: SimulatedDiffuserService.demoDiffuser.id)
        }
    }
    .environment(DiffuserStore.preview())
}
