import SwiftUI
import SwiftData
import HealthKit

struct MainAppView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var workoutStore: WorkoutStore
    @Environment(\.modelContext) private var modelContext
    @State private var selectedTab: Tab = .home
    
    enum Tab: CaseIterable {
        case home
        case workouts
        case progress
        case profile
        
        var icon: String {
            switch self {
            case .home: return "house"
            case .workouts: return "dumbbell"
            case .progress: return "chart.line.uptrend.xyaxis"
            case .profile: return "person"
            }
        }
        
        var iconFilled: String {
            switch self {
            case .home: return "house.fill"
            case .workouts: return "dumbbell.fill"
            case .progress: return "chart.line.uptrend.xyaxis"
            case .profile: return "person.fill"
            }
        }
        
        var label: String {
            switch self {
            case .home: return "Home"
            case .workouts: return "Workouts"
            case .progress: return "Progress"
            case .profile: return "Profile"
            }
        }
    }
    
    var body: some View {
        ZStack(alignment: .bottom) {
            // Content
            Group {
                switch selectedTab {
                case .home:
                    HomeView(selectedTab: $selectedTab)
                case .workouts:
                    WorkoutsRootView()
                case .progress:
                    ProgressTrackingView()
                case .profile:
                    ProfileView()
                }
            }
            .safeAreaInset(edge: .bottom) {
                // Reserve space for the floating dock
                Color.clear.frame(height: 100)
            }
            
            // Custom Floating Tab Bar
            CustomTabBar(selectedTab: $selectedTab)
        }
        .ignoresSafeArea(.keyboard)
        .task {
            // Refresh HealthKit data on app launch
            await refreshHealthKitData()
        }
    }
    
    /// Refresh HealthKit data from the Health app
    private func refreshHealthKitData() async {
        let healthKit = HealthKitService()
        guard healthKit.isAvailable() else {
            print("[HealthKit] Not available on this device")
            return
        }
        
        print("[HealthKit] Refreshing data...")
        let repo = DailyBiometricsRepository(
            modelContext: modelContext,
            healthKit: healthKit
        )
        await repo.refreshDailyBiometrics(lastNDays: 30)
        
        // If user has no bodyweight set, try to populate from HealthKit body mass
        if appState.userProfile.bodyWeightLbs == nil {
            do {
                if let bodyMassLbs = try await healthKit.fetchMostRecentBodyMassLbs() {
                    print("[HealthKit] Populating bodyWeightLbs from HealthKit: \(bodyMassLbs) lbs")
                    appState.userProfile.bodyWeightLbs = bodyMassLbs
                    appState.saveUserProfile()
                } else {
                    print("[HealthKit] No body mass data available")
                }
            } catch {
                print("[HealthKit] Failed to fetch body mass: \(error.localizedDescription)")
            }
        } else {
            print("[HealthKit] bodyWeightLbs already set (\(appState.userProfile.bodyWeightLbs!) lbs), not overwriting")
        }
        
        print("[HealthKit] Refresh complete")
    }
}

// MARK: - Custom Floating Dock Tab Bar
struct CustomTabBar: View {
    @Binding var selectedTab: MainAppView.Tab
    @Namespace private var animation
    
    var body: some View {
        VStack(spacing: 0) {
            // The floating dock pill
            HStack(spacing: 0) {
                ForEach(MainAppView.Tab.allCases, id: \.self) { tab in
                    FloatingTabBarItem(
                        tab: tab,
                        isSelected: selectedTab == tab,
                        namespace: animation
                    ) {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            selectedTab = tab
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background {
                // Floating glass pill
                Capsule()
                    .fill(.ultraThinMaterial)
                    .overlay {
                        Capsule()
                            .stroke(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.25),
                                        Color.white.opacity(0.08),
                                        Color.ironPurple.opacity(0.15)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    }
                    .shadow(color: Color.black.opacity(0.4), radius: 25, x: 0, y: 10)
                    .shadow(color: Color.ironPurple.opacity(0.15), radius: 30, x: 0, y: 5)
            }
            .padding(.horizontal, 32)
        }
        .padding(.bottom, 8)
        .background {
            // Solid background to prevent content leaking through
            Color.ironBackground
                .ignoresSafeArea(.container, edges: .bottom)
        }
    }
}

struct FloatingTabBarItem: View {
    let tab: MainAppView.Tab
    let isSelected: Bool
    var namespace: Namespace.ID
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                ZStack {
                    // Neon underglow for active tab
                    if isSelected {
                        // Glow orb behind icon
                        Circle()
                            .fill(Color.ironPurple.opacity(0.5))
                            .frame(width: 44, height: 44)
                            .blur(radius: 14)
                            .matchedGeometryEffect(id: "glow", in: namespace)
                        
                        // Underglow bar
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.ironPurple)
                            .frame(width: 36, height: 3)
                            .blur(radius: 4)
                            .offset(y: 16)
                            .matchedGeometryEffect(id: "underglow", in: namespace)
                    }
                    
                    Image(systemName: isSelected ? tab.iconFilled : tab.icon)
                        .font(.system(size: 22, weight: isSelected ? .semibold : .regular))
                        .foregroundColor(isSelected ? .white : Color.white.opacity(0.4))
                        .shadow(color: isSelected ? Color.ironPurple.opacity(0.9) : .clear, radius: 10)
                }
                .frame(height: 30)
                
                Text(tab.label)
                    .font(.system(size: 10, weight: isSelected ? .semibold : .regular))
                    .foregroundColor(isSelected ? .white : Color.white.opacity(0.4))
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }
}


// MARK: - Home View
struct HomeView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var workoutStore: WorkoutStore
    @Binding var selectedTab: MainAppView.Tab
    @Query(sort: \DailyBiometrics.date) private var dailyBiometrics: [DailyBiometrics]
    @State private var readinessScore: Int = 78
    @State private var animatePulse = false
    
    private var recentBiometrics: [DailyBiometrics] {
        // TrainingEngine deload logic wants a rolling baseline; keep this bounded.
        Array(dailyBiometrics.suffix(60))
    }
    
