import Foundation
import Testing
@testable import AuraDrive

/// Reconnecting when a diffuser comes back in range, through the store, the
/// Bluetooth service and the mock link.
@MainActor
struct BackgroundReconnectionTests {
    private func makeStore(_ transport: MockBLETransport, defaults: UserDefaults) -> DiffuserStore {
        DiffuserStore(
            service: BluetoothDiffuserService(
                transport: transport,
                scanDuration: .milliseconds(10),
                responseTimeout: .milliseconds(200)
            ),
            persistence: DiffuserPersistence(defaults: defaults),
            reconnectDelays: [.milliseconds(20), .milliseconds(20)]
        )
    }

    private func makeDefaults() -> UserDefaults {
        UserDefaults(suiteName: "tests-\(UUID().uuidString)")!
    }

    @Test func savedDiffusersReconnectWhenTheyComeInRangeAfterRelaunch() async {
        let defaults = makeDefaults()
        let diffuser = MockBLETransport.Peripheral()
        let first = makeStore(MockBLETransport(peripherals: [diffuser]), defaults: defaults)
        first.add(DiscoveredDiffuser(id: diffuser.id, name: diffuser.name, firmwareVersion: "Unknown"))

        // The app starts again later, with the diffuser out of range.
        diffuser.intensity = 5
        let transport = MockBLETransport(peripherals: [diffuser])
        let store = makeStore(transport, defaults: defaults)
        #expect(transport.waitingForRange == [diffuser.id])
        #expect(store.connectionState(for: diffuser.id) == .disconnected)

        transport.bringIntoRange(diffuser.id)
        #expect(await waitUntil { store.connectionState(for: diffuser.id) == .connected })
        #expect(store.diffuser(withID: diffuser.id)?.intensity == 5)
        #expect(store.diffuser(withID: diffuser.id)?.firmwareVersion == diffuser.firmwareVersion)
    }

    @Test func afterGivingUpItWaitsForTheDiffuser() async {
        let diffuser = MockBLETransport.Peripheral()
        let transport = MockBLETransport(peripherals: [diffuser])
        let store = makeStore(transport, defaults: makeDefaults())
        store.add(DiscoveredDiffuser(id: diffuser.id, name: diffuser.name, firmwareVersion: "Unknown"))
        await store.connect(diffuser.id)

        transport.failingConnectAttempts = 2
        transport.dropConnection(to: diffuser.id)
        #expect(await waitUntil { store.connectionState(for: diffuser.id) == .disconnected })
        #expect(transport.waitingForRange == [diffuser.id])

        transport.bringIntoRange(diffuser.id)
        #expect(await waitUntil { store.connectionState(for: diffuser.id) == .connected })
    }

    @Test func aFailedConnectionAttemptKeepsWaiting() async {
        let diffuser = MockBLETransport.Peripheral()
        let transport = MockBLETransport(peripherals: [diffuser])
        transport.failingConnectAttempts = 1
        let store = makeStore(transport, defaults: makeDefaults())
        store.add(DiscoveredDiffuser(id: diffuser.id, name: diffuser.name, firmwareVersion: "Unknown"))

        await store.connect(diffuser.id)
        #expect(store.connectionState(for: diffuser.id) == .disconnected)
        #expect(store.errorMessage != nil)
        #expect(transport.waitingForRange == [diffuser.id])
    }

    @Test func aDiffuserThatDoesntAnswerIsWaitedForAgain() async {
        let diffuser = MockBLETransport.Peripheral()
        let defaults = makeDefaults()
        let earlier = makeStore(MockBLETransport(peripherals: [diffuser]), defaults: defaults)
        earlier.add(DiscoveredDiffuser(id: diffuser.id, name: diffuser.name, firmwareVersion: "Unknown"))
        let transport = MockBLETransport(peripherals: [diffuser])
        let store = makeStore(transport, defaults: defaults)

        transport.respondsToRequests = false
        transport.bringIntoRange(diffuser.id)
        #expect(transport.waitingForRange.isEmpty)
        #expect(await waitUntil { transport.waitingForRange == [diffuser.id] })
        #expect(store.connectionState(for: diffuser.id) == .disconnected)
        #expect(transport.connectedIDs.isEmpty)
    }

    @Test func forgettingStopsWaiting() async {
        let diffuser = MockBLETransport.Peripheral()
        let transport = MockBLETransport(peripherals: [diffuser])
        transport.failingConnectAttempts = 1
        let store = makeStore(transport, defaults: makeDefaults())
        store.add(DiscoveredDiffuser(id: diffuser.id, name: diffuser.name, firmwareVersion: "Unknown"))
        await store.connect(diffuser.id)
        #expect(transport.waitingForRange == [diffuser.id])

        store.remove(diffuser.id)
        #expect(transport.waitingForRange.isEmpty)
    }

    @Test func theDemoDiffuserIsNeverWaitedFor() async {
        let defaults = makeDefaults()
        let transport = MockBLETransport()
        let demo = SimulatedDiffuserService(defaults: defaults, responseDelay: .zero)
        let service = CombinedDiffuserService(
            demo: demo,
            bluetooth: BluetoothDiffuserService(transport: transport, scanDuration: .milliseconds(10))
        )
        let first = DiffuserStore(service: service, persistence: DiffuserPersistence(defaults: defaults))
        first.add(SimulatedDiffuserService.demoDiffuser)

        _ = DiffuserStore(service: service, persistence: DiffuserPersistence(defaults: defaults))
        #expect(transport.waitingForRange.isEmpty)
    }
}

@MainActor
struct ErrorAlertHostTests {
    @Test func onlyTheFrontmostScreenShowsTheError() {
        let store = DiffuserStore.preview(withDemoDiffuser: false)
        let main = UUID()
        let sheet = UUID()
        store.registerAlertHost(main)
        store.errorMessage = "Something failed"
        #expect(store.showsError(in: main))

        // A panel opens on top: the alert moves to it.
        store.registerAlertHost(sheet)
        #expect(store.showsError(in: sheet))
        #expect(!store.showsError(in: main))

        // The panel closes: the main screen shows it again.
        store.unregisterAlertHost(sheet)
        #expect(store.showsError(in: main))

        store.errorMessage = nil
        #expect(!store.showsError(in: main))
    }
}

struct InfoPlistTests {
    @Test func bluetoothBackgroundModeIsDeclared() {
        // Without it, iOS can't reconnect in the background, and starting
        // Bluetooth with state restoration would crash the app.
        let modes = Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String]
        #expect(modes?.contains("bluetooth-central") == true)
    }

    @Test func generatedKeysAreStillPresent() {
        // The Info.plist file is merged with the keys from the build settings.
        #expect(Bundle.main.object(forInfoDictionaryKey: "NSBluetoothAlwaysUsageDescription") != nil)
        #expect(Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String == "AuraDrive")
    }
}
