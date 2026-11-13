import SwiftUI

/// Shows the welcome screen on first launch, then the list of diffusers.
struct RootView: View {
    @AppStorage(StorageKey.hasCompletedOnboarding) private var hasCompletedOnboarding = false
    var body: some View {
        NavigationStack {
            if hasCompletedOnboarding {
                DiffuserListView()
            } else {
                WelcomeView {
                    hasCompletedOnboarding = true
                }
            }
        }
        .showsStoreErrors()
    }
}

#Preview {
    RootView()
        .environment(DiffuserStore.preview())
}