    var body: some View {
        ZStack {
            // Deep charcoal background
            Color(red: 0.02, green: 0.02, blue: 0.02)
                .ignoresSafeArea()
            
            // Ambient light blobs for liquid glass refraction
            GeometryReader { geo in
                // Purple blob - top right
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color(red: 0.4, green: 0.2, blue: 0.8).opacity(0.35),
                                Color.clear
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: 180
                        )
                    )
                    .frame(width: 350, height: 350)
                    .offset(x: geo.size.width * 0.4, y: -50)
                
                // Blue blob - left side
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color(red: 0.1, green: 0.3, blue: 0.7).opacity(0.25),
                                Color.clear
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: 150
                        )
                    )
                    .frame(width: 300, height: 300)
                    .offset(x: -100, y: geo.size.height * 0.3)
                
                // Amber/gold blob - center top (behind gauge)
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color(red: 0.6, green: 0.4, blue: 0.1).opacity(0.15),
                                Color.clear
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: 200
                        )
                    )
                    .frame(width: 400, height: 400)
                    .offset(x: geo.size.width * 0.15, y: 80)
                
                // Teal blob - bottom
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color(red: 0.1, green: 0.5, blue: 0.5).opacity(0.2),
                                Color.clear
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: 140
                        )
                    )
                    .frame(width: 280, height: 280)
                    .offset(x: geo.size.width * 0.5, y: geo.size.height * 0.65)
            }
            .ignoresSafeArea()
            
            ScrollView(showsIndicators: false) {
                VStack(spacing: 24) {
                    // Header
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(greeting.uppercased())
                                .font(.system(size: 11, weight: .medium))
                                .tracking(2)
                                .foregroundColor(.white.opacity(0.4))
                            
                            Text(appState.userProfile.name)
                                .font(.system(size: 26, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                        }
                        Spacer()
                    }
                    .padding(.top, 8)
                    
                    // HUD Readiness Gauge
                    HUDReadinessGauge(score: readinessScore)
                    
                    // Biometrics Row
                    BiometricsRow(latest: recentBiometrics.last)
                    
                    // Up Next - Mission Card
                    MissionCard(
                        workoutName: todayWorkout,
                        exerciseCount: workoutStore.templates.first?.exercises.count ?? 6,
                        animatePulse: $animatePulse,
                        onBeginSession: {
                            // Start recommended session using TrainingEngine
                            workoutStore.startRecommendedSession(
                                userProfile: appState.userProfile,
                                readiness: readinessScore,
                                dailyBiometrics: recentBiometrics
                            )
                            // Switch to workouts tab
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                selectedTab = .workouts
                            }
                        }
                    )
                    
                    // Recent Sessions
                    RecentSessionsCard(
                        sessions: workoutStore.sessions,
                        onSessionTap: { session in
                            // Navigate to workout details - handled by switching to workouts tab
                            selectedTab = .workouts
                        }
                    )
                    
                    // Week Progress
                    WeekProgressCard(
                        sessions: workoutStore.sessions,
                        targetDays: appState.userProfile.weeklyFrequency
                    )
                    
                    Spacer(minLength: 140)
                }
                .padding(.horizontal, 20)
            }
            .scrollContentBackground(.hidden)
            .overlay(alignment: .top) {
                // Top safe area cover - solid background behind status bar
                Color(red: 0.02, green: 0.02, blue: 0.02)
                    .frame(height: 0)
                    .background(
                        Color(red: 0.02, green: 0.02, blue: 0.02)
                            .ignoresSafeArea(.container, edges: .top)
                    )
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 2).repeatForever(autoreverses: true)) {
                animatePulse = true
            }
            refreshReadinessFromBiometrics()
        }
        .onChange(of: dailyBiometrics.count) { _, _ in
            refreshReadinessFromBiometrics()
        }
    }

    private func refreshReadinessFromBiometrics() {
        // If the user hasn't connected HealthKit yet, keep a neutral/default score.
        if let computed = ReadinessScoreCalculator.todayScore(from: recentBiometrics) {
            readinessScore = computed
        }
    }
    
    var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        case 17..<22: return "Good evening"
        default: return "Good night"
        }
    }
    
    var todayWorkout: String {
        switch appState.userProfile.workoutSplit {
        case .pushPullLegs: return "PUSH PROTOCOL"
        case .fullBody: return "FULL BODY"
        case .upperLower: return "UPPER BODY"
        case .pushPullLegsArms: return "PUSH PROTOCOL"
        case .broSplit: return "CHEST DAY"
        case .arnoldSplit: return "CHEST & BACK"
        case .powerBuilding: return "STRENGTH"
        case .custom: return "WORKOUT"
        }
    }
}

// MARK: - HUD Readiness Gauge
struct HUDReadinessGauge: View {
    let score: Int
    let segments: Int = 40
    
    // Metallic gold gradient colors
    var goldLight: Color { Color(red: 1.0, green: 0.9, blue: 0.5) }
    var goldMid: Color { Color(red: 0.95, green: 0.75, blue: 0.25) }
    var goldDark: Color { Color(red: 0.7, green: 0.5, blue: 0.15) }
    
    var statusColor: Color {
        if score >= 80 { return goldMid }
        else if score >= 60 { return Color(red: 1.0, green: 0.7, blue: 0.2) }
        else if score >= 40 { return Color(red: 1.0, green: 0.5, blue: 0.2) }
        else { return Color(red: 1.0, green: 0.3, blue: 0.3) }
    }
    
    var statusText: String {
        if score >= 80 { return "OPTIMAL" }
        else if score >= 60 { return "MODERATE" }
        else if score >= 40 { return "RECOVER" }
        else { return "REST" }
    }
    
