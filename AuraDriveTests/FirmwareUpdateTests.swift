import Foundation
import Testing
@testable import AuraDrive

/// Offers whatever firmware the test gives it.
@MainActor
private final class StubFirmwareSource: FirmwareSource {
    var image: FirmwareImage?

    init(_ image: FirmwareImage?) {
        self.image = image
    }

    func latestFirmware(for diffuser: Diffuser) async throws -> FirmwareImage? {
        image
    }
}

/// Firmware updates through the store, the Bluetooth service and the mock diffuser.
@MainActor
struct FirmwareUpdateTests {
    /// 2,500 bytes: 20 chunks of 128 bytes, the last one shorter.
    private let image = FirmwareImage(
        version: "2.0.0",
        data: Data((0..<2_500).map { UInt8(truncatingIfNeeded: $0 &* 7) })
    )

    private func makeStore(_ transport: MockBLETransport, offering image: FirmwareImage?) -> DiffuserStore {
        let defaults = UserDefaults(suiteName: "tests-\(UUID().uuidString)")!
        let service = BluetoothDiffuserService(
            transport: transport,
            scanDuration: .milliseconds(10),
            responseTimeout: .milliseconds(500),
            firmwareFinishTimeout: .seconds(1)
        )
        return DiffuserStore(
            service: service,
            persistence: DiffuserPersistence(defaults: defaults),
            reconnectDelays: [.milliseconds(20)],
            firmwareSource: StubFirmwareSource(image)
        )
    }

    private func connectedDiffuser(
        in transport: MockBLETransport,
        store: DiffuserStore,
        firmware: String = "1.2.0"
    ) async -> MockBLETransport.Peripheral {
        let diffuser = MockBLETransport.Peripheral()
        diffuser.firmwareVersion = firmware
        transport.add(diffuser)
        store.add(DiscoveredDiffuser(id: diffuser.id, name: diffuser.name, firmwareVersion: "Unknown"))
        await store.connect(diffuser.id)
        return diffuser
    }

    @Test func installsAnUpdateEndToEnd() async {
        let transport = MockBLETransport()
        let store = makeStore(transport, offering: image)
        let diffuser = await connectedDiffuser(in: transport, store: store)

        await store.checkForFirmwareUpdate(diffuser.id)
        #expect(store.firmwareUpdateState(for: diffuser.id) == .available(version: "2.0.0"))

        store.installFirmwareUpdate(diffuser.id)
        #expect(await waitUntil { store.firmwareUpdateState(for: diffuser.id) == .completed(version: "2.0.0") })

        // The mock only installs firmware whose size and CRC-32 match.
        #expect(diffuser.firmwareVersion == "2.0.0")
        #expect(store.diffuser(withID: diffuser.id)?.firmwareVersion == "2.0.0")
        let chunks = transport.writtenRequests.filter { if case .firmwareChunk = $0 { true } else { false } }
        #expect(chunks.count == 20)
    }

    @Test func noUpdateWhenTheDiffuserIsAlreadyCurrent() async {
        let transport = MockBLETransport()
        let store = makeStore(transport, offering: image)
        let diffuser = await connectedDiffuser(in: transport, store: store, firmware: "2.0.0")

        await store.checkForFirmwareUpdate(diffuser.id)
        #expect(store.firmwareUpdateState(for: diffuser.id) == .upToDate)
        store.installFirmwareUpdate(diffuser.id)
        #expect(store.firmwareUpdateState(for: diffuser.id) == .upToDate)
    }

    @Test func damagedFirmwareIsReportedAndNotInstalled() async {
        let transport = MockBLETransport()
        transport.failsFirmwareVerification = true
        let store = makeStore(transport, offering: image)
        let diffuser = await connectedDiffuser(in: transport, store: store)

        await store.checkForFirmwareUpdate(diffuser.id)
        store.installFirmwareUpdate(diffuser.id)
        #expect(await waitUntil { store.firmwareUpdateState(for: diffuser.id) == .failed(.verificationFailed) })
        #expect(diffuser.firmwareVersion == "1.2.0")
        #expect(store.diffuser(withID: diffuser.id)?.firmwareVersion == "1.2.0")
    }

