import SwiftUI

extension ConnectionState {
    var title: LocalizedStringKey {
        switch self {
        case .connected: "Connected"
        case .connecting: "Connecting"
        case .disconnected: "Not connected"
        case .reconnecting: "Reconnecting"
        }
    }

    var badgeKind: StatusBadge.Kind {
        switch self {
        case .connected: .success
        case .connecting, .disconnected, .reconnecting: .neutral
        }
    }
}