    var body: some View {
        ZStack {
            // Outer tick marks (static reference ring)
            ForEach(0..<60, id: \.self) { i in
                Rectangle()
                    .fill(Color.white.opacity(i % 5 == 0 ? 0.15 : 0.05))
                    .frame(width: i % 5 == 0 ? 1.5 : 0.5, height: i % 5 == 0 ? 12 : 6)
                    .offset(y: -100)
                    .rotationEffect(.degrees(Double(i) * 6))
            }
            
            // Recessed groove/track with inner shadow effect
            ZStack {
                // Outer shadow (creates depth)
                Circle()
                    .stroke(Color.black.opacity(0.8), lineWidth: 14)
                    .frame(width: 164, height: 164)
                    .blur(radius: 4)
                
                // The groove itself
                Circle()
                    .stroke(Color(red: 0.08, green: 0.08, blue: 0.1), lineWidth: 12)
                    .frame(width: 164, height: 164)
                
                // Inner shadow highlight (top-left light source)
                Circle()
                    .stroke(
                        LinearGradient(
                            colors: [Color.white.opacity(0.08), Color.clear, Color.black.opacity(0.3)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 12
                    )
                    .frame(width: 164, height: 164)
            }
            
            // Segmented progress ring with metallic gradient
            ForEach(0..<segments, id: \.self) { i in
                let isActive = Double(i) / Double(segments) < Double(score) / 100
                let segmentAngle = Double(i) * (360.0 / Double(segments))
                
                Capsule()
                    .fill(
                        isActive ?
                        LinearGradient(
                            colors: [goldLight, goldMid, goldDark],
                            startPoint: .top,
                            endPoint: .bottom
                        ) :
                        LinearGradient(colors: [Color.clear], startPoint: .top, endPoint: .bottom)
                    )
                    .frame(width: 4, height: 16)
                    .offset(y: -82)
                    .rotationEffect(.degrees(segmentAngle) + .degrees(-90))
                    .shadow(color: isActive ? goldMid.opacity(0.8) : .clear, radius: 8)
                    .shadow(color: isActive ? goldLight.opacity(0.4) : .clear, radius: 3)
            }
            
            // Inner bezel ring
            Circle()
                .stroke(
                    LinearGradient(
                        colors: [Color.white.opacity(0.1), Color.white.opacity(0.02)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
                .frame(width: 140, height: 140)
            
            // Glass lens reflection overlay
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.white.opacity(0.06),
                            Color.clear
                        ],
                        center: UnitPoint(x: 0.3, y: 0.3),
                        startRadius: 0,
                        endRadius: 80
                    )
                )
                .frame(width: 130, height: 130)
            
            // Center content
            VStack(spacing: 6) {
                Text("\(score)")
                    .font(.system(size: 58, weight: .bold, design: .rounded))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.white, Color.white.opacity(0.85)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                
                Text("READINESS")
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(3)
                    .foregroundColor(.white.opacity(0.4))
            }
            
            // Status indicator - minimal with decorative lines
            VStack {
                Spacer()
                HStack(spacing: 10) {
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [Color.clear, statusColor.opacity(0.5)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: 20, height: 2)
                    
                    Text(statusText)
                        .font(.system(size: 11, weight: .bold))
                        .tracking(2)
                        .foregroundColor(statusColor)
                        .shadow(color: statusColor.opacity(0.5), radius: 6)
                    
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [statusColor.opacity(0.5), Color.clear],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: 20, height: 2)
                }
            }
            .frame(height: 230)
        }
        .frame(height: 250)
    }
}

// MARK: - Biometrics Row
struct BiometricsRow: View {
    let latest: DailyBiometrics?
    // Unified gold/silver color for all icons
    let iconColor = Color(red: 0.85, green: 0.8, blue: 0.65)
    
