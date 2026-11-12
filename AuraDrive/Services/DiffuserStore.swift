import Accessibility
import Foundation
import Observation
import SwiftUI

/// The app's single source of truth: the user's diffusers, their connection
/// state, and every action a screen can take on them.
@MainActor
@Observable
final class DiffuserStore {
    private(set) var diffusers: [Diffuser] = []
    private(set) var connectionStates: [UUID: ConnectionState] = [:]
    private(set) var bluetoothAvailability: BluetoothAvailability
    private(set) var firmwareUpdates: [UUID: FirmwareUpdateMachine] = [:]
    /// Set when something fails. The root view shows it in an alert.
    var errorMessage: String?

    @ObservationIgnored private let service: any DiffuserService
    @ObservationIgnored private let persistence: DiffuserPersistence
    @ObservationIgnored private let alerts: (any FragranceAlerting)?
    @ObservationIgnored private var sleepTimerTasks: [UUID: Task<Void, Never>] = [:]
    /// Waits between reconnection attempts. The app gives up after the last one.
    @ObservationIgnored private let reconnectDelays: [Duration]
    @ObservationIgnored private var reconnectTasks: [UUID: Task<Void, Never>] = [:]
    /// Diffusers that have been connected, and so are reconnected automatically.
    @ObservationIgnored private var autoReconnectIDs: Set<UUID> = []
    @ObservationIgnored private let firmwareSource: any FirmwareSource
    @ObservationIgnored private var availableFirmware: [UUID: FirmwareImage] = [:]
    @ObservationIgnored private var firmwareTasks: [UUID: Task<Void, Never>] = [:]

    init(
        service: any DiffuserService,
        persistence: DiffuserPersistence,
        alerts: (any FragranceAlerting)? = nil,
        reconnectDelays: [Duration] = [.seconds(1), .seconds(2), .seconds(4), .seconds(8), .seconds(16)],
        firmwareSource: any FirmwareSource = PlaceholderFirmwareSource()
    ) {
        self.service = service
        self.firmwareSource = firmwareSource
        self.persistence = persistence
        self.alerts = alerts
        self.reconnectDelays = reconnectDelays
        bluetoothAvailability = service.availability
        diffusers = persistence.load()
        restoreSleepTimers()
        service.onEvent = { [weak self] event in
            self?.handle(event)
        }
    }

    // MARK: Reading

    func diffuser(withID id: UUID) -> Diffuser? {
        diffusers.first { $0.id == id }
    }

    func connectionState(for id: UUID) -> ConnectionState {
        connectionStates[id] ?? .disconnected
    }

    // MARK: Adding and removing

    /// Looks for nearby diffusers that have not been added yet.
    func discover() async -> [DiscoveredDiffuser] {
        do {
            let found = try await service.discover()
            return found.filter { diffuser(withID: $0.id) == nil }
        } catch is CancellationError {
            return []
        } catch {
            report(error)
            return []
        }
    }

    func add(_ discovered: DiscoveredDiffuser) {
        guard diffuser(withID: discovered.id) == nil else { return }
        diffusers.append(
            Diffuser(id: discovered.id, name: discovered.name, firmwareVersion: discovered.firmwareVersion)
        )
        save()
        announce("\(discovered.name) added")
    }

    func remove(_ id: UUID) {
        firmwareTasks[id]?.cancel()
        firmwareTasks[id] = nil
        firmwareUpdates[id] = nil
        availableFirmware[id] = nil
        cancelSleepTimerTask(for: id)
        stopReconnecting(id)
        autoReconnectIDs.remove(id)
        service.disconnect(from: id)
        connectionStates[id] = nil
        diffusers.removeAll { $0.id == id }
        save()
    }

    func rename(_ id: UUID, to newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let index = index(of: id) else { return }
        diffusers[index].name = trimmed
        save()
    }

    // MARK: Connection

    func connect(_ id: UUID) async {
        guard connectionState(for: id) == .disconnected, let name = diffuser(withID: id)?.name else { return }
        connectionStates[id] = .connecting
        do {
            let status = try await service.connect(to: id)
            guard diffuser(withID: id) != nil else {
                // Forgotten while the connection was being made.
                service.disconnect(from: id)
                connectionStates[id] = nil
                return
            }
            apply(status, to: id)
            connectionStates[id] = .connected
            autoReconnectIDs.insert(id)
            announce("\(name) connected")
        } catch {
            connectionStates[id] = diffuser(withID: id) == nil ? nil : .disconnected
            if !(error is CancellationError) {
                report(error)
            }
        }
    }

