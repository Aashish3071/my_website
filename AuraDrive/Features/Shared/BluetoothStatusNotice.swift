import SwiftUI
import UIKit

/// Explains why real diffusers can't be reached when Bluetooth is off or not
/// allowed. Shows nothing otherwise.
struct BluetoothStatusNotice: View {
    let availability: BluetoothAvailability

    @Environment(\.openURL) private var openURL

    static func isShown(for availability: BluetoothAvailability) -> Bool {
        availability == .poweredOff || availability == .unauthorized
    }

    var body: some View {
        switch availability {
        case .poweredOff:
            StatusBadge(kind: .warning, text: "Bluetooth is off. Turn it on in Control Centre to connect to your diffuser.")
        case .unauthorized:
            VStack(alignment: .leading, spacing: Spacing.s) {
                StatusBadge(kind: .warning, text: "AuraDrive isn't allowed to use Bluetooth, so it can't find your diffuser.")
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        openURL(url)
                    }
                }
                .buttonStyle(.secondary)
                .accessibilityHint("Opens AuraDrive's settings, where you can allow Bluetooth.")
            }
        case .unknown, .resetting, .unsupported, .poweredOn:
            EmptyView()
        }
    }
}

extension Diffuser {
    /// The built-in demo diffuser, which doesn't use Bluetooth.
    var isDemo: Bool { id == SimulatedDiffuserService.demoDiffuser.id }
}

#Preview("Bluetooth off") {
    List { BluetoothStatusNotice(availability: .poweredOff) }
}

#Preview("Not allowed") {
    List { BluetoothStatusNotice(availability: .unauthorized) }
}
