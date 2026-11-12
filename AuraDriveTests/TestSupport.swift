import Foundation
@testable import AuraDrive

/// Waits until `condition` is true, checking every 10 ms. Returns false on timeout.
@MainActor
func waitUntil(timeout: Duration = .seconds(3), _ condition: () -> Bool) async -> Bool {
    let clock = ContinuousClock()
    let deadline = clock.now + timeout
    while !condition() {
        if clock.now >= deadline { return false }
        try? await Task.sleep(for: .milliseconds(10))
    }
    return true
}

/// Records the events a service reports.
@MainActor
final class EventRecorder {
    private(set) var events: [DiffuserServiceEvent] = []

    func record(_ event: DiffuserServiceEvent) {
        events.append(event)
    }
}
