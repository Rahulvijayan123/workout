import SwiftUI
import SwiftData

struct MainAppView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var workoutStore: WorkoutStore
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
            
            // Custom Tab Bar
            CustomTabBar(selectedTab: $selectedTab)
        }
        .ignoresSafeArea(.keyboard)
    }
}

// MARK: - Custom Tab Bar
struct CustomTabBar: View {
    @Binding var selectedTab: MainAppView.Tab
    @Namespace private var animation
    
    let neonPurple = Color(red: 0.6, green: 0.3, blue: 1.0)
    
    var body: some View {
        HStack(spacing: 0) {
            ForEach(MainAppView.Tab.allCases, id: \.self) { tab in
                TabBarItem(
                    tab: tab,
                    isSelected: selectedTab == tab,
                    neonPurple: neonPurple,
                    namespace: animation
                ) {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        selectedTab = tab
                    }
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(
            ZStack {
                // Dark glass background
                Rectangle()
                    .fill(Color(red: 0.04, green: 0.04, blue: 0.05))
                
                // Top border
                VStack {
                    Rectangle()
                        .fill(Color.white.opacity(0.08))
                        .frame(height: 0.5)
                    Spacer()
                }
            }
            .ignoresSafeArea(.container, edges: .bottom)
        )
    }
}

struct TabBarItem: View {
    let tab: MainAppView.Tab
    let isSelected: Bool
    let neonPurple: Color
    var namespace: Namespace.ID
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                ZStack {
                    // Glow for active tab
                    if isSelected {
                        Circle()
                            .fill(neonPurple.opacity(0.4))
                            .frame(width: 40, height: 40)
                            .blur(radius: 12)
                            .matchedGeometryEffect(id: "glow", in: namespace)
                    }
                    
                    Image(systemName: isSelected ? tab.iconFilled : tab.icon)
                        .font(.system(size: 20, weight: isSelected ? .semibold : .regular))
                        .foregroundColor(isSelected ? .white : Color.white.opacity(0.35))
                        .shadow(color: isSelected ? neonPurple.opacity(0.8) : .clear, radius: 8)
                }
                .frame(height: 28)
                
                Text(tab.label)
                    .font(.system(size: 10, weight: isSelected ? .semibold : .regular))
                    .foregroundColor(isSelected ? .white : Color.white.opacity(0.35))
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
                    RecentSessionsCard()
                    
                    // Week Progress
                    WeekProgressCard()
                    
                    Spacer(minLength: 100)
                }
                .padding(.horizontal, 20)
            }
            .scrollContentBackground(.hidden)
            .contentMargins(.bottom, 80, for: .scrollContent)
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
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("RECENT")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(2)
                    .foregroundColor(.white.opacity(0.45))
                
                Spacer()
                
                Text("See All")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color(red: 0.6, green: 0.3, blue: 1.0))
            }
            
            VStack(spacing: 10) {
                RecentSessionRow(name: "PULL DAY", date: "Yesterday", duration: "52m", sets: 24)
                RecentSessionRow(name: "PUSH DAY", date: "2 days ago", duration: "48m", sets: 22)
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
    let name: String
    let date: String
    let duration: String
    let sets: Int
    
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
                Text(name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                Text(date)
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.4))
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 2) {
                Text(duration)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.7))
                Text("\(sets) sets")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.35))
            }
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
    let days = ["M", "T", "W", "T", "F", "S", "S"]
    let completed = [true, true, false, false, false, false, false]
    let today = 2
    let neonPurple = Color(red: 0.6, green: 0.3, blue: 1.0)
    
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("THIS WEEK")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(2)
                    .foregroundColor(.white.opacity(0.45))
                
                Spacer()
                
                Text("2/4")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(.white.opacity(0.7))
            }
            
            HStack(spacing: 6) {
                ForEach(0..<7, id: \.self) { i in
                    VStack(spacing: 8) {
                        Text(days[i])
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(i == today ? neonPurple : .white.opacity(0.4))
                        
                        ZStack {
                            if completed[i] {
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
                            } else if i == today {
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
    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Spacer()
                
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.system(size: 48))
                    .foregroundColor(.ironPurple)
                
                Text("Coming Soon")
                    .font(.system(size: 20, weight: .semibold))
                
                Text("Track your progress over time")
                    .font(.system(size: 15))
                    .foregroundColor(.secondary)
                
                Spacer()
            }
            .navigationTitle("Progress")
        }
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
                
                // Reset button
                Section {
                    Button(role: .destructive) {
                        UserDefaults.standard.set(false, forKey: "hasCompletedOnboarding")
                        appState.hasCompletedOnboarding = false
                    } label: {
                        Text("Reset Onboarding")
                    }
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
