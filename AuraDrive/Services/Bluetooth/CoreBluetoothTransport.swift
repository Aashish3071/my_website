@preconcurrency import CoreBluetooth
import Foundation

/// The real Bluetooth link, built on CoreBluetooth.
///
/// Bluetooth is started the first time it's needed (the first scan or
/// connection), so iOS asks the user for permission at that moment rather
/// than when the app opens.
///
/// Background reconnection: `connectWhenNearby` leaves a connection request
/// with iOS that never times out. iOS completes it when the diffuser comes in
/// range, even with the app in the background, and if the app was closed iOS
/// relaunches it in the background and hands back the connection through state
/// restoration (`willRestoreState`). This needs the `bluetooth-central`
/// background mode in Info.plist.
///
/// Not yet tested against hardware: the simulator has no Bluetooth, so this
/// needs a real iPhone and diffuser. The service and characteristic
/// identifiers are placeholders; see `DiffuserBLEIdentifiers`.
@MainActor
final class CoreBluetoothTransport: NSObject, BLETransport {
    var eventHandler: (@MainActor (BLETransportEvent) -> Void)?
    private(set) var availability: BluetoothAvailability = .unknown

    private struct PendingConnect {
        let attempt: UUID
        let continuation: CheckedContinuation<Void, any Error>
    }

    private let serviceUUID = CBUUID(string: DiffuserBLEIdentifiers.service)
    private let commandUUID = CBUUID(string: DiffuserBLEIdentifiers.commandCharacteristic)
    private let notifyUUID = CBUUID(string: DiffuserBLEIdentifiers.notifyCharacteristic)
    private let connectTimeout: Duration

    private var central: CBCentralManager?
    private var stateWaiters: [CheckedContinuation<Void, Never>] = []
    private var knownPeripherals: [UUID: CBPeripheral] = [:]
    private var scanResults: [UUID: BLEPeripheralInfo] = [:]
    private var pendingConnects: [UUID: PendingConnect] = [:]
    private var commandCharacteristics: [UUID: CBCharacteristic] = [:]
    private var pendingWrites: [UUID: [CheckedContinuation<Void, any Error>]] = [:]
    /// Diffusers to connect to whenever they come in range.
    private var waitingForRange: Set<UUID> = []

    /// Lets iOS hand back connections after relaunching the app in the background.
    private static let restoreIdentifier = "AuraDriveBluetoothCentral"

    init(connectTimeout: Duration = .seconds(10)) {
        self.connectTimeout = connectTimeout
        super.init()
    }

    // MARK: BLETransport

    func scan(for duration: Duration) async throws -> [BLEPeripheralInfo] {
        let central = try await readyCentral()
        scanResults = [:]
        central.scanForPeripherals(withServices: [serviceUUID], options: nil)
        try? await Task.sleep(for: duration)
        central.stopScan()
        try Task.checkCancellation()
        return scanResults.values.sorted { $0.rssi > $1.rssi }
    }

