import Foundation

/// A message from the app to the diffuser.
enum DiffuserRequest: Equatable, Sendable {
    case command(DiffuserCommand)
    case status
    case firmwareVersion

    enum Kind: Hashable, Sendable {
        case power, intensity, interval, resetFragrance, status, firmwareVersion
    }

    var kind: Kind {
        switch self {
        case .command(.setPower): .power
        case .command(.setIntensity): .intensity
        case .command(.setInterval): .interval
        case .command(.resetFragranceLevel): .resetFragrance
        case .status: .status
        case .firmwareVersion: .firmwareVersion
        }
    }
}

/// A message from the diffuser to the app.
enum DiffuserMessage: Equatable, Sendable {
    /// The diffuser's current state. Sent in reply to `.status`, and may also
    /// be sent unasked when something changes on the device.
    case status(DiffuserStatus)
    case firmwareVersion(String)
    /// The command was carried out.
    case acknowledged(DiffuserRequest.Kind)
    /// The command was refused. The code's meaning comes from the protocol document.
    case rejected(DiffuserRequest.Kind, code: UInt8)

    /// Whether this message is the reply to a request of `kind`.
    func answers(_ kind: DiffuserRequest.Kind) -> Bool {
        switch self {
        case .status: kind == .status
        case .firmwareVersion: kind == .firmwareVersion
        case .acknowledged(let answered), .rejected(let answered, _): answered == kind
        }
    }
}

/// Turns requests into the bytes the diffuser expects, and its bytes back
/// into messages. Swapping the byte format means writing a new codec; nothing
/// else changes.
protocol DiffuserCodec: Sendable {
    func encode(_ request: DiffuserRequest) throws -> Data
    func decodeMessage(_ data: Data) throws -> DiffuserMessage
}

enum DiffuserCodecError: Error, Equatable {
    case frameTooShort
    case badHeader
    case lengthMismatch
    case badChecksum
    case unknownOpcode(UInt8)
    case invalidPayload
    /// A value can't be sent, for example an intensity outside 1–5.
    case valueOutOfRange
}
