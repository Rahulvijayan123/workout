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
class AppState: ObservableObject {
    @Published var hasCompletedOnboarding: Bool = false
    @Published var userProfile: UserProfile = UserProfile()
    
    init() {
        // Check if user has completed onboarding
        hasCompletedOnboarding = UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
        loadUserProfile()
    }
    
    func completeOnboarding() {
        hasCompletedOnboarding = true
        UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
        saveUserProfile()
    }
    
    func saveUserProfile() {
        if let encoded = try? JSONEncoder().encode(userProfile) {
            UserDefaults.standard.set(encoded, forKey: "userProfile")
        }
    }
    
    func loadUserProfile() {
        if let data = UserDefaults.standard.data(forKey: "userProfile"),
           let decoded = try? JSONDecoder().decode(UserProfile.self, from: data) {
            userProfile = decoded
        }
    }
}
