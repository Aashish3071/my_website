import Foundation

/// A pretend Bluetooth link with pretend diffusers on the other end.
///
/// The pretend diffusers read and answer the same bytes as real ones (through
/// `PlaceholderDiffuserCodec`), so everything above the radio can be tested
/// without hardware. Tests can make the link slow, silent, refuse commands,
/// fail to connect, drop the connection, or turn Bluetooth off.
@MainActor
final class MockBLETransport: BLETransport {
    /// One pretend diffuser and its state.
    final class Peripheral {
        let id: UUID
        var name: String
        var firmwareVersion = "1.2.0"
        var isOn = false
        var intensity = 3
        var interval = IntervalSettings()
        var fragrancePercent = 80
        /// A firmware update being received.
        var firmwareUpdate: FirmwareTransfer?

        struct FirmwareTransfer {
            let size: Int
            let checksum: UInt32
            let version: String
            var received: [UInt8] = []
        }

        init(id: UUID = UUID(), name: String = "Mock Diffuser") {
            self.id = id
            self.name = name
        }
    }

    var eventHandler: (@MainActor (BLETransportEvent) -> Void)?
    private(set) var availability: BluetoothAvailability
    private(set) var peripherals: [UUID: Peripheral] = [:]
    private(set) var connectedIDs: Set<UUID> = []
    /// Every request the app sent, in order.
    private(set) var writtenRequests: [DiffuserRequest] = []

    var connectDelay: Duration = .zero
    var responseDelay: Duration = .zero
    /// The next this-many connection attempts fail.
    var failingConnectAttempts = 0
    /// When false, requests are received but never answered.
    var respondsToRequests = true
    /// Requests of these kinds are refused.
    var rejectedKinds: Set<DiffuserRequest.Kind> = []
    /// Finishing a firmware update fails as if the firmware arrived damaged.
    var failsFirmwareVerification = false
    /// The connection drops when this many firmware chunks have arrived.
    var dropConnectionAfterFirmwareChunks: Int?
    private var firmwareChunksReceived = 0

    private let codec = PlaceholderDiffuserCodec()

    init(availability: BluetoothAvailability = .poweredOn, peripherals: [Peripheral] = []) {
        self.availability = availability
        for peripheral in peripherals {
            self.peripherals[peripheral.id] = peripheral
        }
    }

    // MARK: Controls for tests

    func add(_ peripheral: Peripheral) {
        peripherals[peripheral.id] = peripheral
    }

    func setAvailability(_ newValue: BluetoothAvailability) {
        availability = newValue
        if newValue != .poweredOn {
            connectedIDs.removeAll()
        }
        eventHandler?(.availabilityChanged(newValue))
    }

    /// Ends a connection as if the diffuser went out of range.
    func dropConnection(to id: UUID) {
        guard connectedIDs.remove(id) != nil else { return }
        eventHandler?(.disconnected(id))
    }

    /// Makes the diffuser report its state without being asked.
    func pushStatus(from id: UUID) {
        guard let peripheral = peripherals[id], connectedIDs.contains(id) else { return }
        deliver(.status(status(of: peripheral)), from: id)
    }

    /// Delivers bytes as if the diffuser sent them.
    func receive(_ data: Data, from id: UUID) {
        eventHandler?(.received(id, data))
    }

    // MARK: BLETransport

    func scan(for duration: Duration) async throws -> [BLEPeripheralInfo] {
        try requirePoweredOn()
        try await Task.sleep(for: .milliseconds(10))
        return peripherals.values
            .map { BLEPeripheralInfo(id: $0.id, name: $0.name, rssi: -50) }
            .sorted { $0.name < $1.name }
    }

    func connect(_ id: UUID) async throws {
        try requirePoweredOn()
        try await Task.sleep(for: connectDelay)
        try requirePoweredOn()
        guard peripherals[id] != nil else { throw DiffuserServiceError.deviceNotFound }
        if failingConnectAttempts > 0 {
            failingConnectAttempts -= 1
            throw DiffuserServiceError.couldNotConnect
        }
        connectedIDs.insert(id)
    }

    func disconnect(_ id: UUID) {
        guard connectedIDs.remove(id) != nil else { return }
        // CoreBluetooth reports a disconnect even when the app asked for it.
        Task { [weak self] in
            self?.eventHandler?(.disconnected(id))
        }
    }

    func write(_ data: Data, to id: UUID) async throws {
        guard connectedIDs.contains(id), let peripheral = peripherals[id] else {
            throw DiffuserServiceError.notConnected
        }
        let request = try codec.decodeRequest(data)
        writtenRequests.append(request)
        if case .firmwareChunk = request {
            firmwareChunksReceived += 1
            if firmwareChunksReceived == dropConnectionAfterFirmwareChunks {
                dropConnection(to: id)
                return
            }
        }
        guard respondsToRequests else { return }
        deliver(reply(to: request, on: peripheral), from: id)
    }

    // MARK: Private

    private func requirePoweredOn() throws {
        guard availability == .poweredOn else {
            throw DiffuserServiceError.bluetoothUnavailable(availability)
        }
    }

    private func reply(to request: DiffuserRequest, on peripheral: Peripheral) -> DiffuserMessage {
        if rejectedKinds.contains(request.kind) {
            return .rejected(request.kind, code: 1)
        }
        switch request {
        case .command(.setPower(let isOn)):
            peripheral.isOn = isOn
        case .command(.setIntensity(let level)):
            peripheral.intensity = level
        case .command(.setInterval(let interval)):
            peripheral.interval = interval
        case .command(.resetFragranceLevel):
            peripheral.fragrancePercent = 100
        case .status:
            return .status(status(of: peripheral))
        case .firmwareVersion:
            return .firmwareVersion(peripheral.firmwareVersion)
        case .firmwareUpdateBegin(let size, let checksum, let version):
            peripheral.firmwareUpdate = Peripheral.FirmwareTransfer(size: size, checksum: checksum, version: version)
        case .firmwareChunk(let offset, let bytes):
            guard var transfer = peripheral.firmwareUpdate,
                  offset == transfer.received.count,
                  offset + bytes.count <= transfer.size else {
                return .rejected(request.kind, code: 2)
            }
            transfer.received += [UInt8](bytes)
            peripheral.firmwareUpdate = transfer
        case .firmwareUpdateFinish:
            guard let transfer = peripheral.firmwareUpdate,
                  transfer.received.count == transfer.size,
                  FirmwareImage.crc32(transfer.received) == transfer.checksum,
                  !failsFirmwareVerification else {
                peripheral.firmwareUpdate = nil
                return .rejected(request.kind, code: 3)
            }
            peripheral.firmwareVersion = transfer.version
            peripheral.firmwareUpdate = nil
        case .firmwareUpdateAbort:
            peripheral.firmwareUpdate = nil
        }
        return .acknowledged(request.kind)
    }

    private func status(of peripheral: Peripheral) -> DiffuserStatus {
        DiffuserStatus(
            isOn: peripheral.isOn,
            intensity: peripheral.intensity,
            fragranceLevel: Double(peripheral.fragrancePercent) / 100
        )
    }

    /// Sends a reply after `responseDelay`, as a real radio would, unless the
    /// connection has gone by then.
    private func deliver(_ message: DiffuserMessage, from id: UUID) {
        let data = codec.encodeMessage(message)
        Task { [weak self, responseDelay] in
            try? await Task.sleep(for: responseDelay)
            guard let self, self.connectedIDs.contains(id) else { return }
            self.eventHandler?(.received(id, data))
        }
    }
}
