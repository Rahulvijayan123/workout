import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        ZStack {
            if appState.hasCompletedOnboarding {
                MainAppView()
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
            } else {
                OnboardingContainerView()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.5), value: appState.hasCompletedOnboarding)
    }
}

#Preview {
    ContentView()
        .environmentObject(AppState())
}
