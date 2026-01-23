import SwiftUI
import SwiftData

struct HealthKitConnectView: View {
    let onContinue: () -> Void
    
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \DailyBiometrics.date, order: .reverse) private var cachedBiometrics: [DailyBiometrics]
    
    @StateObject private var viewModel: ViewModel
    
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
                Spacer(minLength: 20)
                
                reactorCoreHeader
                
                // Typography updates
                VStack(spacing: 12) {
                    Text("BIOMETRIC SYNC")
                        .font(.system(size: 28, weight: .black, design: .default))
                        .tracking(3)
                        .foregroundColor(.ironTextPrimary)
                    
                    Text("We only read sleep, HRV, resting heart rate, and activity to personalize training readiness.")
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundColor(Color(red: 0.61, green: 0.64, blue: 0.69)) // Silver #9CA3AF
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                        .padding(.horizontal, 8)
                    
                    Text("Works without this — you can connect later.")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundColor(.ironTextTertiary.opacity(0.7))
                }
                
                if viewModel.isHealthKitAvailable {
                    selectionCards
                } else {
                    unavailableCard
                }
                
                if let result = viewModel.authorizationResult {
                    permissionResultCard(result: result)
                }
                
                buttons
                    .padding(.bottom, 8)
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
    
    // MARK: - Reactor Core Header (The "Wireframe Heart" in Glass Sphere)
    
    private var reactorCoreHeader: some View {
        ZStack {
            // Breathing concentric rings - thin 1px, varying opacities
            ForEach(0..<4) { i in
                Circle()
                    .stroke(
                        Color.ironPurple.opacity(0.15 - Double(i) * 0.03),
                        lineWidth: 1
                    )
                    .frame(width: CGFloat(110 + i * 35), height: CGFloat(110 + i * 35))
                    .scaleEffect(viewModel.breatheIn ? 1.08 : 0.95)
                    .opacity(viewModel.breatheIn ? 0.8 : 0.4)
                    .animation(
                        .easeInOut(duration: 3.0)
                            .repeatForever(autoreverses: true)
                            .delay(Double(i) * 0.15),
                        value: viewModel.breatheIn
                    )
            }
            
            // Glass Sphere container
            ZStack {
                // Base sphere with radial gradient (white -> transparent)
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color.white.opacity(0.08),
                                Color.white.opacity(0.03),
                                Color.clear
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: 55
                        )
                    )
                    .frame(width: 110, height: 110)
                
                // Sharp white reflection curve at top-left (lens effect)
                Circle()
                    .trim(from: 0.55, to: 0.75)
                    .stroke(
                        LinearGradient(
                            colors: [Color.white.opacity(0.4), Color.white.opacity(0.05)],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        style: StrokeStyle(lineWidth: 2, lineCap: .round)
                    )
                    .frame(width: 90, height: 90)
                    .rotationEffect(.degrees(-10))
                
                // Outer sphere border
                Circle()
                    .stroke(
                        LinearGradient(
                            colors: [Color.white.opacity(0.25), Color.white.opacity(0.05)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.5
                    )
                    .frame(width: 108, height: 108)
                
                // EKG Waveform Icon (medical imaging style)
                EKGWaveformIcon()
                    .frame(width: 60, height: 40)
            }
            .shadow(color: Color.ironPurpleGlow.opacity(0.4), radius: 30, x: 0, y: 10)
        }
        .onAppear {
            viewModel.breatheIn = true
            viewModel.isAnimating = true
        }
    }
    
    // MARK: - Selection Cards with Liquid Toggles
    
    private var selectionCards: some View {
        VStack(alignment: .leading, spacing: 14) {
            cyberMetricSection(title: "RECOVERY", metrics: [
                (.sleepAnalysis, $viewModel.selection.sleepAnalysis),
                (.heartRateVariabilitySDNN, $viewModel.selection.heartRateVariabilitySDNN),
                (.restingHeartRate, $viewModel.selection.restingHeartRate)
            ])
            
            cyberMetricSection(title: "ACTIVITY", metrics: [
                (.activeEnergyBurned, $viewModel.selection.activeEnergyBurned),
                (.stepCount, $viewModel.selection.stepCount)
            ])
            
            cyberMetricSection(title: "OPTIONAL", metrics: [
                (.workouts, $viewModel.selection.workouts),
                (.bodyMass, $viewModel.selection.bodyMass),
                (.bodyFatPercentage, $viewModel.selection.bodyFatPercentage)
            ], showDividerAfter: 0, isOptional: true)
        }
    }
    
    private func cyberMetricSection(
        title: String,
        metrics: [(HealthKitMetric, Binding<Bool>)],
        showDividerAfter: Int? = nil,
        isOptional: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header with purple accent line - dimmed for optional
            HStack(spacing: 8) {
                Rectangle()
                    .fill(isOptional ? Color.ironPurple.opacity(0.5) : Color.ironPurple)
                    .frame(width: 2, height: 12)
                    .cornerRadius(1)
                
                Text(title)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(isOptional ? .ironTextTertiary.opacity(0.6) : .ironTextTertiary)
                    .tracking(1.5)
            }
            .padding(.horizontal, 4)
            
            VStack(spacing: 0) {
                ForEach(Array(metrics.enumerated()), id: \.offset) { index, item in
                    liquidToggleRow(metric: item.0, isOn: item.1)
                    
                    // Etched glass divider between rows
                    if index < metrics.count - 1 {
                        etchedGlassDivider()
                    }
                    
                    // Optional divider after specific index
                    if let dividerIndex = showDividerAfter, index == dividerIndex {
                        etchedGlassDivider(isAccented: true)
                    }
                }
            }
            .padding(.vertical, 6)
            .liquidGlass()
        }
    }
    
    private func etchedGlassDivider(isAccented: Bool = false) -> some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [
                        Color.clear,
                        isAccented ? Color.ironPurple.opacity(0.3) : Color.white.opacity(0.12),
                        Color.clear
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(height: 1)
            .padding(.horizontal, 16)
    }
    
    private func liquidToggleRow(metric: HealthKitMetric, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 12) {
            Image(systemName: metric.systemImage)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.ironPurple)
                .frame(width: 28, height: 28)
            
            Text(metric.displayName)
                .font(.system(size: 16, weight: .medium, design: .rounded))
                .foregroundColor(.ironTextPrimary)
            
            Spacer()
            
            LiquidToggle(isOn: isOn)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
    }
    
    private var unavailableCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Health data not available")
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundColor(.ironTextPrimary)
            
            Text("This device doesn't support HealthKit. You can still finish onboarding and use the app normally.")
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundColor(.ironTextSecondary)
        }
        .padding(16)
        .liquidGlass()
    }
    
    private func permissionResultCard(result: HealthKitService.AuthorizationResult) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Rectangle()
                    .fill(Color.ironPurple)
                    .frame(width: 2, height: 12)
                    .cornerRadius(1)
                
                Text("PERMISSIONS")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(.ironTextTertiary)
                    .tracking(1.5)
            }
            
            VStack(spacing: 10) {
                ForEach(result.requestedMetrics) { metric in
                    let state = result.stateByMetric[metric] ?? .notDetermined
                    HStack(spacing: 12) {
                        Image(systemName: metric.systemImage)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.ironPurple)
                            .frame(width: 24)
                        
                        Text(metric.displayName)
                            .font(.system(size: 15, weight: .medium, design: .rounded))
                            .foregroundColor(.ironTextSecondary)
                        
                        Spacer()
                        
                        permissionBadge(state: state)
                    }
                }
            }
            
            if !result.deniedMetrics.isEmpty {
                Text("You can change this later in Settings.")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(.ironTextTertiary)
                    .padding(.top, 4)
            }
        }
        .padding(16)
        .liquidGlass()
    }
    
    private func permissionBadge(state: HealthKitService.PermissionState) -> some View {
        let (text, color, icon): (String, Color, String) = {
            switch state {
            case .authorized:
                return ("Authorized", .green.opacity(0.9), "checkmark.circle.fill")
            case .denied:
                return ("Denied", .red.opacity(0.85), "xmark.circle.fill")
            case .notDetermined:
                return ("—", .ironTextTertiary, "minus.circle")
            }
        }()
        
        return HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
            Text(text)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
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
                        Image(systemName: "bolt.horizontal.circle.fill")
                            .font(.system(size: 15, weight: .bold))
                        Text(viewModel.isRequesting ? "INITIALIZING..." : "INITIALIZE SYNC")
                            .font(.system(size: 14, weight: .bold))
                            .tracking(1.5)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(LiquidGlassButtonStyle(isPrimary: true))
                .disabled(viewModel.isRequesting || !viewModel.selection.hasAnySelected)
                .opacity(viewModel.isRequesting || !viewModel.selection.hasAnySelected ? 0.7 : 1)
            }
            
            Button {
                onContinue()
            } label: {
                Text("Skip for now")
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundColor(.ironTextTertiary.opacity(0.8))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
        }
    }
}