    /// Reads the latest values from the diffuser, such as the fragrance level.
    func refreshStatus(of id: UUID) async {
        guard connectionState(for: id) == .connected else { return }
        if let status = try? await service.readStatus(of: id) {
            apply(status, to: id)
        }
    }

    // MARK: Controls

    func setPower(_ isOn: Bool, for id: UUID) async {
        guard let current = diffuser(withID: id), current.isOn != isOn else { return }
        let succeeded = await send(.setPower(isOn), to: id) { diffuser in
            diffuser.isOn = isOn
            if !isOn { diffuser.sleepTimerEnd = nil }
        } revert: { diffuser in
            diffuser.isOn = current.isOn
            diffuser.sleepTimerEnd = current.sleepTimerEnd
        }
        guard succeeded else { return }
        if !isOn { cancelSleepTimerTask(for: id) }
        announce(isOn ? "\(current.name) turned on" : "\(current.name) turned off")
    }

    func setIntensity(_ intensity: Int, for id: UUID) async {
        let clamped = min(max(intensity, Diffuser.intensityRange.lowerBound), Diffuser.intensityRange.upperBound)
        guard let current = diffuser(withID: id), current.intensity != clamped else { return }
        await send(.setIntensity(clamped), to: id) {
            $0.intensity = clamped
        } revert: {
            $0.intensity = current.intensity
        }
    }

    func setInterval(_ interval: IntervalSettings, for id: UUID) async {
        guard let current = diffuser(withID: id), current.interval != interval else { return }
        await send(.setInterval(interval), to: id) {
            $0.interval = interval
        } revert: {
            $0.interval = current.interval
        }
    }

    func resetFragranceLevel(for id: UUID) async {
        guard let current = diffuser(withID: id) else { return }
        await send(.resetFragranceLevel, to: id) {
            $0.fragranceLevel = 1
        } revert: {
            $0.fragranceLevel = current.fragranceLevel
        }
    }

    /// Starts a timer that turns the diffuser off after `minutes`. Pass `nil` to cancel.
    ///
    /// The timer is kept by the app, so it fires only while the app is running.
    func setSleepTimer(minutes: Int?, for id: UUID) {
        cancelSleepTimerTask(for: id)
        guard let index = index(of: id) else { return }
        guard let minutes else {
            diffusers[index].sleepTimerEnd = nil
            save()
            return
        }
        let end = Date().addingTimeInterval(Double(minutes) * 60)
        diffusers[index].sleepTimerEnd = end
        save()
        scheduleSleepTimer(for: id, end: end)
    }

    // MARK: Private

    private func index(of id: UUID) -> Int? {
        diffusers.firstIndex { $0.id == id }
    }

    /// Applies `change` straight away so the screen responds instantly, then
    /// sends the command. If the command fails, `revert` undoes that change
    /// only, so anything else that changed in the meantime is kept.
    @discardableResult
    private func send(
        _ command: DiffuserCommand,
        to id: UUID,
        applying change: (inout Diffuser) -> Void,
        revert: (inout Diffuser) -> Void
    ) async -> Bool {
        guard let index = index(of: id) else { return false }
        guard !firmwareUpdateState(for: id).isInProgress else {
            report(FirmwareUpdateInProgressError())
            return false
        }
        change(&diffusers[index])
        do {
            try await service.send(command, to: id)
            save()
            return true
        } catch {
            if let index = self.index(of: id) {
                revert(&diffusers[index])
            }
            if !(error is CancellationError) {
                report(error)
            }
            return false
        }
    }

    private func apply(_ status: DiffuserStatus, to id: UUID) {
        guard let index = index(of: id) else { return }
        let wasLow = diffusers[index].isFragranceLow
        diffusers[index].isOn = status.isOn
        diffusers[index].intensity = status.intensity
        diffusers[index].fragranceLevel = status.fragranceLevel
        if let version = status.firmwareVersion {
            diffusers[index].firmwareVersion = version
        }
        if !wasLow, diffusers[index].isFragranceLow {
            alerts?.fragranceBecameLow(for: diffusers[index])
        }
        if !status.isOn {
            diffusers[index].sleepTimerEnd = nil
        }
        save()
    }

