import Foundation

/// Talks to real diffusers: turns each request into bytes with the codec, sends
/// it over the transport, and waits for the matching reply.
@MainActor
final class BluetoothDiffuserService: DiffuserService {
    var onEvent: (@MainActor (DiffuserServiceEvent) -> Void)?
    var availability: BluetoothAvailability { transport.availability }

    /// A request waiting for its reply.
    private struct Waiter {
        let id: UUID
        let device: UUID
        let kind: DiffuserRequest.Kind
        let continuation: CheckedContinuation<DiffuserMessage, any Error>
        let timeout: Task<Void, Never>
    }

    private let transport: any BLETransport
    private let codec: any DiffuserCodec
    private let scanDuration: Duration
    private let responseTimeout: Duration
    private var connected: Set<UUID> = []
    private var waiters: [Waiter] = []

    init(
        transport: any BLETransport,
        codec: any DiffuserCodec = PlaceholderDiffuserCodec(),
        scanDuration: Duration = .seconds(4),
        responseTimeout: Duration = .seconds(3)
    ) {
        self.transport = transport
        self.codec = codec
        self.scanDuration = scanDuration
        self.responseTimeout = responseTimeout
        transport.eventHandler = { [weak self] event in
            self?.handle(event)
        }
    }

    // MARK: DiffuserService

    func discover() async throws -> [DiscoveredDiffuser] {
        try await transport.scan(for: scanDuration).map {
            // The firmware version is read when the diffuser is first connected.
            DiscoveredDiffuser(id: $0.id, name: $0.name, firmwareVersion: "Unknown")
        }
    }

    func connect(to id: UUID) async throws -> DiffuserStatus {
        try await transport.connect(id)
        connected.insert(id)
        do {
            // Not every diffuser may report its firmware, so this one is optional.
            var version: String?
            if case .firmwareVersion(let value)? = try? await request(.firmwareVersion, to: id) {
                version = value
            }
            var status = try await readStatus(of: id)
            status.firmwareVersion = version
            return status
        } catch {
            disconnect(from: id)
            throw error
        }
    }

    func disconnect(from id: UUID) {
        connected.remove(id)
        failWaiters(for: id, with: DiffuserServiceError.notConnected)
        transport.disconnect(id)
    }

    func send(_ command: DiffuserCommand, to id: UUID) async throws {
        guard connected.contains(id) else { throw DiffuserServiceError.notConnected }
        if case .rejected = try await request(.command(command), to: id) {
            throw DiffuserServiceError.commandRejected
        }
    }

    func readStatus(of id: UUID) async throws -> DiffuserStatus {
        guard connected.contains(id) else { throw DiffuserServiceError.notConnected }
        guard case .status(let status) = try await request(.status, to: id) else {
            throw DiffuserServiceError.commandRejected
        }
        return status
    }

    // MARK: Requests and replies

    private func request(_ request: DiffuserRequest, to id: UUID) async throws -> DiffuserMessage {
        let data = try codec.encode(request)
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<DiffuserMessage, any Error>) in
            let waiterID = UUID()
            let timeout = Task { [weak self, responseTimeout] in
                try? await Task.sleep(for: responseTimeout)
                guard !Task.isCancelled else { return }
                self?.finish(waiterID, with: .failure(DiffuserServiceError.timedOut))
            }
            // Registered before writing, so a very fast reply can't be missed.
            waiters.append(Waiter(id: waiterID, device: id, kind: request.kind, continuation: continuation, timeout: timeout))
            Task { [weak self] in
                do {
                    try await self?.transport.write(data, to: id)
                } catch {
                    self?.finish(waiterID, with: .failure(error))
                }
            }
        }
    }

    private func finish(_ waiterID: UUID, with result: Result<DiffuserMessage, any Error>) {
        guard let index = waiters.firstIndex(where: { $0.id == waiterID }) else { return }
        let waiter = waiters.remove(at: index)
        waiter.timeout.cancel()
        waiter.continuation.resume(with: result)
    }

    private func failWaiters(for device: UUID, with error: any Error) {
        for waiter in waiters where waiter.device == device {
            finish(waiter.id, with: .failure(error))
        }
    }

    private func handle(_ event: BLETransportEvent) {
        switch event {
        case .received(let id, let data):
            // Damaged or unknown messages are ignored; the request times out instead.
            guard let message = try? codec.decodeMessage(data) else { return }
            if let waiter = waiters.first(where: { $0.device == id && message.answers($0.kind) }) {
                finish(waiter.id, with: .success(message))
            } else if case .status(let status) = message, connected.contains(id) {
                onEvent?(.statusChanged(id, status))
            }

        case .disconnected(let id):
            failWaiters(for: id, with: DiffuserServiceError.connectionLost)
            // A disconnect the app asked for has already been removed from `connected`.
            if connected.remove(id) != nil {
                onEvent?(.connectionLost(id))
            }

        case .availabilityChanged(let availability):
            // Reported first, so listeners know Bluetooth is off before the
            // connections are reported lost, and don't try to reconnect.
            onEvent?(.availabilityChanged(availability))
            guard availability != .poweredOn else { return }
            let lost = connected
            connected.removeAll()
            for id in lost {
                failWaiters(for: id, with: DiffuserServiceError.connectionLost)
                onEvent?(.connectionLost(id))
            }
        }
    }
}
