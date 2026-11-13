import Foundation

/// PLACEHOLDER byte format, used until the manufacturer's protocol document
/// arrives. Replace this file with a codec for the real format.
///
/// Every message is one frame:
///
///     A5 | opcode | payload length | payload… | checksum
///
/// The checksum is the XOR of the opcode, the length and every payload byte.
///
/// | Opcode | Direction    | Meaning              | Payload                                   |
/// |--------|--------------|----------------------|-------------------------------------------|
/// | 01     | to diffuser  | Power                | 1 byte: 0 off, 1 on                       |
/// | 02     | to diffuser  | Intensity            | 1 byte: 1–5                               |
/// | 03     | to diffuser  | Interval mode        | on/off, run seconds (2 bytes), pause (2)  |
/// | 04     | to diffuser  | Cartridge replaced   | none                                      |
/// | 10     | to diffuser  | Ask for status       | none                                      |
/// | 11     | to diffuser  | Ask for firmware     | none                                      |
/// | 20     | to diffuser  | Begin update         | size (4), CRC-32 (4), version (UTF-8)     |
/// | 21     | to diffuser  | Firmware piece       | offset (4), up to 128 bytes               |
/// | 22     | to diffuser  | Finish update        | none                                      |
/// | 23     | to diffuser  | Abandon update       | none                                      |
/// | 81     | from         | Status               | on/off, intensity, fragrance 0–100 %      |
/// | 82     | from         | Firmware version     | UTF-8 text                                |
/// | 90     | from         | Done                 | opcode of the command                     |
/// | 91     | from         | Refused              | opcode of the command, error code         |
///
/// Numbers of two or four bytes are big-endian. Every firmware message is
/// answered with Done or Refused.
struct PlaceholderDiffuserCodec: DiffuserCodec {
    static let header: UInt8 = 0xA5
    static let firmwareChunkSize = 128
    static let maxVersionLength = 32

    var maxFirmwareChunkSize: Int { Self.firmwareChunkSize }

    enum Opcode {
        static let power: UInt8 = 0x01
        static let intensity: UInt8 = 0x02
        static let interval: UInt8 = 0x03
        static let resetFragrance: UInt8 = 0x04
        static let status: UInt8 = 0x10
        static let firmwareVersion: UInt8 = 0x11
        static let firmwareBegin: UInt8 = 0x20
        static let firmwareChunk: UInt8 = 0x21
        static let firmwareFinish: UInt8 = 0x22
        static let firmwareAbort: UInt8 = 0x23
        static let statusReply: UInt8 = 0x81
        static let firmwareVersionReply: UInt8 = 0x82
        static let acknowledged: UInt8 = 0x90
        static let rejected: UInt8 = 0x91
    }

    // MARK: App side

    func encode(_ request: DiffuserRequest) throws -> Data {
        switch request {
        case .command(.setPower(let isOn)):
            return frame(Opcode.power, [isOn ? 1 : 0])
        case .command(.setIntensity(let level)):
            guard Diffuser.intensityRange.contains(level) else { throw DiffuserCodecError.valueOutOfRange }
            return frame(Opcode.intensity, [UInt8(level)])
        case .command(.setInterval(let interval)):
            guard let run = UInt16(exactly: interval.runSeconds), run > 0,
                  let pause = UInt16(exactly: interval.pauseSeconds), pause > 0 else {
                throw DiffuserCodecError.valueOutOfRange
            }
            return frame(Opcode.interval, [interval.isEnabled ? 1 : 0] + Self.bytes(run) + Self.bytes(pause))
        case .command(.resetFragranceLevel):
            return frame(Opcode.resetFragrance, [])
        case .status:
            return frame(Opcode.status, [])
        case .firmwareVersion:
            return frame(Opcode.firmwareVersion, [])
        case .firmwareUpdateBegin(let size, let checksum, let version):
            let versionBytes = Array(version.utf8)
            guard let size32 = UInt32(exactly: size), size32 > 0,
                  !versionBytes.isEmpty, versionBytes.count <= Self.maxVersionLength else {
                throw DiffuserCodecError.valueOutOfRange
            }
            return frame(Opcode.firmwareBegin, Self.bytes(size32) + Self.bytes(checksum) + versionBytes)
        case .firmwareChunk(let offset, let bytes):
            guard let offset32 = UInt32(exactly: offset),
                  (1...Self.firmwareChunkSize).contains(bytes.count) else {
                throw DiffuserCodecError.valueOutOfRange
            }
            return frame(Opcode.firmwareChunk, Self.bytes(offset32) + [UInt8](bytes))
        case .firmwareUpdateFinish:
            return frame(Opcode.firmwareFinish, [])
        case .firmwareUpdateAbort:
            return frame(Opcode.firmwareAbort, [])
        }
    }

