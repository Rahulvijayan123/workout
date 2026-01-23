import SwiftUI

struct PersonalInfoView: View {
    @EnvironmentObject var appState: AppState
    let onContinue: () -> Void
    
    @State private var name: String = ""
    @State private var age: Int = 25
    @State private var selectedSex: Sex = .male
    @FocusState private var isNameFocused: Bool
    
    let neonPurple = Color(red: 0.6, green: 0.3, blue: 1.0)
    let brightViolet = Color(red: 0.68, green: 0.35, blue: 1.0)
    let deepIndigo = Color(red: 0.38, green: 0.15, blue: 0.72)
    let metallicSilver = Color(red: 0.58, green: 0.60, blue: 0.65)
    
    var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
    }
    
    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 32) {
                // Header - Sleek, metallic, tech font
                VStack(spacing: 8) {
                    Text("ABOUT YOU")
                        .font(IronFont.header(13))
                        .tracking(6)
                        .foregroundColor(Color(red: 0.53, green: 0.60, blue: 0.65)) // #8899A6 cool grey
                    
                    Text("CALIBRATE PROFILE")
                        .font(IronFont.headerMedium(22))
                        .tracking(3)
                        .foregroundColor(.white.opacity(0.55))
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 24)
                
                // Name Input - Cyberpunk Underline Style (Clean)
                CyberpunkNameInput(
                    name: $name,
                    isFocused: $isNameFocused,
                    neonPurple: neonPurple
                )
                
                // Age Selector - The Hero Element with Precision Ruler
                PrecisionAgeRuler(age: $age, neonPurple: neonPurple)
                
                // Sex Selector - Compact, scientific symbols in segmented glass bar (Technical)
                ScientificSexSelector(
                    selectedSex: $selectedSex,
                    neonPurple: neonPurple
                )
                
                Spacer(minLength: 100)
            }
            .padding(.horizontal, 20)
        }
        .safeAreaInset(edge: .bottom) {
            // Tactile, glowing button with liquid energy sheen
            TactileGlassButton(
                title: "NEXT PHASE",
                isEnabled: isValid,
                brightViolet: brightViolet,
                deepIndigo: deepIndigo
            ) {
                saveAndContinue()
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 30)
        }
        .onTapGesture {
            isNameFocused = false
        }
    }
    
    private func saveAndContinue() {
        appState.userProfile.name = name
        appState.userProfile.age = age
        appState.userProfile.sex = selectedSex
        onContinue()
    }
}

// MARK: - Liquid Glass Name Input (Premium contained input)
struct CyberpunkNameInput: View {
    @Binding var name: String
    var isFocused: FocusState<Bool>.Binding
    let neonPurple: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("YOUR NAME")
                .font(IronFont.header(10))
                .tracking(3)
                .foregroundColor(.white.opacity(0.35))
            
            ZStack(alignment: .leading) {
                // Blinking cursor when empty and not focused
                if name.isEmpty && !isFocused.wrappedValue {
                    BlinkingCursor(neonPurple: neonPurple)
                        .padding(.leading, 18)
                }
                
                TextField("", text: $name, prompt: 
                    Text("Enter your name")
                        .font(IronFont.bodyMedium(17))
                        .foregroundColor(.white.opacity(0.35))
                )
                .font(IronFont.bodyMedium(18))
                .foregroundColor(.white)
                .focused(isFocused)
                .padding(.vertical, 16)
                .padding(.horizontal, 18)
                .background(
                    ZStack {
                        // Frosted glass background
                        RoundedRectangle(cornerRadius: 14)
                            .fill(.ultraThinMaterial.opacity(0.5))
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color.white.opacity(0.03))
                        
                        // Inner glow at top
                        VStack {
                            LinearGradient(
                                colors: [Color.white.opacity(isFocused.wrappedValue ? 0.15 : 0.08), Color.clear],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                            .frame(height: 20)
                            Spacer()
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(
                            LinearGradient(
                                colors: isFocused.wrappedValue
                                    ? [neonPurple.opacity(0.8), neonPurple.opacity(0.4), Color.white.opacity(0.2)]
                                    : [Color.white.opacity(0.25), Color.white.opacity(0.1), Color.clear],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: isFocused.wrappedValue ? 1.5 : 1
                        )
                )
                .shadow(color: isFocused.wrappedValue ? neonPurple.opacity(0.3) : .clear, radius: 12, y: 4)
            }
            .animation(.easeInOut(duration: 0.25), value: isFocused.wrappedValue)
        }
    }
}

// MARK: - Precision Age Ruler (The Hero Element with Glass Lens)
struct PrecisionAgeRuler: View {
    @Binding var age: Int
    let neonPurple: Color
    