// MARK: - EKG Waveform Icon (Wireframe Heart replacement)

struct EKGWaveformIcon: View {
    @State private var animate = false
    
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let midY = h / 2
            
            ZStack {
                // EKG waveform path
                Path { path in
                    path.move(to: CGPoint(x: 0, y: midY))
                    path.addLine(to: CGPoint(x: w * 0.2, y: midY))
                    // Small bump
                    path.addLine(to: CGPoint(x: w * 0.25, y: midY - h * 0.1))
                    path.addLine(to: CGPoint(x: w * 0.3, y: midY))
                    // QRS complex - sharp spike
                    path.addLine(to: CGPoint(x: w * 0.38, y: midY + h * 0.15))
                    path.addLine(to: CGPoint(x: w * 0.45, y: midY - h * 0.45))
                    path.addLine(to: CGPoint(x: w * 0.52, y: midY + h * 0.25))
                    path.addLine(to: CGPoint(x: w * 0.58, y: midY))
                    // T wave
                    path.addQuadCurve(
                        to: CGPoint(x: w * 0.75, y: midY),
                        control: CGPoint(x: w * 0.66, y: midY - h * 0.18)
                    )
                    path.addLine(to: CGPoint(x: w, y: midY))
                }
                .stroke(
                    LinearGradient(
                        colors: [.ironPurple.opacity(0.6), .ironPurple, .ironPurpleLight],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
                )
                .shadow(color: .ironPurpleGlow, radius: 6, x: 0, y: 0)
                
                // Scanning line effect
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [Color.clear, Color.ironPurple.opacity(0.5), Color.clear],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: 20)
                    .offset(x: animate ? w / 2 : -w / 2)
                    .animation(
                        .linear(duration: 2.0).repeatForever(autoreverses: false),
                        value: animate
                    )
            }
        }
        .onAppear { animate = true }
    }
}

