import Foundation
import Testing
@testable import AuraDrive

struct FirmwareUpdateMachineTests {
    @Test func aSuccessfulUpdateGoesThroughEveryStep() {
        var machine = FirmwareUpdateMachine()
        let steps: [(FirmwareUpdateMachine.Event, FirmwareUpdateState)] = [
            (.check, .checking),
            (.foundUpdate(version: "2.0"), .available(version: "2.0")),
            (.start, .preparing),
            (.prepared, .transferring(progress: 0)),
            (.progress(0.5), .transferring(progress: 0.5)),
            (.progress(1), .transferring(progress: 1)),
            (.transferFinished, .verifying),
            (.verified(version: "2.0"), .completed(version: "2.0")),
        ]
        for (event, expected) in steps {
            let accepted = machine.handle(event)
            #expect(accepted, "\(event) was refused")
            #expect(machine.state == expected)
        }
    }

    @Test func nothingNewMeansUpToDate() {
        var machine = FirmwareUpdateMachine()
        machine.handle(.check)
        machine.handle(.foundNothing)
        #expect(machine.state == .upToDate)
        let accepted1 = machine.handle(.check)
        #expect(accepted1)
    }

    @Test func stepsOutOfOrderAreRefused() {
        var machine = FirmwareUpdateMachine()
        let accepted2 = machine.handle(.start)
        #expect(!accepted2)
        let accepted3 = machine.handle(.progress(0.3))
        #expect(!accepted3)
        let accepted4 = machine.handle(.verified(version: "2.0"))
        #expect(!accepted4)
        #expect(machine.state == .idle)

        machine.handle(.check)
        machine.handle(.foundUpdate(version: "2.0"))
        machine.handle(.start)
        machine.handle(.prepared)
        // No second update or new check while one is being sent.
        let accepted5 = machine.handle(.start)
        #expect(!accepted5)
        let accepted6 = machine.handle(.check)
        #expect(!accepted6)
        #expect(machine.state == .transferring(progress: 0))
    }

    @Test func failingOrCancellingKeepsTheReason() {
        var machine = FirmwareUpdateMachine()
        machine.handle(.check)
        machine.handle(.foundUpdate(version: "2.0"))
        machine.handle(.start)
        machine.handle(.prepared)
        machine.handle(.cancel)
        #expect(machine.state == .failed(.cancelled))

        machine.handle(.check)
        machine.handle(.foundUpdate(version: "2.0"))
        machine.handle(.start)
        machine.handle(.fail(.connectionLost))
        #expect(machine.state == .failed(.connectionLost))
        #expect(!machine.state.isInProgress)
    }

    @Test func progressStaysBetweenZeroAndOne() {
        var machine = FirmwareUpdateMachine()
        machine.handle(.check)
        machine.handle(.foundUpdate(version: "2.0"))
        machine.handle(.start)
        machine.handle(.prepared)
        machine.handle(.progress(1.7))
        #expect(machine.state == .transferring(progress: 1))
        machine.handle(.progress(-1))
        #expect(machine.state == .transferring(progress: 0))
    }

    @Test func resetAlwaysReturnsToIdle() {
        var machine = FirmwareUpdateMachine()
        machine.handle(.check)
        let accepted7 = machine.handle(.reset)
        #expect(accepted7)
        #expect(machine.state == .idle)
    }

    @Test func onlyTheMiddleStepsCountAsInProgress() {
        #expect(FirmwareUpdateState.preparing.isInProgress)
        #expect(FirmwareUpdateState.transferring(progress: 0.2).isInProgress)
        #expect(FirmwareUpdateState.verifying.isInProgress)
        #expect(!FirmwareUpdateState.available(version: "1").isInProgress)
        #expect(!FirmwareUpdateState.completed(version: "1").isInProgress)
    }
}

struct FirmwareImageTests {
    @Test func checksumIsStandardCRC32() {
        // The standard check value for CRC-32/IEEE.
        #expect(FirmwareImage.crc32(Array("123456789".utf8)) == 0xCBF4_3926)
        #expect(FirmwareImage(version: "1", data: Data()).checksum == 0)
    }

    @Test func versionsCompareNumberByNumber() {
        #expect(FirmwareVersion.isNewer("1.10.0", than: "1.9.2"))
        #expect(FirmwareVersion.isNewer("2.0", than: "1.99.99"))
        #expect(FirmwareVersion.isNewer("1.0.1", than: "1.0"))
        #expect(!FirmwareVersion.isNewer("1.0", than: "1.0.0"))
        #expect(!FirmwareVersion.isNewer("1.2.0", than: "1.3.0"))
        #expect(FirmwareVersion.isNewer("1.0.0", than: "Unknown"))
        #expect(!FirmwareVersion.isNewer("beta", than: "1.0.0"))
    }
}
