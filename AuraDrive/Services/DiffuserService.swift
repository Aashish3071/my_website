import Foundation

/// The link between the app and the diffuser hardware.
///
/// The app only talks to this protocol. `SimulatedDiffuserService` is the demo
/// implementation. A Bluetooth implementation can be added behind the same
/// protocol once the device's protocol document is available, without changing
/// any screen.
@MainActor
protocol DiffuserService: AnyObject {
    func discover() async throws -> [DiscoveredDiffuser]
    func connect(to id: UUID) async throws -> DiffuserStatus
    func disconnect(from id: UUID)
    func send(_ command: DiffuserCommand, to id: UUID) async throws
    func readStatus(of id: UUID) async throws -> DiffuserStatus
}

enum DiffuserServiceError: LocalizedError, Equatable {
    case deviceNotFound
    case notConnected

    var errorDescription: String? {
        switch self {
        case .deviceNotFound:
            "The diffuser could not be found. Make sure it is switched on and nearby."
        case .notConnected:
            "The diffuser is not connected. Reconnect and try again."
        }
    }
}