    private let minAge: CGFloat = 16
    private let maxAge: CGFloat = 80
    private let tickSpacing: CGFloat = 5
    
    @State private var isDragging = false
    @State private var previousAge: Int = 25
    @State private var dragVelocity: CGFloat = 0
    
    var body: some View {
        VStack(spacing: 6) {
            // Hero number - massive digital readout with motion blur effect
            ZStack {
                // Motion blur trail (when dragging fast)
                if isDragging && abs(dragVelocity) > 0.5 {
                    Text("\(age)")
                        .font(IronFont.digital(86))
                        .foregroundStyle(neonPurple.opacity(0.3))
                        .blur(radius: min(abs(dragVelocity) * 2, 8))
                        .offset(x: dragVelocity > 0 ? -6 : 6)
                }
                
                // Main number
                Text("\(age)")
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
                    .animation(.snappy(duration: 0.12), value: age)
                    .blur(radius: isDragging && abs(dragVelocity) > 1 ? 1 : 0)
            }
            
            Text("YEARS OLD")
                .font(IronFont.header(10))
                .tracking(4)
                .foregroundColor(.white.opacity(0.35))
                .padding(.bottom, 16)
            
            // Precision Ruler Slider with Glass Lens Thumb
            GeometryReader { geo in
                let totalWidth = geo.size.width - 32
                let progress = CGFloat(age - Int(minAge)) / (maxAge - minAge)
                
                ZStack(alignment: .leading) {
                    // Base rail/track line (grounds the slider)
                    Rectangle()
                        .fill(Color.white.opacity(0.10))
                        .frame(width: totalWidth, height: 1)
                        .offset(y: 6)
                        .padding(.horizontal, 16)
                    
                    // Track background with tick marks
                    HStack(spacing: 0) {
                        ForEach(0..<Int((maxAge - minAge) / tickSpacing) + 1, id: \.self) { i in
                            let tickAge = Int(minAge) + i * Int(tickSpacing)
                            let isMajor = tickAge % 10 == 0
                            let isLit = tickAge <= age
                            
                            VStack(spacing: 4) {
                                Rectangle()
                                    .fill(
                                        isLit
                                            ? neonPurple
                                            : Color.white.opacity(0.15)
                                    )
                                    .frame(width: isMajor ? 2 : 1, height: isMajor ? 16 : 10)
                                    .shadow(color: isLit ? neonPurple.opacity(0.6) : .clear, radius: 3)
                                
                                if isMajor {
                                    Text("\(tickAge)")
                                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                                        .foregroundColor(isLit ? .white.opacity(0.7) : .white.opacity(0.3))
                                }
                            }
                            
                            if i < Int((maxAge - minAge) / tickSpacing) {
                                Spacer()
                            }
                        }
                    }
                    .frame(width: totalWidth)
                    .padding(.horizontal, 16)
                    
                    // Glow track overlay (lit portion)
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [neonPurple.opacity(0.5), neonPurple.opacity(0.15)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: totalWidth * progress, height: 3)
                        .offset(y: 6)
                        .padding(.leading, 16)
                        .blur(radius: 2)
                    
                    // Glass Lens Thumb (magnification effect)
                    GlassLensThumb(size: 32, isActive: isDragging, neonPurple: neonPurple)
                        .offset(x: totalWidth * progress + 2, y: -2)
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    isDragging = true
                                    let newProgress = min(max(0, (value.location.x - 16) / totalWidth), 1)
                                    let newAge = Int(minAge + newProgress * (maxAge - minAge))
                                    
                                    // Calculate velocity for motion blur
                                    dragVelocity = CGFloat(newAge - age)
                                    
                                    if newAge != age {
                                        previousAge = age
                                        age = newAge
                                        // Haptic feedback
                                        let generator = UIImpactFeedbackGenerator(style: .light)
                                        generator.impactOccurred()
                                    }
                                }
                                .onEnded { _ in
                                    withAnimation(.easeOut(duration: 0.2)) {
                                        isDragging = false
                                        dragVelocity = 0
                                    }
                                }
                        )
                }
            }
            .frame(height: 55)
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Scientific Sex Selector (Premium Glass Buttons with Inner Glow)
struct ScientificSexSelector: View {
    @Binding var selectedSex: Sex
    let neonPurple: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("BIOLOGICAL SEX")
                .font(IronFont.header(10))
                .tracking(3)
                .foregroundColor(.white.opacity(0.35))
            