    func connect(_ id: UUID) async throws {
        let central = try await readyCentral()
        // A diffuser added in an earlier session is looked up by its identifier.
        guard let peripheral = knownPeripherals[id] ?? central.retrievePeripherals(withIdentifiers: [id]).first else {
            throw DiffuserServiceError.deviceNotFound
        }
        guard pendingConnects[id] == nil else { throw DiffuserServiceError.couldNotConnect }
        knownPeripherals[id] = peripheral
        peripheral.delegate = self
        // This attempt now owns the connection; it reports to the caller, not as an event.
        waitingForRange.remove(id)

        let attempt = UUID()
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            pendingConnects[id] = PendingConnect(attempt: attempt, continuation: continuation)
            central.connect(peripheral, options: nil)
            // CoreBluetooth keeps trying forever, so give up after a while.
            Task { [weak self, connectTimeout] in
                try? await Task.sleep(for: connectTimeout)
                self?.failConnect(id, attempt: attempt, with: DiffuserServiceError.timedOut, cancel: true)
            }
        }
    }

    func connectWhenNearby(_ id: UUID) {
        // Never asks for permission: if the user hasn't allowed Bluetooth yet,
        // it waits until they connect a diffuser themselves.
        guard CBManager.authorization == .allowedAlways else { return }
        waitingForRange.insert(id)
        let central = self.central ?? makeCentral()
        // Otherwise requested when Bluetooth reports it is on.
        if central.state == .poweredOn {
            requestConnectionWhenNearby(id)
        }
    }

    func disconnect(_ id: UUID) {
        waitingForRange.remove(id)
        failConnect(id, with: DiffuserServiceError.notConnected, cancel: false)
        commandCharacteristics[id] = nil
        if let peripheral = knownPeripherals[id] {
            central?.cancelPeripheralConnection(peripheral)
        }
    }

    func write(_ data: Data, to id: UUID) async throws {
        guard let peripheral = knownPeripherals[id], peripheral.state == .connected,
              let characteristic = commandCharacteristics[id] else {
            throw DiffuserServiceError.notConnected
        }
        if characteristic.properties.contains(.write) {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                pendingWrites[id, default: []].append(continuation)
                peripheral.writeValue(data, for: characteristic, type: .withResponse)
            }
        } else {
            peripheral.writeValue(data, for: characteristic, type: .withoutResponse)
        }
    }

    // MARK: Private

    /// Starts Bluetooth if needed and waits until iOS reports whether it's usable.
    private func readyCentral() async throws -> CBCentralManager {
        let central = self.central ?? makeCentral()
        if central.state == .unknown {
            await withCheckedContinuation { stateWaiters.append($0) }
        }
        guard availability == .poweredOn else {
            throw DiffuserServiceError.bluetoothUnavailable(availability)
        }
        return central
    }

    private func makeCentral() -> CBCentralManager {
        let central = CBCentralManager(
            delegate: self,
            queue: nil,
            options: [CBCentralManagerOptionRestoreIdentifierKey: Self.restoreIdentifier]
        )
        self.central = central
        return central
    }

    /// Leaves a connection request with iOS. It has no time limit.
    private func requestConnectionWhenNearby(_ id: UUID) {
        guard pendingConnects[id] == nil, let central, central.state == .poweredOn else { return }
        guard let peripheral = knownPeripherals[id] ?? central.retrievePeripherals(withIdentifiers: [id]).first else {
            waitingForRange.remove(id)
            return
        }
        knownPeripherals[id] = peripheral
        peripheral.delegate = self
        if peripheral.state == .connected {
            // Already connected (for example handed back by iOS): just set it up.
            peripheral.discoverServices([serviceUUID])
        } else {
            central.connect(peripheral, options: nil)
        }
    }

    private func finishConnect(_ id: UUID) {
        pendingConnects.removeValue(forKey: id)?.continuation.resume()
    }

    /// Fails the pending connection to `id`. With `attempt`, only if it's still that attempt.
    private func failConnect(_ id: UUID, attempt: UUID? = nil, with error: any Error, cancel: Bool) {
        guard let pending = pendingConnects[id], attempt == nil || pending.attempt == attempt else { return }
        pendingConnects[id] = nil
        if cancel, let peripheral = knownPeripherals[id] {
            central?.cancelPeripheralConnection(peripheral)
        }
        pending.continuation.resume(throwing: error)
    }

    private func failWrites(for id: UUID, with error: any Error) {
        let writes = pendingWrites.removeValue(forKey: id) ?? []
        for continuation in writes {
            continuation.resume(throwing: error)
        }
    }

    /// The device connected but isn't set up the way a diffuser should be.
    private func failSetup(of peripheral: CBPeripheral) {
        if waitingForRange.remove(peripheral.identifier) != nil {
            central?.cancelPeripheralConnection(peripheral)
        }
        failConnect(peripheral.identifier, with: DiffuserServiceError.unsupportedDevice, cancel: true)
    }

    private static func availability(from state: CBManagerState) -> BluetoothAvailability {
        switch state {
        case .poweredOn: .poweredOn
        case .poweredOff: .poweredOff
        case .unauthorized: .unauthorized
        case .unsupported: .unsupported
        case .resetting: .resetting
        case .unknown: .unknown
        @unknown default: .unknown
        }
    }
}

