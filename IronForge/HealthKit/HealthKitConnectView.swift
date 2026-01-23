import SwiftUI
import SwiftData

struct HealthKitConnectView: View {
    let onContinue: () -> Void
    
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \DailyBiometrics.date, order: .reverse) private var cachedBiometrics: [DailyBiometrics]
    
    @StateObject private var viewModel: ViewModel
    
    let neonPurple = Color(red: 0.6, green: 0.3, blue: 1.0)
    
    init(
        onContinue: @escaping () -> Void,
        healthKitService: HealthKitService = HealthKitService()
    ) {
        self.onContinue = onContinue
        _viewModel = StateObject(wrappedValue: ViewModel(healthKit: healthKitService))
    }
    
    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 24) {
                // Header icon
                header
                    .padding(.top, 20)
                
                // Title
                VStack(spacing: 10) {
                    Text("Connect Apple Health")
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    
                    Text("We read sleep, HRV, resting heart rate, and activity to personalize training readiness.")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white.opacity(0.5))
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                    
                    Text("Works without this — connect later.")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.35))
                }
                .padding(.horizontal, 10)
                
                // Readiness preview
                readinessCard
                
                // Selection toggles
                if viewModel.isHealthKitAvailable {
                    selectionCards
                } else {
                    unavailableCard
                }
                
                // Permission results
                if let result = viewModel.authorizationResult {
                    permissionResultCard(result: result)
                }
                
                // Buttons
                buttons
                
                Spacer(minLength: 40)
            }
            .padding(.horizontal, 20)
        }
        .onAppear {
            viewModel.refreshAvailability()
        }
        .alert("Health Access", isPresented: $viewModel.showAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.alertMessage ?? "Something went wrong.")
        }
    }
    
    // MARK: - UI
    
    private var header: some View {
        ZStack {
            ForEach(0..<3) { i in
                Circle()
                    .stroke(neonPurple.opacity(0.2 - Double(i) * 0.05), lineWidth: 2)
                    .frame(width: CGFloat(100 + i * 35), height: CGFloat(100 + i * 35))
                    .scaleEffect(viewModel.isAnimating ? 1.1 : 1.0)
                    .animation(
                        .easeInOut(duration: 2)
                        .repeatForever(autoreverses: true)
                        .delay(Double(i) * 0.2),
                        value: viewModel.isAnimating
                    )
            }
            
            Circle()
                .fill(neonPurple.opacity(0.15))
                .frame(width: 80, height: 80)
            
            Circle()
                .stroke(neonPurple.opacity(0.3), lineWidth: 2)
                .frame(width: 80, height: 80)
            
            Image(systemName: "heart.fill")
                .font(.system(size: 36, weight: .medium))
                .foregroundStyle(
                    LinearGradient(
                        colors: [neonPurple, neonPurple.opacity(0.7)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .shadow(color: neonPurple.opacity(0.5), radius: 12)
        }
        .onAppear {
            viewModel.isAnimating = true
        }
    }
    
    private var readinessCard: some View {
        let preview = viewModel.isHealthKitAvailable
            ? ReadinessPreview.fromCachedBiometrics(cachedBiometrics)
            : ReadinessPreview.demo
        
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("READINESS PREVIEW")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(2)
                    .foregroundColor(.white.opacity(0.4))
                
                Spacer()
                
                confidencePill(preview.readinessConfidence)
            }
            
            if preview.drivers.isEmpty {
                Text(viewModel.isHealthKitAvailable ? "Connect Apple Health to build your readiness baseline." : "Demo preview (Health data not available).")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white.opacity(0.5))
            } else {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(preview.drivers, id: \.self) { driver in
                        HStack(spacing: 8) {
                            Image(systemName: "sparkle")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(neonPurple)
                            Text(driver)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.white.opacity(0.6))
                        }
                    }
                }
            }
        }
        .padding(16)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(.ultraThinMaterial.opacity(0.4))
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.white.opacity(0.02))
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
    }
    
    private func confidencePill(_ confidence: ReadinessPreview.Confidence) -> some View {
        let (label, color): (String, Color) = {
            switch confidence {
            case .low: return ("LOW", .white.opacity(0.4))
            case .medium: return ("MED", neonPurple)
            case .high: return ("HIGH", .green)
            }
        }()
        
        return Text(label)
            .font(.system(size: 10, weight: .bold))
            .foregroundColor(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(color.opacity(0.15)))
            .overlay(Capsule().stroke(color.opacity(0.3), lineWidth: 1))
    }
    
    private var selectionCards: some View {
        VStack(alignment: .leading, spacing: 12) {
            metricSection(title: "RECOVERY") {
                metricToggle(metric: .sleepAnalysis, isOn: $viewModel.selection.sleepAnalysis)
                metricToggle(metric: .heartRateVariabilitySDNN, isOn: $viewModel.selection.heartRateVariabilitySDNN)
                metricToggle(metric: .restingHeartRate, isOn: $viewModel.selection.restingHeartRate)
            }
            
            metricSection(title: "ACTIVITY") {
                metricToggle(metric: .activeEnergyBurned, isOn: $viewModel.selection.activeEnergyBurned)
                metricToggle(metric: .stepCount, isOn: $viewModel.selection.stepCount)
            }
            
            metricSection(title: "OPTIONAL") {
                metricToggle(metric: .workouts, isOn: $viewModel.selection.workouts)
                Divider().overlay(Color.white.opacity(0.1))
                metricToggle(metric: .bodyMass, isOn: $viewModel.selection.bodyMass)
                metricToggle(metric: .bodyFatPercentage, isOn: $viewModel.selection.bodyFatPercentage)
            }
        }
    }
    
    private func metricSection<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 10, weight: .bold))
                .tracking(2)
                .foregroundColor(.white.opacity(0.4))
                .padding(.horizontal, 4)
            
            VStack(spacing: 0) {
                content()
            }
            .padding(.vertical, 4)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(.ultraThinMaterial.opacity(0.4))
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.white.opacity(0.02))
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
        }
    }
    
    private func metricToggle(metric: HealthKitMetric, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            HStack(spacing: 10) {
                Image(systemName: metric.systemImage)
                    .font(.system(size: 14, weight: .light))
                    .foregroundColor(neonPurple)
                    .frame(width: 24, height: 24)
                
                Text(metric.displayName)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
        }
        .tint(neonPurple)
    }
    
    private var unavailableCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Health data not available")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.white)
            
            Text("This device doesn't support HealthKit. You can still finish onboarding and use the app normally.")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white.opacity(0.5))
        }
        .padding(14)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(.ultraThinMaterial.opacity(0.4))
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.white.opacity(0.02))
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }
    
    private func permissionResultCard(result: HealthKitService.AuthorizationResult) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("PERMISSIONS")
                .font(.system(size: 10, weight: .bold))
                .tracking(2)
                .foregroundColor(.white.opacity(0.4))
            
            VStack(spacing: 8) {
                ForEach(result.requestedMetrics) { metric in
                    let state = result.stateByMetric[metric] ?? .notDetermined
                    HStack(spacing: 10) {
                        Image(systemName: metric.systemImage)
                            .font(.system(size: 13, weight: .light))
                            .foregroundColor(neonPurple)
                            .frame(width: 20)
                        
                        Text(metric.displayName)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.white.opacity(0.6))
                        
                        Spacer()
                        
                        permissionBadge(state: state)
                    }
                }
            }
            
            if !result.deniedMetrics.isEmpty {
                Text("You can change this later in Settings.")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.35))
                    .padding(.top, 4)
            }
        }
        .padding(14)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(.ultraThinMaterial.opacity(0.4))
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.white.opacity(0.02))
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }
    
    private func permissionBadge(state: HealthKitService.PermissionState) -> some View {
        let (text, color, icon): (String, Color, String) = {
            switch state {
            case .authorized:
                return ("OK", .green, "checkmark.circle.fill")
            case .denied:
                return ("Denied", .red.opacity(0.8), "xmark.circle.fill")
            case .notDetermined:
                return ("—", .white.opacity(0.4), "minus.circle")
            }
        }()
        
        return HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
            Text(text)
                .font(.system(size: 11, weight: .semibold))
        }
        .foregroundColor(color)
    }
    
    private var buttons: some View {
        VStack(spacing: 12) {
            if viewModel.isHealthKitAvailable {
                Button {
                    Task { await viewModel.connect(modelContext: modelContext) }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "heart.fill")
                            .font(.system(size: 14))
                        Text(viewModel.isRequesting ? "CONNECTING..." : "CONNECT")
                            .font(.system(size: 14, weight: .bold))
                            .tracking(1.5)
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .background(
                        ZStack {
                            RoundedRectangle(cornerRadius: 14)
                                .fill(neonPurple)
                            VStack {
                                LinearGradient(
                                    colors: [Color.white.opacity(0.25), Color.clear],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                                .frame(height: 1)
                                Spacer()
                            }
                        }
                    )
                    .cornerRadius(14)
                    .shadow(color: neonPurple.opacity(0.5), radius: 16, y: 6)
                }
                .disabled(viewModel.isRequesting || !viewModel.selection.hasAnySelected)
                .opacity(viewModel.isRequesting || !viewModel.selection.hasAnySelected ? 0.5 : 1)
            }
            
            Button {
                onContinue()
            } label: {
                Text("Not now")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white.opacity(0.4))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
        }
    }
}

