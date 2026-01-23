import SwiftUI

struct MaxesView: View {
    @EnvironmentObject var appState: AppState
    let onContinue: () -> Void
    
    @State private var benchPress: String = ""
    @State private var squat: String = ""
    @State private var deadlift: String = ""
    @State private var overheadPress: String = ""
    @State private var barbellRow: String = ""
    
    let neonPurple = Color(red: 0.6, green: 0.3, blue: 1.0)
    let brightViolet = Color(red: 0.68, green: 0.35, blue: 1.0)
    let deepIndigo = Color(red: 0.38, green: 0.15, blue: 0.72)
    let coolGrey = Color(red: 0.53, green: 0.60, blue: 0.65)
    
    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 24) {
                // Header - Tech/System style
                VStack(spacing: 8) {
                    HStack(spacing: 10) {
                        Text("STRENGTH DATA")
                            .font(IronFont.header(13))
                            .tracking(6)
                            .foregroundColor(coolGrey)
                        
                        Text("OPTIONAL")
                            .font(IronFont.bodySemibold(9))
                            .tracking(2)
                            .foregroundColor(neonPurple)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                Capsule()
                                    .fill(neonPurple.opacity(0.15))
                                    .overlay(Capsule().stroke(neonPurple.opacity(0.3), lineWidth: 1))
                            )
                    }
                    
                    Text("1-REP MAXES")
                        .font(IronFont.headerMedium(22))
                        .tracking(3)
                        .foregroundColor(.white.opacity(0.55))
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 24)
                
                // Big Three
                VStack(spacing: 12) {
                    Text("PRIMARY LIFTS")
                        .font(IronFont.header(10))
                        .tracking(3)
                        .foregroundColor(coolGrey)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    
                    TechMaxInput(title: "Bench Press", icon: "dumbbell", value: $benchPress, placeholder: "225", neonPurple: neonPurple)
                    TechMaxInput(title: "Squat", icon: "figure.strengthtraining.traditional", value: $squat, placeholder: "315", neonPurple: neonPurple)
                    TechMaxInput(title: "Deadlift", icon: "scalemass", value: $deadlift, placeholder: "405", neonPurple: neonPurple)
                }
                
                // Accessories
                VStack(spacing: 12) {
                    Text("ACCESSORY LIFTS")
                        .font(IronFont.header(10))
                        .tracking(3)
                        .foregroundColor(coolGrey)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    
                    TechMaxInput(title: "Overhead Press", icon: "arrow.up.circle", value: $overheadPress, placeholder: "135", neonPurple: neonPurple)
                    TechMaxInput(title: "Barbell Row", icon: "arrow.left.and.right.circle", value: $barbellRow, placeholder: "185", neonPurple: neonPurple)
                }
                
                // Total
                if hasAllBigThree {
                    LiquidGlassTotalCard(
                        bench: Int(benchPress) ?? 0,
                        squat: Int(squat) ?? 0,
                        deadlift: Int(deadlift) ?? 0,
                        neonPurple: neonPurple
                    )
                }
                
                Spacer(minLength: 140)
            }
            .padding(.horizontal, 20)
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 14) {
                TactileGlassButton(
                    title: "NEXT PHASE",
                    isEnabled: true,
                    brightViolet: brightViolet,
                    deepIndigo: deepIndigo
                ) {
                    saveAndContinue()
                }
                
                Button {
                    onContinue()
                } label: {
                    Text("SKIP FOR NOW")
                        .font(IronFont.bodyMedium(12))
                        .tracking(2)
                        .foregroundColor(.white.opacity(0.45)) // More visible
                }
                .padding(.bottom, 4) // Extra spacing from home indicator
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 34) // Pushed up from home indicator
        }
    }
    
    var hasAllBigThree: Bool {
        !benchPress.isEmpty && !squat.isEmpty && !deadlift.isEmpty
    }
    
    private func saveAndContinue() {
        var maxes = LiftMaxes()
        maxes.benchPress = Int(benchPress)
        maxes.squat = Int(squat)
        maxes.deadlift = Int(deadlift)
        maxes.overheadPress = Int(overheadPress)
        maxes.barbellRow = Int(barbellRow)
        appState.userProfile.maxes = maxes
        onContinue()
    }
}

