import SwiftUI

struct GoalsView: View {
    @EnvironmentObject var appState: AppState
    let onContinue: () -> Void
    
    @State private var selectedGoals: Set<FitnessGoal> = []
    
    let neonPurple = Color(red: 0.6, green: 0.3, blue: 1.0)
    let brightViolet = Color(red: 0.68, green: 0.35, blue: 1.0)
    let deepIndigo = Color(red: 0.38, green: 0.15, blue: 0.72)
    let coolGrey = Color(red: 0.53, green: 0.60, blue: 0.65)
    
    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 24) {
                // Header - Tech/System style
                VStack(spacing: 8) {
                    Text("TARGET OBJECTIVES")
                        .font(IronFont.header(13))
                        .tracking(6)
                        .foregroundColor(coolGrey)
                    
                    Text("What do you want\nto achieve?")
                        .font(IronFont.headerMedium(22))
                        .tracking(2)
                        .foregroundColor(.white.opacity(0.55))
                        .multilineTextAlignment(.center)
                    
                    Text("SELECT ALL THAT APPLY")
                        .font(IronFont.bodySemibold(11))
                        .tracking(3)
                        .foregroundColor(Color(red: 0.55, green: 0.60, blue: 0.68)) // Silver
                        .padding(.top, 6)
                }
                .padding(.top, 24)
                
                // Goals grid - taller cards with more spacing
                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 14),
                    GridItem(.flexible(), spacing: 14)
                ], spacing: 14) {
                    ForEach(FitnessGoal.allCases, id: \.self) { goal in
                        TechGoalCard(
                            goal: goal,
                            isSelected: selectedGoals.contains(goal),
                            neonPurple: neonPurple
                        ) {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                if selectedGoals.contains(goal) {
                                    selectedGoals.remove(goal)
                                } else {
                                    selectedGoals.insert(goal)
                                }
                            }
                        }
                    }
                }
                
                Spacer(minLength: 120)
            }
            .padding(.horizontal, 20)
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 0) {
                // Gradient fade from transparent to background
                LinearGradient(
                    colors: [Color.clear, Color(red: 0.02, green: 0.02, blue: 0.02)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 30)
                
                VStack(spacing: 10) {
                    if !selectedGoals.isEmpty {
                        Text("\(selectedGoals.count) OBJECTIVE\(selectedGoals.count == 1 ? "" : "S") SELECTED")
                            .font(IronFont.bodySemibold(10))
                            .tracking(2)
                            .foregroundColor(coolGrey)
                    }
                    
                    TactileGlassButton(
                        title: "NEXT PHASE",
                        isEnabled: !selectedGoals.isEmpty,
                        brightViolet: brightViolet,
                        deepIndigo: deepIndigo
                    ) {
                        saveAndContinue()
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 30)
                .background(Color(red: 0.02, green: 0.02, blue: 0.02))
            }
        }
    }
    
    private func saveAndContinue() {
        appState.userProfile.goals = Array(selectedGoals)
        onContinue()
    }
}

// MARK: - Tech Goal Card (Taller, Geometric)
struct TechGoalCard: View {
    let goal: FitnessGoal
    let isSelected: Bool
    let neonPurple: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 16) { // Increased spacing between icon and text
                // Wireframe icon (thin outline style)
                Image(systemName: goal.icon)
                    .font(.system(size: 28, weight: .ultraLight)) // Thin outlines
                    .foregroundColor(isSelected ? neonPurple : .white.opacity(0.45))
                    .shadow(color: isSelected ? neonPurple.opacity(0.6) : .clear, radius: 8)
                    .frame(height: 32)
                
                Text(goal.rawValue.uppercased())
                    .font(IronFont.bodySemibold(11))
                    .tracking(1)
                    .foregroundColor(isSelected ? .white : .white.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24) // Taller cards
            .padding(.horizontal, 12)
            .background(
                ZStack {
                    // Base glass
                    RoundedRectangle(cornerRadius: 14)
                        .fill(.ultraThinMaterial.opacity(0.35))
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.white.opacity(0.03))
                    
                    // Selected: Purple illumination (consistent color!)
                    if isSelected {
                        RoundedRectangle(cornerRadius: 14)
                            .fill(neonPurple.opacity(0.12))
                            .blur(radius: 1)
                        
                        RoundedRectangle(cornerRadius: 14)
                            .fill(
                                RadialGradient(
                                    colors: [neonPurple.opacity(0.18), Color.clear],
                                    center: .center,
                                    startRadius: 0,
                                    endRadius: 80
                                )
                            )
                    }
                    
                    // Top edge highlight (stacked glass) - ALL cards
                    VStack {
                        Rectangle()
                            .fill(Color.white.opacity(isSelected ? 0.18 : 0.12))
                            .frame(height: 1)
                        Spacer()
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(
                        isSelected
                            ? LinearGradient(
                                colors: [neonPurple.opacity(0.6), neonPurple.opacity(0.25)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                            : LinearGradient(
                                colors: [Color.white.opacity(0.1), Color.white.opacity(0.05)],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                        lineWidth: isSelected ? 1.5 : 1
                    )
            )
            .shadow(color: isSelected ? neonPurple.opacity(0.25) : .clear, radius: 12, y: 4)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

#Preview {
    OnboardingContainerView()
        .environmentObject(AppState())
}