    var body: some View {
        let sleepHours: String = {
            guard let minutes = latest?.sleepMinutes else { return "--" }
            return String(format: "%.1f", minutes / 60.0)
        }()
        let rhr: String = {
            guard let v = latest?.restingHR else { return "--" }
            return "\(Int(v.rounded()))"
        }()
        let hrv: String = {
            guard let v = latest?.hrvSDNN else { return "--" }
            return "\(Int(v.rounded()))"
        }()
        
        HStack(spacing: 10) {
            BiometricCard(icon: "moon", value: sleepHours, unit: "HRS", label: "SLEEP", iconColor: iconColor)
            BiometricCard(icon: "heart", value: rhr, unit: "BPM", label: "RHR", iconColor: iconColor)
            BiometricCard(icon: "waveform.path.ecg", value: hrv, unit: "MS", label: "HRV", iconColor: iconColor)
        }
    }
}

struct BiometricCard: View {
    let icon: String
    let value: String
    let unit: String
    let label: String
    let iconColor: Color
    
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .light))
                .foregroundColor(iconColor.opacity(0.8))
            
            HStack(alignment: .lastTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                Text(unit)
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundColor(.white.opacity(0.4))
            }
            
            Text(label)
                .font(.system(size: 8, weight: .semibold))
                .tracking(1.5)
                .foregroundColor(.white.opacity(0.35))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .background(
            ZStack {
                // Liquid glass background
                RoundedRectangle(cornerRadius: 16)
                    .fill(.ultraThinMaterial)
                    .opacity(0.6)
                
                // Dark tint overlay
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(red: 0.1, green: 0.1, blue: 0.12).opacity(0.7))
                
                // Glossy highlight at top
                VStack {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(
                            LinearGradient(
                                colors: [Color.white.opacity(0.15), Color.clear],
                                startPoint: .top,
                                endPoint: .center
                            )
                        )
                        .frame(height: 40)
                    Spacer()
                }
                .clipShape(RoundedRectangle(cornerRadius: 16))
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(
                    LinearGradient(
                        colors: [Color.white.opacity(0.25), Color.white.opacity(0.05)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
    }
}

// MARK: - Mission Card (Up Next)
struct MissionCard: View {
    let workoutName: String
    let exerciseCount: Int
    @Binding var animatePulse: Bool
    let onBeginSession: () -> Void
    
    let neonPurple = Color(red: 0.6, green: 0.3, blue: 1.0)
    
    private var estimatedDuration: Int {
        // Roughly 7-8 minutes per exercise
        max(20, exerciseCount * 8)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("UP NEXT")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(2)
                    .foregroundColor(.white.opacity(0.4))
                
                Spacer()
                
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color(red: 0.3, green: 1, blue: 0.5))
                        .frame(width: 5, height: 5)
                    Text("READY")
                        .font(.system(size: 9, weight: .bold))
                        .tracking(1)
                        .foregroundColor(Color(red: 0.3, green: 1, blue: 0.5))
                }
            }
            
            HStack(spacing: 16) {
                // Hexagon icon with lightning bolt
                ZStack {
                    // Glow
                    HexagonShape()
                        .fill(neonPurple.opacity(0.3))
                        .frame(width: 58, height: 58)
                        .blur(radius: animatePulse ? 14 : 10)
                    
                    // Hexagon background
                    HexagonShape()
                        .fill(Color(red: 0.08, green: 0.08, blue: 0.12))
                        .frame(width: 50, height: 50)
                    
                    // Hexagon border
                    HexagonShape()
                        .stroke(neonPurple.opacity(0.5), lineWidth: 1.5)
                        .frame(width: 50, height: 50)
                    
                    // Lightning bolt
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(neonPurple)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(workoutName)
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .tracking(0.5)
                        .foregroundColor(.white)
                    
                    Text("\(exerciseCount) EXERCISES • ~\(estimatedDuration) MIN")
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(1)
                        .foregroundColor(.white.opacity(0.4))
                }
                
                Spacer()
            }
            
            // Begin Session button with 3D effect
            Button {
                onBeginSession()
            } label: {
                HStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "play.fill")
                        .font(.system(size: 11))
                    Text("BEGIN SESSION")
                        .font(.system(size: 12, weight: .bold))
                        .tracking(1.5)
                    Spacer()
                }
                .foregroundColor(.white)
                .padding(.vertical, 16)
                .background(
                    ZStack {
                        // Main gradient
                        LinearGradient(
                            colors: [
                                neonPurple,
                                neonPurple.opacity(0.7)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        
                        // Top highlight for 3D tactile feel
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
                .cornerRadius(12)
                .shadow(color: neonPurple.opacity(0.5), radius: 16, y: 6)
            }
        }
        .padding(20)
        .background(
            ZStack {
                // Liquid glass
                RoundedRectangle(cornerRadius: 20)
                    .fill(.ultraThinMaterial)
                    .opacity(0.5)
                
                // Dark tint
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color(red: 0.08, green: 0.08, blue: 0.12).opacity(0.75))
                
                // Top glossy reflection
                VStack {
                    RoundedRectangle(cornerRadius: 20)
                        .fill(
                            LinearGradient(
                                colors: [Color.white.opacity(0.1), Color.clear],
                                startPoint: .top,
                                endPoint: .center
                            )
                        )
                        .frame(height: 60)
                    Spacer()
                }
                .clipShape(RoundedRectangle(cornerRadius: 20))
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(
                    LinearGradient(
                        colors: [neonPurple.opacity(0.7), neonPurple.opacity(0.2), Color.white.opacity(0.1)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.5
                )
        )
        .shadow(color: neonPurple.opacity(0.15), radius: 20, y: 8)
    }
}

// Hexagon shape for the icon
struct HexagonShape: Shape {
    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        var path = Path()
        
        for i in 0..<6 {
            let angle = Angle(degrees: Double(i) * 60 - 90).radians
            let point = CGPoint(
                x: center.x + radius * Foundation.cos(angle),
                y: center.y + radius * Foundation.sin(angle)
            )
            if i == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        path.closeSubpath()
        return path
    }
}

// MARK: - Recent Sessions Card
struct RecentSessionsCard: View {
    let sessions: [WorkoutSession]
    var onSessionTap: ((WorkoutSession) -> Void)? = nil
    
    private var recentSessions: [WorkoutSession] {
        // Get completed sessions (with endedAt), sorted by date, take first 3
        sessions
            .filter { $0.endedAt != nil }
            .sorted { $0.startedAt > $1.startedAt }
            .prefix(3)
            .map { $0 }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("RECENT")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(2)
                    .foregroundColor(.white.opacity(0.45))
                
                Spacer()
                
                if sessions.count > 3 {
                    Text("See All")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Color(red: 0.6, green: 0.3, blue: 1.0))
                }
            }
            
            if recentSessions.isEmpty {
                Text("No workouts yet. Start your first session!")
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.5))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
            } else {
                VStack(spacing: 10) {
                    ForEach(recentSessions) { session in
                        Button {
                            onSessionTap?(session)
                        } label: {
                            RecentSessionRow(session: session)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(18)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 18)
                    .fill(.ultraThinMaterial)
                    .opacity(0.4)
                
                RoundedRectangle(cornerRadius: 18)
                    .fill(Color(red: 0.08, green: 0.08, blue: 0.1).opacity(0.8))
                
                // Subtle top highlight
                VStack {
                    RoundedRectangle(cornerRadius: 18)
                        .fill(
                            LinearGradient(
                                colors: [Color.white.opacity(0.08), Color.clear],
                                startPoint: .top,
                                endPoint: .center
                            )
                        )
                        .frame(height: 50)
                    Spacer()
                }
                .clipShape(RoundedRectangle(cornerRadius: 18))
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(
                    LinearGradient(
                        colors: [Color.white.opacity(0.15), Color.white.opacity(0.03)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
    }
}

struct RecentSessionRow: View {
    let session: WorkoutSession
    
    private var formattedDate: String {
        let calendar = Calendar.current
        let now = Date()
        
        if calendar.isDateInToday(session.startedAt) {
            return "Today"
        } else if calendar.isDateInYesterday(session.startedAt) {
            return "Yesterday"
        } else {
            let days = calendar.dateComponents([.day], from: session.startedAt, to: now).day ?? 0
            if days < 7 {
                return "\(days) days ago"
            } else {
                let formatter = DateFormatter()
                formatter.dateFormat = "MMM d"
                return formatter.string(from: session.startedAt)
            }
        }
    }
    
    private var duration: String {
        guard let endedAt = session.endedAt else { return "--" }
        let seconds = Int(endedAt.timeIntervalSince(session.startedAt))
        let minutes = seconds / 60
        if minutes >= 60 {
            return "\(minutes / 60)h \(minutes % 60)m"
        }
        return "\(minutes)m"
    }
    
    private var totalSets: Int {
        session.exercises.reduce(0) { $0 + $1.sets.filter { $0.isCompleted }.count }
    }
    
    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .stroke(Color.purple.opacity(0.4), lineWidth: 1.5)
                .frame(width: 36, height: 36)
                .overlay(
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.purple)
                )
            
            VStack(alignment: .leading, spacing: 2) {
                Text(session.name.uppercased())
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                Text(formattedDate)
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.4))
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 2) {
                Text(duration)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.7))
                Text("\(totalSets) sets")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.35))
            }
            
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white.opacity(0.3))
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.02))
        )
    }
}

// MARK: - Week Progress Card
struct WeekProgressCard: View {
    let sessions: [WorkoutSession]
    let targetDays: Int // User's weekly frequency goal
    