// MARK: - ViewModel

extension HealthKitConnectView {
    @MainActor
    final class ViewModel: ObservableObject {
        private let healthKit: HealthKitService
        
        @Published var selection: HealthKitSelection = HealthKitSelection()
        @Published var authorizationResult: HealthKitService.AuthorizationResult?
        
        @Published var isRequesting: Bool = false
        @Published var isHealthKitAvailable: Bool = true
        
        @Published var showAlert: Bool = false
        @Published var alertMessage: String?
        
        @Published var isAnimating: Bool = false
        
        init(healthKit: HealthKitService) {
            self.healthKit = healthKit
            self.isHealthKitAvailable = healthKit.isAvailable()
        }
        
        func refreshAvailability() {
            isHealthKitAvailable = healthKit.isAvailable()
        }
        
        func connect(modelContext: ModelContext) async {
            guard isHealthKitAvailable else { return }
            guard selection.hasAnySelected else { return }
            
            isRequesting = true
            defer { isRequesting = false }
            
            do {
                let result = try await healthKit.requestAuthorization(selected: selection)
                authorizationResult = result
                
                let repo = DailyBiometricsRepository(modelContext: modelContext, healthKit: healthKit)
                await repo.refreshDailyBiometrics(lastNDays: 30)
            } catch {
                alertMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                showAlert = true
            }
        }
    }
}

#Preview {
    OnboardingContainerView()
        .environmentObject(AppState())
        .modelContainer(for: DailyBiometrics.self, inMemory: true)
}
