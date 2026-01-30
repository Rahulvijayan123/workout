import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var workoutStore: WorkoutStore
    @State private var isInitialDataLoaded = false
    
    var body: some View {
        ZStack {
            // Check for configuration errors first
            if !SupabaseConfig.isConfigured {
                ConfigurationErrorView()
                    .transition(.opacity)
            } else if appState.isCheckingAuth {
                // Loading/splash screen while checking auth
                SplashView()
                    .transition(.opacity)
            } else if !appState.isAuthenticated {
                // Not authenticated - show auth screen
                AuthContainerView()
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
        .animation(.easeInOut(duration: 0.5), value: appState.isAuthenticated)
        .animation(.easeInOut(duration: 0.5), value: appState.hasCompletedOnboarding)
        .task {
            // Pull data from Supabase on app launch if authenticated
            if SupabaseConfig.isConfigured && appState.isAuthenticated && !isInitialDataLoaded {
                await DataSyncService.shared.pullAllData(
                    into: appState,
                    workoutStore: workoutStore
                )
                isInitialDataLoaded = true
            }
        }
    }
}

// MARK: - Configuration Error View

struct ConfigurationErrorView: View {
    let neonPurple = Color(red: 0.6, green: 0.3, blue: 1.0)
    
    var body: some View {
        ZStack {
            Color(red: 0.02, green: 0.02, blue: 0.02)
                .ignoresSafeArea()
            
            VStack(spacing: 24) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.orange)
                
                Text("Configuration Error")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.white)
                
                VStack(alignment: .leading, spacing: 12) {
                    if let error = SupabaseConfig.loadError {
                        Text(error)
                            .font(.system(size: 14))
                            .foregroundColor(.white.opacity(0.8))
                            .multilineTextAlignment(.center)
                    } else if SupabaseConfig.anonKey.contains("PASTE_") {
                        Text("Secrets.plist contains placeholder values.\n\nPlease update with your actual Supabase credentials.")
                            .font(.system(size: 14))
                            .foregroundColor(.white.opacity(0.8))
                            .multilineTextAlignment(.center)
                    } else {
                        Text("Secrets.plist is missing or invalid.\n\nMake sure it's added to the Xcode project.")
                            .font(.system(size: 14))
                            .foregroundColor(.white.opacity(0.8))
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(.horizontal, 32)
                
                Text("Developer Instructions:")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(neonPurple)
                    .padding(.top, 16)
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("1. Add Secrets.plist to Xcode project")
                    Text("2. Ensure it's in 'Copy Bundle Resources'")
                    Text("3. Add valid Supabase URL and keys")
                }
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(.white.opacity(0.6))
            }
            .padding()
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