// MARK: - Flat EKG Line (for empty state)

struct FlatEKGLine: View {
    @State private var scanPosition: CGFloat = 0
    
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let midY = h / 2
            
            ZStack {
                // Flat baseline
                Path { path in
                    path.move(to: CGPoint(x: 0, y: midY))
                    path.addLine(to: CGPoint(x: w, y: midY))
                }
                .stroke(
                    Color.ironTextTertiary.opacity(0.3),
                    style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [4, 4])
                )
                
                // Small blip in the center
                Path { path in
                    path.move(to: CGPoint(x: w * 0.45, y: midY))
                    path.addLine(to: CGPoint(x: w * 0.48, y: midY - 4))
                    path.addLine(to: CGPoint(x: w * 0.52, y: midY + 4))
                    path.addLine(to: CGPoint(x: w * 0.55, y: midY))
                }
                .stroke(
                    Color.ironTextTertiary.opacity(0.4),
                    style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round)
                )
                
                // Scanning dot
                Circle()
                    .fill(Color.ironTextTertiary.opacity(0.5))
                    .frame(width: 6, height: 6)
                    .offset(x: scanPosition - w / 2, y: 0)
                    .animation(
                        .linear(duration: 3.0).repeatForever(autoreverses: false),
                        value: scanPosition
                    )
            }
            .onAppear {
                scanPosition = w
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
        @Published var breatheIn: Bool = false
        
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
                
                // Best-effort cache warm-up. Never blocks onboarding.
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
    ZStack {
        AnimatedMeshBackground()
        HealthKitConnectView(onContinue: {})
            .padding(.top, 40)
    }
    .modelContainer(for: DailyBiometrics.self, inMemory: true)
}
