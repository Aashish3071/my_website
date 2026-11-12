import Foundation

/// Where a firmware update for one diffuser stands.
enum FirmwareUpdateState: Equatable, Sendable {
    case idle
    case checking
    case upToDate
    case available(version: String)
    /// Telling the diffuser an update is coming.
    case preparing
    /// Sending the firmware. Progress runs from 0 to 1.
    case transferring(progress: Double)
    /// All firmware sent; the diffuser is checking it and installing it.
    case verifying
    case completed(version: String)
    case failed(FirmwareUpdateError)

    /// True while the diffuser is being updated and shouldn't be controlled.
    var isInProgress: Bool {
        switch self {
        case .preparing, .transferring, .verifying: true
        case .idle, .checking, .upToDate, .available, .completed, .failed: false
        }
    }
}

enum FirmwareUpdateError: Error, Equatable, Sendable {
    case notConnected
    case connectionLost
    case timedOut
    /// The diffuser refused the update.
    case rejected
    /// The diffuser received the firmware but found it damaged.
    case verificationFailed
    case cancelled
    case failed

    var message: String {
        switch self {
        case .notConnected: "Connect to the diffuser first, then try again."
        case .connectionLost: "The connection was lost during the update. The diffuser keeps its current firmware."
        case .timedOut: "The diffuser stopped responding during the update."
        case .rejected: "The diffuser couldn't accept this update."
        case .verificationFailed: "The update was damaged on the way. The diffuser keeps its current firmware."
        case .cancelled: "Update cancelled. The diffuser keeps its current firmware."
        case .failed: "The update couldn't be completed."
        }
    }
}

/// The rules for moving between firmware update states. Anything not listed
/// here is refused, so the screen can't, for example, start a second update
/// while one is running.
///
///     idle, upToDate, available, completed, failed ──check──▶ checking
///     checking ──foundUpdate──▶ available     checking ──foundNothing──▶ upToDate
///     available ──start──▶ preparing ──prepared──▶ transferring ──transferFinished──▶ verifying
///     transferring ──progress──▶ transferring
///     verifying ──verified──▶ completed
///     checking, preparing, transferring, verifying ──fail──▶ failed
///     preparing, transferring, verifying ──cancel──▶ failed(cancelled)
///     any ──reset──▶ idle
struct FirmwareUpdateMachine: Equatable, Sendable {
    enum Event: Equatable, Sendable {
        case check
        case foundUpdate(version: String)
        case foundNothing
        case start
        case prepared
        case progress(Double)
        case transferFinished
        case verified(version: String)
        case fail(FirmwareUpdateError)
        case cancel
        case reset
    }

    private(set) var state: FirmwareUpdateState = .idle

    /// Moves to the next state. Returns false, changing nothing, if `event` isn't allowed now.
    @discardableResult
    mutating func handle(_ event: Event) -> Bool {
        guard let next = Self.next(from: state, on: event) else { return false }
        state = next
        return true
    }

    static func next(from state: FirmwareUpdateState, on event: Event) -> FirmwareUpdateState? {
        switch (state, event) {
        case (_, .reset):
            return .idle
        case (.idle, .check), (.upToDate, .check), (.available, .check), (.completed, .check), (.failed, .check):
            return .checking
        case (.checking, .foundUpdate(let version)):
            return .available(version: version)
        case (.checking, .foundNothing):
            return .upToDate
        case (.available, .start):
            return .preparing
        case (.preparing, .prepared):
            return .transferring(progress: 0)
        case (.transferring, .progress(let progress)):
            return .transferring(progress: min(max(progress, 0), 1))
        case (.transferring, .transferFinished):
            return .verifying
        case (.verifying, .verified(let version)):
            return .completed(version: version)
        case (.checking, .fail(let error)), (.preparing, .fail(let error)),
             (.transferring, .fail(let error)), (.verifying, .fail(let error)):
            return .failed(error)
        case (.preparing, .cancel), (.transferring, .cancel), (.verifying, .cancel):
            return .failed(.cancelled)
        default:
            return nil
        }
    }
}

/// A firmware file and its checksum.
struct FirmwareImage: Equatable, Sendable {
    let version: String
    let data: Data
    /// CRC-32 (the common IEEE variant) of `data`. The diffuser compares it with
    /// the bytes it received before installing them.
    let checksum: UInt32

    init(version: String, data: Data) {
        self.version = version
        self.data = data
        checksum = Self.crc32(data)
    }

    static func crc32(_ bytes: some Sequence<UInt8>) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in bytes {
            crc ^= UInt32(byte)
            for _ in 0..<8 {
                crc = (crc & 1) == 1 ? (crc >> 1) ^ 0xEDB8_8320 : crc >> 1
            }
        }
        return crc ^ 0xFFFF_FFFF
    }
}

enum FirmwareVersion {
    /// Whether `candidate` is a later version than `current`, comparing dotted
    /// numbers ("1.10.0" is later than "1.9.2"). A current version that isn't a
    /// version number, such as "Unknown", counts as older than any real one.
    static func isNewer(_ candidate: String, than current: String) -> Bool {
        let new = numbers(in: candidate)
        let old = numbers(in: current)
        guard !new.isEmpty else { return false }
        guard !old.isEmpty else { return true }
        for index in 0..<max(new.count, old.count) {
            let a = index < new.count ? new[index] : 0
            let b = index < old.count ? old[index] : 0
            if a != b { return a > b }
        }
        return false
    }

    private static func numbers(in version: String) -> [Int] {
        let parts = version.split(separator: ".")
        let numbers = parts.compactMap { Int($0) }
        return numbers.count == parts.count ? numbers : []
    }
}

/// Where firmware updates come from.
@MainActor
protocol FirmwareSource {
    /// The newest firmware for `diffuser`, or nil if there is none.
    func latestFirmware(for diffuser: Diffuser) async throws -> FirmwareImage?
}

/// PLACEHOLDER: offers a made-up update for the Demo Diffuser only. Real
/// diffusers need firmware from the manufacturer, usually downloaded from
/// their server; replace this once that is known.
struct PlaceholderFirmwareSource: FirmwareSource {
    static let demoVersion = "1.1.0"
    /// 96 KB of made-up firmware.
    static let demoImage = FirmwareImage(
        version: demoVersion,
        data: Data((0..<98_304).map { UInt8(truncatingIfNeeded: $0 &* 31 &+ 7) })
    )

    var checkDelay: Duration = .milliseconds(600)

    func latestFirmware(for diffuser: Diffuser) async throws -> FirmwareImage? {
        try await Task.sleep(for: checkDelay)
        return diffuser.isDemo ? Self.demoImage : nil
    }
}
