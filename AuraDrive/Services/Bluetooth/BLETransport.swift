import Foundation

/// Whether Bluetooth can be used right now, as reported by iOS.
enum BluetoothAvailability: Equatable, Sendable {
    /// iOS hasn't reported yet. Bluetooth isn't started until the app needs it.
    case unknown
    case resetting
    /// This device has no Bluetooth LE, for example the iOS Simulator.
    case unsupported
    /// The user hasn't allowed the app to use Bluetooth.
    case unauthorized
    case poweredOff
    case poweredOn
}

/// A Bluetooth LE device found while scanning.
struct BLEPeripheralInfo: Equatable, Sendable {
    let id: UUID
    let name: String
    /// Signal strength in dBm. Closer devices have higher (less negative) values.
    let rssi: Int
}

/// Something the Bluetooth link reports without being asked.
enum BLETransportEvent: Equatable, Sendable {
    case availabilityChanged(BluetoothAvailability)
    /// Bytes the diffuser sent, either a reply or a message of its own.
    case received(UUID, Data)
    /// The link to the device closed, whether or not the app asked for it.
    case disconnected(UUID)
    /// A connection requested with `connectWhenNearby`, or restored by iOS after
    /// it relaunched the app, is now ready for `write`.
    case connected(UUID)
}

/// Moves bytes to and from diffusers. It knows nothing about what the bytes
/// mean; `DiffuserCodec` does that. `CoreBluetoothTransport` is the real
/// implementation and `MockBLETransport` the one used in tests.
@MainActor
protocol BLETransport: AnyObject {
    var availability: BluetoothAvailability { get }
    var eventHandler: (@MainActor (BLETransportEvent) -> Void)? { get set }

    /// Scans for diffusers for `duration`, then returns what was found.
    func scan(for duration: Duration) async throws -> [BLEPeripheralInfo]
    /// Connects and gets the device ready for `write`. Throws if that fails or times out.
    func connect(_ id: UUID) async throws
    func disconnect(_ id: UUID)
    /// Asks for a connection as soon as the device is in range, with no time
    /// limit, even while the app is in the background. Reported with `.connected`.
    func connectWhenNearby(_ id: UUID)
    /// Sends one complete message to the device.
    func write(_ data: Data, to id: UUID) async throws
}

/// Bluetooth identifiers of the diffuser.
///
/// PLACEHOLDER: these are the identifiers of the Nordic UART Service, which
/// many Bluetooth accessories use. Replace them with the ones in the
/// manufacturer's protocol document.
enum DiffuserBLEIdentifiers {
    static let service = "6E400001-B5A3-F393-E0A9-E50E24DCCA9E"
    /// The app writes commands here.
    static let commandCharacteristic = "6E400002-B5A3-F393-E0A9-E50E24DCCA9E"
    /// The diffuser sends replies and status updates here.
    static let notifyCharacteristic = "6E400003-B5A3-F393-E0A9-E50E24DCCA9E"
}
