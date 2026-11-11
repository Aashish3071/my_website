import Foundation

/// A diffuser the user has added to the app, with its last known settings.
struct Diffuser: Identifiable, Codable, Equatable, Sendable {
    static let intensityRange = 1...5
    /// At or below this level the app warns that the cartridge is running out.
    static let lowFragranceThreshold = 0.15

    let id: UUID
    var name: String
    var firmwareVersion: String
    var isOn = false
    var intensity = 3
    var interval = IntervalSettings()
    /// Fraction of fragrance left, from 0 (empty) to 1 (full).
    var fragranceLevel = 1.0
    /// When the sleep timer will turn the diffuser off, if one is set.
    var sleepTimerEnd: Date?

    var isFragranceLow: Bool { fragranceLevel <= Self.lowFragranceThreshold }
    var fragrancePercent: Int { Int((fragranceLevel * 100).rounded()) }
}

/// Interval mode: the diffuser runs, pauses, and repeats.
struct IntervalSettings: Codable, Equatable, Sendable {
    static let secondsRange = 10...300
    static let secondsStep = 10

    var isEnabled = false
    var runSeconds = 30
    var pauseSeconds = 60
}

enum ConnectionState: Equatable, Sendable {
    case disconnected
    case connecting
    case connected
}

/// A diffuser found nearby that has not been added yet.
struct DiscoveredDiffuser: Identifiable, Equatable, Sendable {
    let id: UUID
    let name: String
    let firmwareVersion: String
}

/// Live values reported by the diffuser itself.
struct DiffuserStatus: Equatable, Sendable {
    var isOn: Bool
    var intensity: Int
    var fragranceLevel: Double
}

enum DiffuserCommand: Equatable, Sendable {
    case setPower(Bool)
    case setIntensity(Int)
    case setInterval(IntervalSettings)
    /// Sent after the user fits a new cartridge.
    case resetFragranceLevel
}
