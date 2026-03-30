import SwiftUI

struct RootView: View {
    @Environment(AuthRepository.self) private var authRepository

    var body: some View {
        Group {
            if authRepository.isAuthenticated {
                MainTabView()
            } else {
                SetupView()
            }
        }
        .animation(.easeInOut, value: authRepository.isAuthenticated)
    }
}
