import SwiftUI

struct GymTypeView: View {
    @EnvironmentObject var appState: AppState
    let onContinue: () -> Void
    
    @State private var selectedGymType: GymType = .commercial
    
    let neonPurple = Color(red: 0.6, green: 0.3, blue: 1.0)
    let brightViolet = Color(red: 0.68, green: 0.35, blue: 1.0)
    let deepIndigo = Color(red: 0.38, green: 0.15, blue: 0.72)
    let coolGrey = Color(red: 0.53, green: 0.60, blue: 0.65)
    
    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 24) {
                // Header - Tech/System style
                VStack(spacing: 8) {
                    Text("TRAINING ENVIRONMENT")
                        .font(IronFont.header(13))
                        .tracking(6)
                        .foregroundColor(coolGrey)
                    
                    Text("WHERE DO YOU TRAIN?")
                        .font(IronFont.headerMedium(22))
                        .tracking(3)
                        .foregroundColor(.white.opacity(0.55))
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 24)
                
                // Gym type list (matching WorkoutSplit style)
                VStack(spacing: 10) {
                    ForEach(GymType.allCases, id: \.self) { gymType in
                        TechGymCard(
                            gymType: gymType,
                            isSelected: selectedGymType == gymType,
                            neonPurple: neonPurple
                        ) {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                selectedGymType = gymType
                            }
                        }
                    }
                }
                
                // Info card - Console/System Note style with left purple accent
                HStack(spacing: 0) {
                    // Left purple accent bar
                    Rectangle()
                        .fill(neonPurple)
                        .frame(width: 2)
                        .shadow(color: neonPurple.opacity(0.5), radius: 4)
                    
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
                            Image(systemName: "terminal")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(neonPurple)
                            
                            Text("SYSTEM NOTE")
                                .font(IronFont.header(10))
                                .tracking(3)
                                .foregroundColor(neonPurple.opacity(0.8))
                        }
                        
                        Text("Workouts optimized for available equipment. Exercise selection calibrated to your training environment.")
                            .font(IronFont.body(12))
                            .foregroundColor(.white.opacity(0.55))
                            .lineSpacing(4)
                    }
                    .padding(.leading, 14)
                    .padding(.trailing, 16)
                    .padding(.vertical, 14)
                }
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.black.opacity(0.6))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.white.opacity(0.06), lineWidth: 1)
                )
                
                Spacer(minLength: 100)
            }
            .padding(.horizontal, 20)
        }
        .safeAreaInset(edge: .bottom) {
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
        appState.userProfile.gymType = selectedGymType
        onContinue()
    }
}

// MARK: - Tech Gym Card (No LED - background shift is the indicator)
struct TechGymCard: View {
    let gymType: GymType
    let isSelected: Bool
    let neonPurple: Color
    let purpleGlow = Color(red: 0.85, green: 0.71, blue: 0.99) // #D8B4FE for glows
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                // Icon in small glass container
                Image(systemName: gymType.icon)
                    .font(.system(size: 20, weight: .ultraLight))
                    .foregroundColor(isSelected ? neonPurple : .white.opacity(0.5))
                    .shadow(color: isSelected ? purpleGlow.opacity(0.6) : .clear, radius: 6)
                    .frame(width: 32, height: 32)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(isSelected ? neonPurple.opacity(0.12) : Color.white.opacity(0.04))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.white.opacity(isSelected ? 0.15 : 0.06), lineWidth: 1)
                            )
                    )
                
                // Text
                VStack(alignment: .leading, spacing: 4) {
                    Text(gymType.rawValue.uppercased())
                        .font(IronFont.bodyMedium(14))
                        .foregroundColor(isSelected ? .white : .white.opacity(0.8))
                    
                    Text(gymType.description)
                        .font(IronFont.bodyMedium(11))
                        .foregroundColor(Color(red: 0.61, green: 0.64, blue: 0.69)) // Silver
                }
                
                Spacer()
                
                // Selection chevron (subtle)
                if isSelected {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(neonPurple.opacity(0.7))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                ZStack {
                    // Base glass layer
                    RoundedRectangle(cornerRadius: 20)
                        .fill(.ultraThinMaterial.opacity(0.4))
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Color.white.opacity(0.03))
                    
                    // Selected: Radial gradient "glow from inside" (0% center fill, 20% purple fading out)
                    if isSelected {
                        RoundedRectangle(cornerRadius: 20)
                            .fill(
                                RadialGradient(
                                    colors: [neonPurple.opacity(0.20), neonPurple.opacity(0.08), Color.clear],
                                    center: .center,
                                    startRadius: 0,
                                    endRadius: 140
                                )
                            )
                    }
                    
                    // Inner glow (light catching curvature)
                    VStack {
                        LinearGradient(
                            colors: [Color.white.opacity(isSelected ? 0.12 : 0.08), Color.clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(height: 25)
                        Spacer()
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                }
            )
            .overlay(
                // Specular ridge: Top brighter than bottom
                RoundedRectangle(cornerRadius: 20)
                    .stroke(
                        LinearGradient(
                            colors: isSelected
                                ? [purpleGlow.opacity(0.5), neonPurple.opacity(0.2), Color.black.opacity(0.2)]
                                : [Color.white.opacity(0.2), Color.white.opacity(0.06), Color.black.opacity(0.15)],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(color: isSelected ? purpleGlow.opacity(0.25) : .clear, radius: 14, y: 5)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

#Preview {
    OnboardingContainerView()
        .environmentObject(AppState())
}
