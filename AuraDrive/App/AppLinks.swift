import Foundation

/// Contact details shown in Settings.
enum AppLinks {
    /// PLACEHOLDER: replace with the real support address before release.
    static let supportEmail = "support@example.com"

    static var supportEmailURL: URL? {
        URL(string: "mailto:\(supportEmail)?subject=AuraDrive%20support")
    }
}