    let dayLabels = ["M", "T", "W", "T", "F", "S", "S"]
    let neonPurple = Color(red: 0.6, green: 0.3, blue: 1.0)
    
    private var calendar: Calendar { Calendar.current }
    
    /// Get the start of the current week (Monday)
    private var weekStart: Date {
        let now = Date()
        var cal = calendar
        cal.firstWeekday = 2 // Monday
        let components = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)
        return cal.date(from: components) ?? now
    }
    
    /// Array of which days this week have completed sessions
    private var completedDays: [Bool] {
        let weekSessions = sessions.filter { session in
            guard session.endedAt != nil else { return false }
            return session.startedAt >= weekStart
        }
        
        var completed = [false, false, false, false, false, false, false]
        for session in weekSessions {
            // Get weekday (1 = Sunday, 2 = Monday, ..., 7 = Saturday)
            let weekday = calendar.component(.weekday, from: session.startedAt)
            // Convert to Monday-first index (0 = Monday, 6 = Sunday)
            let index = (weekday + 5) % 7
            if index >= 0 && index < 7 {
                completed[index] = true
            }
        }
        return completed
    }
    
    /// Index of today (0 = Monday, 6 = Sunday)
    private var todayIndex: Int {
        let weekday = calendar.component(.weekday, from: Date())
        return (weekday + 5) % 7
    }
    
    /// Count of completed days this week
    private var completedCount: Int {
        completedDays.filter { $0 }.count
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("THIS WEEK")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(2)
                    .foregroundColor(.white.opacity(0.45))
                
                Spacer()
                
                Text("\(completedCount)/\(targetDays)")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(.white.opacity(0.7))
            }
            
            HStack(spacing: 6) {
                ForEach(0..<7, id: \.self) { i in
                    VStack(spacing: 8) {
                        Text(dayLabels[i])
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(i == todayIndex ? neonPurple : .white.opacity(0.4))
                        
                        ZStack {
                            if completedDays[i] {
                                Circle()
                                    .fill(
                                        LinearGradient(
                                            colors: [neonPurple, neonPurple.opacity(0.7)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .frame(width: 32, height: 32)
                                    .shadow(color: neonPurple.opacity(0.5), radius: 6)
                                
                                Image(systemName: "checkmark")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(.white)
                            } else if i == todayIndex {
                                Circle()
                                    .fill(Color.white.opacity(0.05))
                                    .frame(width: 32, height: 32)
                                
                                Circle()
                                    .stroke(neonPurple, lineWidth: 2)
                                    .frame(width: 32, height: 32)
                                    .shadow(color: neonPurple.opacity(0.4), radius: 4)
                            } else {
                                Circle()
                                    .fill(Color.white.opacity(0.03))
                                    .frame(width: 32, height: 32)
                                
                                Circle()
                                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
                                    .frame(width: 32, height: 32)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(18)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 18)
                    .fill(.ultraThinMaterial)
                    .opacity(0.4)
                
                RoundedRectangle(cornerRadius: 18)
                    .fill(Color(red: 0.08, green: 0.08, blue: 0.1).opacity(0.8))
                
                VStack {
                    RoundedRectangle(cornerRadius: 18)
                        .fill(
                            LinearGradient(
                                colors: [Color.white.opacity(0.08), Color.clear],
                                startPoint: .top,
                                endPoint: .center
                            )
                        )
                        .frame(height: 50)
                    Spacer()
                }
                .clipShape(RoundedRectangle(cornerRadius: 18))
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(
                    LinearGradient(
                        colors: [Color.white.opacity(0.15), Color.white.opacity(0.03)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
    }
}



struct ProgressTrackingView: View {
    @EnvironmentObject var workoutStore: WorkoutStore
    
    enum ChartType: String, CaseIterable {
        case volume = "Volume"
        case weight = "Weight"
        case strength = "Strength"
    }
    
    @State private var selectedChartType: ChartType = .volume
    @State private var selectedExercise: ExerciseRef?
    
    private let neonPurple = Color(red: 0.6, green: 0.3, blue: 1.0)
    private let neonCyan = Color(red: 0.0, green: 0.9, blue: 1.0)
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Background
                Color.ironBackground.ignoresSafeArea()
                
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 20) {
                        // Summary Stats Cards
                        summaryCards
                        
                        // Chart Type Selector
                        chartTypeSelector
                        
                        // Main Chart
                        mainChart
                        
                        // Exercise List
                        exerciseListSection
                        
                        Spacer(minLength: 140)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                }
            }
            .navigationTitle("Progress")
            .navigationBarTitleDisplayMode(.large)
            .sheet(item: $selectedExercise) { exercise in
                ExerciseProgressDetailView(
                    exercise: exercise,
                    workoutStore: workoutStore
                )
            }
        }
    }
    
    // MARK: - Summary Cards
    private var summaryCards: some View {
        HStack(spacing: 12) {
            SummaryStatCard(
                title: "WORKOUTS",
                value: "\(completedSessionsCount)",
                subtitle: "Total",
                icon: "figure.strengthtraining.traditional",
                color: neonPurple
            )
            
            SummaryStatCard(
                title: "THIS WEEK",
                value: "\(thisWeekSessionCount)",
                subtitle: "Sessions",
                icon: "calendar",
                color: neonCyan
            )
            
            SummaryStatCard(
                title: "STREAK",
                value: "\(currentStreak)",
                subtitle: "Days",
                icon: "flame.fill",
                color: .orange
            )
        }
    }
    
    // MARK: - Chart Type Selector
    private var chartTypeSelector: some View {
        HStack(spacing: 0) {
            ForEach(ChartType.allCases, id: \.self) { type in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedChartType = type
                    }
                } label: {
                    Text(type.rawValue)
                        .font(.system(size: 14, weight: selectedChartType == type ? .semibold : .regular))
                        .foregroundColor(selectedChartType == type ? .white : .white.opacity(0.5))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            selectedChartType == type ?
                            neonPurple.opacity(0.3) : Color.clear
                        )
                        .overlay(
                            Rectangle()
                                .fill(selectedChartType == type ? neonPurple : Color.clear)
                                .frame(height: 2)
                                .offset(y: 16)
                        )
                }
            }
        }
        .background(Color.white.opacity(0.05))
        .cornerRadius(8)
    }
    
    // MARK: - Main Chart
    private var mainChart: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(chartTitle)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white.opacity(0.6))
                .textCase(.uppercase)
                .tracking(1)
            
            if chartData.isEmpty {
                emptyChartPlaceholder
            } else {
                ProgressChartView(
                    data: chartData,
                    chartType: selectedChartType,
                    color: neonPurple
                )
                .frame(height: 200)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.03))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
    }
    
    private var emptyChartPlaceholder: some View {
        VStack(spacing: 12) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 32))
                .foregroundColor(.white.opacity(0.3))
            
            Text("Complete more workouts to see your progress")
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.5))
                .multilineTextAlignment(.center)
        }
        .frame(height: 200)
        .frame(maxWidth: .infinity)
    }
    
    private var chartTitle: String {
        switch selectedChartType {
        case .volume: return "Total Volume (Sets × Reps × Weight)"
        case .weight: return "Average Working Weight"
        case .strength: return "Estimated 1RM Progress"
        }
    }
    
    // MARK: - Exercise List Section
    private var exerciseListSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("EXERCISES")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white.opacity(0.6))
                .textCase(.uppercase)
                .tracking(1)
            
            if uniqueExercises.isEmpty {
                Text("No exercises logged yet")
                    .font(.system(size: 15))
                    .foregroundColor(.white.opacity(0.4))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(uniqueExercises, id: \.id) { exercise in
                        ExerciseProgressRow(
                            exercise: exercise,
                            workoutStore: workoutStore,
                            onTap: {
                                selectedExercise = exercise
                            }
                        )
                    }
                }
            }
        }
    }
    
    // MARK: - Computed Properties
    
    private var completedSessionsCount: Int {
        workoutStore.sessions.filter { $0.endedAt != nil }.count
    }
    
    private var thisWeekSessionCount: Int {
        let calendar = Calendar.current
        let startOfWeek = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date()))!
        return workoutStore.sessions.filter { $0.startedAt >= startOfWeek && $0.endedAt != nil }.count
    }
    
    private var currentStreak: Int {
        let calendar = Calendar.current
        var streak = 0
        var checkDate = Date()
        
        let sessionDates = Set(workoutStore.sessions.compactMap { session -> Date? in
            guard session.endedAt != nil else { return nil }
            return calendar.startOfDay(for: session.startedAt)
        })
        
        while true {
            let dayStart = calendar.startOfDay(for: checkDate)
            if sessionDates.contains(dayStart) {
                streak += 1
                checkDate = calendar.date(byAdding: .day, value: -1, to: checkDate)!
            } else if streak == 0 && calendar.isDateInToday(checkDate) {
                // Allow today to not have a workout yet
                checkDate = calendar.date(byAdding: .day, value: -1, to: checkDate)!
            } else {
                break
            }
        }
        return streak
    }
    
    private var uniqueExercises: [ExerciseRef] {
        var seen = Set<String>()
        var exercises: [ExerciseRef] = []
        
        for session in workoutStore.sessions {
            for performance in session.exercises {
                if !seen.contains(performance.exercise.id) {
                    seen.insert(performance.exercise.id)
                    exercises.append(performance.exercise)
                }
            }
        }
        return exercises
    }
    
    private var chartData: [ProgressDataPoint] {
        let calendar = Calendar.current
        var dataByDate: [Date: (volume: Double, weight: Double, e1rm: Double, count: Int)] = [:]
        
        for session in workoutStore.sessions.reversed() {
            guard session.endedAt != nil else { continue }
            let dayStart = calendar.startOfDay(for: session.startedAt)
            
            var sessionVolume: Double = 0
            var sessionWeight: Double = 0
            var sessionE1RM: Double = 0
            var setCount: Int = 0
            
            for performance in session.exercises {
                let completedSets = performance.sets.filter { $0.isCompleted && $0.weight > 0 }
                for set in completedSets {
                    sessionVolume += Double(set.reps) * set.weight
                    sessionWeight += set.weight
                    // Brzycki formula for e1RM
                    if set.reps > 0 && set.reps < 37 {
                        let e1rm = set.weight * (36.0 / (37.0 - Double(set.reps)))
                        sessionE1RM += e1rm
                    }
                    setCount += 1
                }
            }
            
            if setCount > 0 {
                let existing = dataByDate[dayStart] ?? (0, 0, 0, 0)
                dataByDate[dayStart] = (
                    existing.volume + sessionVolume,
                    existing.weight + sessionWeight,
                    existing.e1rm + sessionE1RM,
                    existing.count + setCount
                )
            }
        }
        
        return dataByDate.map { date, values in
            let avgWeight = values.count > 0 ? values.weight / Double(values.count) : 0
            let avgE1RM = values.count > 0 ? values.e1rm / Double(values.count) : 0
            return ProgressDataPoint(
                date: date,
                volume: values.volume,
                avgWeight: avgWeight,
                avgE1RM: avgE1RM
            )
        }.sorted { $0.date < $1.date }
    }
}

