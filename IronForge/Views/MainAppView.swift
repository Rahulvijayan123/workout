import SwiftUI
import SwiftData
import HealthKit
import UIKit

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
        ZStack {
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
                Color.clear
                    .frame(height: 96)
                    .allowsHitTesting(false)
            }
            
            // Custom Floating Tab Bar - pinned to bottom
            VStack {
                Spacer()
                LiquidGlassTabBar(selectedTab: $selectedTab)
            }
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

// MARK: - Liquid Glass Bottom Navigation (tap + drag scrub)
struct LiquidGlassTabBar: View {
    @Binding var selectedTab: MainAppView.Tab
    
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    
    private let tabs = MainAppView.Tab.allCases
    
    @State private var isDragging = false
    @State private var lensCenterX: CGFloat = 0
    @State private var lensTargetX: CGFloat = 0
    @State private var lastHapticIndex: Int?
    @State private var selectionFeedback = UISelectionFeedbackGenerator()
    
    // Tunables (feel free to tweak)
    private let capsuleHeight: CGFloat = 64
    private let capsuleMaxWidth: CGFloat = 520
    private let horizontalMargin: CGFloat = 22
    private let bottomMargin: CGFloat = 10
    private let lensHorizontalInset: CGFloat = 10
    private let lensVerticalInset: CGFloat = 9
    private let magnetRadiusFactor: CGFloat = 0.45
    
    var body: some View {
        GeometryReader { geo in
            let fullWidth = geo.size.width
            let capsuleWidth = max(0, min(fullWidth - (horizontalMargin * 2), capsuleMaxWidth))
            let capsuleMinX = (fullWidth - capsuleWidth) / 2
            let segmentWidth = capsuleWidth / CGFloat(max(tabs.count, 1))
            
            let selectedIndex = tabs.firstIndex(of: selectedTab) ?? 0
            let selectedCenterXLocal = (CGFloat(selectedIndex) + 0.5) * segmentWidth
            let selectedCenterXGlobal = capsuleMinX + selectedCenterXLocal
            
            let effectiveLensCenterX = (lensCenterX == 0) ? selectedCenterXGlobal : lensCenterX
            let refractionShiftX = reduceMotion ? 0 : clamp((lensTargetX - effectiveLensCenterX) * 0.14, -6, 6)
            let lensSize = CGSize(
                width: max(44, segmentWidth - (lensHorizontalInset * 2)),
                height: max(36, capsuleHeight - (lensVerticalInset * 2))
            )
            
            ZStack {
                // Outer floating capsule (navigation layer)
                Capsule()
                    .fill(.ultraThinMaterial)
                    .overlay {
                        Capsule()
                            .fill(Color.black.opacity(reduceTransparency ? 0.28 : 0.14))
                    }
                    .overlay {
                        Capsule()
                            .stroke(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.45),
                                        Color.white.opacity(0.14),
                                        Color.clear
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    }
                    .frame(width: capsuleWidth, height: capsuleHeight)
                    .position(x: fullWidth / 2, y: capsuleHeight / 2)
                    .shadow(color: Color.black.opacity(0.45), radius: 22, x: 0, y: 14)
                    .shadow(color: Color.white.opacity(0.06), radius: 1, x: 0, y: 1)
                
                // Lens indicator (separate layer so icons stay crisp).
                // Reduced Motion fallback: hide lens (standard translucent tab bar).
                if !reduceMotion {
                    LiquidGlassLens(
                        size: lensSize,
                        tint: lensTint(for: effectiveLensCenterX, capsuleMinX: capsuleMinX, segmentWidth: segmentWidth),
                        refractionShiftX: refractionShiftX,
                        reduceMotion: reduceMotion,
                        reduceTransparency: reduceTransparency
                    )
                    .position(x: effectiveLensCenterX, y: capsuleHeight / 2)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }
                
                // Icons (never distorted)
                HStack(spacing: 0) {
                    ForEach(Array(tabs.enumerated()), id: \.element) { index, tab in
                        LiquidGlassTabBarItem(
                            tab: tab,
                            isSelected: selectedTab == tab,
                            reduceTransparency: reduceTransparency
                        ) {
                            selectTab(at: index, capsuleMinX: capsuleMinX, segmentWidth: segmentWidth)
                        }
                        .frame(width: segmentWidth, height: capsuleHeight)
                    }
                }
                .frame(width: capsuleWidth, height: capsuleHeight)
                .position(x: fullWidth / 2, y: capsuleHeight / 2)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .simultaneousGesture(
                dragGesture(
                    capsuleMinX: capsuleMinX,
                    capsuleWidth: capsuleWidth,
                    capsuleHeight: capsuleHeight,
                    segmentWidth: segmentWidth
                )
            )
            .onAppear {
                lastHapticIndex = selectedIndex
                lensCenterX = selectedCenterXGlobal
                lensTargetX = selectedCenterXGlobal
            }
            .onChange(of: selectedTab) { _, newValue in
                // Ignore selection changes while dragging (drag drives the lens).
                guard !isDragging else { return }
                let idx = tabs.firstIndex(of: newValue) ?? 0
                let centerGlobal = capsuleMinX + (CGFloat(idx) + 0.5) * segmentWidth
                snapLens(to: centerGlobal, isFinal: true)
                lastHapticIndex = idx
            }
            .onChange(of: fullWidth) { _, _ in
                // Keep the lens aligned on size changes (rotation, split-screen).
                guard !isDragging else { return }
                let idx = tabs.firstIndex(of: selectedTab) ?? 0
                let centerGlobal = capsuleMinX + (CGFloat(idx) + 0.5) * segmentWidth
                lensCenterX = centerGlobal
                lensTargetX = centerGlobal
            }
        }
        .frame(height: capsuleHeight)
        .padding(.bottom, bottomMargin)
        .accessibilityElement(children: .contain)
    }
    
    private func selectTab(at index: Int, capsuleMinX: CGFloat, segmentWidth: CGFloat) {
        guard index >= 0 && index < tabs.count else { return }
        let centerGlobal = capsuleMinX + (CGFloat(index) + 0.5) * segmentWidth
        snapLens(to: centerGlobal, isFinal: true)
        selectedTab = tabs[index]
        lastHapticIndex = index
    }
    
    private func dragGesture(
        capsuleMinX: CGFloat,
        capsuleWidth: CGFloat,
        capsuleHeight: CGFloat,
        segmentWidth: CGFloat
    ) -> some Gesture {
        DragGesture(minimumDistance: 6, coordinateSpace: .local)
            .onChanged { value in
                // Only engage scrubbing on intentional horizontal drags.
                // This keeps the bar "glued" while the user scrolls vertically.
                let dx = value.translation.width
                let dy = value.translation.height
                let isHorizontalIntent = abs(dx) > 10 && abs(dx) > abs(dy) * 1.25
                
                if !isDragging {
                    // Only begin scrubbing if the gesture starts on the capsule.
                    guard value.startLocation.x >= capsuleMinX,
                          value.startLocation.x <= capsuleMinX + capsuleWidth,
                          value.startLocation.y >= 0,
                          value.startLocation.y <= capsuleHeight
                    else { return }
                    
                    guard isHorizontalIntent else { return }
                    
                    isDragging = true
                    selectionFeedback.prepare()
                }
                
                guard isDragging else { return }
                
                let localX = clamp(value.location.x - capsuleMinX, 0, capsuleWidth)
                let (magnetizedLocalX, nearestIndex) = magnetize(
                    localX: localX,
                    segmentWidth: segmentWidth
                )
                
                let centerGlobal = capsuleMinX + magnetizedLocalX
                snapLens(to: centerGlobal, isFinal: false)
                
                if nearestIndex != lastHapticIndex {
                    selectionFeedback.selectionChanged()
                    selectionFeedback.prepare()
                    lastHapticIndex = nearestIndex
                }
                
                if nearestIndex >= 0 && nearestIndex < tabs.count {
                    selectedTab = tabs[nearestIndex]
                }
            }
            .onEnded { value in
                guard isDragging else { return }
                defer { isDragging = false }
                
                let localX = clamp(value.location.x - capsuleMinX, 0, capsuleWidth)
                let nearestIndex = nearestTabIndex(localX: localX, segmentWidth: segmentWidth)
                let snappedLocalX = (CGFloat(nearestIndex) + 0.5) * segmentWidth
                let centerGlobal = capsuleMinX + snappedLocalX
                
                snapLens(to: centerGlobal, isFinal: true)
                
                if nearestIndex >= 0 && nearestIndex < tabs.count {
                    selectedTab = tabs[nearestIndex]
                    lastHapticIndex = nearestIndex
                }
            }
    }
    
    private func snapLens(to centerX: CGFloat, isFinal: Bool) {
        lensTargetX = centerX
        
        if reduceMotion {
            lensCenterX = centerX
            return
        }
        
        let animation: Animation = isFinal
            ? .spring(response: 0.42, dampingFraction: 0.78, blendDuration: 0.2)
            : .interactiveSpring(response: 0.38, dampingFraction: 0.84, blendDuration: 0.12)
        
        withAnimation(animation) {
            lensCenterX = centerX
        }
    }
    
    private func nearestTabIndex(localX: CGFloat, segmentWidth: CGFloat) -> Int {
        let raw = (localX / segmentWidth) - 0.5
        return clampInt(Int(raw.rounded()), 0, tabs.count - 1)
    }
    
    private func magnetize(localX: CGFloat, segmentWidth: CGFloat) -> (localX: CGFloat, nearestIndex: Int) {
        let idx = nearestTabIndex(localX: localX, segmentWidth: segmentWidth)
        let center = (CGFloat(idx) + 0.5) * segmentWidth
        
        let radius = max(10, segmentWidth * magnetRadiusFactor)
        let distance = abs(localX - center)
        let t = 1 - min(distance / radius, 1)
        let smooth = t * t * (3 - 2 * t) // smoothstep 0..1
        let magnetized = localX + (center - localX) * (smooth * 0.88)
        
        return (magnetized, idx)
    }
    
    private func lensTint(for lensCenterGlobalX: CGFloat, capsuleMinX: CGFloat, segmentWidth: CGFloat) -> Color {
        let localX = clamp(
            lensCenterGlobalX - capsuleMinX,
            0,
            segmentWidth * CGFloat(max(tabs.count, 1))
        )
        let raw = (localX / segmentWidth) - 0.5
        let clamped = clamp(raw, 0, CGFloat(max(tabs.count - 1, 0)))
        
        let lower = Int(floor(clamped))
        let upper = min(lower + 1, tabs.count - 1)
        let t = clamped - CGFloat(lower)
        
        return lerpColor(tabs[lower].tintColor, tabs[upper].tintColor, t: t)
    }
    
    // MARK: - Helpers
    
    private func clamp(_ v: CGFloat, _ lo: CGFloat, _ hi: CGFloat) -> CGFloat {
        min(max(v, lo), hi)
    }
    
    private func clampInt(_ v: Int, _ lo: Int, _ hi: Int) -> Int {
        min(max(v, lo), hi)
    }
    
    private func lerpColor(_ a: Color, _ b: Color, t: CGFloat) -> Color {
        let t = clamp(t, 0, 1)
        
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        
        let uiA = UIColor(a)
        let uiB = UIColor(b)
        
        guard uiA.getRed(&r1, green: &g1, blue: &b1, alpha: &a1),
              uiB.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        else {
            return a
        }
        
        let r = r1 + (r2 - r1) * t
        let g = g1 + (g2 - g1) * t
        let b = b1 + (b2 - b1) * t
        let a = a1 + (a2 - a1) * t
        
        return Color(red: Double(r), green: Double(g), blue: Double(b), opacity: Double(a))
    }
}

private struct LiquidGlassTabBarItem: View {
    let tab: MainAppView.Tab
    let isSelected: Bool
    let reduceTransparency: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Image(systemName: isSelected ? tab.iconFilled : tab.icon)
                .font(.system(size: 20, weight: isSelected ? .semibold : .medium))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(isSelected ? Color.white : Color.white.opacity(reduceTransparency ? 0.75 : 0.55))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .shadow(color: isSelected ? Color.white.opacity(0.16) : .clear, radius: 10, x: 0, y: 2)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tab.label)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct LiquidGlassLens: View {
    let size: CGSize
    let tint: Color
    let refractionShiftX: CGFloat
    let reduceMotion: Bool
    let reduceTransparency: Bool
    
    var body: some View {
        let tintOpacity = reduceTransparency ? 0.18 : 0.14
        let baseOpacity = reduceTransparency ? 0.95 : 0.80
        let rimMaskRadius = max(size.width, size.height) * 0.70
        
        ZStack {
            // Base (sampled blur/tint from underlying content)
            Capsule()
                .fill(.ultraThinMaterial)
                .opacity(baseOpacity)
            
            Capsule()
                .fill(tint.opacity(tintOpacity))
            
            // Subtle internal blur for thickness
            Capsule()
                .fill(Color.white.opacity(0.06))
                .blur(radius: 0.8)
                .opacity(0.65)
            
            // Refraction + pseudo-distortion (edge-focused, disabled for Reduce Motion)
            if !reduceMotion {
                // 1) Rim magnification layer (slight scale = "lens" distortion)
                Capsule()
                    .fill(.ultraThinMaterial)
                    .opacity(reduceTransparency ? 0.65 : 0.50)
                    .scaleEffect(1.10)
                    .offset(x: refractionShiftX * 0.25, y: -refractionShiftX * 0.06)
                    .mask {
                        Capsule()
                            .fill(
                                RadialGradient(
                                    colors: [Color.black.opacity(0.0), Color.black.opacity(1.0)],
                                    center: .center,
                                    startRadius: rimMaskRadius * 0.25,
                                    endRadius: rimMaskRadius
                                )
                            )
                    }
                    .blendMode(.plusLighter)
                
                // 2) Directional edge refraction (viscous-lag biased)
                Capsule()
                    .fill(.ultraThinMaterial)
                    .opacity(reduceTransparency ? 0.55 : 0.42)
                    .offset(x: refractionShiftX, y: -refractionShiftX * 0.12)
                    .mask {
                        Capsule()
                            .fill(
                                RadialGradient(
                                    colors: [Color.black.opacity(0.0), Color.black.opacity(1.0)],
                                    center: .center,
                                    startRadius: 0,
                                    endRadius: rimMaskRadius
                                )
                            )
                    }
                    .blendMode(.screen)
            }
            
            // Specular highlights + rim (kept crisp)
            Capsule()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.white.opacity(0.55),
                            Color.clear
                        ],
                        center: UnitPoint(x: 0.25, y: 0.25),
                        startRadius: 0,
                        endRadius: max(size.width, size.height) * 0.8
                    )
                )
                .opacity(0.22)
            
