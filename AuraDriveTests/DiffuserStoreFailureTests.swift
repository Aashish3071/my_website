import Foundation
import Testing
@testable import AuraDrive

/// A diffuser link that can be made slow or made to fail, for testing what the
/// store does when things go wrong.
@MainActor
private final class FakeDiffuserService: DiffuserService {
    var availability: BluetoothAvailability = .poweredOn
    var onEvent: (@MainActor (DiffuserServiceEvent) -> Void)?
    var connectDelay: Duration = .zero
    var sendDelay: Duration = .zero
    var failingCommands: (DiffuserCommand) -> Bool = { _ in false }
    private(set) var disconnectCount = 0
    private(set) var sentCommands: [DiffuserCommand] = []
    var status = DiffuserStatus(isOn: false, intensity: 3, fragranceLevel: 0.5)

    func discover() async throws -> [DiscoveredDiffuser] { [] }

    func connect(to id: UUID) async throws -> DiffuserStatus {
        try await Task.sleep(for: connectDelay)
        return status
    }

    func disconnect(from id: UUID) {
        disconnectCount += 1
    }

    func send(_ command: DiffuserCommand, to id: UUID) async throws {
        try await Task.sleep(for: sendDelay)
        if failingCommands(command) {
            throw DiffuserServiceError.notConnected
        }
        sentCommands.append(command)
    }

    func readStatus(of id: UUID) async throws -> DiffuserStatus {
        status
    }

    func beginFirmwareUpdate(on id: UUID, image: FirmwareImage) async throws -> Int {
        throw DiffuserServiceError.notConnected
    }

    func sendFirmwareChunk(_ chunk: Data, offset: Int, to id: UUID) async throws {
        throw DiffuserServiceError.notConnected
    }

    func finishFirmwareUpdate(on id: UUID) async throws {
        throw DiffuserServiceError.notConnected
    }

    func abortFirmwareUpdate(on id: UUID) {}
}

@MainActor
private final class FakeFragranceAlerts: FragranceAlerting {
    private(set) var alertedLevels: [Int] = []

    func fragranceBecameLow(for diffuser: Diffuser) {
        alertedLevels.append(diffuser.fragrancePercent)
    }
}

@MainActor
struct DiffuserStoreFailureTests {
    private let demo = SimulatedDiffuserService.demoDiffuser

    private func makeDefaults() -> UserDefaults {
        UserDefaults(suiteName: "tests-\(UUID().uuidString)")!
    }

    private func makeStore(service: FakeDiffuserService) -> DiffuserStore {
        DiffuserStore(service: service, persistence: DiffuserPersistence(defaults: makeDefaults()))
    }

    @Test func lowFragranceAlertFiresOnceEachTimeTheLevelDropsLow() async {
        let service = FakeDiffuserService()
        let alerts = FakeFragranceAlerts()
        let store = DiffuserStore(
            service: service,
            persistence: DiffuserPersistence(defaults: makeDefaults()),
            alerts: alerts
        )
        store.add(demo)
        await store.connect(demo.id)
        #expect(alerts.alertedLevels.isEmpty)

        service.status.fragranceLevel = 0.15
        await store.refreshStatus(of: demo.id)
        #expect(alerts.alertedLevels == [15])

        // Still low: no second alert.
        service.status.fragranceLevel = 0.1
        await store.refreshStatus(of: demo.id)
        #expect(alerts.alertedLevels == [15])

        // New cartridge, then low again: alert again.
        service.status.fragranceLevel = 1
        await store.refreshStatus(of: demo.id)
        service.status.fragranceLevel = 0.12
        await store.refreshStatus(of: demo.id)
        #expect(alerts.alertedLevels == [15, 12])
    }

    @Test func failedCommandUndoesOnlyItsOwnChange() async throws {
        let service = FakeDiffuserService()
        let store = makeStore(service: service)
        store.add(demo)
        await store.connect(demo.id)

        service.sendDelay = .milliseconds(200)
        service.failingCommands = { _ in true }
        let command = Task { await store.setIntensity(5, for: demo.id) }

        // Rename while the command is still on its way.
        try await Task.sleep(for: .milliseconds(50))
        store.rename(demo.id, to: "Family Car")
        await command.value

        #expect(store.diffuser(withID: demo.id)?.intensity == 3)
        #expect(store.diffuser(withID: demo.id)?.name == "Family Car")
        #expect(store.errorMessage != nil)
    }

    @Test func sleepTimerSurvivesAFailedPowerOff() async {
        let service = FakeDiffuserService()
        let store = makeStore(service: service)
        store.add(demo)
        await store.connect(demo.id)
        await store.setPower(true, for: demo.id)
        store.setSleepTimer(minutes: 30, for: demo.id)

        service.failingCommands = { $0 == .setPower(false) }
        await store.setPower(false, for: demo.id)

        #expect(store.diffuser(withID: demo.id)?.isOn == true)
        #expect(store.diffuser(withID: demo.id)?.sleepTimerEnd != nil)
    }

    @Test func forgettingWhileConnectingLeavesNothingBehind() async throws {
        let service = FakeDiffuserService()
        service.connectDelay = .milliseconds(200)
        let store = makeStore(service: service)
        store.add(demo)

        let connecting = Task { await store.connect(demo.id) }
        try await Task.sleep(for: .milliseconds(50))
        store.remove(demo.id)
        await connecting.value

        #expect(store.diffusers.isEmpty)
        #expect(store.connectionState(for: demo.id) == .disconnected)
        #expect(store.connectionStates[demo.id] == nil)
        // Once when forgotten, once when the late connection is dropped.
        #expect(service.disconnectCount == 2)
    }

    @Test func sleepTimerThatRanOutWhileTheAppWasClosedTurnsTheDiffuserOff() async throws {
        let defaults = makeDefaults()
        let persistence = DiffuserPersistence(defaults: defaults)

        // First launch: the diffuser is switched on.
        let first = DiffuserStore(
            service: SimulatedDiffuserService(defaults: defaults, responseDelay: .zero),
            persistence: persistence
        )
        first.add(demo)
        await first.connect(demo.id)
        await first.setPower(true, for: demo.id)

        // The app is closed with a timer that has since run out.
        var saved = persistence.load()
        saved[0].sleepTimerEnd = Date().addingTimeInterval(-60)
        persistence.save(saved)

        // Next launch.
        let second = DiffuserStore(
            service: SimulatedDiffuserService(defaults: defaults, responseDelay: .zero),
            persistence: persistence
        )
        for _ in 0..<100 where second.diffuser(withID: demo.id)?.isOn != false {
            try await Task.sleep(for: .milliseconds(20))
        }

        #expect(second.diffuser(withID: demo.id)?.isOn == false)
        #expect(second.diffuser(withID: demo.id)?.sleepTimerEnd == nil)
    }
}
