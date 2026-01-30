import SwiftUI

struct FitnessDetailsView: View {
    @EnvironmentObject var appState: AppState
    let onContinue: () -> Void
    
    @State private var fitnessLevel: FitnessLevel = .intermediate
    @State private var proteinIntake: Int = 150
    @State private var sleepHours: Double = 7.5
    @State private var waterIntake: Double = 3.0
    
    let neonPurple = Color(red: 0.6, green: 0.3, blue: 1.0)
    let brightViolet = Color(red: 0.68, green: 0.35, blue: 1.0)
    let deepIndigo = Color(red: 0.38, green: 0.15, blue: 0.72)
    let coolGrey = Color(red: 0.53, green: 0.60, blue: 0.65)
    
    // Desaturated colors for dark mode
    let proteinColor = Color(red: 0.85, green: 0.55, blue: 0.25) // Desaturated orange
    let sleepColor = Color(red: 0.45, green: 0.40, blue: 0.75)   // Desaturated indigo
    let waterColor = Color(red: 0.35, green: 0.55, blue: 0.65)   // Desaturated cyan
    
    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 24) {
                // Header - Tech/System style
                VStack(spacing: 8) {
                    Text("SYSTEM CALIBRATION")
                        .font(IronFont.header(13))
                        .tracking(6)
                        .foregroundColor(coolGrey)
                    
                    Text("FINE TUNING")
                        .font(IronFont.headerMedium(22))
                        .tracking(3)
                        .foregroundColor(.white.opacity(0.55))
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 32)
                
                // Fitness Level - Glass Segmented Control (larger)
                VStack(alignment: .leading, spacing: 14) {
                    Text("PERFORMANCE TIER")
                        .font(IronFont.header(11))
                        .tracking(3)
                        .foregroundColor(coolGrey)
                    
                    GlassSegmentedControl(
                        selectedLevel: $fitnessLevel,
                        neonPurple: neonPurple
                    )
                    .frame(height: 50)
                }
                .padding(.bottom, 8)
                
                // Nutrition & Recovery
                VStack(spacing: 12) {
                    Text("NUTRITION & RECOVERY")
                        .font(IronFont.header(10))
                        .tracking(3)
                        .foregroundColor(coolGrey)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    
                    TechMetricSlider(
                        title: "Daily Protein",
                        icon: "fork.knife",
                        value: $proteinIntake,
                        range: 50...300,
                        step: 10,
                        unit: "g",
                        color: proteinColor,
                        neonPurple: neonPurple
                    )
                    
                    TechMetricSlider(
                        title: "Sleep",
                        icon: "moon",
                        value: Binding(
                            get: { Int(sleepHours * 2) },
                            set: { sleepHours = Double($0) / 2 }
                        ),
                        range: 8...20,
                        step: 1,
                        unit: "hrs",
                        displayValue: String(format: "%.1f", sleepHours),
                        color: sleepColor,
                        neonPurple: neonPurple
                    )
                    
                    TechMetricSlider(
                        title: "Water Intake",
                        icon: "drop",
                        value: Binding(
                            get: { Int(waterIntake * 2) },
                            set: { waterIntake = Double($0) / 2 }
                        ),
                        range: 2...12,
                        step: 1,
                        unit: "L",
                        displayValue: String(format: "%.1f", waterIntake),
                        color: waterColor,
                        neonPurple: neonPurple
                    )
                }
                
                Spacer(minLength: 100)
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
                .background(Color(red: 0.02, green: 0.02, blue: 0.02))
            }
        }
    }
    
    private func saveAndContinue() {
        appState.userProfile.fitnessLevel = fitnessLevel
        appState.userProfile.dailyProteinGrams = proteinIntake
        appState.userProfile.sleepHours = sleepHours
        appState.userProfile.waterIntakeLiters = waterIntake
        onContinue()
    }
}

// MARK: - Glass Segmented Control (Sliding Glass Door Effect)
struct GlassSegmentedControl: View {
    @Binding var selectedLevel: FitnessLevel
    let neonPurple: Color
    let purpleGlow = Color(red: 0.85, green: 0.71, blue: 0.99)
    