    func decodeMessage(_ data: Data) throws -> DiffuserMessage {
        let (opcode, payload) = try unframe(data)
        switch opcode {
        case Opcode.statusReply:
            guard payload.count == 3, payload[0] <= 1,
                  Diffuser.intensityRange.contains(Int(payload[1])), payload[2] <= 100 else {
                throw DiffuserCodecError.invalidPayload
            }
            return .status(DiffuserStatus(
                isOn: payload[0] == 1,
                intensity: Int(payload[1]),
                fragranceLevel: Double(payload[2]) / 100
            ))
        case Opcode.firmwareVersionReply:
            guard let version = String(bytes: payload, encoding: .utf8), !version.isEmpty else {
                throw DiffuserCodecError.invalidPayload
            }
            return .firmwareVersion(version)
        case Opcode.acknowledged:
            guard payload.count == 1, let kind = Self.kind(forOpcode: payload[0]) else {
                throw DiffuserCodecError.invalidPayload
            }
            return .acknowledged(kind)
        case Opcode.rejected:
            guard payload.count == 2, let kind = Self.kind(forOpcode: payload[0]) else {
                throw DiffuserCodecError.invalidPayload
            }
            return .rejected(kind, code: payload[1])
        default:
            throw DiffuserCodecError.unknownOpcode(opcode)
        }
    }

    // MARK: Diffuser side (used by the mock diffuser and the tests)

    func decodeRequest(_ data: Data) throws -> DiffuserRequest {
        let (opcode, payload) = try unframe(data)
        switch opcode {
        case Opcode.power:
            guard payload.count == 1, payload[0] <= 1 else { throw DiffuserCodecError.invalidPayload }
            return .command(.setPower(payload[0] == 1))
        case Opcode.intensity:
            guard payload.count == 1, Diffuser.intensityRange.contains(Int(payload[0])) else {
                throw DiffuserCodecError.invalidPayload
            }
            return .command(.setIntensity(Int(payload[0])))
        case Opcode.interval:
            guard payload.count == 5, payload[0] <= 1 else { throw DiffuserCodecError.invalidPayload }
            return .command(.setInterval(IntervalSettings(
                isEnabled: payload[0] == 1,
                runSeconds: Int(payload[1]) << 8 | Int(payload[2]),
                pauseSeconds: Int(payload[3]) << 8 | Int(payload[4])
            )))
        case Opcode.resetFragrance:
            guard payload.isEmpty else { throw DiffuserCodecError.invalidPayload }
            return .command(.resetFragranceLevel)
        case Opcode.status:
            guard payload.isEmpty else { throw DiffuserCodecError.invalidPayload }
            return .status
        case Opcode.firmwareVersion:
            guard payload.isEmpty else { throw DiffuserCodecError.invalidPayload }
            return .firmwareVersion
        case Opcode.firmwareBegin:
            guard payload.count > 8,
                  let version = String(bytes: payload[8...], encoding: .utf8) else {
                throw DiffuserCodecError.invalidPayload
            }
            return .firmwareUpdateBegin(
                size: Int(Self.uint32(payload, at: 0)),
                checksum: Self.uint32(payload, at: 4),
                version: version
            )
        case Opcode.firmwareChunk:
            guard payload.count > 4, payload.count - 4 <= Self.firmwareChunkSize else {
                throw DiffuserCodecError.invalidPayload
            }
            return .firmwareChunk(offset: Int(Self.uint32(payload, at: 0)), bytes: Data(payload[4...]))
        case Opcode.firmwareFinish:
            guard payload.isEmpty else { throw DiffuserCodecError.invalidPayload }
            return .firmwareUpdateFinish
        case Opcode.firmwareAbort:
            guard payload.isEmpty else { throw DiffuserCodecError.invalidPayload }
            return .firmwareUpdateAbort
        default:
            throw DiffuserCodecError.unknownOpcode(opcode)
        }
    }

