import SwiftUI

/// Shows the welcome screen on first launch, then the list of diffusers.
struct RootView: View {
    @AppStorage(StorageKey.hasCompletedOnboarding) private var hasCompletedOnboarding = false
    @Environment(DiffuserStore.self) private var store

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
        .alert("Something went wrong", isPresented: isShowingError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(store.errorMessage ?? "")
        }
    }

    private var isShowingError: Binding<Bool> {
        Binding(
            get: { store.errorMessage != nil },
            set: { isShown in
                if !isShown { store.errorMessage = nil }
            }
        )
    }
}

#Preview {
    RootView()
        .environment(DiffuserStore.preview())
}
