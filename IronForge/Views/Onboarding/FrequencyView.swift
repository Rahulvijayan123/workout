import SwiftUI

struct FrequencyView: View {
    @EnvironmentObject var appState: AppState
    let onContinue: () -> Void
    
    @State private var selectedDays: Int = 4
    
    let neonPurple = Color(red: 0.6, green: 0.3, blue: 1.0)
    let brightViolet = Color(red: 0.68, green: 0.35, blue: 1.0)
    let deepIndigo = Color(red: 0.38, green: 0.15, blue: 0.72)
    let coolGrey = Color(red: 0.53, green: 0.60, blue: 0.65)
    
    var frequencyLabel: String {
        switch selectedDays {
        case 1: return "Light"
        case 2: return "Casual"
        case 3: return "Moderate"
        case 4: return "Committed"
        case 5: return "Dedicated"
        case 6: return "Intense"
        case 7: return "Elite"
        default: return ""
        }
    }
    
    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 28) {
                // Header - Tech/System style
                VStack(spacing: 8) {
                    Text("TRAINING VOLUME")
                        .font(IronFont.header(13))
                        .tracking(6)
                        .foregroundColor(coolGrey)
                    
                    Text("WEEKLY FREQUENCY")
                        .font(IronFont.headerMedium(22))
                        .tracking(3)
                        .foregroundColor(.white.opacity(0.55))
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 24)
                
                // Big number display with styled description
                VStack(spacing: 8) {
                    Text("\(selectedDays)")
                        .font(IronFont.digital(86))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.white, neonPurple.opacity(0.9)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .shadow(color: neonPurple.opacity(0.5), radius: 20, y: 4)
                        .shadow(color: neonPurple.opacity(0.3), radius: 40, y: 8)
                        .contentTransition(.numericText())
                        .animation(.snappy(duration: 0.15), value: selectedDays)
                    
                    Text("DAYS PER WEEK")
                        .font(IronFont.header(10))
                        .tracking(4)
                        .foregroundColor(.white.opacity(0.35))
                    
                    // Styled frequency description: "Committed" white, "4x per week" purple
                    HStack(spacing: 6) {
                        Text(frequencyLabel)
                            .font(IronFont.bodySemibold(14))
                            .foregroundColor(.white.opacity(0.85))
                        
                        Text("•")
                            .foregroundColor(.white.opacity(0.3))
                        
                        Text("\(selectedDays)x per week")
                            .font(IronFont.bodySemibold(14))
                            .foregroundColor(neonPurple)
                    }
                    .padding(.top, 8)
                }
                .padding(.vertical, 12)
                
                // Frequency Bar (replaces day circles) + Slider
                VStack(spacing: 20) {
                    // Segmented Frequency Bar
                    FrequencyBar(
                        selectedDays: selectedDays,
                        totalDays: 7,
                        neonPurple: neonPurple
                    )
                    
                    // Slider with custom track
                    VStack(spacing: 8) {
                        GeometryReader { geo in
                            let totalWidth = geo.size.width
                            let progress = CGFloat(selectedDays - 1) / 6.0
                            
                            ZStack(alignment: .leading) {
                                // Track background
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color.white.opacity(0.1))
                                    .frame(height: 6)
                                
                                // Lit track
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(
                                        LinearGradient(
                                            colors: [neonPurple, neonPurple.opacity(0.7)],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .frame(width: totalWidth * progress + 16, height: 6)
                                    .shadow(color: neonPurple.opacity(0.5), radius: 6)
                                
                                // Thumb (ring style)
                                ZStack {
                                    Circle()
                                        .stroke(neonPurple, lineWidth: 4)
                                        .frame(width: 22, height: 22)
                                        .shadow(color: neonPurple.opacity(0.7), radius: 8)
                                    
                                    Circle()
                                        .stroke(Color.white.opacity(0.4), lineWidth: 1)
                                        .frame(width: 14, height: 14)
                                }
                                .offset(x: totalWidth * progress)
                                .gesture(
                                    DragGesture(minimumDistance: 0)
                                        .onChanged { value in
                                            let newProgress = min(max(0, value.location.x / totalWidth), 1)
                                            let newDays = Int(round(newProgress * 6)) + 1
                                            if newDays != selectedDays {
                                                selectedDays = newDays
                                                let generator = UIImpactFeedbackGenerator(style: .light)
                                                generator.impactOccurred()
                                            }
                                        }
                                )
                            }
                        }
                        .frame(height: 22)
                        
                        HStack {
                            Text("1 DAY")
                                .font(IronFont.bodySemibold(10))
                                .tracking(1)
                                .foregroundColor(.white.opacity(0.35))
                            Spacer()
                            Text("7 DAYS")
                                .font(IronFont.bodySemibold(10))
                                .tracking(1)
                                .foregroundColor(.white.opacity(0.35))
                        }
                    }
                }
                .padding(20)
                .background(
                    ZStack {
                        RoundedRectangle(cornerRadius: 16)
                            .fill(.ultraThinMaterial.opacity(0.4))
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color.white.opacity(0.03))
                        
                        // Top highlight (glass)
                        VStack {
                            Rectangle()
                                .fill(Color.white.opacity(0.12))
                                .frame(height: 1)
                            Spacer()
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                    }
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
                
                // Tip card - Glass treatment with spark icon (exact same purple)
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 14, weight: .light))
                            .foregroundColor(neonPurple)
                            .shadow(color: neonPurple.opacity(0.6), radius: 6)
                        
                        Text("INSIGHT")
                            .font(IronFont.header(10))
                            .tracking(3)
                            .foregroundColor(neonPurple.opacity(0.8))
                    }
                    
                    Text("For optimal muscle growth, 4-5 days per week allows for adequate training volume while ensuring proper recovery.")
                        .font(IronFont.body(13))
                        .foregroundColor(.white.opacity(0.65))
                        .lineSpacing(4)
                }
                .padding(16)
                .background(
                    ZStack {
                        RoundedRectangle(cornerRadius: 14)
                            .fill(.ultraThinMaterial.opacity(0.35))
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color.white.opacity(0.03))
                        
                        // Top highlight (glass stacking)
                        VStack {
                            Rectangle()
                                .fill(Color.white.opacity(0.10))
                                .frame(height: 1)
                            Spacer()
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
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
        appState.userProfile.weeklyFrequency = selectedDays
        onContinue()
    }
}