            Capsule()
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.75),
                            Color.white.opacity(0.25),
                            tint.opacity(0.35),
                            Color.clear
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
            
            Capsule()
                .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
                .blur(radius: 0.6)
                .offset(y: -0.5)
                .mask(Capsule())
        }
        .frame(width: size.width, height: size.height)
        .compositingGroup()
        .shadow(color: Color.black.opacity(0.25), radius: 14, x: 0, y: 10)
    }
}

private extension MainAppView.Tab {
    var tintColor: Color {
        switch self {
        case .home:
            return .ironPurple
        case .workouts:
            return Color(red: 0.3, green: 1.0, blue: 0.55)
        case .progress:
            return .ironCyan
        case .profile:
            return Color(red: 1.0, green: 0.75, blue: 0.25)
        }
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
        guard let startOfWeek = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())) else {
            return 0
        }
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
                guard let prevDay = calendar.date(byAdding: .day, value: -1, to: checkDate) else { break }
                checkDate = prevDay
            } else if streak == 0 && calendar.isDateInToday(checkDate) {
                // Allow today to not have a workout yet
                guard let prevDay = calendar.date(byAdding: .day, value: -1, to: checkDate) else { break }
                checkDate = prevDay
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
    @EnvironmentObject var workoutStore: WorkoutStore
    @Query(sort: \DailyBiometrics.date) private var dailyBiometrics: [DailyBiometrics]
    
    @State private var showingGoalsEditor = false
    
    let neonPurple = Color(red: 0.6, green: 0.3, blue: 1.0)
    let coolGrey = Color(red: 0.53, green: 0.60, blue: 0.65)
    let purpleGlow = Color(red: 0.85, green: 0.71, blue: 0.99)
    
    // Get latest biometrics from HealthKit
    private var latestBiometrics: DailyBiometrics? {
        dailyBiometrics.last
    }
    
    // Check if we have HealthKit sleep data
    private var hasSleepData: Bool {
        latestBiometrics?.sleepMinutes != nil
    }
    
    // Get actual sleep hours from HealthKit or user setting
    private var actualSleepHours: Double {
        if let minutes = latestBiometrics?.sleepMinutes {
            return minutes / 60.0
        }
        return appState.userProfile.sleepHours
    }
    
    var body: some View {
        ZStack {
            // Deep charcoal background
            Color(red: 0.02, green: 0.02, blue: 0.04)
                .ignoresSafeArea()
            
            // Ambient light blobs
            GeometryReader { geo in
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [neonPurple.opacity(0.25), Color.clear],
                            center: .center,
                            startRadius: 0,
                            endRadius: 200
                        )
                    )
                    .frame(width: 400, height: 400)
                    .offset(x: geo.size.width * 0.3, y: -100)
                
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color.ironCyan.opacity(0.15), Color.clear],
                            center: .center,
                            startRadius: 0,
                            endRadius: 150
                        )
                    )
                    .frame(width: 300, height: 300)
                    .offset(x: -50, y: geo.size.height * 0.6)
            }
            .ignoresSafeArea()
            
            ScrollView(showsIndicators: false) {
                VStack(spacing: 24) {
                    // MARK: - Holographic ID Header
                    HolographicIDHeader(
                        name: appState.userProfile.name,
                        experience: appState.userProfile.workoutExperience,
                        neonPurple: neonPurple
                    )
                    .padding(.top, 20)
                    
                    // MARK: - Training Bento Grid with Edit Button
                    TrainingBentoGridWithEdit(
                        split: appState.userProfile.workoutSplit,
                        frequency: appState.userProfile.weeklyFrequency,
                        gymType: appState.userProfile.gymType,
                        neonPurple: neonPurple,
                        onEditGoals: { showingGoalsEditor = true }
                    )
                    
                    // MARK: - Recovery Metrics (with HealthKit integration)
                    RecoveryMetricsPanel(
                        proteinGrams: appState.userProfile.dailyProteinGrams,
                        sleepHours: actualSleepHours,
                        hasSleepData: hasSleepData,
                        onProteinChange: { newValue in
                            appState.userProfile.dailyProteinGrams = newValue
                            appState.saveUserProfile()
                        },
                        onSleepChange: { newValue in
                            appState.userProfile.sleepHours = newValue
                            appState.saveUserProfile()
                        }
                    )
                    
                    // MARK: - Achievements / Badges Section
                    AchievementBadgesSection(
                        workoutStore: workoutStore,
                        neonPurple: neonPurple
                    )
                    
                    // MARK: - Tactical Actions Footer
                    TacticalActionsFooter(
                        onSignOut: { appState.signOut() },
                        onResetOnboarding: {
                            UserDefaults.standard.set(false, forKey: "hasCompletedOnboarding")
                            appState.hasCompletedOnboarding = false
                        }
                    )
                    
                    Spacer(minLength: 140)
                }
                .padding(.horizontal, 20)
            }
        }
        .sheet(isPresented: $showingGoalsEditor) {
            GoalsEditorSheet(appState: appState)
        }
    }
}