// MARK: - Progress Data Point
struct ProgressDataPoint: Identifiable {
    let id = UUID()
    let date: Date
    let volume: Double
    let avgWeight: Double
    let avgE1RM: Double
}

// MARK: - Summary Stat Card
private struct SummaryStatCard: View {
    let title: String
    let value: String
    let subtitle: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundColor(color)
                Spacer()
            }
            
            Text(value)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundColor(.white)
            
            Text(subtitle)
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.5))
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.03))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(color.opacity(0.2), lineWidth: 1)
                )
        )
    }
}

// MARK: - Progress Chart View
private struct ProgressChartView: View {
    let data: [ProgressDataPoint]
    let chartType: ProgressTrackingView.ChartType
    let color: Color
    
    var body: some View {
        GeometryReader { geometry in
            let maxValue = data.map { valueFor($0) }.max() ?? 1
            let minValue = data.map { valueFor($0) }.min() ?? 0
            let range = max(maxValue - minValue, 1)
            
            ZStack {
                // Grid lines
                VStack(spacing: 0) {
                    ForEach(0..<4) { i in
                        Divider()
                            .background(Color.white.opacity(0.1))
                        if i < 3 { Spacer() }
                    }
                }
                
                // Chart line
                if data.count > 1 {
                    Path { path in
                        for (index, point) in data.enumerated() {
                            let x = geometry.size.width * CGFloat(index) / CGFloat(data.count - 1)
                            let normalizedY = (valueFor(point) - minValue) / range
                            let y = geometry.size.height * (1 - CGFloat(normalizedY))
                            
                            if index == 0 {
                                path.move(to: CGPoint(x: x, y: y))
                            } else {
                                path.addLine(to: CGPoint(x: x, y: y))
                            }
                        }
                    }
                    .stroke(
                        LinearGradient(
                            colors: [color, color.opacity(0.6)],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round)
                    )
                    
                    // Gradient fill under line
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: geometry.size.height))
                        
                        for (index, point) in data.enumerated() {
                            let x = geometry.size.width * CGFloat(index) / CGFloat(data.count - 1)
                            let normalizedY = (valueFor(point) - minValue) / range
                            let y = geometry.size.height * (1 - CGFloat(normalizedY))
                            
                            if index == 0 {
                                path.addLine(to: CGPoint(x: x, y: y))
                            } else {
                                path.addLine(to: CGPoint(x: x, y: y))
                            }
                        }
                        
                        path.addLine(to: CGPoint(x: geometry.size.width, y: geometry.size.height))
                        path.closeSubpath()
                    }
                    .fill(
                        LinearGradient(
                            colors: [color.opacity(0.3), color.opacity(0.0)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    
                    // Data points
                    ForEach(Array(data.enumerated()), id: \.offset) { index, point in
                        let x = geometry.size.width * CGFloat(index) / CGFloat(data.count - 1)
                        let normalizedY = (valueFor(point) - minValue) / range
                        let y = geometry.size.height * (1 - CGFloat(normalizedY))
                        
                        Circle()
                            .fill(color)
                            .frame(width: 8, height: 8)
                            .position(x: x, y: y)
                    }
                }
            }
        }
    }
    
