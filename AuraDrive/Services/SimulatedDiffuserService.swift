import Foundation

/// A stand-in for real hardware. It behaves like one diffuser: it can be found,
/// connected, switched on and off, and its fragrance slowly runs down while on.
@MainActor
final class SimulatedDiffuserService: DiffuserService {
    /// The demo diffuser doesn't use Bluetooth, so it is always available.
    var availability: BluetoothAvailability { .poweredOn }
    var onEvent: (@MainActor (DiffuserServiceEvent) -> Void)?

    nonisolated static let demoDiffuser = DiscoveredDiffuser(
        id: UUID(uuidString: "0A7D1F5E-3C2B-4E61-9A84-5D1E6F2B7C90")!,
        name: "Demo Diffuser",
        firmwareVersion: "1.0.0"
    )

    static let storageKey = "simulatedDiffuserState"
    /// A full cartridge lasts 60 hours of continuous use at intensity 3.
    private static let secondsPerCartridge: Double = 60 * 60 * 60

    private struct DeviceState: Codable {
        var isOn = false
        var intensity = 3
        var fragranceLevel = 0.62
        var lastUpdated: Date
        /// Set once the demo has been "updated"; before that it reports nothing.
        var firmwareVersion: String?
    }

    private let defaults: UserDefaults
    private let responseDelay: Duration
    private let now: () -> Date
    private var state: DeviceState
    private var isConnected = false
    private var pendingFirmwareVersion: String?

    init(
        defaults: UserDefaults,
        responseDelay: Duration = .milliseconds(500),
        now: @escaping () -> Date = { Date() }
    ) {
        self.defaults = defaults
        self.responseDelay = responseDelay
        self.now = now
        if let data = defaults.data(forKey: Self.storageKey),
           let saved = try? JSONDecoder().decode(DeviceState.self, from: data) {
            state = saved
        } else {
            state = DeviceState(lastUpdated: now())
        }
    }

    func discover() async throws -> [DiscoveredDiffuser] {
        try await Task.sleep(for: responseDelay * 2)
        return [Self.demoDiffuser]
    }

    func connect(to id: UUID) async throws -> DiffuserStatus {
        try await Task.sleep(for: responseDelay)
        guard id == Self.demoDiffuser.id else { throw DiffuserServiceError.deviceNotFound }
        isConnected = true
        return currentStatus()
    }

    func disconnect(from id: UUID) {
        guard id == Self.demoDiffuser.id else { return }
        isConnected = false
    }

    /// The demo diffuser is always in range, so there is nothing to wait for.
    func connectWhenNearby(_ id: UUID) {}

    func send(_ command: DiffuserCommand, to id: UUID) async throws {
        try await Task.sleep(for: responseDelay / 2)
        guard id == Self.demoDiffuser.id, isConnected else { throw DiffuserServiceError.notConnected }

        useUpFragrance()
        switch command {
        case .setPower(let isOn):
            state.isOn = isOn
        case .setIntensity(let intensity):
            state.intensity = intensity
        case .setInterval:
            break
        case .resetFragranceLevel:
            state.fragranceLevel = 1
        }
        save()
    }

    func readStatus(of id: UUID) async throws -> DiffuserStatus {
        guard id == Self.demoDiffuser.id, isConnected else { throw DiffuserServiceError.notConnected }
        return currentStatus()
    }

    private func currentStatus() -> DiffuserStatus {
        useUpFragrance()
        save()
        return DiffuserStatus(
            isOn: state.isOn,
            intensity: state.intensity,
            fragranceLevel: state.fragranceLevel,
            firmwareVersion: state.firmwareVersion
        )
    }

    // MARK: Firmware updates (pretend)

    func beginFirmwareUpdate(on id: UUID, image: FirmwareImage) async throws -> Int {
        try await Task.sleep(for: responseDelay)
        guard id == Self.demoDiffuser.id, isConnected else { throw DiffuserServiceError.notConnected }
        pendingFirmwareVersion = image.version
        return 2048
    }

    func sendFirmwareChunk(_ chunk: Data, offset: Int, to id: UUID) async throws {
        try await Task.sleep(for: responseDelay / 10)
        guard id == Self.demoDiffuser.id, isConnected, pendingFirmwareVersion != nil else {
            throw DiffuserServiceError.notConnected
        }
    }

    func finishFirmwareUpdate(on id: UUID) async throws {
        try await Task.sleep(for: responseDelay * 2)
        guard id == Self.demoDiffuser.id, isConnected else { throw DiffuserServiceError.notConnected }
        guard let version = pendingFirmwareVersion else { throw DiffuserServiceError.commandRejected }
        pendingFirmwareVersion = nil
        state.firmwareVersion = version
        save()
    }

    func abortFirmwareUpdate(on id: UUID) {
        pendingFirmwareVersion = nil
    }

    /// Lowers the fragrance level for the time the diffuser has been running.
    private func useUpFragrance() {
        let current = now()
        let elapsed = current.timeIntervalSince(state.lastUpdated)
        state.lastUpdated = current
        guard state.isOn, elapsed > 0 else { return }
        let used = elapsed * (Double(state.intensity) / 3) / Self.secondsPerCartridge
        state.fragranceLevel = max(0, state.fragranceLevel - used)
    }

    private func save() {
        if let data = try? JSONEncoder().encode(state) {
            defaults.set(data, forKey: Self.storageKey)
        }
    }
}
