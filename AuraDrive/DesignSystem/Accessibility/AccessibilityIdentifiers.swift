/// Stable identifiers for UI tests. This file is compiled into both the app and
/// the UI test target so the two never drift apart.
///
/// Identifiers are not read by VoiceOver; labels and hints are set separately.
enum AccessibilityID {
    enum Welcome {
        static let title = "welcome.title"
        static let getStartedButton = "welcome.getStarted"
    }

    enum DiffuserList {
        static let emptyAddButton = "diffuserList.emptyAdd"
        static let addButton = "diffuserList.add"
        static let settingsButton = "diffuserList.settings"
        static let row = "diffuserList.row"
    }

    enum AddDiffuser {
        static let result = "addDiffuser.result"
        static let cancelButton = "addDiffuser.cancel"
    }

    enum Control {
        static let powerToggle = "control.power"
        static let intensitySlider = "control.intensity"
        static let detailsButton = "control.details"
    }

    enum Details {
        static let nameField = "details.name"
        static let forgetButton = "details.forget"
        static let doneButton = "details.done"
    }

    enum Settings {
        static let doneButton = "settings.done"
    }
}

/// Launch arguments understood by the app.
enum LaunchArgument {
    /// Clears saved data so every UI test starts from a first launch.
    static let uiTesting = "-uiTesting"
}