// MARK: - Training Bento Grid with Edit Button
struct TrainingBentoGridWithEdit: View {
    let split: WorkoutSplit
    let frequency: Int
    let gymType: GymType
    let neonPurple: Color
    let onEditGoals: () -> Void
    
    var body: some View {
        VStack(spacing: 10) {
            // Section Label with Edit Button
            HStack {
                Text("TRAINING PROTOCOL")
                    .font(IronFont.header(10))
                    .tracking(3)
                    .foregroundColor(Color(red: 0.61, green: 0.64, blue: 0.69))
                
                Spacer()
                
                Button(action: onEditGoals) {
                    HStack(spacing: 4) {
                        Image(systemName: "pencil")
                            .font(.system(size: 10, weight: .semibold))
                        Text("EDIT")
                            .font(.system(size: 10, weight: .semibold))
                            .tracking(1)
                    }
                    .foregroundColor(neonPurple)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        Capsule()
                            .fill(neonPurple.opacity(0.12))
                            .overlay(
                                Capsule()
                                    .stroke(neonPurple.opacity(0.3), lineWidth: 1)
                            )
                    )
                }
                .buttonStyle(PlainButtonStyle())
            }
            
            // Bento Grid Layout
            HStack(spacing: 10) {
                BentoTile(
                    icon: split.icon,
                    label: "SPLIT",
                    value: splitShortName(split),
                    neonPurple: neonPurple
                )
                
                BentoFrequencyTile(
                    frequency: frequency,
                    neonPurple: neonPurple
                )
            }
            
            BentoWideTile(
                icon: gymType.icon,
                label: "TRAINING ENVIRONMENT",
                value: gymType.rawValue.uppercased(),
                neonPurple: neonPurple
            )
        }
    }
    
    private func splitShortName(_ split: WorkoutSplit) -> String {
        switch split {
        case .pushPullLegs: return "PPL"
        case .fullBody: return "FULL"
        case .upperLower: return "U/L"
        case .pushPullLegsArms: return "PPL+"
        case .broSplit: return "BRO"
        case .arnoldSplit: return "ARNOLD"
        case .powerBuilding: return "POWER"
        case .custom: return "CUSTOM"
        }
    }
}

// MARK: - Goals Editor Sheet
struct GoalsEditorSheet: View {
    @ObservedObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    
    @State private var selectedGoals: Set<FitnessGoal>
    @State private var selectedSplit: WorkoutSplit
    @State private var frequency: Int
    @State private var selectedGymType: GymType
    @State private var selectedTrainingPhase: TrainingPhase
    
    let neonPurple = Color(red: 0.6, green: 0.3, blue: 1.0)
    
    init(appState: AppState) {
        self.appState = appState
        _selectedGoals = State(initialValue: Set(appState.userProfile.goals))
        _selectedSplit = State(initialValue: appState.userProfile.workoutSplit)
        _frequency = State(initialValue: appState.userProfile.weeklyFrequency)
        _selectedGymType = State(initialValue: appState.userProfile.gymType)
        _selectedTrainingPhase = State(initialValue: appState.userProfile.trainingPhase)
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.ironBackground.ignoresSafeArea()
                
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 24) {
                        // Goals Section
                        VStack(alignment: .leading, spacing: 12) {
                            Text("FITNESS GOALS")
                                .font(IronFont.label(11))
                                .tracking(2)
                                .foregroundColor(.ironTextTertiary)
                            
                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                                ForEach(FitnessGoal.allCases, id: \.self) { goal in
                                    GoalPickerChip(
                                        goal: goal,
                                        isSelected: selectedGoals.contains(goal),
                                        neonPurple: neonPurple
                                    ) {
                                        if selectedGoals.contains(goal) {
                                            selectedGoals.remove(goal)
                                        } else {
                                            selectedGoals.insert(goal)
                                        }
                                    }
                                }
                            }
                        }
                        
                        // Split Section
                        VStack(alignment: .leading, spacing: 12) {
                            Text("WORKOUT SPLIT")
                                .font(IronFont.label(11))
                                .tracking(2)
                                .foregroundColor(.ironTextTertiary)
                            
                            ForEach(WorkoutSplit.allCases, id: \.self) { split in
                                SplitOptionRow(
                                    split: split,
                                    isSelected: selectedSplit == split,
                                    neonPurple: neonPurple
                                ) {
                                    selectedSplit = split
                                }
                            }
                        }
                        
                        // Frequency Section
                        VStack(alignment: .leading, spacing: 12) {
                            Text("WEEKLY FREQUENCY")
                                .font(IronFont.label(11))
                                .tracking(2)
                                .foregroundColor(.ironTextTertiary)
                            
                            HStack {
                                Text("\(frequency) days/week")
                                    .font(IronFont.bodySemibold(16))
                                    .foregroundColor(.white)
                                
                                Spacer()
                                
                                Stepper("", value: $frequency, in: 1...7)
                                    .labelsHidden()
                            }
                            .padding(16)
                            .liquidGlass()
                        }
                        
                        // Gym Type Section
                        VStack(alignment: .leading, spacing: 12) {
                            Text("GYM TYPE")
                                .font(IronFont.label(11))
                                .tracking(2)
                                .foregroundColor(.ironTextTertiary)
                            
                            ForEach(GymType.allCases, id: \.self) { gymType in
                                GymTypeOptionRow(
                                    gymType: gymType,
                                    isSelected: selectedGymType == gymType,
                                    neonPurple: neonPurple
                                ) {
                                    selectedGymType = gymType
                                }
                            }
                        }
                        
                        // Training Phase Section (Critical for ML)
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("TRAINING PHASE")
                                    .font(IronFont.label(11))
                                    .tracking(2)
                                    .foregroundColor(.ironTextTertiary)
                                
                                Spacer()
                                
                                // Info badge
                                Text("AFFECTS PROGRESSION")
                                    .font(.system(size: 8, weight: .bold))
                                    .tracking(1)
                                    .foregroundColor(neonPurple)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(
                                        Capsule()
                                            .fill(neonPurple.opacity(0.15))
                                    )
                            }
                            
                            ForEach(TrainingPhase.allCases, id: \.self) { phase in
                                TrainingPhaseOptionRow(
                                    phase: phase,
                                    isSelected: selectedTrainingPhase == phase,
                                    neonPurple: neonPurple
                                ) {
                                    selectedTrainingPhase = phase
                                }
                            }
                        }
                        
                        Spacer(minLength: 100)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                }
            }
            .navigationTitle("Edit Goals")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        appState.userProfile.goals = Array(selectedGoals)
                        appState.userProfile.workoutSplit = selectedSplit
                        appState.userProfile.weeklyFrequency = frequency
                        appState.userProfile.gymType = selectedGymType
                        appState.userProfile.trainingPhase = selectedTrainingPhase
                        appState.saveUserProfile()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
}

