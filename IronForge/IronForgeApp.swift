import SwiftUI
import SwiftData

@main
struct IronForgeApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var workoutStore = WorkoutStore()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .environmentObject(workoutStore)
                .preferredColorScheme(.dark)
        }
        .modelContainer(for: DailyBiometrics.self)
    }
}

// MARK: - App State
@MainActor
class AppState: ObservableObject {
    @Published var hasCompletedOnboarding: Bool = false
    @Published var userProfile: UserProfile = UserProfile()
    @Published var isAuthenticated: Bool = false
    @Published var isCheckingAuth: Bool = true
    
    init() {
        // Check stored authentication state from SupabaseService
        isAuthenticated = SupabaseService.shared.isAuthenticated
        isCheckingAuth = false
        
        // Check if user has completed onboarding
        hasCompletedOnboarding = UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
        loadUserProfile()
    }
    
    func completeOnboarding() {
        hasCompletedOnboarding = true
        UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
        saveUserProfile()
        
        // Sync profile to Supabase after onboarding
        Task {
            try? await DataSyncService.shared.syncUserProfile(userProfile)
        }
    }
    
    func saveUserProfile() {
        if let encoded = try? JSONEncoder().encode(userProfile) {
            UserDefaults.standard.set(encoded, forKey: "userProfile")
        }
        
        // Sync profile to Supabase when saved
        if isAuthenticated {
            Task {
                try? await DataSyncService.shared.syncUserProfile(userProfile)
            }
        }
    }
    
    func loadUserProfile() {
        if let data = UserDefaults.standard.data(forKey: "userProfile"),
           let decoded = try? JSONDecoder().decode(UserProfile.self, from: data) {
            userProfile = decoded
        }
    }
    
    func signOut() {
        Task {
            try? await SupabaseService.shared.signOut()
            await MainActor.run {
                isAuthenticated = false
                hasCompletedOnboarding = false
                userProfile = UserProfile()
                UserDefaults.standard.set(false, forKey: "hasCompletedOnboarding")
            }
        }
    }
}