    private func valueFor(_ point: ProgressDataPoint) -> Double {
        switch chartType {
        case .volume: return point.volume
        case .weight: return point.avgWeight
        case .strength: return point.avgE1RM
        }
    }
}

// MARK: - Exercise Progress Row
private struct ExerciseProgressRow: View {
    let exercise: ExerciseRef
    let workoutStore: WorkoutStore
    let onTap: () -> Void
    
    private var history: [ExercisePerformance] {
        workoutStore.performanceHistory(for: exercise.id, limit: 50)
    }
    
    private var latestWeight: Double? {
        history.first?.sets.filter { $0.isCompleted && $0.weight > 0 }.map(\.weight).max()
    }
    
    private var progressPercent: Double? {
        guard history.count >= 2 else { return nil }
        let recent = history[0].sets.filter { $0.isCompleted && $0.weight > 0 }.map(\.weight).max() ?? 0
        let older = history[min(4, history.count - 1)].sets.filter { $0.isCompleted && $0.weight > 0 }.map(\.weight).max() ?? 0
        guard older > 0 else { return nil }
        return ((recent - older) / older) * 100
    }
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Exercise icon
                Circle()
                    .fill(Color.ironPurple.opacity(0.2))
                    .frame(width: 40, height: 40)
                    .overlay(
                        Image(systemName: "dumbbell.fill")
                            .font(.system(size: 16))
                            .foregroundColor(.ironPurple)
                    )
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(exercise.displayName)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.white)
                    
                    Text("\(history.count) sessions logged")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.5))
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 2) {
                    if let weight = latestWeight {
                        Text("\(Int(weight)) lb")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.white)
                    }
                    
                    if let progress = progressPercent {
                        HStack(spacing: 2) {
                            Image(systemName: progress >= 0 ? "arrow.up.right" : "arrow.down.right")
                                .font(.system(size: 10))
                            Text(String(format: "%.1f%%", abs(progress)))
                                .font(.system(size: 11))
                        }
                        .foregroundColor(progress >= 0 ? .green : .red)
                    }
                }
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.3))
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white.opacity(0.03))
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Exercise Progress Detail View
struct ExerciseProgressDetailView: View {
    let exercise: ExerciseRef
    let workoutStore: WorkoutStore
    @Environment(\.dismiss) private var dismiss
    
    private let neonPurple = Color(red: 0.6, green: 0.3, blue: 1.0)
    
    private var history: [ExercisePerformance] {
        workoutStore.performanceHistory(for: exercise.id, limit: 100)
    }
    
    private var exerciseState: ExerciseState? {
        workoutStore.exerciseStates[exercise.id]
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.ironBackground.ignoresSafeArea()
                
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 20) {
                        // Header Stats
                        headerStats
                        
                        // Weight Progress Chart
                        weightProgressChart
                        
                        // Session History
                        sessionHistory
                        
                        Spacer(minLength: 40)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                }
            }
            .navigationTitle(exercise.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(neonPurple)
                }
            }
        }
    }
    
    private var headerStats: some View {
        HStack(spacing: 12) {
            StatBox(
                title: "Current",
                value: exerciseState.map { "\(Int($0.currentWorkingWeight))" } ?? "--",
                unit: "lb"
            )
            
            StatBox(
                title: "Est. 1RM",
                value: exerciseState?.rollingE1RM.map { "\(Int($0))" } ?? "--",
                unit: "lb"
            )
            
            StatBox(
                title: "Sessions",
                value: "\(history.count)",
                unit: "total"
            )
        }
    }
    
    private var weightProgressChart: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("WEIGHT PROGRESSION")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white.opacity(0.6))
                .textCase(.uppercase)
                .tracking(1)
            
            if history.count < 2 {
                Text("Log more sessions to see progress chart")
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.4))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 40)
            } else {
                ExerciseWeightChartView(history: history, color: neonPurple)
                    .frame(height: 180)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.03))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
    }
    
    private var sessionHistory: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("SESSION HISTORY")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white.opacity(0.6))
                .textCase(.uppercase)
                .tracking(1)
            
            if history.isEmpty {
                Text("No sessions logged yet")
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.4))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(Array(history.enumerated()), id: \.offset) { index, performance in
                        SessionHistoryRow(performance: performance, index: index)
                    }
                }
            }
        }
    }
}

// MARK: - Stat Box
private struct StatBox: View {
    let title: String
    let value: String
    let unit: String
    