// MARK: - Goal Chip
private struct GoalPickerChip: View {
    let goal: FitnessGoal
    let isSelected: Bool
    let neonPurple: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: goal.icon)
                    .font(.system(size: 14))
                Text(goal.rawValue)
                    .font(IronFont.bodySemibold(12))
            }
            .foregroundColor(isSelected ? neonPurple : .white.opacity(0.6))
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? neonPurple.opacity(0.15) : Color.white.opacity(0.03))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(isSelected ? neonPurple.opacity(0.5) : Color.white.opacity(0.1), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Split Option Row
private struct SplitOptionRow: View {
    let split: WorkoutSplit
    let isSelected: Bool
    let neonPurple: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: split.icon)
                    .font(.system(size: 18))
                    .foregroundColor(isSelected ? neonPurple : .white.opacity(0.5))
                    .frame(width: 24)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(split.rawValue)
                        .font(IronFont.bodySemibold(14))
                        .foregroundColor(isSelected ? .white : .white.opacity(0.8))
                    Text(split.description)
                        .font(IronFont.body(11))
                        .foregroundColor(.ironTextTertiary)
                }
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(neonPurple)
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(isSelected ? neonPurple.opacity(0.1) : Color.white.opacity(0.02))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(isSelected ? neonPurple.opacity(0.4) : Color.white.opacity(0.08), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Gym Type Option Row
private struct GymTypeOptionRow: View {
    let gymType: GymType
    let isSelected: Bool
    let neonPurple: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: gymType.icon)
                    .font(.system(size: 18))
                    .foregroundColor(isSelected ? neonPurple : .white.opacity(0.5))
                    .frame(width: 24)
                
                Text(gymType.rawValue)
                    .font(IronFont.bodySemibold(14))
                    .foregroundColor(isSelected ? .white : .white.opacity(0.8))
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(neonPurple)
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(isSelected ? neonPurple.opacity(0.1) : Color.white.opacity(0.02))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(isSelected ? neonPurple.opacity(0.4) : Color.white.opacity(0.08), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Training Phase Option Row (ML Critical)
private struct TrainingPhaseOptionRow: View {
    let phase: TrainingPhase
    let isSelected: Bool
    let neonPurple: Color
    let action: () -> Void
    
    private var phaseColor: Color {
        switch phase {
        case .cut: return .orange
        case .maintenance: return .blue
        case .bulk: return .green
        case .recomp: return .purple
        }
    }
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                // Phase icon with color indicator
                ZStack {
                    Circle()
                        .fill(phaseColor.opacity(0.2))
                        .frame(width: 32, height: 32)
                    
                    Image(systemName: phase.icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(phaseColor)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(phase.rawValue.uppercased())
                        .font(IronFont.bodySemibold(14))
                        .foregroundColor(isSelected ? .white : .white.opacity(0.8))
                    
                    Text(phase.description)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.4))
                }
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(neonPurple)
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(isSelected ? neonPurple.opacity(0.1) : Color.white.opacity(0.02))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(isSelected ? neonPurple.opacity(0.4) : Color.white.opacity(0.08), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Recovery Metrics Panel (with HealthKit integration)
struct RecoveryMetricsPanel: View {
    let proteinGrams: Int
    let sleepHours: Double
    let hasSleepData: Bool
    let onProteinChange: (Int) -> Void
    let onSleepChange: (Double) -> Void
    
    @State private var isEditingProtein = false
    @State private var isEditingSleep = false
    @State private var tempProtein: Int = 0
    @State private var tempSleep: Double = 7.5
    
    var body: some View {
        VStack(spacing: 10) {
            // Section Label
            HStack {
                Text("RECOVERY METRICS")
                    .font(IronFont.header(10))
                    .tracking(3)
                    .foregroundColor(Color(red: 0.61, green: 0.64, blue: 0.69))
                Spacer()
            }
            
            // Protein Gauge (always manual input)
            RecoveryMetricCard(
                icon: "fork.knife",
                label: "DAILY PROTEIN TARGET",
                value: "\(proteinGrams)g",
                progress: min(Double(proteinGrams) / 200.0, 1.0),
                gradientColors: [
                    Color(red: 1.0, green: 0.6, blue: 0.2),
                    Color(red: 1.0, green: 0.4, blue: 0.1)
                ],
                isFromHealthKit: false,
                onTapEdit: {
                    tempProtein = proteinGrams
                    isEditingProtein = true
                }
            )
            
            // Sleep Gauge (from HealthKit or manual)
            RecoveryMetricCard(
                icon: "moon.fill",
                label: hasSleepData ? "LAST NIGHT'S SLEEP" : "SLEEP TARGET",
                value: String(format: "%.1f hrs", sleepHours),
                progress: min(sleepHours / 9.0, 1.0),
                gradientColors: [
                    Color(red: 0.2, green: 0.6, blue: 1.0),
                    Color(red: 0.1, green: 0.4, blue: 0.9)
                ],
                isFromHealthKit: hasSleepData,
                onTapEdit: hasSleepData ? nil : {
                    tempSleep = sleepHours
                    isEditingSleep = true
                }
            )
        }
        .sheet(isPresented: $isEditingProtein) {
            ProteinEditorSheet(protein: $tempProtein) {
                onProteinChange(tempProtein)
                isEditingProtein = false
            }
            .presentationDetents([.height(280)])
        }
        .sheet(isPresented: $isEditingSleep) {
            SleepEditorSheet(sleep: $tempSleep) {
                onSleepChange(tempSleep)
                isEditingSleep = false
            }
            .presentationDetents([.height(280)])
        }
    }
}

// MARK: - Recovery Metric Card
struct RecoveryMetricCard: View {
    let icon: String
    let label: String
    let value: String
    let progress: Double
    let gradientColors: [Color]
    let isFromHealthKit: Bool
    let onTapEdit: (() -> Void)?
    
    var body: some View {
        VStack(spacing: 10) {
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(gradientColors[0])
                    
                    Text(label)
                        .font(.system(size: 10, weight: .medium))
                        .tracking(1.5)
                        .foregroundColor(.white.opacity(0.5))
                }
                
                Spacer()
                
                HStack(spacing: 8) {
                    if isFromHealthKit {
                        HStack(spacing: 4) {
                            Image(systemName: "heart.fill")
                                .font(.system(size: 8))
                            Text("HEALTH")
                                .font(.system(size: 8, weight: .semibold))
                                .tracking(0.5)
                        }
                        .foregroundColor(.red.opacity(0.7))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(
                            Capsule()
                                .fill(Color.red.opacity(0.1))
                        )
                    }
                    
                    Text(value)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    
                    if let onTap = onTapEdit {
                        Button(action: onTap) {
                            Image(systemName: "slider.horizontal.3")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.white.opacity(0.4))
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
            }
            
            // Progress Bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.white.opacity(0.06))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.white.opacity(0.08), lineWidth: 1)
                        )
                    
                    RoundedRectangle(cornerRadius: 6)
                        .fill(
                            LinearGradient(
                                colors: gradientColors,
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geo.size.width * progress)
                        .shadow(color: gradientColors[0].opacity(0.5), radius: 8)
                }
            }
            .frame(height: 12)
        }
        .padding(16)
        .background(BentoGlassBackground())
    }
}

// MARK: - Protein Editor Sheet
struct ProteinEditorSheet: View {
    @Binding var protein: Int
    let onSave: () -> Void
    @Environment(\.dismiss) private var dismiss
    
    let neonPurple = Color(red: 0.6, green: 0.3, blue: 1.0)
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Text("Set your daily protein target")
                    .font(IronFont.body(15))
                    .foregroundColor(.ironTextSecondary)
                
                HStack(spacing: 16) {
                    Button {
                        if protein > 50 { protein -= 10 }
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .font(.system(size: 32))
                            .foregroundColor(neonPurple)
                    }
                    
                    Text("\(protein)g")
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .frame(minWidth: 120)
                    
                    Button {
                        if protein < 300 { protein += 10 }
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 32))
                            .foregroundColor(neonPurple)
                    }
                }
                
                Spacer()
            }
            .padding(.top, 24)
            .navigationTitle("Protein Target")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: onSave)
                        .fontWeight(.semibold)
                }
            }
        }
    }
}

// MARK: - Sleep Editor Sheet
struct SleepEditorSheet: View {
    @Binding var sleep: Double
    let onSave: () -> Void
    @Environment(\.dismiss) private var dismiss
    
    let neonPurple = Color(red: 0.6, green: 0.3, blue: 1.0)
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Text("Set your sleep target")
                    .font(IronFont.body(15))
                    .foregroundColor(.ironTextSecondary)
                
                VStack(spacing: 12) {
                    Text(String(format: "%.1f hrs", sleep))
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    
                    Slider(value: $sleep, in: 5...10, step: 0.5)
                        .tint(neonPurple)
                        .padding(.horizontal, 20)
                    
                    HStack {
                        Text("5 hrs")
                            .font(IronFont.body(12))
                            .foregroundColor(.ironTextTertiary)
                        Spacer()
                        Text("10 hrs")
                            .font(IronFont.body(12))
                            .foregroundColor(.ironTextTertiary)
                    }
                    .padding(.horizontal, 20)
                }
                
                Spacer()
            }
            .padding(.top, 24)
            .navigationTitle("Sleep Target")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: onSave)
                        .fontWeight(.semibold)
                }
            }
        }
    }
}

// MARK: - Achievement Badges Section
struct AchievementBadgesSection: View {
    let workoutStore: WorkoutStore
    let neonPurple: Color
    
    @State private var selectedTrack: BadgeTrack = .volume
    
    // Check if HealthKit has been connected (stored when user completes HealthKit onboarding)
    private var hasHealthKitConnected: Bool {
        UserDefaults.standard.bool(forKey: "hasConnectedHealthKit")
    }
    
    // Check if notifications are enabled
    private var hasNotificationsEnabled: Bool {
        UserDefaults.standard.bool(forKey: "hasEnabledNotifications")
    }
    
    // User is signed up if they can see this view (they're authenticated)
    private var isSignedUp: Bool {
        true // Always true since you must be signed in to see Profile
    }
    
