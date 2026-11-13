import Foundation
import Testing
@testable import AuraDrive

@MainActor
struct BluetoothDiffuserServiceTests {
    private func makeService(
        _ transport: MockBLETransport,
        // Generous by default: the tests share the main thread, so replies can
        // be slow under load. Tests about timeouts pass a short one.
        responseTimeout: Duration = .seconds(2)
    ) -> BluetoothDiffuserService {
        BluetoothDiffuserService(transport: transport, scanDuration: .milliseconds(10), responseTimeout: responseTimeout)
    }

    @Test func discoverListsNearbyDiffusers() async throws {
        let diffuser = MockBLETransport.Peripheral(name: "Car Diffuser")
        let service = makeService(MockBLETransport(peripherals: [diffuser]))

        let found = try await service.discover()
        #expect(found.map(\.id) == [diffuser.id])
        #expect(found.first?.name == "Car Diffuser")
    }

    @Test func connectReadsFirmwareAndStatus() async throws {
        let diffuser = MockBLETransport.Peripheral()
        diffuser.isOn = true
        diffuser.intensity = 4
        diffuser.fragrancePercent = 55
        diffuser.firmwareVersion = "3.1.4"
        let transport = MockBLETransport(peripherals: [diffuser])
        let service = makeService(transport)

        let status = try await service.connect(to: diffuser.id)
        #expect(status == DiffuserStatus(isOn: true, intensity: 4, fragranceLevel: 0.55, firmwareVersion: "3.1.4"))
        #expect(transport.writtenRequests == [.firmwareVersion, .status])
    }

    @Test func commandsReachTheDiffuser() async throws {
        let diffuser = MockBLETransport.Peripheral()
        diffuser.fragrancePercent = 20
        let service = makeService(MockBLETransport(peripherals: [diffuser]))
        _ = try await service.connect(to: diffuser.id)

        let interval = IntervalSettings(isEnabled: true, runSeconds: 20, pauseSeconds: 40)
        try await service.send(.setPower(true), to: diffuser.id)
        try await service.send(.setIntensity(5), to: diffuser.id)
        try await service.send(.setInterval(interval), to: diffuser.id)
        try await service.send(.resetFragranceLevel, to: diffuser.id)

        #expect(diffuser.isOn)
        #expect(diffuser.intensity == 5)
        #expect(diffuser.interval == interval)
        #expect(diffuser.fragrancePercent == 100)
    }