// MARK: - Frequency Bar (Segmented Blocks - Battery Meter Style)
struct FrequencyBar: View {
    let selectedDays: Int
    let totalDays: Int
    let neonPurple: Color
    
    var body: some View {
        HStack(spacing: 5) {
            ForEach(1...totalDays, id: \.self) { day in
                let isLit = day <= selectedDays
                
                // Tighter corners (2px) for tech/battery look
                RoundedRectangle(cornerRadius: 2)
                    .fill(
                        isLit
                            ? LinearGradient(
                                colors: [neonPurple, neonPurple.opacity(0.75)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                            : LinearGradient(
                                colors: [Color.white.opacity(0.1), Color.white.opacity(0.06)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                    )
                    .frame(height: 34)
                    .overlay(
                        // Inner top highlight
                        VStack {
                            Rectangle()
                                .fill(Color.white.opacity(isLit ? 0.3 : 0.08))
                                .frame(height: 1)
                            Spacer()
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 2))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 2)
                            .stroke(
                                isLit ? neonPurple.opacity(0.6) : Color.white.opacity(0.08),
                                lineWidth: 1
                            )
                    )
                    .shadow(color: isLit ? neonPurple.opacity(0.5) : .clear, radius: 5, y: 2)
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: selectedDays)
    }
}

#Preview {
    OnboardingContainerView()
        .environmentObject(AppState())
}