    // MARK: - Computed Stats
    private var completedWorkouts: Int {
        workoutStore.sessions.filter { $0.endedAt != nil }.count
    }
    
    private var currentStreak: Int {
        calculateCurrentStreak()
    }
    
    private var longestStreak: Int {
        calculateLongestStreak()
    }
    
    private var hasCompletedFullPlan: Bool {
        // Check if any session completed all exercises
        workoutStore.sessions.contains { session in
            session.endedAt != nil && session.exercises.allSatisfy { $0.isCompleted }
        }
    }
    
    private var uniqueWorkoutTypes: Int {
        // Count unique template types used
        Set(workoutStore.sessions.compactMap { $0.templateId }).count
    }
    
    private var personalRecords: Int {
        // Simplified: count exercises with improving e1rm trend
        workoutStore.exerciseStates.values.filter { $0.e1rmTrend == .improving }.count
    }
    
    // MARK: - Badge Tracks
    enum BadgeTrack: String, CaseIterable {
        case volume = "Volume"
        case streaks = "Streaks"
        case strength = "Strength"
        case milestones = "Milestones"
        
        var icon: String {
            switch self {
            case .volume: return "flame.fill"
            case .streaks: return "link"
            case .strength: return "scalemass.fill"
            case .milestones: return "flag.fill"
            }
        }
    }
    
    // MARK: - Tier Colors (Bronze → Silver → Gold progression)
    static let tierBronze = Color(red: 0.80, green: 0.50, blue: 0.20)
    static let tierSilver = Color(red: 0.75, green: 0.75, blue: 0.80)
    static let tierGold = Color(red: 1.0, green: 0.84, blue: 0.0)
    static let tierPlatinum = Color(red: 0.90, green: 0.95, blue: 1.0)
    
    // MARK: - Volume Track Badges (Workout Count)
    private var volumeBadges: [AchievementBadge] {
        [
            AchievementBadge(
                id: "first_rep",
                name: "First Rep",
                description: "Complete your first workout",
                icon: "play.fill",
                tier: .bronze,
                tierNumber: 1,
                isUnlocked: completedWorkouts >= 1
            ),
            AchievementBadge(
                id: "momentum",
                name: "Momentum",
                description: "Complete 5 workouts",
                icon: "bolt.fill",
                tier: .bronze,
                tierNumber: 2,
                isUnlocked: completedWorkouts >= 5
            ),
            AchievementBadge(
                id: "routine",
                name: "Routine",
                description: "Complete 10 workouts",
                icon: "calendar.badge.checkmark",
                tier: .silver,
                tierNumber: 1,
                isUnlocked: completedWorkouts >= 10
            ),
            AchievementBadge(
                id: "consistency",
                name: "Consistency",
                description: "Complete 25 workouts",
                icon: "link",
                tier: .silver,
                tierNumber: 2,
                isUnlocked: completedWorkouts >= 25
            ),
            AchievementBadge(
                id: "grit",
                name: "Grit",
                description: "Complete 50 workouts",
                icon: "shield.fill",
                tier: .gold,
                tierNumber: 1,
                isUnlocked: completedWorkouts >= 50
            ),
            AchievementBadge(
                id: "centurion",
                name: "Centurion",
                description: "Complete 100 workouts",
                icon: "laurel.leading",
                tier: .platinum,
                tierNumber: 1,
                isUnlocked: completedWorkouts >= 100
            )
        ]
    }
    
    // MARK: - Streak Track Badges
    private var streakBadges: [AchievementBadge] {
        [
            AchievementBadge(
                id: "on_a_roll",
                name: "On a Roll",
                description: "3-day workout streak",
                icon: "calendar",
                tier: .bronze,
                tierNumber: 1,
                isUnlocked: longestStreak >= 3
            ),
            AchievementBadge(
                id: "weekly_rhythm",
                name: "Weekly Rhythm",
                description: "7-day workout streak",
                icon: "calendar.badge.checkmark",
                tier: .bronze,
                tierNumber: 2,
                isUnlocked: longestStreak >= 7
            ),
            AchievementBadge(
                id: "unbreakable",
                name: "Unbreakable",
                description: "21-day workout streak",
                icon: "link",
                tier: .silver,
                tierNumber: 1,
                isUnlocked: longestStreak >= 21
            ),
            AchievementBadge(
                id: "comeback",
                name: "Comeback",
                description: "Workout after 7+ days off",
                icon: "arrow.uturn.backward",
                tier: .silver,
                tierNumber: 2,
                isUnlocked: hasComeback()
            ),
            AchievementBadge(
                id: "perfect_week",
                name: "Perfect Week",
                description: "Hit your weekly goal",
                icon: "checkmark.seal.fill",
                tier: .gold,
                tierNumber: 1,
                isUnlocked: hasPerfectWeek()
            ),
            AchievementBadge(
                id: "month_warrior",
                name: "Month Warrior",
                description: "30-day workout streak",
                icon: "flame.fill",
                tier: .platinum,
                tierNumber: 1,
                isUnlocked: longestStreak >= 30
            )
        ]
    }
    
    // MARK: - Strength Track Badges
    private var strengthBadges: [AchievementBadge] {
        [
            AchievementBadge(
                id: "pr_pop",
                name: "PR Pop",
                description: "Set your first personal record",
                icon: "arrow.up",
                tier: .bronze,
                tierNumber: 1,
                isUnlocked: personalRecords >= 1
            ),
            AchievementBadge(
                id: "stacked",
                name: "Stacked",
                description: "Set 5 personal records",
                icon: "square.stack.3d.up.fill",
                tier: .bronze,
                tierNumber: 2,
                isUnlocked: personalRecords >= 5
            ),
            AchievementBadge(
                id: "no_skips",
                name: "No Skips",
                description: "Complete a full workout plan",
                icon: "checklist",
                tier: .silver,
                tierNumber: 1,
                isUnlocked: hasCompletedFullPlan
            ),
            AchievementBadge(
                id: "explorer",
                name: "Explorer",
                description: "Try 5 different workouts",
                icon: "map.fill",
                tier: .silver,
                tierNumber: 2,
                isUnlocked: uniqueWorkoutTypes >= 5
            ),
            AchievementBadge(
                id: "pr_hunter",
                name: "PR Hunter",
                description: "Set 10 personal records",
                icon: "target",
                tier: .gold,
                tierNumber: 1,
                isUnlocked: personalRecords >= 10
            ),
            AchievementBadge(
                id: "iron_master",
                name: "Iron Master",
                description: "Set 25 personal records",
                icon: "trophy.fill",
                tier: .platinum,
                tierNumber: 1,
                isUnlocked: personalRecords >= 25
            )
        ]
    }
    
    // MARK: - Milestones Track Badges
    private var milestoneBadges: [AchievementBadge] {
        [
            AchievementBadge(
                id: "welcome",
                name: "Welcome",
                description: "Create your account",
                icon: "person.crop.circle.badge.checkmark",
                tier: .bronze,
                tierNumber: 1,
                isUnlocked: isSignedUp
            ),
            AchievementBadge(
                id: "health_sync",
                name: "Health Sync",
                description: "Connect Apple Health",
                icon: "heart.circle.fill",
                tier: .bronze,
                tierNumber: 2,
                isUnlocked: hasHealthKitConnected
            ),
            AchievementBadge(
                id: "notifications_on",
                name: "Stay Alert",
                description: "Enable notifications",
                icon: "bell.badge.fill",
                tier: .bronze,
                tierNumber: 3,
                isUnlocked: hasNotificationsEnabled
            ),
            AchievementBadge(
                id: "first_week",
                name: "First Week",
                description: "3 workouts in your first 7 days",
                icon: "flag.fill",
                tier: .silver,
                tierNumber: 1,
                isUnlocked: hasFirstWeekComplete()
            ),
            AchievementBadge(
                id: "template_builder",
                name: "Template Builder",
                description: "Create your first custom workout",
                icon: "hammer.fill",
                tier: .silver,
                tierNumber: 1,
                isUnlocked: workoutStore.templates.count >= 1
            ),
            AchievementBadge(
                id: "ten_weeks",
                name: "Ten Weeks Strong",
                description: "10 weeks with 2+ workouts each",
                icon: "calendar",
                tier: .silver,
                tierNumber: 1,
                isUnlocked: hasTenWeeksStrong()
            ),
            AchievementBadge(
                id: "early_bird",
                name: "Early Bird",
                description: "Workout before 8am",
                icon: "sunrise.fill",
                tier: .silver,
                tierNumber: 2,
                isUnlocked: hasEarlyBirdWorkout()
            ),
            AchievementBadge(
                id: "night_owl",
                name: "Night Owl",
                description: "Workout after 9pm",
                icon: "moon.fill",
                tier: .gold,
                tierNumber: 1,
                isUnlocked: hasNightOwlWorkout()
            ),
            AchievementBadge(
                id: "collector",
                name: "The Collector",
                description: "Earn 15 badges",
                icon: "square.stack.fill",
                tier: .platinum,
                tierNumber: 1,
                // Use non-milestone badges to avoid circular dependency
                isUnlocked: nonMilestoneUnlockedBadges >= 15
            )
        ]
    }
    