    private func save() {
        persistence.save(diffusers)
    }

    private func report(_ error: Error) {
        let message = error.localizedDescription
        errorMessage = message
        announce(message)
    }

    private func announce(_ message: String) {
        AccessibilityNotification.Announcement(message).post()
    }

    // MARK: Firmware updates

    func firmwareUpdateState(for id: UUID) -> FirmwareUpdateState {
        firmwareUpdates[id]?.state ?? .idle
    }

    /// Looks for newer firmware for the diffuser.
    func checkForFirmwareUpdate(_ id: UUID) async {
        guard let diffuser = diffuser(withID: id), transition(id, .check) else { return }
        do {
            if let image = try await firmwareSource.latestFirmware(for: diffuser),
               FirmwareVersion.isNewer(image.version, than: diffuser.firmwareVersion) {
                availableFirmware[id] = image
                transition(id, .foundUpdate(version: image.version))
            } else {
                availableFirmware[id] = nil
                transition(id, .foundNothing)
            }
        } catch {
            transition(id, .fail(.failed))
        }
    }

    /// Installs the update found by `checkForFirmwareUpdate`. Runs until it
    /// finishes, fails or is cancelled, even if the screen is closed.
    func installFirmwareUpdate(_ id: UUID) {
        guard let image = availableFirmware[id], transition(id, .start) else { return }
        guard connectionState(for: id) == .connected else {
            transition(id, .fail(.notConnected))
            return
        }
        firmwareTasks[id] = Task { [weak self] in
            await self?.runFirmwareUpdate(image, on: id)
        }
    }

    func cancelFirmwareUpdate(_ id: UUID) {
        firmwareTasks[id]?.cancel()
    }

    private func runFirmwareUpdate(_ image: FirmwareImage, on id: UUID) async {
        defer { firmwareTasks[id] = nil }
        let bytes = [UInt8](image.data)
        do {
            let requestedChunkSize = try await service.beginFirmwareUpdate(on: id, image: image)
            let chunkSize = max(1, requestedChunkSize)
            try Task.checkCancellation()
            transition(id, .prepared)

            var offset = 0
            while offset < bytes.count {
                try Task.checkCancellation()
                let end = min(offset + chunkSize, bytes.count)
                try await service.sendFirmwareChunk(Data(bytes[offset..<end]), offset: offset, to: id)
                offset = end
                transition(id, .progress(Double(offset) / Double(bytes.count)))
            }

            try Task.checkCancellation()
            transition(id, .transferFinished)
            do {
                try await service.finishFirmwareUpdate(on: id)
            } catch DiffuserServiceError.commandRejected {
                throw FirmwareUpdateError.verificationFailed
            }

            availableFirmware[id] = nil
            if let index = index(of: id) {
                diffusers[index].firmwareVersion = image.version
                save()
            }
            transition(id, .verified(version: image.version))
            announce("Firmware updated to version \(image.version)")
        } catch {
            service.abortFirmwareUpdate(on: id)
            if error is CancellationError || Task.isCancelled {
                transition(id, .cancel)
            } else {
                transition(id, .fail(Self.firmwareError(from: error)))
            }
            if case .failed(let reason) = firmwareUpdateState(for: id) {
                announce(reason.message)
            }
        }
    }

    @discardableResult
    private func transition(_ id: UUID, _ event: FirmwareUpdateMachine.Event) -> Bool {
        var machine = firmwareUpdates[id] ?? FirmwareUpdateMachine()
        guard machine.handle(event) else { return false }
        firmwareUpdates[id] = machine
        return true
    }

    private static func firmwareError(from error: any Error) -> FirmwareUpdateError {
        if let error = error as? FirmwareUpdateError { return error }
        switch error as? DiffuserServiceError {
        case .connectionLost, .notConnected: return .connectionLost
        case .timedOut: return .timedOut
        case .commandRejected: return .rejected
        default: return .failed
        }
    }

    // MARK: Events and reconnecting

