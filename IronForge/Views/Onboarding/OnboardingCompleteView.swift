import SwiftUI

struct OnboardingCompleteView: View {
    @EnvironmentObject var appState: AppState
    let onFinish: () -> Void
    
    @State private var isAnimating = false
    @State private var showContent = false
    @State private var ringRotation: Double = 0
    
    let neonPurple = Color(red: 0.6, green: 0.3, blue: 1.0)
    let purpleGlow = Color(red: 0.85, green: 0.71, blue: 0.99)
    let coolGrey = Color(red: 0.53, green: 0.60, blue: 0.65)
    
    var capitalizedName: String {
        appState.userProfile.name.isEmpty ? "User" : appState.userProfile.name.capitalized
    }
    
    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 20) {
                // Holographic Seal - Glass Orb with Rotating Ring
                ZStack {
                    // Outer rotating dashed ring
                    Circle()
                        .stroke(
                            LinearGradient(
                                colors: [neonPurple.opacity(0.6), purpleGlow.opacity(0.3), neonPurple.opacity(0.4)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            style: StrokeStyle(lineWidth: 2, dash: [8, 6])
                        )
                        .frame(width: 130, height: 130)
                        .rotationEffect(.degrees(ringRotation))
                    
                    // Outer glow rings (pulsing)
                    ForEach(0..<2) { i in
                        Circle()
                            .stroke(
                                LinearGradient(
                                    colors: [neonPurple.opacity(0.2 - Double(i) * 0.08), neonPurple.opacity(0.1 - Double(i) * 0.04)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1.5
                            )
                            .frame(width: CGFloat(150 + i * 25), height: CGFloat(150 + i * 25))
                            .scaleEffect(isAnimating ? 1.03 : 0.97)
                            .opacity(isAnimating ? 0.7 : 0.4)
                            .animation(
                                .easeInOut(duration: 2.5)
                                .repeatForever(autoreverses: true)
                                .delay(Double(i) * 0.2),
                                value: isAnimating
                            )
                    }
                    
                    // Glass Orb
                    ZStack {
                        // Base orb with gradient
                        Circle()
                            .fill(
                                RadialGradient(
                                    colors: [
                                        neonPurple.opacity(0.9),
                                        neonPurple,
                                        neonPurple.opacity(0.8)
                                    ],
                                    center: .center,
                                    startRadius: 0,
                                    endRadius: 50
                                )
                            )
                            .frame(width: 100, height: 100)
                        
                        // Glass overlay (white -> transparent radial)
                        Circle()
                            .fill(
                                RadialGradient(
                                    colors: [
                                        Color.white.opacity(0.2),
                                        Color.white.opacity(0.05),
                                        Color.clear
                                    ],
                                    center: .topLeading,
                                    startRadius: 0,
                                    endRadius: 70
                                )
                            )
                            .frame(width: 100, height: 100)
                        
                        // Top-left specular reflection (crisp white curve)
                        Circle()
                            .trim(from: 0.55, to: 0.75)
                            .stroke(
                                LinearGradient(
                                    colors: [Color.white.opacity(0.8), Color.white.opacity(0.1)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                ),
                                lineWidth: 3
                            )
                            .frame(width: 80, height: 80)
                            .rotationEffect(.degrees(-30))
                        
                        // Small highlight dot
                        Circle()
                            .fill(Color.white.opacity(0.6))
                            .frame(width: 8, height: 8)
                            .offset(x: -24, y: -24)
                            .blur(radius: 2)
                        
                        // Checkmark
                        Image(systemName: "checkmark")
                            .font(.system(size: 40, weight: .bold))
                            .foregroundColor(.white)
                            .shadow(color: .white.opacity(0.5), radius: 4)
                            .scaleEffect(showContent ? 1 : 0)
                            .animation(.spring(response: 0.5, dampingFraction: 0.6).delay(0.3), value: showContent)
                    }
                    .shadow(color: neonPurple.opacity(0.6), radius: 25, x: 0, y: 8)
                    .shadow(color: purpleGlow.opacity(0.3), radius: 40, x: 0, y: 12)
                }
                .padding(.top, 20)
                
                // Text content - Branded copy
                VStack(spacing: 8) {
                    Text("SYSTEM OPTIMIZED")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .tracking(2)
                        .foregroundColor(.white)
                        .opacity(showContent ? 1 : 0)
                        .offset(y: showContent ? 0 : 20)
                        .animation(.easeOut(duration: 0.5).delay(0.4), value: showContent)
                    
                    HStack(spacing: 0) {
                        Text("Training parameters calibrated for ")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.white.opacity(0.5))
                        
                        Text(capitalizedName)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(neonPurple)
                        
                        Text(".")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.white.opacity(0.5))
                    }
                    .opacity(showContent ? 1 : 0)
                    .offset(y: showContent ? 0 : 20)
                    .animation(.easeOut(duration: 0.5).delay(0.5), value: showContent)
                    
                    Text("LET'S WORK.")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(3)
                        .foregroundColor(coolGrey)
                        .padding(.top, 2)
                    .opacity(showContent ? 1 : 0)
                    .animation(.easeOut(duration: 0.5).delay(0.55), value: showContent)
                }
                
                // Visual Summary Card - "Don't Tell Me, Show Me"
                VStack(spacing: 14) {
                    Text("YOUR PROFILE")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(2)
                        .foregroundColor(.white.opacity(0.4))
                    
                    VStack(spacing: 12) {
                        // Split - Icon + Text
                        VisualSummaryRow(
                            label: "SPLIT",
                            icon: appState.userProfile.workoutSplit.icon,
                            value: appState.userProfile.workoutSplit.rawValue,
                            neonPurple: neonPurple
                        )
                        
                        Divider().background(Color.white.opacity(0.08))
                        
                        // Frequency - Battery Bar
                        FrequencySummaryRow(
                            selectedDays: appState.userProfile.weeklyFrequency,
                            neonPurple: neonPurple
                        )
                        
                        Divider().background(Color.white.opacity(0.08))
                        
                        // Goals - Chips/Pills
                        GoalsSummaryRow(
                            goals: appState.userProfile.goals,
                            neonPurple: neonPurple
                        )
                        
                        Divider().background(Color.white.opacity(0.08))
                        
                        // Experience - Signal Bars
                        ExperienceSummaryRow(
                            experience: appState.userProfile.workoutExperience,
                            neonPurple: neonPurple
                        )
                    }
                }
                .padding(18)
                .background(
                    ZStack {
                        RoundedRectangle(cornerRadius: 18)
                            .fill(.ultraThinMaterial.opacity(0.5))
                        RoundedRectangle(cornerRadius: 18)
                            .fill(Color.white.opacity(0.03))
                        VStack {
                            RoundedRectangle(cornerRadius: 18)
                                .fill(
                                    LinearGradient(
                                        colors: [Color.white.opacity(0.1), Color.clear],
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
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
                .opacity(showContent ? 1 : 0)
                .offset(y: showContent ? 0 : 30)
                .animation(.easeOut(duration: 0.5).delay(0.6), value: showContent)
                
                Spacer(minLength: 100)
            }
            .padding(.horizontal, 20)
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 0) {
                LinearGradient(
                    colors: [Color.clear, Color(red: 0.02, green: 0.02, blue: 0.02)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 30)
                
                // Start button
                Button {
                    onFinish()
                } label: {
                    HStack(spacing: 10) {
                        Text("START TRAINING")
                            .font(.system(size: 14, weight: .bold))
                            .tracking(1.5)
                        Image(systemName: "arrow.right")
                            .font(.system(size: 13, weight: .semibold))
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
                .padding(.horizontal, 20)
                .padding(.bottom, 30)
                .background(Color(red: 0.02, green: 0.02, blue: 0.02))
                .opacity(showContent ? 1 : 0)
                .offset(y: showContent ? 0 : 20)
                .animation(.easeOut(duration: 0.5).delay(0.7), value: showContent)
            }
        }
        .onAppear {
            isAnimating = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                showContent = true
            }
            // Start rotating ring animation
            withAnimation(.linear(duration: 20).repeatForever(autoreverses: false)) {
                ringRotation = 360
            }
        }
    }
}

// MARK: - Visual Summary Row (Icon + Text)
struct VisualSummaryRow: View {
    let label: String
    let icon: String
    let value: String
    let neonPurple: Color
    
    var body: some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.system(size: 10, weight: .bold))
                .tracking(1.5)
                .foregroundColor(.white.opacity(0.35))
                .frame(width: 70, alignment: .leading)
            
            // Icon in glass container
            Image(systemName: icon)
                .font(.system(size: 16, weight: .ultraLight))
                .foregroundColor(neonPurple)
                .shadow(color: neonPurple.opacity(0.6), radius: 4)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(neonPurple.opacity(0.12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.white.opacity(0.1), lineWidth: 1)
                        )
                )
            
            Text(value)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white)
            
            Spacer()
        }
    }
}

// MARK: - Frequency Summary Row (Battery Bar)
struct FrequencySummaryRow: View {
    let selectedDays: Int
    let neonPurple: Color
    
    var body: some View {
        HStack(spacing: 12) {
            Text("FREQUENCY")
                .font(.system(size: 10, weight: .bold))
                .tracking(1.5)
                .foregroundColor(.white.opacity(0.35))
                .frame(width: 70, alignment: .leading)
            
            // Mini frequency bar (battery meter)
            HStack(spacing: 3) {
                ForEach(1...7, id: \.self) { day in
                    let isLit = day <= selectedDays
                    
                    RoundedRectangle(cornerRadius: 2)
                        .fill(
                            isLit
                                ? LinearGradient(
                                    colors: [neonPurple, neonPurple.opacity(0.75)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                                : LinearGradient(
                                    colors: [Color.white.opacity(0.12), Color.white.opacity(0.06)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                        )
                        .frame(width: 14, height: 22)
                        .overlay(
                            VStack {
                                Rectangle()
                                    .fill(Color.white.opacity(isLit ? 0.3 : 0.06))
                                    .frame(height: 1)
                                Spacer()
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 2))
                        )
                        .shadow(color: isLit ? neonPurple.opacity(0.4) : .clear, radius: 3, y: 1)
                }
            }
            
            Text("\(selectedDays) days")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white.opacity(0.6))
            
            Spacer()
        }
    }
}

// MARK: - Goals Summary Row (Chips/Pills)
struct GoalsSummaryRow: View {
    let goals: [FitnessGoal]
    let neonPurple: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("GOALS")
                .font(.system(size: 10, weight: .bold))
                .tracking(1.5)
                .foregroundColor(.white.opacity(0.35))
            
            if goals.isEmpty {
                Text("Not set")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.4))
            } else {
                // Wrapping chips layout
                FlowLayout(spacing: 6) {
                    ForEach(goals, id: \.self) { goal in
                        GoalChip(goal: goal, neonPurple: neonPurple)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Goal Chip (Pill)
struct GoalChip: View {
    let goal: FitnessGoal
    let neonPurple: Color
    
    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: goal.icon)
                .font(.system(size: 10, weight: .light))
                .foregroundColor(neonPurple)
            
            Text(goal.rawValue)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white.opacity(0.85))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(neonPurple.opacity(0.12))
                .overlay(
                    Capsule()
                        .stroke(neonPurple.opacity(0.3), lineWidth: 1)
                )
        )
    }
}

// MARK: - Experience Summary Row (Signal Bars)
struct ExperienceSummaryRow: View {
    let experience: WorkoutExperience
    let neonPurple: Color
    
    var experienceLevel: Int {
        switch experience {
        case .newbie: return 1
        case .beginner: return 2
        case .intermediate: return 3
        case .advanced: return 4
        case .expert: return 5
        }
    }
    
    var body: some View {
        HStack(spacing: 12) {
            Text("EXPERIENCE")
                .font(.system(size: 10, weight: .bold))
                .tracking(1.5)
                .foregroundColor(.white.opacity(0.35))
                .frame(width: 70, alignment: .leading)
            
            // Mini signal bars
            MiniSignalBars(
                level: experienceLevel,
                totalLevels: 5,
                neonPurple: neonPurple
            )
            
            Text(experience.rawValue)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white.opacity(0.8))
            
            Spacer()
        }
    }
}