// CoreBluetooth calls these on the main queue (`queue: nil` above), which
// matches the class's main-actor isolation.
extension CoreBluetoothTransport: @preconcurrency CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        let newValue = Self.availability(from: central.state)
        availability = newValue
        if newValue != .unknown {
            let waiters = stateWaiters
            stateWaiters = []
            for waiter in waiters {
                waiter.resume()
            }
        }
        if newValue != .poweredOn {
            // iOS drops every connection when Bluetooth stops.
            for id in Array(pendingConnects.keys) {
                failConnect(id, with: DiffuserServiceError.bluetoothUnavailable(newValue), cancel: false)
            }
            for id in Array(pendingWrites.keys) {
                failWrites(for: id, with: DiffuserServiceError.connectionLost)
            }
            commandCharacteristics.removeAll()
        } else {
            // Requests left while Bluetooth was off, or handed back by iOS.
            for id in waitingForRange {
                requestConnectionWhenNearby(id)
            }
        }
        eventHandler?(.availabilityChanged(newValue))
    }

    func centralManager(_ central: CBCentralManager, willRestoreState dict: [String: Any]) {
        // iOS relaunched the app in the background and is handing back the
        // diffusers it was connected to, or still waiting for.
        let peripherals = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral] ?? []
        for peripheral in peripherals {
            knownPeripherals[peripheral.identifier] = peripheral
            peripheral.delegate = self
            waitingForRange.insert(peripheral.identifier)
        }
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        knownPeripherals[peripheral.identifier] = peripheral
        let name = peripheral.name
            ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String
            ?? "Fragrance Diffuser"
        scanResults[peripheral.identifier] = BLEPeripheralInfo(
            id: peripheral.identifier,
            name: name,
            rssi: RSSI.intValue
        )
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.discoverServices([serviceUUID])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: (any Error)?) {
        failConnect(peripheral.identifier, with: DiffuserServiceError.couldNotConnect, cancel: false)
    }

    func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: (any Error)?
    ) {
        let id = peripheral.identifier
        commandCharacteristics[id] = nil
        failConnect(id, with: DiffuserServiceError.couldNotConnect, cancel: false)
        failWrites(for: id, with: DiffuserServiceError.connectionLost)
        eventHandler?(.disconnected(id))
        // Dropped while being set up after a background connection: keep waiting.
        if waitingForRange.contains(id) {
            requestConnectionWhenNearby(id)
        }
    }
}

extension CoreBluetoothTransport: @preconcurrency CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: (any Error)?) {
        guard error == nil, let service = peripheral.services?.first(where: { $0.uuid == serviceUUID }) else {
            return failSetup(of: peripheral)
        }
        peripheral.discoverCharacteristics([commandUUID, notifyUUID], for: service)
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: (any Error)?
    ) {
        let characteristics = service.characteristics ?? []
        guard error == nil,
              let command = characteristics.first(where: { $0.uuid == commandUUID }),
              let notify = characteristics.first(where: { $0.uuid == notifyUUID }) else {
            return failSetup(of: peripheral)
        }
        commandCharacteristics[peripheral.identifier] = command
        peripheral.setNotifyValue(true, for: notify)
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateNotificationStateFor characteristic: CBCharacteristic,
        error: (any Error)?
    ) {
        guard characteristic.uuid == notifyUUID else { return }
        guard error == nil, characteristic.isNotifying else {
            return failSetup(of: peripheral)
        }
        // Ready: commands can be written and replies will arrive.
        let id = peripheral.identifier
        if pendingConnects[id] != nil {
            finishConnect(id)
        } else if waitingForRange.remove(id) != nil {
            eventHandler?(.connected(id))
        }
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: (any Error)?
    ) {
        guard error == nil, characteristic.uuid == notifyUUID, let data = characteristic.value else { return }
        eventHandler?(.received(peripheral.identifier, data))
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didWriteValueFor characteristic: CBCharacteristic,
        error: (any Error)?
    ) {
        let id = peripheral.identifier
        guard var writes = pendingWrites[id], !writes.isEmpty else { return }
        let continuation = writes.removeFirst()
        pendingWrites[id] = writes
        if error == nil {
            continuation.resume()
        } else {
            continuation.resume(throwing: DiffuserServiceError.connectionLost)
        }
    }
}
