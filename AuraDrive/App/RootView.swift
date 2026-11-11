import SwiftUI

/// Top-level container for the app's navigation.
/// Device pairing, the control screen and settings will be added here.
struct RootView: View {
    var body: some View {
        NavigationStack {
            WelcomeView()
        }
    }
}

#Preview {
    RootView()
}
