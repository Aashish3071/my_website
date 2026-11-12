import SwiftUI

/// The main control screen for one diffuser.
struct DiffuserControlView: View {
    let diffuserID: UUID

    @Environment(DiffuserStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var isShowingDetails = false
    @State private var isConfirmingCartridgeReset = false
    @State private var isChoosingSleepTimer = false

    private static let sleepTimerOptions = [15, 30, 60, 120]

    private var diffuser: Diffuser? { store.diffuser(withID: diffuserID) }
    private var connectionState: ConnectionState { store.connectionState(for: diffuserID) }
    private var isConnected: Bool { connectionState == .connected }

    var body: some View {
        Group {
            if let diffuser {
                controls(for: diffuser)
            } else {
                ContentUnavailableView("Diffuser removed", systemImage: "wind")
            }
        }
        .task(id: diffuserID) {
            await store.connect(diffuserID)
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(15))
                await store.refreshStatus(of: diffuserID)
            }
        }
        .onChange(of: diffuser == nil) { _, isRemoved in
            if isRemoved { dismiss() }
        }
    }

    private func controls(for diffuser: Diffuser) -> some View {
        Form {
            connectionSection(diffuser)
            powerSection(diffuser)
            intensitySection(diffuser)
            intervalSection(diffuser)
            sleepTimerSection(diffuser)
            fragranceSection(diffuser)
        }
        .navigationTitle(diffuser.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Details", systemImage: "info.circle") {
                    isShowingDetails = true
                }
                .accessibilityIdentifier(AccessibilityID.Control.detailsButton)
            }
        }
        .sheet(isPresented: $isShowingDetails) {
            DiffuserDetailView(diffuserID: diffuserID)
        }
    }

    // MARK: Sections

    private func connectionSection(_ diffuser: Diffuser) -> some View {
        Section {
            VStack(alignment: .leading, spacing: Spacing.s) {
                StatusBadge(kind: connectionState.badgeKind, text: connectionState.title)
                if !diffuser.isDemo, BluetoothStatusNotice.isShown(for: store.bluetoothAvailability) {
                    BluetoothStatusNotice(availability: store.bluetoothAvailability)
                } else if connectionState == .disconnected {
                    Button("Reconnect") {
                        Task { await store.connect(diffuserID) }
                    }
                    .buttonStyle(.secondary)
                }
            }
            .padding(.vertical, Spacing.xxs)
        }
    }

    private func powerSection(_ diffuser: Diffuser) -> some View {
        Section {
            Toggle(isOn: powerBinding(diffuser)) {
                Label("Power", systemImage: "power")
                    .font(AppFont.headline)
            }
            .disabled(!isConnected)
            .accessibilityIdentifier(AccessibilityID.Control.powerToggle)
        }
    }

    private func intensitySection(_ diffuser: Diffuser) -> some View {
        let range = Diffuser.intensityRange
        return Section {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("Level \(diffuser.intensity) of \(range.upperBound)")
                    .font(AppFont.headline)
                    .foregroundStyle(AppColor.textPrimary)
                    .accessibilityHidden(true)

                Slider(
                    value: intensityBinding(diffuser),
                    in: Double(range.lowerBound)...Double(range.upperBound),
                    step: 1
                ) {
                    Text("Intensity")
                } minimumValueLabel: {
                    Image(systemName: "minus").accessibilityHidden(true)
                } maximumValueLabel: {
                    Image(systemName: "plus").accessibilityHidden(true)
                }
                .accessibilityValue("Level \(diffuser.intensity) of \(range.upperBound)")
                .accessibilityIdentifier(AccessibilityID.Control.intensitySlider)
            }
            .padding(.vertical, Spacing.xxs)
            .disabled(!isConnected)
        } header: {
            SectionHeader("Intensity")
        } footer: {
            SectionFooter("Higher levels release more fragrance and use the cartridge faster.")
        }
    }

    private func intervalSection(_ diffuser: Diffuser) -> some View {
        let range = IntervalSettings.secondsRange
        let step = IntervalSettings.secondsStep
        return Section {
            Toggle("Run in intervals", isOn: intervalBinding(diffuser, \.isEnabled))
            if diffuser.interval.isEnabled {
                Stepper(value: intervalBinding(diffuser, \.runSeconds), in: range, step: step) {
                    Text("Run for \(diffuser.interval.runSeconds) seconds")
                }
                Stepper(value: intervalBinding(diffuser, \.pauseSeconds), in: range, step: step) {
                    Text("Pause for \(diffuser.interval.pauseSeconds) seconds")
                }
            }
        } header: {
            SectionHeader("Interval mode")
        } footer: {
            SectionFooter("The diffuser runs, pauses, and repeats. This makes the fragrance last longer.")
        }
        .disabled(!isConnected)
    }

    private func sleepTimerSection(_ diffuser: Diffuser) -> some View {
        Section {
            if let end = diffuser.sleepTimerEnd {
                LabeledContent("Turns off in") {
                    // Counts down and stops at zero instead of counting back up.
                    Text(timerInterval: min(Date.now, end)...end, countsDown: true)
                        .monospacedDigit()
                        .foregroundStyle(AppColor.textPrimary)
                }
                Button("Cancel Timer") {
                    store.setSleepTimer(minutes: nil, for: diffuserID)
                }
            } else if !isConnected || !diffuser.isOn {
                Text("Turn the diffuser on to set a sleep timer.")
                    .font(AppFont.body)
                    .foregroundStyle(AppColor.textSecondary)
            } else {
                Button("Set Sleep Timer") {
                    isChoosingSleepTimer = true
                }
                .confirmationDialog(
                    "Turn the diffuser off after",
                    isPresented: $isChoosingSleepTimer,
                    titleVisibility: .visible
                ) {
                    ForEach(Self.sleepTimerOptions, id: \.self) { minutes in
                        Button(Self.title(forMinutes: minutes)) {
                            store.setSleepTimer(minutes: minutes, for: diffuserID)
                        }
                    }
                    Button("Cancel", role: .cancel) {}
                }
            }
        } header: {
            SectionHeader("Sleep timer")
        } footer: {
            SectionFooter("Turns the diffuser off after a set time. The timer runs while the app is open.")
        }
    }

    private func fragranceSection(_ diffuser: Diffuser) -> some View {
        Section {
            VStack(alignment: .leading, spacing: Spacing.s) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline) {
                        fragranceTitle
                        Spacer(minLength: Spacing.s)
                        fragranceValue(diffuser)
                    }
                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        fragranceTitle
                        fragranceValue(diffuser)
                    }
                }
                .accessibilityElement(children: .combine)

                // The bar repeats the percentage above, so VoiceOver skips it.
                ProgressView(value: diffuser.fragranceLevel)
                    .tint(diffuser.isFragranceLow ? AppColor.warning : AppColor.brandPrimary)
                    .accessibilityHidden(true)

                if diffuser.isFragranceLow {
                    StatusBadge(kind: .warning, text: "Fragrance low. Replace the cartridge soon.")
                }
            }
            .padding(.vertical, Spacing.xxs)

            Button("I Replaced the Cartridge") {
                isConfirmingCartridgeReset = true
            }
            .disabled(!isConnected)
            .accessibilityIdentifier(AccessibilityID.Control.replaceCartridgeButton)
            .confirmationDialog(
                "Reset the fragrance level to 100%?",
                isPresented: $isConfirmingCartridgeReset,
                titleVisibility: .visible
            ) {
                Button("Reset Level") {
                    Task { await store.resetFragranceLevel(for: diffuserID) }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Only do this after fitting a new cartridge.")
            }
        } header: {
            SectionHeader("Fragrance")
        }
    }

    private var fragranceTitle: some View {
        Text("Fragrance remaining")
            .font(AppFont.body)
            .foregroundStyle(AppColor.textPrimary)
    }

    private func fragranceValue(_ diffuser: Diffuser) -> some View {
        Text("\(diffuser.fragrancePercent)%")
            .font(AppFont.headline)
            .foregroundStyle(AppColor.textPrimary)
    }

    // MARK: Bindings

    private func powerBinding(_ diffuser: Diffuser) -> Binding<Bool> {
        Binding(
            get: { diffuser.isOn },
            set: { isOn in
                Task { await store.setPower(isOn, for: diffuserID) }
            }
        )
    }

    private func intensityBinding(_ diffuser: Diffuser) -> Binding<Double> {
        Binding(
            get: { Double(diffuser.intensity) },
            set: { level in
                Task { await store.setIntensity(Int(level.rounded()), for: diffuserID) }
            }
        )
    }

    private func intervalBinding<Value>(
        _ diffuser: Diffuser,
        _ keyPath: WritableKeyPath<IntervalSettings, Value>
    ) -> Binding<Value> {
        Binding(
            get: { diffuser.interval[keyPath: keyPath] },
            set: { newValue in
                var interval = diffuser.interval
                interval[keyPath: keyPath] = newValue
                Task { await store.setInterval(interval, for: diffuserID) }
            }
        )
    }

    private static func title(forMinutes minutes: Int) -> String {
        switch minutes {
        case 60: "1 hour"
        case 120: "2 hours"
        default: "\(minutes) minutes"
        }
    }
}

#Preview {
    NavigationStack {
        DiffuserControlView(diffuserID: SimulatedDiffuserService.demoDiffuser.id)
    }
    .environment(DiffuserStore.preview())
}
