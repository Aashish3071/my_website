import SwiftUI

/// Shows the store's error message in an alert.
///
/// Apply it to the main screen and to the root of every sheet. Only the
/// frontmost screen shows the alert, so an error that happens while a panel is
/// open appears on top of that panel instead of waiting behind it.
private struct StoreErrorAlert: ViewModifier {
    @Environment(DiffuserStore.self) private var store
    @State private var hostID = UUID()

    func body(content: Content) -> some View {
        content
            .onAppear { store.registerAlertHost(hostID) }
            .onDisappear { store.unregisterAlertHost(hostID) }
            .alert("Something went wrong", isPresented: isShowingError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(store.errorMessage ?? "")
            }
    }

    private var isShowingError: Binding<Bool> {
        Binding(
            get: { store.showsError(in: hostID) },
            set: { isShown in
                if !isShown { store.errorMessage = nil }
            }
        )
    }
}

extension View {
    /// Shows errors from `DiffuserStore` in an alert when this screen is in front.
    func showsStoreErrors() -> some View {
        modifier(StoreErrorAlert())
    }
}
