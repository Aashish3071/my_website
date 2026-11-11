import SwiftUI

@main
struct AuraDriveApp: App {
    @State private var store: DiffuserStore

    init() {
        let defaults = UserDefaults.standard
        let isUITesting = ProcessInfo.processInfo.arguments.contains(LaunchArgument.uiTesting)
        if isUITesting {
            // UI tests always start from a clean first launch.
            defaults.removeObject(forKey: StorageKey.hasCompletedOnboarding)
            defaults.removeObject(forKey: DiffuserPersistence.storageKey)
            defaults.removeObject(forKey: SimulatedDiffuserService.storageKey)
        }
        let service = SimulatedDiffuserService(
            defaults: defaults,
            responseDelay: isUITesting ? .milliseconds(50) : .milliseconds(500)
        )
        _store = State(
            initialValue: DiffuserStore(service: service, persistence: DiffuserPersistence(defaults: defaults))
        )
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
        }
    }
}
