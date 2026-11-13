import Foundation
import Testing
@testable import AuraDrive

private let sampleRequests: [DiffuserRequest] = [
    .command(.setPower(true)),
    .command(.setPower(false)),
    .command(.setIntensity(1)),
    .command(.setIntensity(5)),
    .command(.setInterval(IntervalSettings(isEnabled: true, runSeconds: 30, pauseSeconds: 300))),
    .command(.setInterval(IntervalSettings(isEnabled: false, runSeconds: 10, pauseSeconds: 10))),
    .command(.resetFragranceLevel),
    .status,
    .firmwareVersion,
    .firmwareUpdateBegin(size: 98_304, checksum: 0xCBF4_3926, version: "1.1.0"),
    .firmwareChunk(offset: 0, bytes: Data([0x00, 0xFF, 0x7E])),
    .firmwareChunk(offset: 70_000, bytes: Data(repeating: 0xAB, count: 128)),
    .firmwareUpdateFinish,
    .firmwareUpdateAbort,
]

private let sampleMessages: [DiffuserMessage] = [
    .status(DiffuserStatus(isOn: true, intensity: 4, fragranceLevel: 0.62)),
    .status(DiffuserStatus(isOn: false, intensity: 1, fragranceLevel: 0)),
    .firmwareVersion("2.0.1"),
    .acknowledged(.intensity),
    .rejected(.power, code: 7),
]

struct PlaceholderDiffuserCodecTests {
    private let codec = PlaceholderDiffuserCodec()

    @Test func powerOnHasTheDocumentedBytes() throws {
        // Header, opcode 01, length 1, payload 01, checksum 01 ^ 01 ^ 01.
        #expect(try codec.encode(.command(.setPower(true))) == Data([0xA5, 0x01, 0x01, 0x01, 0x01]))
    }

    @Test func intervalUsesBigEndianSeconds() throws {
        let interval = IntervalSettings(isEnabled: true, runSeconds: 300, pauseSeconds: 10)
        let bytes = [UInt8](try codec.encode(.command(.setInterval(interval))))
        #expect(Array(bytes[3..<8]) == [0x01, 0x01, 0x2C, 0x00, 0x0A])
    }

    @Test(arguments: sampleRequests)
    func requestsSurviveARoundTrip(_ request: DiffuserRequest) throws {
        #expect(try codec.decodeRequest(codec.encode(request)) == request)
    }

    @Test(arguments: sampleMessages)
    func messagesSurviveARoundTrip(_ message: DiffuserMessage) throws {
        #expect(try codec.decodeMessage(codec.encodeMessage(message)) == message)
    }

    @Test func refusesValuesTheDiffuserCantTake() {
        #expect(throws: DiffuserCodecError.valueOutOfRange) {
            try codec.encode(.command(.setIntensity(9)))
        }
        #expect(throws: DiffuserCodecError.valueOutOfRange) {
            try codec.encode(.command(.setInterval(IntervalSettings(isEnabled: true, runSeconds: 70_000, pauseSeconds: 10))))
        }
    }

    @Test func refusesFirmwareMessagesThatDontFit() {
        #expect(throws: DiffuserCodecError.valueOutOfRange) {
            try codec.encode(.firmwareChunk(offset: 0, bytes: Data(repeating: 0, count: 129)))
        }
        #expect(throws: DiffuserCodecError.valueOutOfRange) {
            try codec.encode(.firmwareChunk(offset: 0, bytes: Data()))
        }
        #expect(throws: DiffuserCodecError.valueOutOfRange) {
            try codec.encode(.firmwareUpdateBegin(size: 10, checksum: 0, version: String(repeating: "9", count: 33)))
        }
        #expect(codec.maxFirmwareChunkSize == 128)
    }

    @Test func rejectsDamagedFrames() throws {
        var frame = [UInt8](try codec.encode(.command(.setIntensity(3))))
        frame[frame.count - 1] ^= 0xFF
        #expect(throws: DiffuserCodecError.badChecksum) {
            try codec.decodeRequest(Data(frame))
        }
        #expect(throws: DiffuserCodecError.badHeader) {
            try codec.decodeMessage(Data([0x00, 0x81, 0x00, 0x81]))
        }
        #expect(throws: DiffuserCodecError.frameTooShort) {
            try codec.decodeMessage(Data([0xA5, 0x81]))
        }
        #expect(throws: DiffuserCodecError.lengthMismatch) {
            try codec.decodeMessage(Data([0xA5, 0x81, 0x05, 0x00, 0x84]))
        }
        #expect(throws: DiffuserCodecError.unknownOpcode(0x7F)) {
            try codec.decodeMessage(Data([0xA5, 0x7F, 0x00, 0x7F]))
        }
    }

    @Test func rejectsImpossibleStatusValues() {
        let overfull = codec.encodeMessage(.status(DiffuserStatus(isOn: true, intensity: 3, fragranceLevel: 1.01)))
        #expect(throws: DiffuserCodecError.invalidPayload) {
            try codec.decodeMessage(overfull)
        }
    }

    @Test func repliesMatchTheirRequests() {
        #expect(DiffuserMessage.acknowledged(.power).answers(.power))
        #expect(!DiffuserMessage.acknowledged(.power).answers(.intensity))
        #expect(DiffuserMessage.rejected(.interval, code: 2).answers(.interval))
        #expect(DiffuserMessage.status(DiffuserStatus(isOn: true, intensity: 2, fragranceLevel: 0.5)).answers(.status))
        #expect(!DiffuserMessage.firmwareVersion("1").answers(.status))
    }
}
