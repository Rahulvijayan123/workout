import SwiftUI

enum OnboardingStep: Int, CaseIterable {
    case healthKit = 0
    case personalInfo = 1
    case experience = 2
    case goals = 3
    case frequency = 4
    case gymType = 5
    case workoutSplit = 6
    case maxes = 7
    case fitnessDetails = 8
    case complete = 9
}

struct OnboardingContainerView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var workoutStore: WorkoutStore
    @State private var currentStep: OnboardingStep = .healthKit
    
    let neonPurple = Color(red: 0.6, green: 0.3, blue: 1.0)
    
    var body: some View {
        ZStack {
            // Deep charcoal background
            Color(red: 0.02, green: 0.02, blue: 0.02)
                .ignoresSafeArea()
            
            // Ambient light blobs for liquid glass
            GeometryReader { geo in
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [neonPurple.opacity(0.4), Color.clear],
                            center: .center,
                            startRadius: 0,
                            endRadius: 200
                        )
                    )
                    .frame(width: 400, height: 400)
                    .offset(x: geo.size.width * 0.3, y: -80)
                
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color(red: 0.1, green: 0.4, blue: 0.8).opacity(0.3), Color.clear],
                            center: .center,
                            startRadius: 0,
                            endRadius: 180
                        )
                    )
                    .frame(width: 360, height: 360)
                    .offset(x: -120, y: geo.size.height * 0.4)
                
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color(red: 0.35, green: 0.2, blue: 0.7).opacity(0.25), Color.clear],
                            center: .center,
                            startRadius: 0,
                            endRadius: 150
                        )
                    )
                    .frame(width: 300, height: 300)
                    .offset(x: geo.size.width * 0.5, y: geo.size.height * 0.7)
            }
            .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header with back button and progress
                HStack {
                    if currentStep != .healthKit {
                        Button {
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                previousStep()
                            }
                        } label: {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundColor(.white.opacity(0.6))
                                .frame(width: 38, height: 38)
                                .background(
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(.ultraThinMaterial.opacity(0.3))
                                        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.03)))
                                )
                                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.1), lineWidth: 1))
                        }
                    } else {
                        Color.clear.frame(width: 38, height: 38)
                    }
                    
                    Spacer()
                    
                    // Progress dots with connected track (liquid light effect)
                    LiquidLightProgressBar(
                        currentStep: currentStep.rawValue,
                        totalSteps: 9,
                        neonPurple: neonPurple
                    )
                    
                    Spacer()
                    
                    Color.clear.frame(width: 38, height: 38)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                
                // Content
                currentStepView
            }
        }
    }
    
    @ViewBuilder
    private var currentStepView: some View {
        switch currentStep {
        case .healthKit:
            HealthKitOnboardingView(onContinue: nextStep)
        case .personalInfo:
            PersonalInfoView(onContinue: nextStep)
        case .experience:
            ExperienceView(onContinue: nextStep)
        case .goals:
            GoalsView(onContinue: nextStep)
        case .frequency:
            FrequencyView(onContinue: nextStep)
        case .gymType:
            GymTypeView(onContinue: nextStep)
        case .workoutSplit:
            WorkoutSplitView(onContinue: nextStep)
        case .maxes:
            MaxesView(onContinue: nextStep)
        case .fitnessDetails:
            FitnessDetailsView(onContinue: nextStep)
        case .complete:
            OnboardingCompleteView(onFinish: completeOnboarding)
        }
    }
    
    private func nextStep() {
        if let nextStepValue = OnboardingStep(rawValue: currentStep.rawValue + 1) {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                currentStep = nextStepValue
            }
        }
    }
    
    private func previousStep() {
        if let prevStepValue = OnboardingStep(rawValue: currentStep.rawValue - 1) {
            currentStep = prevStepValue
        }
    }
    
    private func completeOnboarding() {
        appState.completeOnboarding()
        
        // Perform full sync to Supabase after onboarding
        Task {
            await DataSyncService.shared.performFullSync(
                profile: appState.userProfile,
                templates: workoutStore.templates,
                sessions: workoutStore.sessions,
                liftStates: workoutStore.exerciseStates
            )
        }
    }
}

// MARK: - Liquid Light Progress Bar
struct LiquidLightProgressBar: View {
    let currentStep: Int
    let totalSteps: Int
    let neonPurple: Color
    
    var body: some View {
        ZStack {
            // Faint connecting track (baseline)
            HStack(spacing: 6) {
                ForEach(0..<totalSteps, id: \.self) { i in
                    if i > 0 {
                        // Connecting line segment
                        Rectangle()
                            .fill(Color.white.opacity(0.08))
                            .frame(width: 6, height: 1)
                    }
                    // Placeholder for dot position
                    Color.clear
                        .frame(width: i == currentStep ? 24 : 8, height: 8)
                }
            }
            
            // Lit track up to current step
            HStack(spacing: 6) {
                ForEach(0..<totalSteps, id: \.self) { i in
                    if i > 0 {
                        // Lit connecting line
                        Rectangle()
                            .fill(
                                i <= currentStep
                                    ? neonPurple.opacity(0.5)
                                    : Color.clear
                            )
                            .frame(width: 6, height: 1)
                            .shadow(color: i == currentStep ? neonPurple.opacity(0.4) : .clear, radius: 3)
                    }
                    // Placeholder for dot position
                    Color.clear
                        .frame(width: i == currentStep ? 24 : 8, height: 8)
                }
            }
            
            // Progress dots with glow
            HStack(spacing: 6) {
                ForEach(0..<totalSteps, id: \.self) { i in
                    if i > 0 {
                        // Spacer for connecting line
                        Color.clear
                            .frame(width: 6, height: 1)
                    }
                    
                    let isActive = i == currentStep
                    let isPast = i < currentStep
                    let isNext = i == currentStep + 1
                    
                    // The dot
                    Capsule()
                        .fill(
                            isPast || isActive
                                ? LinearGradient(
                                    colors: [neonPurple, neonPurple.opacity(0.7)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                                : LinearGradient(
                                    colors: [Color.white.opacity(0.15), Color.white.opacity(0.15)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                        )
                        .frame(width: isActive ? 24 : 8, height: 8)
                        .shadow(
                            color: isActive 
                                ? neonPurple.opacity(0.8) 
                                : (isNext ? neonPurple.opacity(0.2) : .clear),
                            radius: isActive ? 8 : 4
                        )
                        .overlay(
                            // Subtle inner highlight for active
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: isActive 
                                            ? [Color.white.opacity(0.4), Color.clear]
                                            : [Color.clear, Color.clear],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                                .padding(1)
                        )
                }
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: currentStep)
    }
}

#Preview {
    OnboardingContainerView()
        .environmentObject(AppState())
        .environmentObject(WorkoutStore())
}
