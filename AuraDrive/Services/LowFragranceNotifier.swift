import Foundation
import UserNotifications

/// Told by the store when a diffuser's fragrance drops to the low level.
@MainActor
protocol FragranceAlerting: AnyObject {
    func fragranceBecameLow(for diffuser: Diffuser)
}

/// Shows a notification when a cartridge is running low, if the user has
/// turned alerts on in Settings.
@MainActor
final class LowFragranceNotifier: FragranceAlerting {
    static let enabledKey = "lowFragranceAlertsEnabled"

    private let defaults: UserDefaults
    private let foregroundPresenter = ForegroundNotificationPresenter()

    init(defaults: UserDefaults) {
        self.defaults = defaults
        // Without this, iOS hides notifications while the app is open.
        UNUserNotificationCenter.current().delegate = foregroundPresenter
    }

    func fragranceBecameLow(for diffuser: Diffuser) {
        guard defaults.bool(forKey: Self.enabledKey) else { return }

        let content = UNMutableNotificationContent()
        content.title = "Fragrance running low"
        content.body = "\(diffuser.name) has \(diffuser.fragrancePercent)% left. Replace the cartridge soon."
        content.sound = .default

        // One notification per diffuser: a newer one replaces the older one.
        let request = UNNotificationRequest(
            identifier: "lowFragrance-\(diffuser.id.uuidString)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    /// Asks iOS for permission to show notifications. Returns whether it was given.
    static func requestPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
                continuation.resume(returning: granted)
            }
        }
    }
}

private final class ForegroundNotificationPresenter: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
