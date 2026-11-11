/// Stable identifiers for UI tests. This file is compiled into both the app and
/// the UI test target so the two never drift apart.
///
/// Identifiers are not read by VoiceOver; labels and hints are set separately.
enum AccessibilityID {
    enum Welcome {
        static let title = "welcome.title"
        static let getStartedButton = "welcome.getStarted"
    }
}