    func encodeMessage(_ message: DiffuserMessage) -> Data {
        switch message {
        case .status(let status):
            frame(Opcode.statusReply, [
                status.isOn ? 1 : 0,
                UInt8(clamping: status.intensity),
                UInt8(clamping: Int((status.fragranceLevel * 100).rounded())),
            ])
        case .firmwareVersion(let version):
            frame(Opcode.firmwareVersionReply, Array(version.utf8.prefix(255)))
        case .acknowledged(let kind):
            frame(Opcode.acknowledged, [Self.opcode(for: kind)])
        case .rejected(let kind, let code):
            frame(Opcode.rejected, [Self.opcode(for: kind), code])
        }
    }

    // MARK: Framing

    static func checksum(opcode: UInt8, payload: [UInt8]) -> UInt8 {
        payload.reduce(opcode ^ UInt8(payload.count), ^)
    }

    private func frame(_ opcode: UInt8, _ payload: [UInt8]) -> Data {
        Data([Self.header, opcode, UInt8(payload.count)] + payload + [Self.checksum(opcode: opcode, payload: payload)])
    }

    private func unframe(_ data: Data) throws -> (opcode: UInt8, payload: [UInt8]) {
        let bytes = [UInt8](data)
        guard bytes.count >= 4 else { throw DiffuserCodecError.frameTooShort }
        guard bytes[0] == Self.header else { throw DiffuserCodecError.badHeader }
        let length = Int(bytes[2])
        guard bytes.count == 4 + length else { throw DiffuserCodecError.lengthMismatch }
        let payload = Array(bytes[3..<(3 + length)])
        guard Self.checksum(opcode: bytes[1], payload: payload) == bytes[bytes.count - 1] else {
            throw DiffuserCodecError.badChecksum
        }
        return (bytes[1], payload)
    }

    private static func bytes(_ value: UInt16) -> [UInt8] {
        [UInt8(value >> 8), UInt8(value & 0xFF)]
    }

    private static func bytes(_ value: UInt32) -> [UInt8] {
        [UInt8(value >> 24), UInt8((value >> 16) & 0xFF), UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF)]
    }

    private static func uint32(_ bytes: [UInt8], at index: Int) -> UInt32 {
        UInt32(bytes[index]) << 24 | UInt32(bytes[index + 1]) << 16
            | UInt32(bytes[index + 2]) << 8 | UInt32(bytes[index + 3])
    }

    private static func opcode(for kind: DiffuserRequest.Kind) -> UInt8 {
        switch kind {
        case .power: Opcode.power
        case .intensity: Opcode.intensity
        case .interval: Opcode.interval
        case .resetFragrance: Opcode.resetFragrance
        case .status: Opcode.status
        case .firmwareVersion: Opcode.firmwareVersion
        case .firmwareBegin: Opcode.firmwareBegin
        case .firmwareChunk: Opcode.firmwareChunk
        case .firmwareFinish: Opcode.firmwareFinish
        case .firmwareAbort: Opcode.firmwareAbort
        }
    }

    private static func kind(forOpcode opcode: UInt8) -> DiffuserRequest.Kind? {
        switch opcode {
        case Opcode.power: .power
        case Opcode.intensity: .intensity
        case Opcode.interval: .interval
        case Opcode.resetFragrance: .resetFragrance
        case Opcode.status: .status
        case Opcode.firmwareVersion: .firmwareVersion
        case Opcode.firmwareBegin: .firmwareBegin
        case Opcode.firmwareChunk: .firmwareChunk
        case Opcode.firmwareFinish: .firmwareFinish
        case Opcode.firmwareAbort: .firmwareAbort
        default: nil
        }
    }
}