// MARK: - Tech Max Input with Underline
struct TechMaxInput: View {
    let title: String
    let icon: String
    @Binding var value: String
    let placeholder: String
    let neonPurple: Color
    
    @FocusState private var isFocused: Bool
    
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .ultraLight))
                .foregroundColor(neonPurple)
                .shadow(color: neonPurple.opacity(0.5), radius: 4)
                .frame(width: 32)
            
            Text(title.uppercased())
                .font(IronFont.bodySemibold(13))
                .foregroundColor(.white.opacity(0.85))
            
            Spacer()
            
            // Input with underline - proper data readout aesthetic
            VStack(spacing: 4) {
                HStack(alignment: .lastTextBaseline, spacing: 3) {
                    TextField("", text: $value, prompt: 
                        Text(placeholder)
                            .foregroundColor(.white.opacity(0.30)) // Brighter placeholder
                    )
                    .keyboardType(.numberPad)
                    .font(IronFont.digital(24)) // Number: 24pt
                    .foregroundColor(value.isEmpty ? .white.opacity(0.35) : neonPurple)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 60)
                    .focused($isFocused)
                    
                    Text("lbs")
                        .font(IronFont.bodyMedium(12)) // Unit: 12pt (smaller, baseline-aligned)
                        .foregroundColor(.white.opacity(0.4))
                        .offset(y: -1) // Baseline alignment tweak
                }
                
                // Animated underline (2px height)
                Rectangle()
                    .fill(
                        isFocused
                            ? LinearGradient(
                                colors: [neonPurple, Color(red: 0.85, green: 0.71, blue: 0.99)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                            : LinearGradient(
                                colors: [Color(red: 0.22, green: 0.25, blue: 0.32), Color(red: 0.22, green: 0.25, blue: 0.32)], // #374151
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                    )
                    .frame(width: 75, height: 2)
                    .shadow(color: isFocused ? Color(red: 0.85, green: 0.71, blue: 0.99).opacity(0.5) : .clear, radius: 4)
                    .animation(.easeInOut(duration: 0.2), value: isFocused)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(.ultraThinMaterial.opacity(0.4))
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.white.opacity(0.03))
                
                // Top highlight
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
    }
}

struct LiquidGlassTotalCard: View {
    let bench: Int
    let squat: Int
    let deadlift: Int
    let neonPurple: Color
    
    var total: Int { bench + squat + deadlift }
    
    var body: some View {
        VStack(spacing: 14) {
            HStack {
                Text("TOTAL")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(2)
                    .foregroundColor(.white.opacity(0.4))
                Spacer()
                Text("\(total) lbs")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [neonPurple, neonPurple.opacity(0.7)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .shadow(color: neonPurple.opacity(0.4), radius: 6)
            }
            
            GeometryReader { geo in
                HStack(spacing: 2) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.red.opacity(0.6))
                        .frame(width: geo.size.width * CGFloat(bench) / CGFloat(total))
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.blue.opacity(0.6))
                        .frame(width: geo.size.width * CGFloat(squat) / CGFloat(total))
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.green.opacity(0.6))
                        .frame(width: geo.size.width * CGFloat(deadlift) / CGFloat(total))
                }
            }
            .frame(height: 6)
            
            HStack(spacing: 16) {
                LiquidGlassLegendItem(color: .red.opacity(0.6), label: "Bench", value: bench)
                LiquidGlassLegendItem(color: .blue.opacity(0.6), label: "Squat", value: squat)
                LiquidGlassLegendItem(color: .green.opacity(0.6), label: "Deadlift", value: deadlift)
            }
        }
        .padding(18)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(.ultraThinMaterial.opacity(0.5))
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.white.opacity(0.03))
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
    }
}

struct LiquidGlassLegendItem: View {
    let color: Color
    let label: String
    let value: Int
    
    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text("\(label): \(value)")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.white.opacity(0.5))
        }
    }
}

#Preview {
    OnboardingContainerView()
        .environmentObject(AppState())
}




