import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var workoutStore: WorkoutStore
    @State private var isInitialDataLoaded = false
    
    var body: some View {
        ZStack {
            if appState.isCheckingAuth {
                // Loading/splash screen while checking auth
                SplashView()
                    .transition(.opacity)
            } else if !appState.hasCompletedOnboarding {
                // Authenticated but hasn't completed onboarding
                OnboardingContainerView()
                    .transition(.opacity)
            } else {
                // Authenticated and onboarded - show main app
                MainAppView()
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
        }
        .animation(.easeInOut(duration: 0.5), value: appState.isCheckingAuth)
        .animation(.easeInOut(duration: 0.5), value: appState.hasCompletedOnboarding)
        .task {
            // Pull data from Supabase on app launch if authenticated
            if appState.isAuthenticated && !isInitialDataLoaded {
                await DataSyncService.shared.pullAllData(
                    into: appState,
                    workoutStore: workoutStore
                )
                isInitialDataLoaded = true
            }
        }
    }
}

// MARK: - Splash View

struct SplashView: View {
    let neonPurple = Color(red: 0.6, green: 0.3, blue: 1.0)
    
    var body: some View {
        ZStack {
            Color(red: 0.02, green: 0.02, blue: 0.02)
                .ignoresSafeArea()
            
            VStack(spacing: 20) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [neonPurple, neonPurple.opacity(0.6)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .shadow(color: neonPurple.opacity(0.6), radius: 20)
                
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    .scaleEffect(1.2)
            }
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AppState())
        .environmentObject(WorkoutStore())
}
