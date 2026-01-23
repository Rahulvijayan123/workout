import SwiftUI
import SwiftData

/// Onboarding step wrapper; the v1 HealthKit integration lives in `HealthKitConnectView`.
struct HealthKitOnboardingView: View {
    let onContinue: () -> Void
    
    var body: some View {
        HealthKitConnectView(onContinue: onContinue)
    }
}

#Preview {
    ZStack {
        AnimatedMeshBackground()
        HealthKitOnboardingView(onContinue: {})
    }
    .modelContainer(for: DailyBiometrics.self, inMemory: true)
}
