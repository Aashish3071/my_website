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
    /// Set when something fails. The root view shows it in an alert.
    var errorMessage: String?

    @ObservationIgnored private let service: any DiffuserService
    @ObservationIgnored private let persistence: DiffuserPersistence
    @ObservationIgnored private var sleepTimerTasks: [UUID: Task<Void, Never>] = [:]

    init(service: any DiffuserService, persistence: DiffuserPersistence) {
        self.service = service
        self.persistence = persistence
        diffusers = persistence.load()
        restoreSleepTimers()
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
        cancelSleepTimerTask(for: id)
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
            apply(status, to: id)
            connectionStates[id] = .connected
            announce("\(name) connected")
        } catch is CancellationError {
            connectionStates[id] = .disconnected
        } catch {
            connectionStates[id] = .disconnected
            report(error)
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
        if !isOn { cancelSleepTimerTask(for: id) }
        let succeeded = await send(.setPower(isOn), to: id) { diffuser in
            diffuser.isOn = isOn
            if !isOn { diffuser.sleepTimerEnd = nil }
        }
        if succeeded {
            announce(isOn ? "\(current.name) turned on" : "\(current.name) turned off")
        }
    }

    func setIntensity(_ intensity: Int, for id: UUID) async {
        let clamped = min(max(intensity, Diffuser.intensityRange.lowerBound), Diffuser.intensityRange.upperBound)
        guard let current = diffuser(withID: id), current.intensity != clamped else { return }
        await send(.setIntensity(clamped), to: id) { $0.intensity = clamped }
    }

    func setInterval(_ interval: IntervalSettings, for id: UUID) async {
        guard let current = diffuser(withID: id), current.interval != interval else { return }
        await send(.setInterval(interval), to: id) { $0.interval = interval }
    }

    func resetFragranceLevel(for id: UUID) async {
        await send(.resetFragranceLevel, to: id) { $0.fragranceLevel = 1 }
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
    /// sends the command. If the command fails, the change is undone.
    @discardableResult
    private func send(
        _ command: DiffuserCommand,
        to id: UUID,
        applying change: (inout Diffuser) -> Void
    ) async -> Bool {
        guard let index = index(of: id) else { return false }
        let previous = diffusers[index]
        change(&diffusers[index])
        do {
            try await service.send(command, to: id)
            save()
            return true
        } catch {
            if let index = self.index(of: id) {
                diffusers[index] = previous
            }
            if !(error is CancellationError) {
                report(error)
            }
            return false
        }
    }

    private func apply(_ status: DiffuserStatus, to id: UUID) {
        guard let index = index(of: id) else { return }
        diffusers[index].isOn = status.isOn
        diffusers[index].intensity = status.intensity
        diffusers[index].fragranceLevel = status.fragranceLevel
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

    // MARK: Sleep timer

    private func restoreSleepTimers() {
        for index in diffusers.indices {
            guard let end = diffusers[index].sleepTimerEnd else { continue }
            if end > Date() {
                scheduleSleepTimer(for: diffusers[index].id, end: end)
            } else {
                diffusers[index].sleepTimerEnd = nil
            }
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