    private var currentBadges: [AchievementBadge] {
        switch selectedTrack {
        case .volume: return volumeBadges
        case .streaks: return streakBadges
        case .strength: return strengthBadges
        case .milestones: return milestoneBadges
        }
    }
    
    /// Count of unlocked badges from volume, streaks, and strength tracks (excluding milestones to avoid circular dependency)
    private var nonMilestoneUnlockedBadges: Int {
        volumeBadges.filter { $0.isUnlocked }.count +
        streakBadges.filter { $0.isUnlocked }.count +
        strengthBadges.filter { $0.isUnlocked }.count
    }
    
    private var totalUnlockedBadges: Int {
        nonMilestoneUnlockedBadges +
        milestoneBadges.filter { $0.isUnlocked }.count
    }
    
    private var totalBadges: Int {
        volumeBadges.count + streakBadges.count + strengthBadges.count + milestoneBadges.count
    }
    
    var body: some View {
        VStack(spacing: 12) {
            // Section Label with total count
            HStack {
                Text("ACHIEVEMENTS")
                    .font(IronFont.header(10))
                    .tracking(3)
                    .foregroundColor(Color(red: 0.61, green: 0.64, blue: 0.69))
                
                Spacer()
                
                Text("\(totalUnlockedBadges)/\(totalBadges)")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(neonPurple)
            }
            
            // Track Selector
            HStack(spacing: 8) {
                ForEach(BadgeTrack.allCases, id: \.self) { track in
                    BadgeTrackTab(
                        track: track,
                        isSelected: selectedTrack == track,
                        unlockedCount: badgesUnlockedIn(track: track),
                        totalCount: badgesIn(track: track).count,
                        neonPurple: neonPurple
                    ) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedTrack = track
                        }
                    }
                }
            }
            
            // Badges Grid
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                ForEach(currentBadges) { badge in
                    BadgeCard(badge: badge)
                }
            }
        }
    }
    
    // MARK: - Helper Methods
    private func badgesIn(track: BadgeTrack) -> [AchievementBadge] {
        switch track {
        case .volume: return volumeBadges
        case .streaks: return streakBadges
        case .strength: return strengthBadges
        case .milestones: return milestoneBadges
        }
    }
    
    private func badgesUnlockedIn(track: BadgeTrack) -> Int {
        badgesIn(track: track).filter { $0.isUnlocked }.count
    }
    
    private func calculateCurrentStreak() -> Int {
        let sessions = workoutStore.sessions.filter { $0.endedAt != nil }
            .sorted { $0.startedAt > $1.startedAt }
        guard !sessions.isEmpty else { return 0 }
        
        let calendar = Calendar.current
        var streak = 0
        var currentDate = calendar.startOfDay(for: Date())
        
        for session in sessions {
            let sessionDay = calendar.startOfDay(for: session.startedAt)
            let previousDay = calendar.date(byAdding: .day, value: -1, to: currentDate)
            
            if sessionDay == currentDate || sessionDay == previousDay {
                streak += 1
                currentDate = sessionDay
            } else if let prevDay = previousDay, sessionDay < prevDay {
                break
            }
        }
        return streak
    }
    
    private func calculateLongestStreak() -> Int {
        let sessions = workoutStore.sessions.filter { $0.endedAt != nil }
            .sorted { $0.startedAt < $1.startedAt }
        guard !sessions.isEmpty else { return 0 }
        
        let calendar = Calendar.current
        var longestStreak = 1
        var currentStreak = 1
        var lastDate = calendar.startOfDay(for: sessions[0].startedAt)
        
        for session in sessions.dropFirst() {
            let sessionDay = calendar.startOfDay(for: session.startedAt)
            if sessionDay == lastDate {
                continue // Same day
            } else if sessionDay == calendar.date(byAdding: .day, value: 1, to: lastDate) {
                currentStreak += 1
                longestStreak = max(longestStreak, currentStreak)
            } else {
                currentStreak = 1
            }
            lastDate = sessionDay
        }
        return longestStreak
    }
    
    private func hasComeback() -> Bool {
        let sessions = workoutStore.sessions.filter { $0.endedAt != nil }
            .sorted { $0.startedAt < $1.startedAt }
        guard sessions.count >= 2 else { return false }
        
        let calendar = Calendar.current
        for i in 1..<sessions.count {
            let daysBetween = calendar.dateComponents([.day], from: sessions[i-1].startedAt, to: sessions[i].startedAt).day ?? 0
            if daysBetween >= 7 {
                return true
            }
        }
        return false
    }
    
    private func hasPerfectWeek() -> Bool {
        // Check if any week had the target number of workouts
        // Simplified: just check if weekly frequency was met in any week
        let sessions = workoutStore.sessions.filter { $0.endedAt != nil }
        guard !sessions.isEmpty else { return false }
        
        let calendar = Calendar.current
        var weekCounts: [Int: Int] = [:]
        
        for session in sessions {
            let weekOfYear = calendar.component(.weekOfYear, from: session.startedAt)
            let year = calendar.component(.year, from: session.startedAt)
            let key = year * 100 + weekOfYear
            weekCounts[key, default: 0] += 1
        }
        
        // Check if any week met at least 4 workouts (reasonable default)
        return weekCounts.values.contains { $0 >= 4 }
    }
    
    private func hasFirstWeekComplete() -> Bool {
        let sessions = workoutStore.sessions.filter { $0.endedAt != nil }
            .sorted { $0.startedAt < $1.startedAt }
        guard let firstSession = sessions.first else { return false }
        
        let calendar = Calendar.current
        guard let firstWeekEnd = calendar.date(byAdding: .day, value: 7, to: firstSession.startedAt) else { return false }
        let firstWeekSessions = sessions.filter { $0.startedAt <= firstWeekEnd }
        return firstWeekSessions.count >= 3
    }
    
    private func hasTenWeeksStrong() -> Bool {
        let sessions = workoutStore.sessions.filter { $0.endedAt != nil }
        guard !sessions.isEmpty else { return false }
        
        let calendar = Calendar.current
        var weekCounts: [Int: Int] = [:]
        
        for session in sessions {
            let weekOfYear = calendar.component(.weekOfYear, from: session.startedAt)
            let year = calendar.component(.year, from: session.startedAt)
            let key = year * 100 + weekOfYear
            weekCounts[key, default: 0] += 1
        }
        
        let weeksWithTwoPlus = weekCounts.values.filter { $0 >= 2 }.count
        return weeksWithTwoPlus >= 10
    }
    
    private func hasEarlyBirdWorkout() -> Bool {
        let sessions = workoutStore.sessions.filter { $0.endedAt != nil }
        let calendar = Calendar.current
        return sessions.contains { session in
            let hour = calendar.component(.hour, from: session.startedAt)
            return hour < 8
        }
    }
    
    private func hasNightOwlWorkout() -> Bool {
        let sessions = workoutStore.sessions.filter { $0.endedAt != nil }
        let calendar = Calendar.current
        return sessions.contains { session in
            let hour = calendar.component(.hour, from: session.startedAt)
            return hour >= 21
        }
    }
}

// MARK: - Badge Track Tab
struct BadgeTrackTab: View {
    let track: AchievementBadgesSection.BadgeTrack
    let isSelected: Bool
    let unlockedCount: Int
    let totalCount: Int
    let neonPurple: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: track.icon)
                    .font(.system(size: 14, weight: .medium))
                
                Text("\(unlockedCount)/\(totalCount)")
                    .font(.system(size: 9, weight: .semibold))
            }
            .foregroundColor(isSelected ? neonPurple : .white.opacity(0.4))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? neonPurple.opacity(0.15) : Color.white.opacity(0.03))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(isSelected ? neonPurple.opacity(0.4) : Color.white.opacity(0.06), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Achievement Badge Model
struct AchievementBadge: Identifiable {
    let id: String
    let name: String
    let description: String
    let icon: String
    let tier: BadgeTier
    let tierNumber: Int // 1 or 2 within tier
    let isUnlocked: Bool
    
    enum BadgeTier {
        case bronze, silver, gold, platinum
        
        var color: Color {
            switch self {
            case .bronze: return Color(red: 0.80, green: 0.50, blue: 0.20)
            case .silver: return Color(red: 0.75, green: 0.75, blue: 0.80)
            case .gold: return Color(red: 1.0, green: 0.84, blue: 0.0)
            case .platinum: return Color(red: 0.85, green: 0.92, blue: 1.0)
            }
        }
        
        var borderStyle: StrokeStyle {
            switch self {
            case .bronze: return StrokeStyle(lineWidth: 2)
            case .silver: return StrokeStyle(lineWidth: 2)
            case .gold: return StrokeStyle(lineWidth: 2.5)
            case .platinum: return StrokeStyle(lineWidth: 3, dash: [4, 2])
            }
        }
    }
}

// MARK: - Badge Card
struct BadgeCard: View {
    let badge: AchievementBadge
    
    var body: some View {
        VStack(spacing: 6) {
            // Badge Icon with tier frame
            ZStack {
                // Tier border (visible for unlocked)
                Circle()
                    .stroke(
                        badge.isUnlocked ? badge.tier.color : Color.white.opacity(0.08),
                        style: badge.isUnlocked ? badge.tier.borderStyle : StrokeStyle(lineWidth: 1.5)
                    )
                    .frame(width: 52, height: 52)
                
                // Inner fill
                Circle()
                    .fill(
                        badge.isUnlocked
                            ? badge.tier.color.opacity(0.15)
                            : Color.white.opacity(0.02)
                    )
                    .frame(width: 46, height: 46)
                
                // Icon
                Image(systemName: badge.icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(badge.isUnlocked ? badge.tier.color : Color.white.opacity(0.15))
                    .shadow(color: badge.isUnlocked ? badge.tier.color.opacity(0.4) : .clear, radius: 3)
                
                // Tier dots (accessibility - bottom center)
                if badge.isUnlocked {
                    VStack {
                        Spacer()
                        TierDots(tier: badge.tier, tierNumber: badge.tierNumber)
                            .offset(y: 4)
                    }
                    .frame(width: 52, height: 52)
                }
            }
            
            // Badge Name
            Text(badge.name)
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(badge.isUnlocked ? .white : .white.opacity(0.25))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .frame(height: 24)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.white.opacity(badge.isUnlocked ? 0.03 : 0.015))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(
                            badge.isUnlocked ? badge.tier.color.opacity(0.2) : Color.white.opacity(0.04),
                            lineWidth: 1
                        )
                )
        )
    }
}