    var body: some View {
        GeometryReader { geo in
            let itemCount = CGFloat(FitnessLevel.allCases.count)
            let itemWidth = (geo.size.width - 8) / itemCount
            let selectedIndex = CGFloat(FitnessLevel.allCases.firstIndex(of: selectedLevel) ?? 0)
            
            ZStack(alignment: .leading) {
                // Dark glass track
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.black.opacity(0.5))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    )
                
                // Sliding glass panel (brighter glass that slides)
                RoundedRectangle(cornerRadius: 10)
                    .fill(
                        LinearGradient(
                            colors: [Color.white.opacity(0.12), Color.white.opacity(0.06)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(neonPurple.opacity(0.12))
                    )
                    .overlay(
                        // Inner glow at top
                        VStack {
                            LinearGradient(
                                colors: [Color.white.opacity(0.2), Color.clear],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                            .frame(height: 15)
                            Spacer()
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(
                                LinearGradient(
                                    colors: [purpleGlow.opacity(0.5), neonPurple.opacity(0.2)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                ),
                                lineWidth: 1
                            )
                    )
                    .shadow(color: purpleGlow.opacity(0.3), radius: 8, y: 2)
                    .frame(width: itemWidth - 2)
                    .padding(4)
                    .offset(x: selectedIndex * itemWidth)
                    .animation(.spring(response: 0.35, dampingFraction: 0.75), value: selectedLevel)
                
                // Labels
                HStack(spacing: 0) {
                    ForEach(FitnessLevel.allCases, id: \.self) { level in
                        let isSelected = selectedLevel == level
                        
                        Button {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                                selectedLevel = level
                            }
                        } label: {
                            Text(level.rawValue.uppercased())
                                .font(IronFont.bodyMedium(9))
                                .tracking(0.5)
                                .foregroundColor(isSelected ? .white : .white.opacity(0.45))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding(.horizontal, 4)
            }
        }
        .frame(height: 44)
    }
}

// MARK: - Tech Metric Slider with Glowing Ring Thumb & Gradient Tracks
struct TechMetricSlider: View {
    let title: String
    let icon: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    let step: Int
    let unit: String
    var displayValue: String? = nil
    let color: Color
    let neonPurple: Color
    
    // Gradient endpoints for each color
    var gradientColors: [Color] {
        // Create gradient from darker to brighter version
        [color.opacity(0.6), color, color.opacity(0.9)]
    }
    
    var body: some View {
        VStack(spacing: 14) {
            HStack {
                HStack(spacing: 10) {
                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .ultraLight))
                        .foregroundColor(color)
                        .shadow(color: color.opacity(0.4), radius: 4)
                        .frame(width: 28)
                    
                    Text(title.uppercased())
                        .font(IronFont.bodyMedium(13))
                        .foregroundColor(.white.opacity(0.85))
                }
                
                Spacer()
                
                HStack(alignment: .lastTextBaseline, spacing: 3) {
                    Text(displayValue ?? "\(value)")
                        .font(IronFont.digital(24))
                        .foregroundColor(color)
                    
                    Text(unit.lowercased())
                        .font(IronFont.bodyMedium(11))
                        .foregroundColor(.white.opacity(0.4))
                }
            }
            
            // Custom slider with glowing ring thumb & gradient track
            GeometryReader { geo in
                let totalWidth = geo.size.width
                let normalizedValue = Double(value - range.lowerBound) / Double(range.upperBound - range.lowerBound)
                let progress = CGFloat(normalizedValue)
                
                ZStack(alignment: .leading) {
                    // Track background
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.white.opacity(0.08))
                        .frame(height: 5)
                    
                    // Lit track - GRADIENT (dark to bright)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(
                            LinearGradient(
                                colors: gradientColors,
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(0, totalWidth * progress), height: 5)
                        .shadow(color: color.opacity(0.5), radius: 5)
                    
                    // Glowing ring thumb (hollow center)
                    ZStack {
                        // Outer glow
                        Circle()
                            .fill(color.opacity(0.2))
                            .frame(width: 24, height: 24)
                            .blur(radius: 4)
                        
                        // Ring
                        Circle()
                            .stroke(
                                LinearGradient(
                                    colors: [color, color.opacity(0.7)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                ),
                                lineWidth: 3
                            )
                            .frame(width: 18, height: 18)
                            .shadow(color: color.opacity(0.6), radius: 6)
                        
                        // Inner highlight
                        Circle()
                            .stroke(Color.white.opacity(0.35), lineWidth: 1)
                            .frame(width: 10, height: 10)
                    }
                    .offset(x: max(0, min(totalWidth - 18, totalWidth * progress - 9)))
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { gesture in
                                let newProgress = min(max(0, gesture.location.x / totalWidth), 1)
                                let newValue = Int(round(Double(range.lowerBound) + newProgress * Double(range.upperBound - range.lowerBound)))
                                let steppedValue = (newValue / step) * step
                                if steppedValue != value && range.contains(steppedValue) {
                                    value = steppedValue
                                    let generator = UIImpactFeedbackGenerator(style: .light)
                                    generator.impactOccurred()
                                }
                            }
                    )
                }
            }
            .frame(height: 24)
        }
        .padding(16)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 20)
                    .fill(.ultraThinMaterial.opacity(0.4))
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color.white.opacity(0.03))
                
                // Inner glow (light catching curvature)
                VStack {
                    LinearGradient(
                        colors: [Color.white.opacity(0.08), Color.clear],
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
            // Specular ridge
            RoundedRectangle(cornerRadius: 20)
                .stroke(
                    LinearGradient(
                        colors: [Color.white.opacity(0.18), Color.white.opacity(0.06), Color.black.opacity(0.15)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1
                )
        )
    }
}

// MARK: - Tech Tip Row
struct TechTipRow: View {
    let text: String
    let neonPurple: Color
    
    var body: some View {
        HStack(spacing: 8) {
            Text(">")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundColor(neonPurple.opacity(0.6))
            
            Text(text)
                .font(IronFont.body(11))
                .foregroundColor(.white.opacity(0.55))
        }
    }
}

#Preview {
    OnboardingContainerView()
        .environmentObject(AppState())
}