    @Test func refusedCommandThrows() async throws {
        let diffuser = MockBLETransport.Peripheral()
        let transport = MockBLETransport(peripherals: [diffuser])
        transport.rejectedKinds = [.intensity]
        let service = makeService(transport)
        _ = try await service.connect(to: diffuser.id)

        await #expect(throws: DiffuserServiceError.commandRejected) {
            try await service.send(.setIntensity(2), to: diffuser.id)
        }
        #expect(diffuser.intensity == 3)
    }

    @Test func silentDiffuserTimesOut() async throws {
        let diffuser = MockBLETransport.Peripheral()
        let transport = MockBLETransport(peripherals: [diffuser])
        let service = makeService(transport, responseTimeout: .milliseconds(300))
        _ = try await service.connect(to: diffuser.id)

        transport.respondsToRequests = false
        await #expect(throws: DiffuserServiceError.timedOut) {
            try await service.readStatus(of: diffuser.id)
        }
    }

    @Test func connectFailsAndCleansUpWhenTheDiffuserNeverAnswers() async {
        let diffuser = MockBLETransport.Peripheral()
        let transport = MockBLETransport(peripherals: [diffuser])
        transport.respondsToRequests = false
        let service = makeService(transport, responseTimeout: .milliseconds(100))

        await #expect(throws: DiffuserServiceError.timedOut) {
            try await service.connect(to: diffuser.id)
        }
        #expect(transport.connectedIDs.isEmpty)
    }

    @Test func slowRepliesStillArrive() async throws {
        let diffuser = MockBLETransport.Peripheral()
        let transport = MockBLETransport(peripherals: [diffuser])
        transport.responseDelay = .milliseconds(100)
        let service = makeService(transport, responseTimeout: .seconds(3))

        let status = try await service.connect(to: diffuser.id)
        #expect(status.intensity == 3)
    }

    @Test func droppedConnectionFailsTheRequestAndIsReported() async throws {
        let diffuser = MockBLETransport.Peripheral()
        let transport = MockBLETransport(peripherals: [diffuser])
        let service = makeService(transport, responseTimeout: .seconds(2))
        let recorder = EventRecorder()
        service.onEvent = { recorder.record($0) }
        _ = try await service.connect(to: diffuser.id)

        transport.respondsToRequests = false
        let pending = Task { try await service.readStatus(of: diffuser.id) }
        try await Task.sleep(for: .milliseconds(50))
        transport.dropConnection(to: diffuser.id)

        await #expect(throws: DiffuserServiceError.connectionLost) {
            try await pending.value
        }
        #expect(recorder.events == [.connectionLost(diffuser.id)])
        await #expect(throws: DiffuserServiceError.notConnected) {
            try await service.send(.setPower(true), to: diffuser.id)
        }
    }

    @Test func disconnectingOnPurposeIsNotReportedAsLost() async throws {
        let diffuser = MockBLETransport.Peripheral()
        let transport = MockBLETransport(peripherals: [diffuser])
        let service = makeService(transport)
        let recorder = EventRecorder()
        service.onEvent = { recorder.record($0) }
        _ = try await service.connect(to: diffuser.id)

        service.disconnect(from: diffuser.id)
        try await Task.sleep(for: .milliseconds(50))
        #expect(recorder.events.isEmpty)
        #expect(transport.connectedIDs.isEmpty)
    }

    @Test func statusSentByTheDiffuserIsForwarded() async throws {
        let diffuser = MockBLETransport.Peripheral()
        let transport = MockBLETransport(peripherals: [diffuser])
        let service = makeService(transport)
        let recorder = EventRecorder()
        service.onEvent = { recorder.record($0) }
        _ = try await service.connect(to: diffuser.id)

        diffuser.fragrancePercent = 10
        transport.pushStatus(from: diffuser.id)

        let expected = DiffuserServiceEvent.statusChanged(
            diffuser.id,
            DiffuserStatus(isOn: false, intensity: 3, fragranceLevel: 0.1)
        )
        #expect(await waitUntil { recorder.events == [expected] })
    }

    @Test func damagedRepliesAreIgnored() async throws {
        let diffuser = MockBLETransport.Peripheral()
        let transport = MockBLETransport(peripherals: [diffuser])
        let service = makeService(transport, responseTimeout: .seconds(2))
        _ = try await service.connect(to: diffuser.id)

        transport.respondsToRequests = false
        let pending = Task { try await service.readStatus(of: diffuser.id) }
        try await Task.sleep(for: .milliseconds(50))
        transport.receive(Data([0x01, 0x02, 0x03]), from: diffuser.id)
        let good = PlaceholderDiffuserCodec().encodeMessage(
            .status(DiffuserStatus(isOn: true, intensity: 2, fragranceLevel: 0.4))
        )
        transport.receive(good, from: diffuser.id)

        let status = try await pending.value
        #expect(status == DiffuserStatus(isOn: true, intensity: 2, fragranceLevel: 0.4))
    }

    @Test func bluetoothOffStopsDiscovery() async {
        let service = makeService(MockBLETransport(availability: .poweredOff))
        await #expect(throws: DiffuserServiceError.bluetoothUnavailable(.poweredOff)) {
            try await service.discover()
        }
    }

    @Test func turningBluetoothOffEndsConnections() async throws {
        let diffuser = MockBLETransport.Peripheral()
        let transport = MockBLETransport(peripherals: [diffuser])
        let service = makeService(transport)
        let recorder = EventRecorder()
        service.onEvent = { recorder.record($0) }
        _ = try await service.connect(to: diffuser.id)

        transport.setAvailability(.poweredOff)
        #expect(service.availability == .poweredOff)
        // Bluetooth off is reported before the lost connection.
        #expect(recorder.events == [.availabilityChanged(.poweredOff), .connectionLost(diffuser.id)])
    }
}