            // Unified segmented control bar with liquid glass
            HStack(spacing: 0) {
                ForEach(Sex.allCases, id: \.self) { sex in
                    let isSelected = selectedSex == sex
                    
                    Button {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                            selectedSex = sex
                        }
                        // Haptic feedback
                        let generator = UIImpactFeedbackGenerator(style: .medium)
                        generator.impactOccurred()
                    } label: {
                        // Large, centered, iconic symbol with inner glow
                        ZStack {
                            // Symbol glow backdrop when selected
                            if isSelected {
                                Text(sex.scientificSymbol)
                                    .font(.system(size: 36, weight: .light))
                                    .foregroundColor(neonPurple.opacity(0.5))
                                    .blur(radius: 12)
                            }
                            
                            Text(sex.scientificSymbol)
                                .font(.system(size: 36, weight: .light))
                                .foregroundColor(isSelected ? .white : .white.opacity(0.45))
                                .shadow(color: isSelected ? neonPurple.opacity(0.9) : .clear, radius: 15)
                                .shadow(color: isSelected ? neonPurple.opacity(0.5) : .clear, radius: 25)
                        }
                        .offset(x: sex == .male ? -2 : 0) // Optical centering for Mars symbol
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                        .background(
                            ZStack {
                                // Base glass layer
                                RoundedRectangle(cornerRadius: 14)
                                    .fill(Color.white.opacity(isSelected ? 0 : 0.02))
                                
                                if isSelected {
                                    // Liquid plasma fill (selected state)
                                    RoundedRectangle(cornerRadius: 14)
                                        .fill(
                                            RadialGradient(
                                                colors: [neonPurple.opacity(0.35), neonPurple.opacity(0.15), neonPurple.opacity(0.05)],
                                                center: .center,
                                                startRadius: 0,
                                                endRadius: 100
                                            )
                                        )
                                    
                                    // Top inner glow (pressed glass effect)
                                    VStack {
                                        LinearGradient(
                                            colors: [Color.white.opacity(0.20), neonPurple.opacity(0.15), Color.clear],
                                            startPoint: .top,
                                            endPoint: .bottom
                                        )
                                        .frame(height: 25)
                                        Spacer()
                                    }
                                    .clipShape(RoundedRectangle(cornerRadius: 14))
                                    
                                    // Bottom subtle glow
                                    VStack {
                                        Spacer()
                                        LinearGradient(
                                            colors: [Color.clear, neonPurple.opacity(0.1)],
                                            startPoint: .top,
                                            endPoint: .bottom
                                        )
                                        .frame(height: 15)
                                    }
                                    .clipShape(RoundedRectangle(cornerRadius: 14))
                                }
                            }
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(
                                    LinearGradient(
                                        colors: isSelected
                                            ? [Color.white.opacity(0.5), neonPurple.opacity(0.6), neonPurple.opacity(0.3)]
                                            : [Color.white.opacity(0.1), Color.white.opacity(0.05)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: isSelected ? 1.5 : 1
                                )
                        )
                        .shadow(color: isSelected ? neonPurple.opacity(0.4) : .clear, radius: 12, y: 4)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .scaleEffect(isSelected ? 1.02 : 1.0)
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
                    
                    // Glass divider between segments
                    if sex != Sex.allCases.last {
                        Rectangle()
                            .fill(
                                LinearGradient(
                                    colors: [Color.white.opacity(0.15), Color.white.opacity(0.05), Color.white.opacity(0.15)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .frame(width: 1)
                            .padding(.vertical, 14)
                    }
                }
            }
            .padding(5)
            .background(
                ZStack {
                    // Deep frosted glass container
                    RoundedRectangle(cornerRadius: 18)
                        .fill(.ultraThinMaterial)
                    RoundedRectangle(cornerRadius: 18)
                        .fill(Color.white.opacity(0.03))
                    
                    // Inner shadow for depth
                    VStack {
                        LinearGradient(
                            colors: [Color.white.opacity(0.08), Color.clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(height: 25)
                        Spacer()
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(
                        LinearGradient(
                            colors: [Color.white.opacity(0.2), Color.white.opacity(0.08), Color.clear],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
        }
    }
}

// MARK: - Tactile Glass Button with Liquid Energy Sheen
struct TactileGlassButton: View {
    let title: String
    let isEnabled: Bool
    let brightViolet: Color
    let deepIndigo: Color
    let action: () -> Void
    
    @State private var isPressed = false
    @State private var sheenOffset: CGFloat = -150
    
    var body: some View {
        Button {
            action()
        } label: {
            HStack(spacing: 8) {
                Text(title)
                    .font(IronFont.header(14))
                    .tracking(2)
                Image(systemName: "arrow.right")
                    .font(.system(size: 13, weight: .bold))
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(
                ZStack {
                    // Outer glow reservoir
                    RoundedRectangle(cornerRadius: 14)
                        .fill(brightViolet.opacity(0.3))
                        .blur(radius: 10)
                    
                    // Base gradient (Bright Violet → Deep Indigo)
                    RoundedRectangle(cornerRadius: 14)
                        .fill(
                            LinearGradient(
                                colors: [brightViolet, deepIndigo],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    
                    // Top edge "lip" - mimics light catching physical button
                    VStack {
                        LinearGradient(
                            colors: [Color.white.opacity(0.40), Color.white.opacity(0.15), Color.clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(height: 1.5)
                        .padding(.horizontal, 1)
                        .padding(.top, 1)
                        Spacer()
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    
                    // Inner glass highlight
                    VStack {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(
                                LinearGradient(
                                    colors: [Color.white.opacity(0.20), Color.white.opacity(0.05), Color.clear],
                                    startPoint: .top,
                                    endPoint: .center
                                )
                            )
                            .frame(height: 26)
                            .padding(.horizontal, 2)
                            .padding(.top, 2)
                        Spacer()
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    
                    // Animated sheen wipe (liquid energy pulse)
                    GeometryReader { geo in
                        LinearGradient(
                            colors: [Color.clear, Color.white.opacity(0.3), Color.white.opacity(0.45), Color.white.opacity(0.3), Color.clear],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(width: 50)
                        .blur(radius: 6)
                        .offset(x: sheenOffset)
                        .onAppear {
                            withAnimation(.easeInOut(duration: 2.5).repeatForever(autoreverses: false).delay(0.5)) {
                                sheenOffset = geo.size.width + 80
                            }
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(
                        LinearGradient(
                            colors: [Color.white.opacity(0.35), Color.white.opacity(0.1), brightViolet.opacity(0.3)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.5
                    )
            )
            .shadow(color: brightViolet.opacity(0.55), radius: 18, y: 8)
            .shadow(color: deepIndigo.opacity(0.35), radius: 35, y: 14)
        }
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.4)
        .scaleEffect(isPressed ? 0.97 : 1.0)
        .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isPressed)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
    }
}

// MARK: - Blinking Cursor (Terminal feel)
struct BlinkingCursor: View {
    let neonPurple: Color
    @State private var isVisible = true
    
    var body: some View {
        Rectangle()
            .fill(neonPurple)
            .frame(width: 2, height: 20)
            .opacity(isVisible ? 1 : 0)
            .shadow(color: neonPurple.opacity(0.6), radius: 4)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true)) {
                    isVisible.toggle()
                }
            }
    }
}

#Preview {
    OnboardingContainerView()
        .environmentObject(AppState())
}