    @Test func lostConnectionStopsTheUpdate() async {
        let transport = MockBLETransport()
        transport.dropConnectionAfterFirmwareChunks = 5
        let store = makeStore(transport, offering: image)
        let diffuser = await connectedDiffuser(in: transport, store: store)

        await store.checkForFirmwareUpdate(diffuser.id)
        store.installFirmwareUpdate(diffuser.id)
        #expect(await waitUntil { store.firmwareUpdateState(for: diffuser.id) == .failed(.connectionLost) })
        #expect(diffuser.firmwareVersion == "1.2.0")
    }

    @Test func cancellingAbandonsTheUpdateOnTheDiffuser() async throws {
        let transport = MockBLETransport()
        transport.responseDelay = .milliseconds(30)
        let store = makeStore(transport, offering: image)
        let diffuser = await connectedDiffuser(in: transport, store: store)

        await store.checkForFirmwareUpdate(diffuser.id)
        store.installFirmwareUpdate(diffuser.id)
        #expect(await waitUntil {
            if case .transferring(let progress) = store.firmwareUpdateState(for: diffuser.id) { progress > 0 } else { false }
        })
        store.cancelFirmwareUpdate(diffuser.id)

        #expect(await waitUntil { store.firmwareUpdateState(for: diffuser.id) == .failed(.cancelled) })
        #expect(await waitUntil { transport.writtenRequests.last == .firmwareUpdateAbort })
        #expect(await waitUntil { diffuser.firmwareUpdate == nil })
        #expect(diffuser.firmwareVersion == "1.2.0")
    }

    @Test func controlsAreBlockedWhileUpdating() async {
        let transport = MockBLETransport()
        transport.responseDelay = .milliseconds(30)
        let store = makeStore(transport, offering: image)
        let diffuser = await connectedDiffuser(in: transport, store: store)

        await store.checkForFirmwareUpdate(diffuser.id)
        store.installFirmwareUpdate(diffuser.id)
        #expect(await waitUntil { store.firmwareUpdateState(for: diffuser.id).isInProgress })

        await store.setPower(true, for: diffuser.id)
        #expect(store.diffuser(withID: diffuser.id)?.isOn == false)
        #expect(store.errorMessage != nil)
        store.cancelFirmwareUpdate(diffuser.id)
    }

    @Test func installingNeedsAConnection() async {
        let transport = MockBLETransport()
        let store = makeStore(transport, offering: image)
        let diffuser = await connectedDiffuser(in: transport, store: store)
        await store.checkForFirmwareUpdate(diffuser.id)

        transport.setAvailability(.poweredOff)
        store.installFirmwareUpdate(diffuser.id)
        #expect(store.firmwareUpdateState(for: diffuser.id) == .failed(.notConnected))
    }

    @Test func theDemoDiffuserCanBeUpdated() async {
        let defaults = UserDefaults(suiteName: "tests-\(UUID().uuidString)")!
        let store = DiffuserStore(
            service: SimulatedDiffuserService(defaults: defaults, responseDelay: .zero),
            persistence: DiffuserPersistence(defaults: defaults),
            firmwareSource: PlaceholderFirmwareSource(checkDelay: .zero)
        )
        let demo = SimulatedDiffuserService.demoDiffuser
        store.add(demo)
        await store.connect(demo.id)

        await store.checkForFirmwareUpdate(demo.id)
        #expect(store.firmwareUpdateState(for: demo.id) == .available(version: PlaceholderFirmwareSource.demoVersion))
        store.installFirmwareUpdate(demo.id)
        #expect(await waitUntil {
            store.firmwareUpdateState(for: demo.id) == .completed(version: PlaceholderFirmwareSource.demoVersion)
        })
        #expect(store.diffuser(withID: demo.id)?.firmwareVersion == PlaceholderFirmwareSource.demoVersion)

        await store.checkForFirmwareUpdate(demo.id)
        #expect(store.firmwareUpdateState(for: demo.id) == .upToDate)
    }
}
