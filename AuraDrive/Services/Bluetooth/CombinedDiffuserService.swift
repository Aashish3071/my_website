import Foundation

/// Offers the built-in demo diffuser alongside real Bluetooth diffusers, and
/// routes each request to the right one.
@MainActor
final class CombinedDiffuserService: DiffuserService {
    var onEvent: (@MainActor (DiffuserServiceEvent) -> Void)?
    var availability: BluetoothAvailability { bluetooth.availability }

    private let demo: SimulatedDiffuserService
    private let bluetooth: BluetoothDiffuserService

    init(demo: SimulatedDiffuserService, bluetooth: BluetoothDiffuserService) {
        self.demo = demo
        self.bluetooth = bluetooth
        demo.onEvent = { [weak self] event in self?.onEvent?(event) }
        bluetooth.onEvent = { [weak self] event in self?.onEvent?(event) }
    }

    func discover() async throws -> [DiscoveredDiffuser] {
        var found = try await demo.discover()
        do {
            found += try await bluetooth.discover()
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            // Bluetooth is off, not allowed or not available. The Add Diffuser
            // screen explains this from `availability`; the demo still shows.
        }
        return found
    }

    func connect(to id: UUID) async throws -> DiffuserStatus {
        try await service(for: id).connect(to: id)
    }

    func disconnect(from id: UUID) {
        service(for: id).disconnect(from: id)
    }

    func connectWhenNearby(_ id: UUID) {
        service(for: id).connectWhenNearby(id)
    }

    func send(_ command: DiffuserCommand, to id: UUID) async throws {
        try await service(for: id).send(command, to: id)
    }

    func readStatus(of id: UUID) async throws -> DiffuserStatus {
        try await service(for: id).readStatus(of: id)
    }

    func beginFirmwareUpdate(on id: UUID, image: FirmwareImage) async throws -> Int {
        try await service(for: id).beginFirmwareUpdate(on: id, image: image)
    }

    func sendFirmwareChunk(_ chunk: Data, offset: Int, to id: UUID) async throws {
        try await service(for: id).sendFirmwareChunk(chunk, offset: offset, to: id)
    }

    func finishFirmwareUpdate(on id: UUID) async throws {
        try await service(for: id).finishFirmwareUpdate(on: id)
    }

    func abortFirmwareUpdate(on id: UUID) {
        service(for: id).abortFirmwareUpdate(on: id)
    }

    private func service(for id: UUID) -> any DiffuserService {
        id == SimulatedDiffuserService.demoDiffuser.id ? demo : bluetooth
    }
}