    var body: some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.5))
            
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                
                Text(unit)
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.4))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.03))
        )
    }
}

// MARK: - Exercise Weight Chart View
private struct ExerciseWeightChartView: View {
    let history: [ExercisePerformance]
    let color: Color
    
    private var chartData: [(date: Date, weight: Double)] {
        history.reversed().compactMap { performance in
            let maxWeight = performance.sets
                .filter { $0.isCompleted && $0.weight > 0 }
                .map(\.weight)
                .max()
            guard let weight = maxWeight else { return nil }
            return (date: Date(), weight: weight) // We don't have exact date, use index
        }
    }
    
    var body: some View {
        GeometryReader { geometry in
            let weights = history.reversed().compactMap { p -> Double? in
                p.sets.filter { $0.isCompleted && $0.weight > 0 }.map(\.weight).max()
            }
            
            if weights.count > 1 {
                let maxValue = weights.max() ?? 1
                let minValue = weights.min() ?? 0
                let range = max(maxValue - minValue, 1)
                
                ZStack {
                    // Grid lines
                    VStack(spacing: 0) {
                        ForEach(0..<4) { i in
                            Divider()
                                .background(Color.white.opacity(0.1))
                            if i < 3 { Spacer() }
                        }
                    }
                    
                    // Chart line
                    Path { path in
                        for (index, weight) in weights.enumerated() {
                            let x = geometry.size.width * CGFloat(index) / CGFloat(weights.count - 1)
                            let normalizedY = (weight - minValue) / range
                            let y = geometry.size.height * (1 - CGFloat(normalizedY))
                            
                            if index == 0 {
                                path.move(to: CGPoint(x: x, y: y))
                            } else {
                                path.addLine(to: CGPoint(x: x, y: y))
                            }
                        }
                    }
                    .stroke(
                        LinearGradient(
                            colors: [color, color.opacity(0.6)],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round)
                    )
                    
                    // Data points
                    ForEach(Array(weights.enumerated()), id: \.offset) { index, weight in
                        let x = geometry.size.width * CGFloat(index) / CGFloat(weights.count - 1)
                        let normalizedY = (weight - minValue) / range
                        let y = geometry.size.height * (1 - CGFloat(normalizedY))
                        
                        Circle()
                            .fill(color)
                            .frame(width: 6, height: 6)
                            .position(x: x, y: y)
                    }
                }
            }
        }
    }
}

// MARK: - Session History Row
private struct SessionHistoryRow: View {
    let performance: ExercisePerformance
    let index: Int
    
    private var completedSets: [WorkoutSet] {
        performance.sets.filter { $0.isCompleted }
    }
    
    private var maxWeight: Double {
        completedSets.map(\.weight).max() ?? 0
    }
    
    private var totalReps: Int {
        completedSets.map(\.reps).reduce(0, +)
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // Session number
            Text("#\(index + 1)")
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundColor(.white.opacity(0.4))
                .frame(width: 32)
            
            VStack(alignment: .leading, spacing: 2) {
                Text("\(Int(maxWeight)) lb × \(totalReps) reps")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.white)
                
                Text("\(completedSets.count) sets completed")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.5))
            }
            
            Spacer()
            
            // Volume
            VStack(alignment: .trailing) {
                let volume = completedSets.map { Double($0.reps) * $0.weight }.reduce(0, +)
                Text("\(Int(volume))")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white.opacity(0.8))
                
                Text("vol")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.4))
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.white.opacity(0.02))
        )
    }
}

struct ProfileView: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        NavigationStack {
            List {
                // Profile header
                Section {
                    HStack {
                        Spacer()
                        VStack(spacing: 12) {
                            Circle()
                                .fill(Color.ironPurple)
                                .frame(width: 60, height: 60)
                                .overlay {
                                    Text(String(appState.userProfile.name.prefix(1)).uppercased())
                                        .font(.system(size: 24, weight: .bold))
                                        .foregroundColor(.white)
                                }
                            
                            Text(appState.userProfile.name)
                                .font(.system(size: 18, weight: .semibold))
                            
                            Text("\(appState.userProfile.workoutExperience.rawValue) • \(appState.userProfile.fitnessLevel.rawValue)")
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                }
                
                // Stats
                Section("Training") {
                    LabeledContent("Split", value: appState.userProfile.workoutSplit.rawValue)
                    LabeledContent("Frequency", value: "\(appState.userProfile.weeklyFrequency) days/week")
                    LabeledContent("Gym Type", value: appState.userProfile.gymType.rawValue)
                }
                
                Section("Nutrition & Recovery") {
                    LabeledContent("Daily Protein", value: "\(appState.userProfile.dailyProteinGrams)g")
                    LabeledContent("Sleep Target", value: String(format: "%.1f hrs", appState.userProfile.sleepHours))
                }
                
                // Sync Status
                Section("Data Sync") {
                    HStack {
                        Text("Sync Status")
                        Spacer()
                        if DataSyncService.shared.isSyncing {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("Syncing...")
                                .foregroundColor(.secondary)
                        } else if let lastSync = DataSyncService.shared.lastSyncAt {
                            Text(lastSync, style: .relative)
                                .foregroundColor(.secondary)
                        } else {
                            Text("Not synced")
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    if DataSyncService.shared.syncError != nil {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                            Text("Sync error occurred")
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                // Account Section
                Section("Account") {
                    Button(role: .destructive) {
                        appState.signOut()
                    } label: {
                        HStack {
                            Image(systemName: "rectangle.portrait.and.arrow.right")
                            Text("Sign Out")
                        }
                    }
                }
                
                // Reset button (for testing)
                Section {
                    Button(role: .destructive) {
                        UserDefaults.standard.set(false, forKey: "hasCompletedOnboarding")
                        appState.hasCompletedOnboarding = false
                    } label: {
                        Text("Reset Onboarding")
                    }
                } footer: {
                    Text("This will restart the onboarding flow but keep your account.")
                }
                
                // Bottom spacer for floating tab bar
                Section {
                    Color.clear
                        .frame(height: 80)
                        .listRowBackground(Color.clear)
                }
            }
            .navigationTitle("Profile")
        }
    }
}


#Preview {
    MainAppView()
        .environmentObject(AppState())
        .environmentObject(WorkoutStore())
}
