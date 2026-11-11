import Foundation

/// Saves the user's diffusers on the phone so they are still there next launch.
struct DiffuserPersistence {
    static let storageKey = "savedDiffusers"

    let defaults: UserDefaults

    func load() -> [Diffuser] {
        guard let data = defaults.data(forKey: Self.storageKey) else { return [] }
        return (try? JSONDecoder().decode([Diffuser].self, from: data)) ?? []
    }

    func save(_ diffusers: [Diffuser]) {
        if let data = try? JSONEncoder().encode(diffusers) {
            defaults.set(data, forKey: Self.storageKey)
        }
    }
}

enum StorageKey {
    static let hasCompletedOnboarding = "hasCompletedOnboarding"
}
