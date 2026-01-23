import SwiftUI

struct ExperienceView: View {
    @EnvironmentObject var appState: AppState
    let onContinue: () -> Void
    
    @State private var selectedExperience: WorkoutExperience = .beginner
    
    let neonPurple = Color(red: 0.6, green: 0.3, blue: 1.0)
    let brightViolet = Color(red: 0.68, green: 0.35, blue: 1.0)
    let deepIndigo = Color(red: 0.38, green: 0.15, blue: 0.72)
    let coolGrey = Color(red: 0.53, green: 0.60, blue: 0.65)
    
    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 28) {
                // Header - Tech/System style
                VStack(spacing: 8) {
                    Text("TRAINING MATRIX")
                        .font(IronFont.header(13))
                        .tracking(6)
                        .foregroundColor(coolGrey)
                    
                    Text("BIOMETRIC HISTORY")
                        .font(IronFont.headerMedium(22))
                        .tracking(3)
                        .foregroundColor(.white.opacity(0.55))
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 24)
                
                // Experience options - Crystal Growth Cards
                VStack(spacing: 12) {
                    ForEach(Array(WorkoutExperience.allCases.enumerated()), id: \.element) { index, experience in
                        CrystalGrowthExperienceCard(
                            experience: experience,
                            level: index + 1,
                            totalLevels: WorkoutExperience.allCases.count,
                            isSelected: selectedExperience == experience,
                            neonPurple: neonPurple
                        ) {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                                selectedExperience = experience
                            }
                            // Haptic feedback
                            let generator = UIImpactFeedbackGenerator(style: .medium)
                            generator.impactOccurred()
                        }
                    }
                }
                
                Spacer(minLength: 100)
            }
            .padding(.horizontal, 20)
        }
        .safeAreaInset(edge: .bottom) {
            // Tactile glass button with liquid energy sheen
            TactileGlassButton(
                title: "NEXT PHASE",
                isEnabled: true,
                brightViolet: brightViolet,
                deepIndigo: deepIndigo
            ) {
                saveAndContinue()
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 30)
        }
    }
    
    private func saveAndContinue() {
        appState.userProfile.workoutExperience = selectedExperience
        onContinue()
    }
}

// MARK: - Crystal Growth Experience Card (Premium liquid glass with crystal icon)
struct CrystalGrowthExperienceCard: View {
    let experience: WorkoutExperience
    let level: Int
    let totalLevels: Int
    let isSelected: Bool
    let neonPurple: Color
    let purpleGlow = Color(red: 0.85, green: 0.71, blue: 0.99) // #D8B4FE for glows
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                // Crystal Growth Icon in glass container
                CrystalGrowthIcon(
                    level: level,
                    isSelected: isSelected,
                    neonPurple: neonPurple
                )
                .frame(width: 48, height: 48)
                .padding(6)
                .background(
                    ZStack {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(isSelected ? neonPurple.opacity(0.15) : Color.white.opacity(0.03))
                        
                        // Inner glow when selected
                        if isSelected {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(
                                    RadialGradient(
                                        colors: [neonPurple.opacity(0.2), Color.clear],
                                        center: .center,
                                        startRadius: 0,
                                        endRadius: 30
                                    )
                                )
                        }
                    }
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(
                                LinearGradient(
                                    colors: isSelected
                                        ? [neonPurple.opacity(0.5), neonPurple.opacity(0.2)]
                                        : [Color.white.opacity(0.1), Color.white.opacity(0.03)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    )
                )
                
                // Text - vertically centered with crystal
                VStack(alignment: .leading, spacing: 5) {
                    Text(experience.rawValue.uppercased())
                        .font(IronFont.bodyMedium(15))
                        .foregroundColor(isSelected ? .white : .white.opacity(0.85))
                    
                    Text(experience.description)
                        .font(IronFont.bodyMedium(12))
                        .foregroundColor(isSelected ? Color.white.opacity(0.65) : Color(red: 0.55, green: 0.58, blue: 0.62)) // Improved contrast
                        .lineLimit(1)
                }
                
                Spacer()
                
                // Selection indicator - glowing chevron
                if isSelected {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(neonPurple)
                        .shadow(color: neonPurple.opacity(0.6), radius: 4)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            .background(
                ZStack {
                    // Deep frosted glass layer
                    RoundedRectangle(cornerRadius: 22)
                        .fill(.ultraThinMaterial)
                    RoundedRectangle(cornerRadius: 22)
                        .fill(Color.white.opacity(0.03))
                    
                    // Selected: Liquid purple plasma fill
                    if isSelected {
                        RoundedRectangle(cornerRadius: 22)
                            .fill(
                                LinearGradient(
                                    colors: [neonPurple.opacity(0.20), neonPurple.opacity(0.12), neonPurple.opacity(0.05)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                        
                        // Plasma glow effect
                        RoundedRectangle(cornerRadius: 22)
                            .fill(
                                RadialGradient(
                                    colors: [neonPurple.opacity(0.18), neonPurple.opacity(0.08), Color.clear],
                                    center: .leading,
                                    startRadius: 0,
                                    endRadius: 200
                                )
                            )
                    }
                    
                    // Inner glow (light catching curvature) - enhanced for selected
                    VStack {
                        LinearGradient(
                            colors: [Color.white.opacity(isSelected ? 0.18 : 0.10), Color.clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(height: 30)
                        Spacer()
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 22))
                }
            )
            .overlay(
                // Refraction border - enhanced for selected
                RoundedRectangle(cornerRadius: 22)
                    .stroke(
                        LinearGradient(
                            colors: isSelected
                                ? [Color.white.opacity(0.5), purpleGlow.opacity(0.6), neonPurple.opacity(0.3), Color.clear]
                                : [Color.white.opacity(0.25), Color.white.opacity(0.08), Color.clear],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: isSelected ? 1.5 : 1
                    )
            )
            .shadow(color: isSelected ? purpleGlow.opacity(0.35) : .clear, radius: 16, y: 6)
            .shadow(color: isSelected ? neonPurple.opacity(0.2) : .clear, radius: 30, y: 10)
        }
        .buttonStyle(PlainButtonStyle())
        .scaleEffect(isSelected ? 1.02 : 1.0)
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: isSelected)
    }
}

#Preview {
    OnboardingContainerView()
        .environmentObject(AppState())
}
