import Foundation

/// The link between the app and the diffuser hardware.
///
/// The app only talks to this protocol:
/// - `SimulatedDiffuserService` is the built-in demo diffuser.
/// - `BluetoothDiffuserService` talks to real diffusers over Bluetooth.
/// - `CombinedDiffuserService` offers both at once and is what the app uses.
@MainActor
protocol DiffuserService: AnyObject {
    var availability: BluetoothAvailability { get }
    /// Called when something happens that nobody asked for, such as a lost connection.
    var onEvent: (@MainActor (DiffuserServiceEvent) -> Void)? { get set }

    func discover() async throws -> [DiscoveredDiffuser]
    func connect(to id: UUID) async throws -> DiffuserStatus
    func disconnect(from id: UUID)
    /// Connects automatically whenever the diffuser comes in range, even with
    /// the app in the background. Reported with `.reconnected`.
    func connectWhenNearby(_ id: UUID)
    func send(_ command: DiffuserCommand, to id: UUID) async throws
    func readStatus(of id: UUID) async throws -> DiffuserStatus

    // MARK: Firmware updates

    /// Tells the diffuser an update is coming. Returns how many bytes to send per chunk.
    func beginFirmwareUpdate(on id: UUID, image: FirmwareImage) async throws -> Int
    func sendFirmwareChunk(_ chunk: Data, offset: Int, to id: UUID) async throws
    /// Asks the diffuser to check the firmware it received and install it.
    /// Throws `commandRejected` if the check fails.
    func finishFirmwareUpdate(on id: UUID) async throws
    /// Abandons an update in progress. The diffuser keeps its current firmware.
    func abortFirmwareUpdate(on id: UUID)
}

enum DiffuserServiceEvent: Equatable, Sendable {
    case availabilityChanged(BluetoothAvailability)
    /// The connection dropped without the app asking for it.
    case connectionLost(UUID)
    /// The diffuser reported a change on its own, for example a button press on the device.
    case statusChanged(UUID, DiffuserStatus)
    /// A diffuser came back in range and connected without the app asking right then.
    case reconnected(UUID, DiffuserStatus)
}

enum DiffuserServiceError: LocalizedError, Equatable {
    case deviceNotFound
    case notConnected
    case couldNotConnect
    case unsupportedDevice
    case timedOut
    case connectionLost
    case commandRejected
    case bluetoothUnavailable(BluetoothAvailability)

    var errorDescription: String? {
        switch self {
        case .deviceNotFound:
            "The diffuser could not be found. Make sure it is switched on and nearby."
        case .notConnected:
            "The diffuser is not connected. Reconnect and try again."
        case .couldNotConnect:
            "Couldn't connect to the diffuser. Make sure it is switched on and nearby, then try again."
        case .unsupportedDevice:
            "This device isn't a supported diffuser."
        case .timedOut:
            "The diffuser didn't respond. Make sure it is switched on and nearby."
        case .connectionLost:
            "The connection to the diffuser was lost."
        case .commandRejected:
            "The diffuser couldn't make that change."
        case .bluetoothUnavailable(let availability):
            switch availability {
            case .poweredOff:
                "Bluetooth is off. Turn it on in Control Centre."
            case .unauthorized:
                "AuraDrive isn't allowed to use Bluetooth. You can allow it in Settings."
            case .unsupported:
                "This device doesn't support Bluetooth."
            case .unknown, .resetting, .poweredOn:
                "Bluetooth isn't ready yet. Try again in a moment."
            }
        }
    }
}
