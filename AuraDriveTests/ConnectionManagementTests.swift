import Foundation
import Testing
@testable import AuraDrive

/// The store, the Bluetooth service and the mock link working together.
@MainActor
struct ConnectionManagementTests {
    private func makeStore(_ transport: MockBLETransport) -> DiffuserStore {
        let defaults = UserDefaults(suiteName: "tests-\(UUID().uuidString)")!
        let service = BluetoothDiffuserService(
            transport: transport,
            scanDuration: .milliseconds(10),
            // Generous: the tests share the main thread, so replies can be slow under load.
            responseTimeout: .seconds(2)
        )
        return DiffuserStore(
            service: service,
            persistence: DiffuserPersistence(defaults: defaults),
            reconnectDelays: [.milliseconds(20), .milliseconds(20), .milliseconds(20)]
        )
    }

    private func addAndConnect(_ diffuser: MockBLETransport.Peripheral, to store: DiffuserStore) async {
        store.add(DiscoveredDiffuser(id: diffuser.id, name: diffuser.name, firmwareVersion: "Unknown"))
        await store.connect(diffuser.id)
    }

    @Test func connectingRecordsTheFirmwareVersion() async {
        let diffuser = MockBLETransport.Peripheral()
        diffuser.firmwareVersion = "4.0.2"
        let store = makeStore(MockBLETransport(peripherals: [diffuser]))

        await addAndConnect(diffuser, to: store)
        #expect(store.connectionState(for: diffuser.id) == .connected)
        #expect(store.diffuser(withID: diffuser.id)?.firmwareVersion == "4.0.2")
    }

    @Test func reconnectsAfterTheConnectionDrops() async {
        let diffuser = MockBLETransport.Peripheral()
        let transport = MockBLETransport(peripherals: [diffuser])
        let store = makeStore(transport)
        await addAndConnect(diffuser, to: store)

        transport.dropConnection(to: diffuser.id)
        #expect(store.connectionState(for: diffuser.id) == .reconnecting)
        #expect(await waitUntil { store.connectionState(for: diffuser.id) == .connected })
        #expect(transport.connectedIDs == [diffuser.id])
    }

    @Test func keepsTryingUntilAnAttemptWorks() async {
        let diffuser = MockBLETransport.Peripheral()
        let transport = MockBLETransport(peripherals: [diffuser])
        let store = makeStore(transport)
        await addAndConnect(diffuser, to: store)

        transport.failingConnectAttempts = 2
        transport.dropConnection(to: diffuser.id)
        #expect(await waitUntil { store.connectionState(for: diffuser.id) == .connected })
    }

    @Test func givesUpAfterTheLastAttempt() async {
        let diffuser = MockBLETransport.Peripheral()
        let transport = MockBLETransport(peripherals: [diffuser])
        let store = makeStore(transport)
        await addAndConnect(diffuser, to: store)

        transport.failingConnectAttempts = 3
        transport.dropConnection(to: diffuser.id)
        #expect(await waitUntil { store.connectionState(for: diffuser.id) == .disconnected })
        #expect(transport.connectedIDs.isEmpty)
        #expect(store.errorMessage == nil)
    }

    @Test func waitsForBluetoothAndReconnectsWhenItComesBack() async throws {
        let diffuser = MockBLETransport.Peripheral()
        let transport = MockBLETransport(peripherals: [diffuser])
        let store = makeStore(transport)
        await addAndConnect(diffuser, to: store)

        transport.setAvailability(.poweredOff)
        #expect(store.bluetoothAvailability == .poweredOff)
        #expect(store.connectionState(for: diffuser.id) == .disconnected)
        try await Task.sleep(for: .milliseconds(150))
        #expect(store.connectionState(for: diffuser.id) == .disconnected)

        transport.setAvailability(.poweredOn)
        #expect(store.bluetoothAvailability == .poweredOn)
        #expect(await waitUntil { store.connectionState(for: diffuser.id) == .connected })
    }

    @Test func forgettingADiffuserStopsReconnecting() async throws {
        let diffuser = MockBLETransport.Peripheral()
        let transport = MockBLETransport(peripherals: [diffuser])
        let store = makeStore(transport)
        await addAndConnect(diffuser, to: store)

        transport.failingConnectAttempts = 1
        transport.dropConnection(to: diffuser.id)
        store.remove(diffuser.id)
        try await Task.sleep(for: .milliseconds(200))

        #expect(store.diffusers.isEmpty)
        #expect(store.connectionStates[diffuser.id] == nil)
        #expect(transport.connectedIDs.isEmpty)
    }

    @Test func statusSentByTheDiffuserUpdatesTheScreen() async {
        let diffuser = MockBLETransport.Peripheral()
        let transport = MockBLETransport(peripherals: [diffuser])
        let store = makeStore(transport)
        await addAndConnect(diffuser, to: store)

        diffuser.isOn = true
        diffuser.intensity = 5
        transport.pushStatus(from: diffuser.id)
        #expect(await waitUntil { store.diffuser(withID: diffuser.id)?.intensity == 5 })
        #expect(store.diffuser(withID: diffuser.id)?.isOn == true)
    }

    @Test func controlsWorkEndToEnd() async {
        let diffuser = MockBLETransport.Peripheral()
        let store = makeStore(MockBLETransport(peripherals: [diffuser]))
        await addAndConnect(diffuser, to: store)

        await store.setPower(true, for: diffuser.id)
        await store.setIntensity(2, for: diffuser.id)
        #expect(diffuser.isOn)
        #expect(diffuser.intensity == 2)
        #expect(store.diffuser(withID: diffuser.id)?.isOn == true)
        #expect(store.errorMessage == nil)
    }
}
