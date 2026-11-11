import Foundation
import Testing
@testable import AuraDrive

@MainActor
struct DiffuserStoreTests {
    private let demo = SimulatedDiffuserService.demoDiffuser

    private func makeDefaults() -> UserDefaults {
        UserDefaults(suiteName: "tests-\(UUID().uuidString)")!
    }

    private func makeStore(defaults: UserDefaults? = nil) -> DiffuserStore {
        let defaults = defaults ?? makeDefaults()
        return DiffuserStore(
            service: SimulatedDiffuserService(defaults: defaults, responseDelay: .zero),
            persistence: DiffuserPersistence(defaults: defaults)
        )
    }

    @Test func discoverFindsTheDemoDiffuserUntilItIsAdded() async {
        let store = makeStore()
        #expect(await store.discover() == [demo])

        store.add(demo)
        #expect(store.diffusers.map(\.id) == [demo.id])
        #expect(await store.discover().isEmpty)
    }

    @Test func addingTheSameDiffuserTwiceKeepsOne() {
        let store = makeStore()
        store.add(demo)
        store.add(demo)
        #expect(store.diffusers.count == 1)
    }

    @Test func connectReadsStatusFromTheDiffuser() async {
        let store = makeStore()
        store.add(demo)
        #expect(store.connectionState(for: demo.id) == .disconnected)

        await store.connect(demo.id)
        #expect(store.connectionState(for: demo.id) == .connected)
        #expect(store.diffuser(withID: demo.id)?.fragrancePercent == 62)
        #expect(store.errorMessage == nil)
    }

    @Test func powerAndIntensityChangeWhenConnected() async {
        let store = makeStore()
        store.add(demo)
        await store.connect(demo.id)

        await store.setPower(true, for: demo.id)
        await store.setIntensity(5, for: demo.id)
        #expect(store.diffuser(withID: demo.id)?.isOn == true)
        #expect(store.diffuser(withID: demo.id)?.intensity == 5)

        await store.setIntensity(99, for: demo.id)
        #expect(store.diffuser(withID: demo.id)?.intensity == 5)
        await store.setIntensity(-4, for: demo.id)
        #expect(store.diffuser(withID: demo.id)?.intensity == 1)
    }

    @Test func failedCommandIsUndoneAndReported() async {
        let store = makeStore()
        store.add(demo)

        await store.setPower(true, for: demo.id)
        #expect(store.diffuser(withID: demo.id)?.isOn == false)
        #expect(store.errorMessage == DiffuserServiceError.notConnected.errorDescription)
    }

    @Test func intervalSettingsAreSaved() async {
        let store = makeStore()
        store.add(demo)
        await store.connect(demo.id)

        let interval = IntervalSettings(isEnabled: true, runSeconds: 20, pauseSeconds: 120)
        await store.setInterval(interval, for: demo.id)
        #expect(store.diffuser(withID: demo.id)?.interval == interval)
    }

    @Test func sleepTimerIsClearedWhenPowerTurnsOff() async {
        let store = makeStore()
        store.add(demo)
        await store.connect(demo.id)
        await store.setPower(true, for: demo.id)

        store.setSleepTimer(minutes: 30, for: demo.id)
        #expect(store.diffuser(withID: demo.id)?.sleepTimerEnd != nil)

        await store.setPower(false, for: demo.id)
        #expect(store.diffuser(withID: demo.id)?.sleepTimerEnd == nil)
    }

    @Test func cancellingTheSleepTimerClearsIt() async {
        let store = makeStore()
        store.add(demo)
        await store.connect(demo.id)
        await store.setPower(true, for: demo.id)

        store.setSleepTimer(minutes: 15, for: demo.id)
        store.setSleepTimer(minutes: nil, for: demo.id)
        #expect(store.diffuser(withID: demo.id)?.sleepTimerEnd == nil)
        #expect(store.diffuser(withID: demo.id)?.isOn == true)
    }

    @Test func renameTrimsSpacesAndIgnoresEmptyNames() {
        let store = makeStore()
        store.add(demo)

        store.rename(demo.id, to: "  Family Car  ")
        #expect(store.diffuser(withID: demo.id)?.name == "Family Car")

        store.rename(demo.id, to: "   ")
        #expect(store.diffuser(withID: demo.id)?.name == "Family Car")
    }

    @Test func removeForgetsTheDiffuser() async {
        let store = makeStore()
        store.add(demo)
        await store.connect(demo.id)

        store.remove(demo.id)
        #expect(store.diffusers.isEmpty)
        #expect(store.connectionState(for: demo.id) == .disconnected)
    }

    @Test func diffusersAreStillThereAfterRelaunch() async {
        let defaults = makeDefaults()
        let first = makeStore(defaults: defaults)
        first.add(demo)
        first.rename(demo.id, to: "Family Car")
        await first.connect(demo.id)
        await first.setIntensity(4, for: demo.id)

        let second = makeStore(defaults: defaults)
        #expect(second.diffusers.count == 1)
        #expect(second.diffuser(withID: demo.id)?.name == "Family Car")
        #expect(second.diffuser(withID: demo.id)?.intensity == 4)
    }

    @Test func replacingTheCartridgeResetsTheLevel() async {
        let store = makeStore()
        store.add(demo)
        await store.connect(demo.id)

        await store.resetFragranceLevel(for: demo.id)
        #expect(store.diffuser(withID: demo.id)?.fragrancePercent == 100)
    }
}

@MainActor
struct SimulatedDiffuserServiceTests {
    private let demo = SimulatedDiffuserService.demoDiffuser

    @Test func fragranceRunsDownOnlyWhileOn() async throws {
        var currentTime = Date(timeIntervalSince1970: 1_000_000)
        let defaults = UserDefaults(suiteName: "tests-\(UUID().uuidString)")!
        let service = SimulatedDiffuserService(defaults: defaults, responseDelay: .zero) { currentTime }

        let initial = try await service.connect(to: demo.id)

        currentTime += 6 * 60 * 60
        let whileOff = try await service.readStatus(of: demo.id)
        #expect(whileOff.fragranceLevel == initial.fragranceLevel)

        try await service.send(.setPower(true), to: demo.id)
        currentTime += 6 * 60 * 60
        let whileOn = try await service.readStatus(of: demo.id)
        // Six hours at intensity 3 uses a tenth of a 60-hour cartridge.
        #expect(abs(whileOn.fragranceLevel - (initial.fragranceLevel - 0.1)) < 0.0001)
    }

    @Test func commandsFailWhenNotConnected() async {
        let defaults = UserDefaults(suiteName: "tests-\(UUID().uuidString)")!
        let service = SimulatedDiffuserService(defaults: defaults, responseDelay: .zero)

        await #expect(throws: DiffuserServiceError.notConnected) {
            try await service.send(.setPower(true), to: demo.id)
        }
    }
}