// MARK: - Tier Dots (for accessibility/colorblind users)
struct TierDots: View {
    let tier: AchievementBadge.BadgeTier
    let tierNumber: Int
    
    private var dotCount: Int {
        switch tier {
        case .bronze: return 1
        case .silver: return 2
        case .gold: return 3
        case .platinum: return 4
        }
    }
    
    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<dotCount, id: \.self) { _ in
                Circle()
                    .fill(tier.color)
                    .frame(width: 3, height: 3)
            }
        }
    }
}

// MARK: - Holographic ID Header
struct HolographicIDHeader: View {
    let name: String
    let experience: WorkoutExperience
    let neonPurple: Color
    
    @State private var scannerRotation: Double = 0
    
    private var experienceLevel: Int {
        switch experience {
        case .newbie: return 1
        case .beginner: return 2
        case .intermediate: return 3
        case .advanced: return 4
        case .expert: return 5
        }
    }
    
    var body: some View {
        VStack(spacing: 16) {
            // Operative Status Label
            Text("OPERATIVE STATUS")
                .font(IronFont.header(11))
                .tracking(4)
                .foregroundColor(Color(red: 0.61, green: 0.64, blue: 0.69))
            
            // Holographic Avatar with Scanner Ring
            ZStack {
                // Outer scanner ring - rotating dashed circle
                Circle()
                    .stroke(
                        neonPurple.opacity(0.4),
                        style: StrokeStyle(lineWidth: 1.5, dash: [4, 6])
                    )
                    .frame(width: 100, height: 100)
                    .rotationEffect(.degrees(scannerRotation))
                
                // Inner glow ring
                Circle()
                    .stroke(
                        LinearGradient(
                            colors: [neonPurple.opacity(0.6), neonPurple.opacity(0.2)],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 2
                    )
                    .frame(width: 88, height: 88)
                    .shadow(color: neonPurple.opacity(0.5), radius: 8)
                
                // Glass hexagon avatar
                HexagonShape()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color.white.opacity(0.08),
                                Color.white.opacity(0.02),
                                neonPurple.opacity(0.1)
                            ],
                            center: UnitPoint(x: 0.3, y: 0.3),
                            startRadius: 0,
                            endRadius: 50
                        )
                    )
                    .frame(width: 70, height: 70)
                    .overlay(
                        HexagonShape()
                            .stroke(
                                LinearGradient(
                                    colors: [Color.white.opacity(0.4), neonPurple.opacity(0.3), Color.white.opacity(0.1)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1.5
                            )
                    )
                    .shadow(color: neonPurple.opacity(0.3), radius: 12)
                
                // Initial letter
                Text(String(name.prefix(1)).uppercased())
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.white, Color.white.opacity(0.8)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .shadow(color: neonPurple.opacity(0.6), radius: 4)
            }
            
            // Name with Signal Bars
            HStack(spacing: 10) {
                Text(name)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                
                // Signal bars for rank
                SignalBarsIndicator(level: experienceLevel, maxLevel: 5, neonPurple: neonPurple)
            }
        }
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 24)
                    .fill(.ultraThinMaterial.opacity(0.4))
                
                RoundedRectangle(cornerRadius: 24)
                    .fill(Color.white.opacity(0.02))
                
                // Top glossy reflection
                VStack {
                    RoundedRectangle(cornerRadius: 24)
                        .fill(
                            LinearGradient(
                                colors: [Color.white.opacity(0.08), Color.clear],
                                startPoint: .top,
                                endPoint: .center
                            )
                        )
                        .frame(height: 60)
                    Spacer()
                }
                .clipShape(RoundedRectangle(cornerRadius: 24))
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .stroke(
                    LinearGradient(
                        colors: [Color.white.opacity(0.2), neonPurple.opacity(0.2), Color.white.opacity(0.05)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .onAppear {
            withAnimation(.linear(duration: 8).repeatForever(autoreverses: false)) {
                scannerRotation = 360
            }
        }
    }
}

// MARK: - Signal Bars Indicator
struct SignalBarsIndicator: View {
    let level: Int
    let maxLevel: Int
    let neonPurple: Color
    
    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<maxLevel, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(
                        i < level
                            ? LinearGradient(colors: [neonPurple, neonPurple.opacity(0.7)], startPoint: .top, endPoint: .bottom)
                            : LinearGradient(colors: [Color.white.opacity(0.15)], startPoint: .top, endPoint: .bottom)
                    )
                    .frame(width: 4, height: CGFloat(6 + i * 3))
                    .shadow(color: i < level ? neonPurple.opacity(0.5) : .clear, radius: 3)
            }
        }
    }
}

// MARK: - Training Bento Grid
struct TrainingBentoGrid: View {
    let split: WorkoutSplit
    let frequency: Int
    let gymType: GymType
    let neonPurple: Color
    
    var body: some View {
        VStack(spacing: 10) {
            // Section Label
            HStack {
                Text("TRAINING PROTOCOL")
                    .font(IronFont.header(10))
                    .tracking(3)
                    .foregroundColor(Color(red: 0.61, green: 0.64, blue: 0.69))
                Spacer()
            }
            
            // Bento Grid Layout
            HStack(spacing: 10) {
                // Split Tile (Square)
                BentoTile(
                    icon: split.icon,
                    label: "SPLIT",
                    value: splitShortName(split),
                    neonPurple: neonPurple
                )
                
                // Frequency Tile (Square)
                BentoFrequencyTile(
                    frequency: frequency,
                    neonPurple: neonPurple
                )
            }
            
            // Gym Type Tile (Wide)
            BentoWideTile(
                icon: gymType.icon,
                label: "TRAINING ENVIRONMENT",
                value: gymType.rawValue.uppercased(),
                neonPurple: neonPurple
            )
        }
    }
    
    private func splitShortName(_ split: WorkoutSplit) -> String {
        switch split {
        case .pushPullLegs: return "PPL"
        case .fullBody: return "FULL"
        case .upperLower: return "U/L"
        case .pushPullLegsArms: return "PPL+"
        case .broSplit: return "BRO"
        case .arnoldSplit: return "ARNOLD"
        case .powerBuilding: return "POWER"
        case .custom: return "CUSTOM"
        }
    }
}

// MARK: - Bento Tile (Square)
struct BentoTile: View {
    let icon: String
    let label: String
    let value: String
    let neonPurple: Color
    
    var body: some View {
        VStack(spacing: 12) {
            // Icon
            ZStack {
                Circle()
                    .fill(neonPurple.opacity(0.15))
                    .frame(width: 44, height: 44)
                
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .light))
                    .foregroundColor(neonPurple)
                    .shadow(color: neonPurple.opacity(0.6), radius: 4)
            }
            
            VStack(spacing: 4) {
                Text(label)
                    .font(.system(size: 9, weight: .medium))
                    .tracking(1.5)
                    .foregroundColor(.white.opacity(0.4))
                
                Text(value)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .background(BentoGlassBackground())
    }
}

// MARK: - Bento Frequency Tile
struct BentoFrequencyTile: View {
    let frequency: Int
    let neonPurple: Color
    
    var body: some View {
        VStack(spacing: 8) {
            // Big frequency number
            Text("\(frequency)")
                .font(.system(size: 42, weight: .bold, design: .rounded))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.white, Color.white.opacity(0.8)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            
            // Frequency bars
            HStack(spacing: 3) {
                ForEach(0..<7, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(
                            i < frequency
                                ? LinearGradient(colors: [neonPurple, neonPurple.opacity(0.6)], startPoint: .top, endPoint: .bottom)
                                : LinearGradient(colors: [Color.white.opacity(0.1)], startPoint: .top, endPoint: .bottom)
                        )
                        .frame(width: 8, height: 4)
                        .shadow(color: i < frequency ? neonPurple.opacity(0.4) : .clear, radius: 2)
                }
            }
            
            Text("DAYS/WEEK")
                .font(.system(size: 9, weight: .medium))
                .tracking(1.5)
                .foregroundColor(.white.opacity(0.4))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(BentoGlassBackground())
    }
}

// MARK: - Bento Wide Tile
struct BentoWideTile: View {
    let icon: String
    let label: String
    let value: String
    let neonPurple: Color
    