    private func handle(_ event: DiffuserServiceEvent) {
        switch event {
        case .availabilityChanged(let availability):
            bluetoothAvailability = availability
            guard availability == .poweredOn else { return }
            for id in autoReconnectIDs where connectionState(for: id) == .disconnected {
                startReconnecting(id)
            }

        case .connectionLost(let id):
            guard let diffuser = diffuser(withID: id) else { return }
            connectionStates[id] = .disconnected
            announce("\(diffuser.name) disconnected")
            // With Bluetooth off, reconnecting starts when it comes back on.
            if autoReconnectIDs.contains(id), bluetoothAvailability == .poweredOn {
                startReconnecting(id)
            }

        case .statusChanged(let id, let status):
            guard connectionState(for: id) == .connected else { return }
            apply(status, to: id)
        }
    }

    private func startReconnecting(_ id: UUID) {
        stopReconnecting(id)
        guard diffuser(withID: id) != nil else { return }
        connectionStates[id] = .reconnecting
        reconnectTasks[id] = Task { [weak self, reconnectDelays] in
            for delay in reconnectDelays {
                try? await Task.sleep(for: delay)
                guard !Task.isCancelled, let self else { return }
                guard self.bluetoothAvailability == .poweredOn else {
                    // Tried again when Bluetooth comes back on.
                    self.endReconnecting(id, state: .disconnected)
                    return
                }
                if await self.attemptReconnect(id) { return }
            }
            guard !Task.isCancelled, let self else { return }
            self.endReconnecting(id, state: .disconnected)
            if let name = self.diffuser(withID: id)?.name {
                self.announce("Couldn't reconnect to \(name)")
            }
        }
    }

    /// Returns true when reconnecting should stop: it worked, or the diffuser was forgotten.
    private func attemptReconnect(_ id: UUID) async -> Bool {
        guard let name = diffuser(withID: id)?.name else { return true }
        do {
            let status = try await service.connect(to: id)
            guard !Task.isCancelled, diffuser(withID: id) != nil else {
                service.disconnect(from: id)
                return true
            }
            apply(status, to: id)
            endReconnecting(id, state: .connected)
            announce("\(name) reconnected")
            return true
        } catch {
            return Task.isCancelled
        }
    }

    private func endReconnecting(_ id: UUID, state: ConnectionState) {
        reconnectTasks[id] = nil
        if diffuser(withID: id) != nil {
            connectionStates[id] = state
        }
    }

    private func stopReconnecting(_ id: UUID) {
        reconnectTasks[id]?.cancel()
        reconnectTasks[id] = nil
    }

    // MARK: Sleep timer

    private func restoreSleepTimers() {
        for index in diffusers.indices {
            guard let end = diffusers[index].sleepTimerEnd else { continue }
            // A timer that ran out while the app was closed fires straight away.
            scheduleSleepTimer(for: diffusers[index].id, end: end)
        }
    }

    private func scheduleSleepTimer(for id: UUID, end: Date) {
        sleepTimerTasks[id] = Task { [weak self] in
            let remaining = end.timeIntervalSinceNow
            if remaining > 0 {
                try? await Task.sleep(for: .seconds(remaining))
            }
            guard !Task.isCancelled else { return }
            await self?.sleepTimerFired(for: id)
        }
    }

    private func sleepTimerFired(for id: UUID) async {
        // Forget the task first so turning the power off does not cancel it mid-way.
        sleepTimerTasks[id] = nil
        if connectionState(for: id) == .disconnected {
            await connect(id)
        }
        await setPower(false, for: id)
        if let index = index(of: id) {
            diffusers[index].sleepTimerEnd = nil
            save()
        }
    }

    private func cancelSleepTimerTask(for id: UUID) {
        sleepTimerTasks[id]?.cancel()
        sleepTimerTasks[id] = nil
    }
}

extension DiffuserStore {
    /// A store with its own empty storage, for Xcode previews.
    static func preview(withDemoDiffuser: Bool = true) -> DiffuserStore {
        let defaults = UserDefaults(suiteName: "preview-\(UUID().uuidString)") ?? .standard
        let store = DiffuserStore(
            service: SimulatedDiffuserService(defaults: defaults, responseDelay: .zero),
            persistence: DiffuserPersistence(defaults: defaults)
        )
        if withDemoDiffuser {
            store.add(SimulatedDiffuserService.demoDiffuser)
        }
        return store
    }
}

private struct FirmwareUpdateInProgressError: LocalizedError {
    var errorDescription: String? { "Wait for the firmware update to finish." }
}