// MARK: - Mini Signal Bars
struct MiniSignalBars: View {
    let level: Int
    let totalLevels: Int
    let neonPurple: Color
    
    var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(1...totalLevels, id: \.self) { bar in
                let isLit = bar <= level
                let barHeight = CGFloat(8 + (bar * 3)) // Progressive heights: 11, 14, 17, 20, 23
                
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(
                        isLit
                            ? neonPurple
                            : Color.white.opacity(0.15)
                    )
                    .frame(width: 5, height: barHeight)
                    .shadow(color: isLit ? neonPurple.opacity(0.5) : .clear, radius: 2)
            }
        }
        .frame(height: 24, alignment: .bottom)
    }
}

// MARK: - Flow Layout (for wrapping chips)
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(in: proposal.width ?? 0, subviews: subviews, spacing: spacing)
        return result.size
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(in: bounds.width, subviews: subviews, spacing: spacing)
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + result.positions[index].x,
                                      y: bounds.minY + result.positions[index].y),
                         proposal: .unspecified)
        }
    }
    
    struct FlowResult {
        var size: CGSize = .zero
        var positions: [CGPoint] = []
        
        init(in width: CGFloat, subviews: Subviews, spacing: CGFloat) {
            var x: CGFloat = 0
            var y: CGFloat = 0
            var rowHeight: CGFloat = 0
            
            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)
                
                if x + size.width > width && x > 0 {
                    x = 0
                    y += rowHeight + spacing
                    rowHeight = 0
                }
                
                positions.append(CGPoint(x: x, y: y))
                rowHeight = max(rowHeight, size.height)
                x += size.width + spacing
                
                self.size.width = max(self.size.width, x - spacing)
            }
            
            self.size.height = y + rowHeight
        }
    }
}

#Preview {
    OnboardingContainerView()
        .environmentObject(AppState())
}