    var body: some View {
        HStack(spacing: 16) {
            // Icon
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(neonPurple.opacity(0.15))
                    .frame(width: 50, height: 50)
                
                Image(systemName: icon)
                    .font(.system(size: 22, weight: .light))
                    .foregroundColor(neonPurple)
                    .shadow(color: neonPurple.opacity(0.6), radius: 4)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(label)
                    .font(.system(size: 9, weight: .medium))
                    .tracking(1.5)
                    .foregroundColor(.white.opacity(0.4))
                
                Text(value)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
            }
            
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(BentoGlassBackground())
    }
}

// MARK: - Bento Glass Background
struct BentoGlassBackground: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18)
                .fill(.ultraThinMaterial.opacity(0.4))
            
            RoundedRectangle(cornerRadius: 18)
                .fill(Color.white.opacity(0.02))
            
            // Top glossy reflection
            VStack {
                RoundedRectangle(cornerRadius: 18)
                    .fill(
                        LinearGradient(
                            colors: [Color.white.opacity(0.08), Color.clear],
                            startPoint: .top,
                            endPoint: .center
                        )
                    )
                    .frame(height: 30)
                Spacer()
            }
            .clipShape(RoundedRectangle(cornerRadius: 18))
        }
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

// MARK: - Nutrition & Recovery Gauges
struct NutritionRecoveryGauges: View {
    let proteinGrams: Int
    let sleepHours: Double
    
    var body: some View {
        VStack(spacing: 10) {
            // Section Label
            HStack {
                Text("RECOVERY METRICS")
                    .font(IronFont.header(10))
                    .tracking(3)
                    .foregroundColor(Color(red: 0.61, green: 0.64, blue: 0.69))
                Spacer()
            }
            
            // Protein Gauge
            NutritionGaugeBar(
                label: "DAILY PROTEIN",
                value: "\(proteinGrams)g",
                progress: min(Double(proteinGrams) / 200.0, 1.0),
                gradientColors: [
                    Color(red: 1.0, green: 0.6, blue: 0.2),
                    Color(red: 1.0, green: 0.4, blue: 0.1)
                ]
            )
            
            // Sleep Gauge
            NutritionGaugeBar(
                label: "SLEEP TARGET",
                value: String(format: "%.1f hrs", sleepHours),
                progress: min(sleepHours / 9.0, 1.0),
                gradientColors: [
                    Color(red: 0.2, green: 0.6, blue: 1.0),
                    Color(red: 0.1, green: 0.4, blue: 0.9)
                ]
            )
        }
    }
}

// MARK: - Nutrition Gauge Bar
struct NutritionGaugeBar: View {
    let label: String
    let value: String
    let progress: Double
    let gradientColors: [Color]
    
    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Text(label)
                    .font(.system(size: 10, weight: .medium))
                    .tracking(1.5)
                    .foregroundColor(.white.opacity(0.5))
                
                Spacer()
                
                Text(value)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
            }
            
            // Progress Bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    // Track
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.white.opacity(0.06))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.white.opacity(0.08), lineWidth: 1)
                        )
                    
                    // Fill
                    RoundedRectangle(cornerRadius: 6)
                        .fill(
                            LinearGradient(
                                colors: gradientColors,
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geo.size.width * progress)
                        .shadow(color: gradientColors[0].opacity(0.5), radius: 8)
                }
            }
            .frame(height: 12)
        }
        .padding(16)
        .background(BentoGlassBackground())
    }
}

// MARK: - Connection Monitor Panel
struct ConnectionMonitorPanel: View {
    @State private var pulseOpacity: Double = 0.3
    @ObservedObject private var syncService = DataSyncService.shared
    
    private var hasError: Bool {
        syncService.syncError != nil
    }
    
    private var isSyncing: Bool {
        syncService.isSyncing
    }
    
    private var statusColor: Color {
        if isSyncing { return Color.yellow }
        if hasError { return Color.orange } // Changed from red to orange for less alarming
        if syncService.lastSyncAt != nil { return Color.green }
        return Color.white.opacity(0.5) // Neutral for never synced
    }
    
    private var statusText: String {
        if isSyncing { return "SYNCING..." }
        if hasError { return "SYNC PENDING" } // Less alarming than "CONNECTION FAILED"
        if syncService.lastSyncAt != nil {
            return "DATA SYNCED"
        }
        return "OFFLINE MODE" // Neutral message for never synced
    }
    
    private var statusDescription: String? {
        if hasError {
            return "Will retry on next app launch"
        }
        if syncService.lastSyncAt == nil && !isSyncing {
            return "Data stored locally"
        }
        return nil
    }
    
    var body: some View {
        VStack(spacing: 10) {
            // Section Label
            HStack {
                Text("SYSTEM STATUS")
                    .font(IronFont.header(10))
                    .tracking(3)
                    .foregroundColor(Color(red: 0.61, green: 0.64, blue: 0.69))
                Spacer()
            }
            
            HStack(spacing: 14) {
                // Globe/Link Icon
                ZStack {
                    Circle()
                        .fill(statusColor.opacity(0.15))
                        .frame(width: 44, height: 44)
                    
                    Image(systemName: hasError ? "link.badge.plus" : "globe")
                        .font(.system(size: 20, weight: .light))
                        .foregroundColor(statusColor)
                        .shadow(color: statusColor.opacity(0.6), radius: 4)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(statusText)
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundColor(statusColor)
                    
                    if let lastSync = syncService.lastSyncAt {
                        Text("Last sync: \(lastSync, style: .relative) ago")
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.4))
                    } else if let description = statusDescription {
                        Text(description)
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.4))
                    }
                }
                
                Spacer()
                
                // Status LED
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                    .shadow(color: statusColor.opacity(0.8), radius: 4)
                    .opacity(hasError ? pulseOpacity : 1)
            }
            .padding(16)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 18)
                        .fill(.ultraThinMaterial.opacity(0.4))
                    
                    RoundedRectangle(cornerRadius: 18)
                        .fill(Color.white.opacity(0.02))
                    
                    // Top glossy reflection
                    VStack {
                        RoundedRectangle(cornerRadius: 18)
                            .fill(
                                LinearGradient(
                                    colors: [Color.white.opacity(0.08), Color.clear],
                                    startPoint: .top,
                                    endPoint: .center
                                )
                            )
                            .frame(height: 30)
                        Spacer()
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                }
            )
            .overlay(
                Group {
                    if hasError {
                        RoundedRectangle(cornerRadius: 18)
                            .stroke(Color.red.opacity(pulseOpacity), lineWidth: 1.5)
                    } else {
                        RoundedRectangle(cornerRadius: 18)
                            .stroke(
                                LinearGradient(
                                    colors: [Color.white.opacity(0.15), Color.white.opacity(0.03)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    }
                }
            )
            .shadow(color: hasError ? Color.red.opacity(0.2) : .clear, radius: 12)
        }
        .onAppear {
            if hasError {
                withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                    pulseOpacity = 0.8
                }
            }
        }
    }
}

// MARK: - Tactical Actions Footer
struct TacticalActionsFooter: View {
    let onSignOut: () -> Void
    let onResetOnboarding: () -> Void
    
    var body: some View {
        VStack(spacing: 16) {
            // Section Label
            HStack {
                Text("SYSTEM CONTROLS")
                    .font(IronFont.header(10))
                    .tracking(3)
                    .foregroundColor(Color(red: 0.61, green: 0.64, blue: 0.69))
                Spacer()
            }
            
            HStack(spacing: 12) {
                // Sign Out Button - Silver/Grey
                Button(action: onSignOut) {
                    HStack(spacing: 6) {
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                            .font(.system(size: 12, weight: .medium))
                        Text("SIGN OUT")
                            .font(.system(size: 11, weight: .semibold))
                            .tracking(1)
                    }
                    .foregroundColor(.white.opacity(0.6))
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(
                        Capsule()
                            .fill(Color.white.opacity(0.04))
                            .overlay(
                                Capsule()
                                    .stroke(Color.white.opacity(0.15), lineWidth: 1)
                            )
                    )
                }
                .buttonStyle(PlainButtonStyle())
                
                // Reset Button - Red tint
                Button(action: onResetOnboarding) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 12, weight: .medium))
                        Text("RESET")
                            .font(.system(size: 11, weight: .semibold))
                            .tracking(1)
                    }
                    .foregroundColor(Color.red.opacity(0.8))
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(
                        Capsule()
                            .fill(Color.red.opacity(0.08))
                            .overlay(
                                Capsule()
                                    .stroke(Color.red.opacity(0.25), lineWidth: 1)
                            )
                    )
                    .shadow(color: Color.red.opacity(0.15), radius: 8)
                }
                .buttonStyle(PlainButtonStyle())
                
                Spacer()
            }
            
            // Footer note
            Text("Reset will restart onboarding but keep your account.")
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.25))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}


#Preview {
    MainAppView()
        .environmentObject(AppState())
        .environmentObject(WorkoutStore())
}
