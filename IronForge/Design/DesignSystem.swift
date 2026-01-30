import SwiftUI
import UIKit

// MARK: - Color Palette
extension Color {
    // Core Background
    static let ironBackground = Color(red: 0.02, green: 0.02, blue: 0.04)
    static let ironSurface = Color(red: 0.06, green: 0.06, blue: 0.10)
    static let ironSurfaceLight = Color(red: 0.10, green: 0.10, blue: 0.14)
    
    // Neon Purple Accents - #A855F7 base
    static let ironPurple = Color(red: 0.66, green: 0.33, blue: 0.97)      // #A855F7 Purple-500
    static let ironPurpleLight = Color(red: 0.85, green: 0.71, blue: 0.99) // #D8B4FE Purple-300 (for glows)
    static let ironPurpleDark = Color(red: 0.35, green: 0.15, blue: 0.70)
    static let ironPurpleGlow = Color(red: 0.85, green: 0.71, blue: 0.99).opacity(0.6) // Brighter glow
    static let ironPurpleNeon = Color(red: 0.70, green: 0.40, blue: 1.0)
    
    // Cyan accent for contrast
    static let ironCyan = Color(red: 0.0, green: 0.90, blue: 1.0)
    static let ironCyanGlow = Color(red: 0.0, green: 0.90, blue: 1.0).opacity(0.5)
    
    // Gradients
    static let purpleGradientStart = Color(red: 0.65, green: 0.35, blue: 1.0)
    static let purpleGradientEnd = Color(red: 0.40, green: 0.15, blue: 0.85)
    
    // Text - Use Silver for better contrast
    static let ironTextPrimary = Color.white
    static let ironTextSecondary = Color.white.opacity(0.75)
    static let ironTextTertiary = Color(red: 0.61, green: 0.64, blue: 0.69) // #9CA3AF Silver
    static let ironTextDisabled = Color(red: 0.42, green: 0.45, blue: 0.50) // #6B7280
    
    // Glass
    static let glassWhite = Color.white.opacity(0.06)
    static let glassBorder = Color.white.opacity(0.12)
    static let glassBorderLight = Color.white.opacity(0.20)
    static let glassBorderNeon = Color(red: 0.66, green: 0.33, blue: 0.97).opacity(0.4)
}

// MARK: - Typography
struct IronFont {
    // If Orbitron/Inter/Rajdhani/Exo2 are added to the project, these will automatically start using them.
    // Otherwise we fall back to system fonts (so the app always runs).
    
    private static func resolvedFont(
        preferredNames: [String],
        size: CGFloat,
        fallback: Font
    ) -> Font {
        for name in preferredNames {
            if UIFont(name: name, size: size) != nil {
                return .custom(name, size: size)
            }
        }
        return fallback
    }
    
    // MARK: Orbitron (headers)
    static func header(_ size: CGFloat) -> Font {
        resolvedFont(
            preferredNames: ["Orbitron-Black", "Orbitron-Bold", "Orbitron"],
            size: size,
            fallback: .system(size: size, weight: .black, design: .default)
        )
    }
    
    static func headerMedium(_ size: CGFloat) -> Font {
        resolvedFont(
            preferredNames: ["Orbitron-Bold", "Orbitron-Medium", "Orbitron"],
            size: size,
            fallback: .system(size: size, weight: .bold, design: .default)
        )
    }
    
    // MARK: Rajdhani (digital readout / hero numbers)
    static func digital(_ size: CGFloat) -> Font {
        resolvedFont(
            preferredNames: ["Rajdhani-Bold", "Rajdhani-SemiBold", "Rajdhani"],
            size: size,
            fallback: .system(size: size, weight: .bold, design: .monospaced)
        )
    }
    
    static func digitalLight(_ size: CGFloat) -> Font {
        resolvedFont(
            preferredNames: ["Rajdhani-Regular", "Rajdhani-Light", "Rajdhani"],
            size: size,
            fallback: .system(size: size, weight: .regular, design: .monospaced)
        )
    }
    
    // MARK: Exo 2 (dynamic / italic placeholders)
    static func dynamic(_ size: CGFloat) -> Font {
        resolvedFont(
            preferredNames: ["Exo2-LightItalic", "Exo2-Italic", "Exo2-Light", "Exo2"],
            size: size,
            fallback: .system(size: size, weight: .light, design: .default).italic()
        )
    }
    
    static func dynamicMedium(_ size: CGFloat) -> Font {
        resolvedFont(
            preferredNames: ["Exo2-MediumItalic", "Exo2-Medium", "Exo2"],
            size: size,
            fallback: .system(size: size, weight: .medium, design: .default).italic()
        )
    }
    
    // MARK: Inter (body)
    static func body(_ size: CGFloat) -> Font {
        resolvedFont(
            preferredNames: ["Inter-Regular", "Inter"],
            size: size,
            fallback: .system(size: size, weight: .regular, design: .default)
        )
    }
    
    static func bodyMedium(_ size: CGFloat) -> Font {
        resolvedFont(
            preferredNames: ["Inter-Medium", "Inter"],
            size: size,
            fallback: .system(size: size, weight: .medium, design: .default)
        )
    }
    
    static func bodySemibold(_ size: CGFloat) -> Font {
        resolvedFont(
            preferredNames: ["Inter-SemiBold", "Inter-Bold", "Inter"],
            size: size,
            fallback: .system(size: size, weight: .semibold, design: .default)
        )
    }
    
    static func bodyLight(_ size: CGFloat) -> Font {
        resolvedFont(
            preferredNames: ["Inter-Light", "Inter-Regular", "Inter"],
            size: size,
            fallback: .system(size: size, weight: .light, design: .default)
        )
    }
    
    static func label(_ size: CGFloat) -> Font {
        resolvedFont(
            preferredNames: ["Inter-Bold", "Inter-SemiBold", "Inter"],
            size: size,
            fallback: .system(size: size, weight: .bold, design: .default)
        )
    }
}

// MARK: - Premium Liquid Glass Card (with Physics)
struct FuturisticGlassCard: ViewModifier {
    var isSelected: Bool = false
    var cornerRadius: CGFloat = 20 // Updated from 24 for better consistency
    var glowColor: Color = .ironPurple
    var glowIntensity: CGFloat = 0.5
    
    func body(content: Content) -> some View {
        content
            .background {
                ZStack {
                    // Deep frosted blur layer - interacts with background glow
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(.ultraThinMaterial)
                        .blur(radius: 0.5)
                    
                    // Glass tint layer
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(Color.white.opacity(0.04))
                    
                    // Inner shadow at top for thickness/depth
                    VStack(spacing: 0) {
                        LinearGradient(
                            colors: [Color.white.opacity(0.15), Color.white.opacity(0.06), Color.clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(height: 35)
                        Spacer()
                    }
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
                    
                    // Selected: Radial gradient "liquid plasma glow from inside"
                    if isSelected {
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .fill(
                                RadialGradient(
                                    colors: [glowColor.opacity(0.25), glowColor.opacity(0.10), glowColor.opacity(0.03), Color.clear],
                                    center: .center,
                                    startRadius: 0,
                                    endRadius: 150
                                )
                            )
                    }
                }
            }
            .overlay {
                // Refraction border - linear gradient white to transparent (simulates light catching edge)
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(
                        LinearGradient(
                            colors: isSelected 
                                ? [glowColor.opacity(0.8), Color.white.opacity(0.3), glowColor.opacity(0.3), Color.clear]
                                : [Color.white.opacity(0.35), Color.white.opacity(0.15), Color.white.opacity(0.05), Color.clear],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
            .shadow(color: isSelected ? Color.ironPurpleLight.opacity(glowIntensity) : .clear, radius: 18, x: 0, y: 8)
            .shadow(color: isSelected ? glowColor.opacity(glowIntensity * 0.5) : .clear, radius: 35, x: 0, y: 14)
    }
}

// MARK: - Legacy Liquid Glass (for compatibility)
struct LiquidGlassCard: ViewModifier {
    var isSelected: Bool = false
    var cornerRadius: CGFloat = 24
    
    func body(content: Content) -> some View {
        content
            .modifier(FuturisticGlassCard(isSelected: isSelected, cornerRadius: cornerRadius))
    }
}

// MARK: - Neon Glow Button with Sheen Animation
struct NeonGlowButtonStyle: ButtonStyle {
    var isPrimary: Bool = false
    
    func makeBody(configuration: Configuration) -> some View {
        LiquidEnergyButton(isPrimary: isPrimary, isPressed: configuration.isPressed) {
            configuration.label
        }
    }
}

// MARK: - Liquid Energy Button (with animated sheen)
struct LiquidEnergyButton<Label: View>: View {
    let isPrimary: Bool
    let isPressed: Bool
    let label: () -> Label
    
    @State private var sheenOffset: CGFloat = -200
    
    var body: some View {
        label()
            .padding(.horizontal, 36)
            .padding(.vertical, 18)
            .background {
                if isPrimary {
                    ZStack {
                        // Outer glow (liquid energy reservoir)
                        Capsule()
                            .fill(Color.ironPurple.opacity(0.35))
                            .blur(radius: 14)
                        
                        // Main gradient (liquid fill)
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [.purpleGradientStart, .purpleGradientEnd],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                        
                        // Inner highlight (glass curvature)
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [Color.white.opacity(0.30), Color.white.opacity(0.05), Color.clear],
                                    startPoint: .top,
                                    endPoint: .center
                                )
                            )
                        
                        // Animated sheen wipe (liquid energy pulse)
                        GeometryReader { geo in
                            LinearGradient(
                                colors: [Color.clear, Color.white.opacity(0.35), Color.white.opacity(0.5), Color.white.opacity(0.35), Color.clear],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                            .frame(width: 60)
                            .blur(radius: 8)
                            .offset(x: sheenOffset)
                            .onAppear {
                                withAnimation(.easeInOut(duration: 2.5).repeatForever(autoreverses: false).delay(1)) {
                                    sheenOffset = geo.size.width + 100
                                }
                            }
                        }
                        .clipShape(Capsule())
                    }
                } else {
                    Capsule()
                        .fill(Color.ironSurface)
                        .overlay {
                            Capsule()
                                .stroke(Color.glassBorder, lineWidth: 1)
                        }
                }
            }
            .overlay {
                if isPrimary {
                    Capsule()
                        .stroke(
                            LinearGradient(
                                colors: [Color.ironPurpleLight.opacity(0.7), Color.white.opacity(0.2), Color.ironPurple.opacity(0.3)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.5
                        )
                }
            }
            .foregroundColor(.white)
            .font(IronFont.bodySemibold(17))
            .scaleEffect(isPressed ? 0.96 : 1)
            .opacity(isPressed ? 0.9 : 1)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isPressed)
            .shadow(color: isPrimary ? Color.ironPurpleGlow : .clear, radius: 22, x: 0, y: 10)
            .shadow(color: isPrimary ? Color.ironPurple.opacity(0.4) : .clear, radius: 45, x: 0, y: 18)
    }
}

// Keep old name for compatibility
typealias LiquidGlassButtonStyle = NeonGlowButtonStyle

// MARK: - Liquid Toggle (Premium Switch with flowing animation)
struct LiquidToggle: View {
    @Binding var isOn: Bool
    
    private let trackWidth: CGFloat = 56
    private let trackHeight: CGFloat = 30
    private let thumbSize: CGFloat = 24
    
    @State private var liquidFill: CGFloat = 0
    @State private var bubbleOffset: CGFloat = 0
    
    var body: some View {
        Button {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.65)) {
                isOn.toggle()
            }
            // Haptic feedback
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()
        } label: {
            ZStack {
                // Track - recessed glass groove
                Capsule()
                    .fill(Color.black.opacity(0.6))
                    .frame(width: trackWidth, height: trackHeight)
                    .overlay(
                        Capsule()
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    )
                    .overlay(
                        // Inner shadow for depth
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [Color.black.opacity(0.5), Color.clear],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .padding(2)
                    )
                
                // Liquid fill animation (when ON)
                if isOn {
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [Color.ironPurple.opacity(0.3), Color.ironPurple.opacity(0.5), Color.ironPurple.opacity(0.3)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: trackWidth - 6, height: trackHeight - 6)
                        .blur(radius: 2)
                    
                    // Bubble/wave effect inside track
                    HStack(spacing: 3) {
                        ForEach(0..<4, id: \.self) { i in
                            Circle()
                                .fill(Color.ironPurpleLight.opacity(0.4))
                                .frame(width: 4, height: 4)
                                .offset(y: sin(Double(i) + bubbleOffset) * 2)
                        }
                    }
                    .offset(x: -8)
                    .onAppear {
                        withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                            bubbleOffset = .pi * 2
                        }
                    }
                }
                
                // Glass bead thumb
                ZStack {
                    if isOn {
                        // ON: Glowing liquid orb
                        Circle()
                            .fill(
                                RadialGradient(
                                    colors: [Color.ironPurpleLight, Color.ironPurple, Color.ironPurpleDark],
                                    center: UnitPoint(x: 0.3, y: 0.3),
                                    startRadius: 0,
                                    endRadius: thumbSize / 2
                                )
                            )
                            .frame(width: thumbSize, height: thumbSize)
                            .shadow(color: Color.ironPurpleGlow, radius: 10, x: 0, y: 0)
                            .shadow(color: Color.ironPurple.opacity(0.6), radius: 5, x: 0, y: 2)
                        
                        // Glass highlight on bead
                        Circle()
                            .fill(
                                RadialGradient(
                                    colors: [Color.white.opacity(0.6), Color.clear],
                                    center: UnitPoint(x: 0.25, y: 0.25),
                                    startRadius: 0,
                                    endRadius: thumbSize / 3
                                )
                            )
                            .frame(width: thumbSize, height: thumbSize)
                    } else {
                        // OFF: Frosted glass bead (hollow ring feel)
                        Circle()
                            .fill(
                                RadialGradient(
                                    colors: [Color.white.opacity(0.15), Color.white.opacity(0.05)],
                                    center: UnitPoint(x: 0.3, y: 0.3),
                                    startRadius: 0,
                                    endRadius: thumbSize / 2
                                )
                            )
                            .frame(width: thumbSize, height: thumbSize)
                            .overlay(
                                Circle()
                                    .stroke(Color.white.opacity(0.25), lineWidth: 2)
                            )
                    }
                }
                .offset(x: isOn ? (trackWidth / 2 - thumbSize / 2 - 4) : -(trackWidth / 2 - thumbSize / 2 - 4))
            }
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Holographic Pulsing Circle (for sync states)
struct HolographicPulseCircle: View {
    let isSearching: Bool
    let size: CGFloat
    
    @State private var pulseScale: CGFloat = 1.0
    @State private var rotationAngle: Double = 0
    @State private var innerPulse: Bool = false
    
    var body: some View {
        ZStack {
            // Outer pulsing rings
            ForEach(0..<3) { i in
                Circle()
                    .stroke(
                        LinearGradient(
                            colors: [Color.ironPurple.opacity(0.4 - Double(i) * 0.1), Color.ironCyan.opacity(0.2)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.5
                    )
                    .frame(width: size + CGFloat(i * 20), height: size + CGFloat(i * 20))
                    .scaleEffect(isSearching ? (pulseScale + CGFloat(i) * 0.1) : 1.0)
                    .opacity(isSearching ? (0.8 - Double(i) * 0.2) : 0.3)
            }
            
            // Main holographic circle
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.ironPurple.opacity(isSearching ? 0.3 : 0.15),
                            Color.ironPurple.opacity(isSearching ? 0.15 : 0.05),
                            Color.clear
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: size / 2
                    )
                )
                .frame(width: size, height: size)
            
            // Rotating scan line
            if isSearching {
                Circle()
                    .trim(from: 0, to: 0.25)
                    .stroke(
                        LinearGradient(
                            colors: [Color.ironCyan, Color.ironPurple.opacity(0.5), Color.clear],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        style: StrokeStyle(lineWidth: 2, lineCap: .round)
                    )
                    .frame(width: size - 10, height: size - 10)
                    .rotationEffect(.degrees(rotationAngle))
            }
            
            // Center signal indicator
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.white.opacity(0.4), Color.ironPurple.opacity(0.3), Color.clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: 15
                    )
                )
                .frame(width: 30, height: 30)
                .scaleEffect(innerPulse ? 1.2 : 0.9)
            
            // Glass border
            Circle()
                .stroke(
                    LinearGradient(
                        colors: [Color.white.opacity(0.4), Color.ironPurple.opacity(0.3), Color.white.opacity(0.1)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.5
                )
                .frame(width: size, height: size)
        }
        .onAppear {
            if isSearching {
                withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                    pulseScale = 1.15
                }
                withAnimation(.linear(duration: 2).repeatForever(autoreverses: false)) {
                    rotationAngle = 360
                }
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                    innerPulse = true
                }
            }
        }
    }
}

// MARK: - Crystal Growth Icon (for experience levels)
struct CrystalGrowthIcon: View {
    let level: Int // 1-5
    let isSelected: Bool
    let neonPurple: Color
    
    var body: some View {
        ZStack {
            // Glow base when selected
            if isSelected {
                crystalShape(level: level)
                    .fill(neonPurple.opacity(0.3))
                    .blur(radius: 8)
                    .scaleEffect(1.1)
            }
            
            // Crystal body
            crystalShape(level: level)
                .fill(
                    LinearGradient(
                        colors: isSelected
                            ? [neonPurple.opacity(0.9), neonPurple.opacity(0.6), neonPurple.opacity(0.4)]
                            : [Color.white.opacity(0.25), Color.white.opacity(0.12), Color.white.opacity(0.05)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            
            // Glass highlight (refraction)
            crystalShape(level: level)
                .stroke(
                    LinearGradient(
                        colors: isSelected
                            ? [Color.white.opacity(0.7), neonPurple.opacity(0.4), Color.clear]
                            : [Color.white.opacity(0.4), Color.white.opacity(0.1), Color.clear],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.5
                )
            
            // Inner facet lines for higher levels
            if level >= 3 {
                crystalFacets(level: level)
                    .stroke(
                        Color.white.opacity(isSelected ? 0.3 : 0.15),
                        lineWidth: 0.5
                    )
            }
        }
        .frame(width: 44, height: 44)
        .shadow(color: isSelected ? neonPurple.opacity(0.6) : .clear, radius: 8)
    }
    
    private func crystalShape(level: Int) -> AnyShape {
        switch level {
        case 1:
            // Raw shard - simple triangle
            return AnyShape(CrystalShard())
        case 2:
            // Small gem - pentagon
            return AnyShape(CrystalGem())
        case 3:
            // Formed crystal - hexagon
            return AnyShape(CrystalHexagon())
        case 4:
            // Complex crystal - octagon
            return AnyShape(CrystalOctagon())
        default:
            // Diamond - multi-faceted
            return AnyShape(CrystalDiamond())
        }
    }
    
    private func crystalFacets(level: Int) -> some Shape {
        CrystalFacetLines(level: level)
    }
}

// Crystal shapes
struct CrystalShard: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        path.move(to: CGPoint(x: w * 0.5, y: h * 0.1))
        path.addLine(to: CGPoint(x: w * 0.75, y: h * 0.85))
        path.addLine(to: CGPoint(x: w * 0.25, y: h * 0.85))
        path.closeSubpath()
        return path
    }
}

struct CrystalGem: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        path.move(to: CGPoint(x: w * 0.5, y: h * 0.08))
        path.addLine(to: CGPoint(x: w * 0.85, y: h * 0.38))
        path.addLine(to: CGPoint(x: w * 0.7, y: h * 0.88))
        path.addLine(to: CGPoint(x: w * 0.3, y: h * 0.88))
        path.addLine(to: CGPoint(x: w * 0.15, y: h * 0.38))
        path.closeSubpath()
        return path
    }
}

struct CrystalHexagon: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        path.move(to: CGPoint(x: w * 0.5, y: h * 0.05))
        path.addLine(to: CGPoint(x: w * 0.9, y: h * 0.28))
        path.addLine(to: CGPoint(x: w * 0.9, y: h * 0.72))
        path.addLine(to: CGPoint(x: w * 0.5, y: h * 0.95))
        path.addLine(to: CGPoint(x: w * 0.1, y: h * 0.72))
        path.addLine(to: CGPoint(x: w * 0.1, y: h * 0.28))
        path.closeSubpath()
        return path
    }
}

struct CrystalOctagon: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        path.move(to: CGPoint(x: w * 0.35, y: h * 0.05))
        path.addLine(to: CGPoint(x: w * 0.65, y: h * 0.05))
        path.addLine(to: CGPoint(x: w * 0.95, y: h * 0.35))
        path.addLine(to: CGPoint(x: w * 0.95, y: h * 0.65))
        path.addLine(to: CGPoint(x: w * 0.65, y: h * 0.95))
        path.addLine(to: CGPoint(x: w * 0.35, y: h * 0.95))
        path.addLine(to: CGPoint(x: w * 0.05, y: h * 0.65))
        path.addLine(to: CGPoint(x: w * 0.05, y: h * 0.35))
        path.closeSubpath()
        return path
    }
}

struct CrystalDiamond: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        // Top point
        path.move(to: CGPoint(x: w * 0.5, y: h * 0.02))
        // Upper right facets
        path.addLine(to: CGPoint(x: w * 0.75, y: h * 0.2))
        path.addLine(to: CGPoint(x: w * 0.95, y: h * 0.45))
        // Right point
        path.addLine(to: CGPoint(x: w * 0.85, y: h * 0.65))
        // Lower right
        path.addLine(to: CGPoint(x: w * 0.6, y: h * 0.95))
        // Bottom point
        path.addLine(to: CGPoint(x: w * 0.5, y: h * 0.98))
        path.addLine(to: CGPoint(x: w * 0.4, y: h * 0.95))
        // Lower left
        path.addLine(to: CGPoint(x: w * 0.15, y: h * 0.65))
        // Left point
        path.addLine(to: CGPoint(x: w * 0.05, y: h * 0.45))
        // Upper left facets
        path.addLine(to: CGPoint(x: w * 0.25, y: h * 0.2))
        path.closeSubpath()
        return path
    }
}

struct CrystalFacetLines: Shape {
    let level: Int
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        let center = CGPoint(x: w * 0.5, y: h * 0.5)
        
        // Add facet lines from center to edges based on level
        let lineCount = min(level + 2, 8)
        for i in 0..<lineCount {
            let angle = (Double(i) / Double(lineCount)) * 2 * .pi - .pi / 2
            let endX = center.x + cos(angle) * w * 0.35
            let endY = center.y + sin(angle) * h * 0.35
            path.move(to: center)
            path.addLine(to: CGPoint(x: endX, y: endY))
        }
        return path
    }
}

// MARK: - Glass Lens Slider Thumb
struct GlassLensThumb: View {
    let size: CGFloat
    let isActive: Bool
    let neonPurple: Color
    
    var body: some View {
        ZStack {
            // Outer glow ring when active
            if isActive {
                Circle()
                    .stroke(neonPurple.opacity(0.5), lineWidth: 3)
                    .frame(width: size + 8, height: size + 8)
                    .blur(radius: 4)
            }
            
            // Main lens ring
            Circle()
                .stroke(
                    LinearGradient(
                        colors: [neonPurple, neonPurple.opacity(0.7)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: isActive ? 6 : 5
                )
                .frame(width: size, height: size)
                .shadow(color: neonPurple.opacity(isActive ? 0.9 : 0.7), radius: isActive ? 18 : 12)
            
            // Inner highlight ring (glass refraction)
            Circle()
                .stroke(
                    LinearGradient(
                        colors: [Color.white.opacity(0.6), Color.white.opacity(0.2)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.5
                )
                .frame(width: size - 8, height: size - 8)
            
            // Magnification center (transparent with subtle distortion hint)
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.white.opacity(0.08), Color.clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: size / 3
                    )
                )
                .frame(width: size - 12, height: size - 12)
        }
        .scaleEffect(isActive ? 1.15 : 1.0)
        .animation(.spring(response: 0.25, dampingFraction: 0.6), value: isActive)
    }
}

// MARK: - Premium Text Field
struct LiquidGlassTextField: View {
    let placeholder: String
    @Binding var text: String
    var keyboardType: UIKeyboardType = .default
    
    var body: some View {
        TextField(placeholder, text: $text)
            .keyboardType(keyboardType)
            .font(IronFont.bodyMedium(18))
            .foregroundColor(.white)
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
            .background {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.ironSurface)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .stroke(
                        LinearGradient(
                            colors: [Color.glassBorder, Color.glassBorder.opacity(0.5)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
            .tint(.ironPurple)
    }
}

// MARK: - Progress Indicator
struct OnboardingProgress: View {
    let currentStep: Int
    let totalSteps: Int
    
    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<totalSteps, id: \.self) { step in
                Capsule()
                    .fill(
                        step < currentStep
                            ? LinearGradient(colors: [.ironPurple, .ironPurpleLight], startPoint: .leading, endPoint: .trailing)
                            : LinearGradient(colors: [Color.glassWhite, Color.glassWhite], startPoint: .leading, endPoint: .trailing)
                    )
                    .frame(width: step == currentStep - 1 ? 28 : 8, height: 8)
                    .shadow(color: step < currentStep ? Color.ironPurpleGlow : .clear, radius: 6, x: 0, y: 2)
                    .animation(.spring(response: 0.4, dampingFraction: 0.7), value: currentStep)
            }
        }
    }
}

// MARK: - View Extensions
extension View {
    func liquidGlass(isSelected: Bool = false, cornerRadius: CGFloat = 24) -> some View {
        modifier(FuturisticGlassCard(isSelected: isSelected, cornerRadius: cornerRadius))
    }
    
    func neonGlass(isSelected: Bool = false, cornerRadius: CGFloat = 24, glowColor: Color = .ironPurple, glowIntensity: CGFloat = 0.5) -> some View {
        modifier(FuturisticGlassCard(isSelected: isSelected, cornerRadius: cornerRadius, glowColor: glowColor, glowIntensity: glowIntensity))
    }
}

// MARK: - Animated Background
struct AnimatedMeshBackground: View {
    @State private var animateGradient = false
    @State private var pulseAnimation = false
    
    var body: some View {
        ZStack {
            Color.ironBackground
            
            // Grid pattern overlay
            GeometryReader { geo in
                Path { path in
                    let spacing: CGFloat = 40
                    for x in stride(from: 0, through: geo.size.width, by: spacing) {
                        path.move(to: CGPoint(x: x, y: 0))
                        path.addLine(to: CGPoint(x: x, y: geo.size.height))
                    }
                    for y in stride(from: 0, through: geo.size.height, by: spacing) {
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addLine(to: CGPoint(x: geo.size.width, y: y))
                    }
                }
                .stroke(Color.ironPurple.opacity(0.03), lineWidth: 0.5)
            }
            
            // Primary purple glow orb
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.ironPurple.opacity(0.25), Color.ironPurple.opacity(0.05), Color.clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: 350
                    )
                )
                .frame(width: 700, height: 700)
                .offset(x: animateGradient ? 80 : -80, y: animateGradient ? -200 : -100)
                .blur(radius: 60)
            
            // Secondary glow orb
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.ironPurpleDark.opacity(0.15), Color.clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: 280
                    )
                )
                .frame(width: 560, height: 560)
                .offset(x: animateGradient ? -60 : 60, y: animateGradient ? 250 : 150)
                .blur(radius: 50)
            
            // Subtle cyan accent
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.ironCyan.opacity(0.08), Color.clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: 200
                    )
                )
                .frame(width: 400, height: 400)
                .offset(x: animateGradient ? 150 : 100, y: animateGradient ? 100 : 200)
                .blur(radius: 40)
        }
        .ignoresSafeArea()
        .onAppear {
            withAnimation(.easeInOut(duration: 10).repeatForever(autoreverses: true)) {
                animateGradient.toggle()
            }
        }
    }
}

// MARK: - Purple Gradient
struct IronGradient: View {
    var body: some View {
        LinearGradient(
            colors: [.purpleGradientStart, .purpleGradientEnd],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

// MARK: - Neon Icon Button
struct GlowingIconButton: View {
    let icon: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 24, weight: .medium))
                .foregroundColor(isSelected ? .ironPurple : .ironTextSecondary)
                .frame(width: 56, height: 56)
                .background {
                    Circle()
                        .fill(isSelected ? Color.ironPurple.opacity(0.15) : Color.glassWhite)
                }
                .overlay {
                    Circle()
                        .stroke(isSelected ? Color.ironPurple.opacity(0.5) : Color.glassBorder, lineWidth: 1)
                }
                .shadow(color: isSelected ? Color.ironPurpleGlow : .clear, radius: 12, x: 0, y: 4)
        }
    }
}

// MARK: - Selection Chip
struct SelectionChip: View {
    let title: String
    let icon: String?
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .semibold))
                }
                Text(title)
                    .font(IronFont.bodySemibold(14))
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background {
                Capsule()
                    .fill(isSelected ? Color.ironPurple.opacity(0.2) : Color.glassWhite)
            }
            .overlay {
                Capsule()
                    .stroke(isSelected ? Color.ironPurple.opacity(0.6) : Color.glassBorder, lineWidth: 1)
            }
            .foregroundColor(isSelected ? .ironPurpleLight : .ironTextSecondary)
            .shadow(color: isSelected ? Color.ironPurpleGlow.opacity(0.3) : .clear, radius: 8, x: 0, y: 4)
        }
    }
}

// MARK: - Option Card
struct OptionCard: View {
    let title: String
    let subtitle: String?
    let icon: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundColor(isSelected ? .ironPurple : .ironTextSecondary)
                    .frame(width: 50, height: 50)
                    .background {
                        Circle()
                            .fill(isSelected ? Color.ironPurple.opacity(0.15) : Color.glassWhite)
                    }
                    .overlay {
                        Circle()
                            .stroke(isSelected ? Color.ironPurple.opacity(0.4) : Color.glassBorder, lineWidth: 1)
                    }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(IronFont.bodySemibold(17))
                        .foregroundColor(.ironTextPrimary)
                    
                    if let subtitle = subtitle {
                        Text(subtitle)
                            .font(IronFont.body(13))
                            .foregroundColor(.ironTextTertiary)
                    }
                }
                
                Spacer()
                
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 24))
                    .foregroundColor(isSelected ? .ironPurple : .ironTextTertiary)
            }
            .padding(16)
            .neonGlass(isSelected: isSelected)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Number Stepper
struct LiquidStepper: View {
    let title: String
    @Binding var value: Int
    var range: ClosedRange<Int>
    var step: Int = 1
    
    var body: some View {
        HStack {
            Text(title)
                .font(IronFont.bodyMedium(17))
                .foregroundColor(.ironTextPrimary)
            
            Spacer()
            
            HStack(spacing: 12) {
                Button {
                    if value - step >= range.lowerBound {
                        value -= step
                    }
                } label: {
                    Image(systemName: "minus")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.ironTextSecondary)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(Color.glassWhite))
                        .overlay(Circle().stroke(Color.glassBorder, lineWidth: 1))
                }
                
                Text("\(value)")
                    .font(IronFont.header(20))
                    .foregroundColor(.ironPurple)
                    .frame(minWidth: 50)
                
                Button {
                    if value + step <= range.upperBound {
                        value += step
                    }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.ironTextSecondary)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(Color.glassWhite))
                        .overlay(Circle().stroke(Color.glassBorder, lineWidth: 1))
                }
            }
        }
        .padding(16)
        .liquidGlass()
    }
}

// MARK: - Split Capsule Hero View (System Override Style)
struct SplitCapsuleHeroView: View {
    let onQuickStart: () -> Void
    let onBuild: () -> Void
    
    var body: some View {
        HStack(spacing: 0) {
            // Left side - Quick Start with hazard stripes
            Button(action: onQuickStart) {
                ZStack {
                    // Base plasma gradient
                    LiquidPlasmaEffect()
                    
                    // Hazard diagonal stripes overlay (very subtle)
                    DiagonalStripesPattern()
                        .opacity(0.08)
                    
                    // Content with lightning bolt
                    HStack(spacing: 8) {
                        // Lightning bolt icon
                        ZStack {
                            Image(systemName: "bolt.fill")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(.white)
                                .shadow(color: .white.opacity(0.8), radius: 4)
                        }
                        
                        Text("QUICK START")
                            .font(IronFont.bodySemibold(13))
                            .tracking(1.5)
                            .foregroundColor(.white)
                    }
                }
            }
            .buttonStyle(PlainButtonStyle())
            .frame(maxWidth: .infinity)
            .layoutPriority(2)
            
            // Laser divider with energy pulse
            ZStack {
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [.white.opacity(0.9), .ironPurple, .white.opacity(0.9)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 2)
                
                // Glow effect
                Rectangle()
                    .fill(Color.ironPurple)
                    .frame(width: 6)
                    .blur(radius: 4)
                    .opacity(0.8)
            }
            .frame(width: 2)
            
            // Right side - Build with dashed border glass (Drafting/Construction style)
            Button(action: onBuild) {
                ZStack {
                    // Frosted glass background
                    Rectangle()
                        .fill(.ultraThinMaterial)
                        .opacity(0.6)
                    
                    // Dark tint
                    Rectangle()
                        .fill(Color(red: 0.08, green: 0.08, blue: 0.1).opacity(0.7))
                    
                    // Dashed border pattern inside
                    Rectangle()
                        .strokeBorder(
                            Color.white.opacity(0.15),
                            style: StrokeStyle(lineWidth: 1, dash: [4, 4])
                        )
                        .padding(4)
                    
                    // Content with drafting plus icon
                    HStack(spacing: 6) {
                        // Plus icon in drafting style
                        ZStack {
                            // Crosshairs style plus
                            Image(systemName: "plus")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.white.opacity(0.7))
                        }
                        
                        Text("BUILD")
                            .font(IronFont.bodySemibold(13))
                            .tracking(1.5)
                            .foregroundColor(.white.opacity(0.8))
                    }
                }
            }
            .buttonStyle(PlainButtonStyle())
            .frame(width: 110)
        }
        .frame(height: 54)
        .clipShape(Capsule())
        .overlay {
            Capsule()
                .stroke(
                    LinearGradient(
                        colors: [.white.opacity(0.35), .white.opacity(0.12), .ironPurple.opacity(0.4)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.5
                )
        }
        .shadow(color: Color.ironPurple.opacity(0.35), radius: 18, x: 0, y: 8)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Diagonal Stripes Pattern (Hazard/Industrial)
struct DiagonalStripesPattern: View {
    var body: some View {
        GeometryReader { geo in
            Canvas { context, size in
                let stripeWidth: CGFloat = 8
                let spacing: CGFloat = 16
                let angle: CGFloat = 45 * .pi / 180
                
                for x in stride(from: -size.height, through: size.width + size.height, by: spacing) {
                    var path = Path()
                    let startX = x
                    let startY: CGFloat = 0
                    let endX = x + size.height * tan(angle)
                    let endY = size.height
                    
                    path.move(to: CGPoint(x: startX, y: startY))
                    path.addLine(to: CGPoint(x: endX, y: endY))
                    
                    context.stroke(
                        path,
                        with: .color(.white.opacity(0.3)),
                        lineWidth: stripeWidth
                    )
                }
            }
        }
        .clipped()
    }
}

// MARK: - Liquid Plasma Effect
struct LiquidPlasmaEffect: View {
    @State private var phase: CGFloat = 0
    
    var body: some View {
        TimelineView(.animation(minimumInterval: 1/30)) { timeline in
            Canvas { context, size in
                let time = timeline.date.timeIntervalSinceReferenceDate
                
                // Create plasma gradient layers
                for i in 0..<3 {
                    let offset = CGFloat(i) * 0.3
                    let x = sin(time * 0.5 + offset) * size.width * 0.3 + size.width * 0.5
                    let y = cos(time * 0.4 + offset) * size.height * 0.4 + size.height * 0.5
                    
                    let gradient = Gradient(colors: [
                        Color.ironPurple.opacity(0.8 - CGFloat(i) * 0.2),
                        Color.purpleGradientEnd.opacity(0.6 - CGFloat(i) * 0.15),
                        Color.clear
                    ])
                    
                    let shading = GraphicsContext.Shading.radialGradient(
                        gradient,
                        center: CGPoint(x: x, y: y),
                        startRadius: 0,
                        endRadius: size.width * 0.6
                    )
                    
                    context.fill(
                        Path(CGRect(origin: .zero, size: size)),
                        with: shading
                    )
                }
            }
        }
        .background(
            LinearGradient(
                colors: [.purpleGradientStart, .purpleGradientEnd],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }
}

// MARK: - Liquid Chrome Orb (Mercury-style play button)
struct LiquidChromeOrb: View {
    let size: CGFloat
    let onTap: () -> Void
    
    @State private var isPressed = false
    @State private var rippleScale: CGFloat = 0
    @State private var rippleOpacity: CGFloat = 0
    
    var body: some View {
        Button(action: {
            // Trigger ripple
            withAnimation(.easeOut(duration: 0.4)) {
                rippleScale = 2.0
                rippleOpacity = 0
            }
            rippleScale = 0.8
            rippleOpacity = 0.6
            
            onTap()
        }) {
            ZStack {
                // Ripple effect
                Circle()
                    .fill(Color.ironPurple.opacity(0.3))
                    .scaleEffect(rippleScale)
                    .opacity(rippleOpacity)
                
                // Outer glow
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color.white.opacity(0.3),
                                Color.ironPurple.opacity(0.2),
                                Color.clear
                            ],
                            center: .center,
                            startRadius: size * 0.3,
                            endRadius: size * 0.6
                        )
                    )
                    .frame(width: size * 1.4, height: size * 1.4)
                    .blur(radius: 8)
                
                // Chrome orb base
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color.white.opacity(0.95),
                                Color(white: 0.85),
                                Color(white: 0.6),
                                Color(white: 0.4)
                            ],
                            center: UnitPoint(x: 0.35, y: 0.25),
                            startRadius: 0,
                            endRadius: size * 0.6
                        )
                    )
                    .frame(width: size, height: size)
                
                // Chrome reflection highlight
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.9),
                                Color.white.opacity(0.3),
                                Color.clear
                            ],
                            startPoint: .topLeading,
                            endPoint: .center
                        )
                    )
                    .frame(width: size * 0.8, height: size * 0.8)
                    .offset(x: -size * 0.08, y: -size * 0.08)
                
                // Play icon
                Image(systemName: "play.fill")
                    .font(.system(size: size * 0.35, weight: .bold))
                    .foregroundColor(Color.ironPurple)
                    .offset(x: size * 0.04, y: 0)
                
                // Bottom reflection
                Ellipse()
                    .fill(
                        LinearGradient(
                            colors: [Color.clear, Color.white.opacity(0.4)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: size * 0.6, height: size * 0.2)
                    .offset(y: size * 0.25)
            }
            .scaleEffect(isPressed ? 0.92 : 1.0)
        }
        .buttonStyle(PlainButtonStyle())
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    withAnimation(.spring(response: 0.2, dampingFraction: 0.6)) {
                        isPressed = true
                    }
                }
                .onEnded { _ in
                    withAnimation(.spring(response: 0.2, dampingFraction: 0.6)) {
                        isPressed = false
                    }
                }
        )
    }
}

// MARK: - Data Stream Placeholder (Empty State)
struct DataStreamPlaceholder: View {
    @State private var wavePhase: CGFloat = 0
    @State private var pulseOpacity: CGFloat = 0.15
    
    var body: some View {
        VStack(spacing: 12) {
            // Animated sine wave graph - thin wireframe style
            ZStack {
                // Grid background (very subtle)
                GridPattern()
                    .stroke(Color.ironPurple.opacity(0.03), lineWidth: 0.5)
                
                // Thin wireframe wave - like a heart monitor trace
                WaveformPath(phase: wavePhase)
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.ironPurple.opacity(0.05),
                                Color.ironPurple.opacity(pulseOpacity),
                                Color.ironPurple.opacity(0.05)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        style: StrokeStyle(lineWidth: 1.5, lineCap: .round)
                    )
                
                // Subtle glow
                WaveformPath(phase: wavePhase)
                    .stroke(Color.ironPurple.opacity(pulseOpacity * 0.3), lineWidth: 3)
                    .blur(radius: 3)
            }
            .frame(height: 50)
            
            // Text
            VStack(spacing: 4) {
                Text("NO BIOMETRIC DATA LOGGED")
                    .font(IronFont.label(10))
                    .tracking(2)
                    .foregroundColor(.ironTextTertiary)
                
                Text("Initiate Sequence")
                    .font(IronFont.body(12))
                    .foregroundColor(.ironPurple.opacity(0.5))
            }
        }
        .padding(16)
        .liquidGlass()
        .onAppear {
            withAnimation(.linear(duration: 4).repeatForever(autoreverses: false)) {
                wavePhase = .pi * 2
            }
            withAnimation(.easeInOut(duration: 2.5).repeatForever(autoreverses: true)) {
                pulseOpacity = 0.3
            }
        }
    }
}

// Helper: Grid pattern for data stream
struct GridPattern: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let spacing: CGFloat = 20
        
        // Vertical lines
        for x in stride(from: 0, through: rect.width, by: spacing) {
            path.move(to: CGPoint(x: x, y: 0))
            path.addLine(to: CGPoint(x: x, y: rect.height))
        }
        
        // Horizontal lines
        for y in stride(from: 0, through: rect.height, by: spacing) {
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: rect.width, y: y))
        }
        
        return path
    }
}

// Helper: Waveform path for data stream
struct WaveformPath: Shape {
    var phase: CGFloat
    
    var animatableData: CGFloat {
        get { phase }
        set { phase = newValue }
    }
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let midY = rect.height / 2
        let amplitude = rect.height * 0.3
        let frequency: CGFloat = 3
        
        path.move(to: CGPoint(x: 0, y: midY))
        
        for x in stride(from: 0, through: rect.width, by: 2) {
            let relativeX = x / rect.width
            let y = midY + sin((relativeX * frequency * .pi * 2) + phase) * amplitude
            path.addLine(to: CGPoint(x: x, y: y))
        }
        
        return path
    }
}

// MARK: - Chromatic Text Effect
struct ChromaticText: View {
    let text: String
    let font: Font
    var offset: CGFloat = 1.0
    
    var body: some View {
        ZStack {
            // Red channel (offset left)
            Text(text)
                .font(font)
                .foregroundColor(.red.opacity(0.3))
                .offset(x: -offset, y: 0)
            
            // Blue channel (offset right)
            Text(text)
                .font(font)
                .foregroundColor(.blue.opacity(0.3))
                .offset(x: offset, y: 0)
            
            // Main text (green/white channel)
            Text(text)
                .font(font)
                .foregroundColor(.ironTextPrimary)
        }
    }
}

// MARK: - Ambient Glow Background
struct AmbientGlowBackground: View {
    @State private var animateGlow = false
    
    var body: some View {
        ZStack {
            // Primary slow-moving purple orb
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.ironPurple.opacity(0.2),
                            Color.ironPurple.opacity(0.08),
                            Color.clear
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: 300
                    )
                )
                .frame(width: 600, height: 600)
                .offset(
                    x: animateGlow ? 50 : -50,
                    y: animateGlow ? -100 : 100
                )
                .blur(radius: 80)
            
            // Secondary blue accent
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.ironCyan.opacity(0.08),
                            Color.clear
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: 200
                    )
                )
                .frame(width: 400, height: 400)
                .offset(
                    x: animateGlow ? -80 : 80,
                    y: animateGlow ? 200 : 50
                )
                .blur(radius: 60)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 12).repeatForever(autoreverses: true)) {
                animateGlow = true
            }
        }
    }
}

// MARK: - Floating Dock Tab Bar
struct FloatingDockTabBar<Tab: Hashable & CaseIterable>: View where Tab: RawRepresentable, Tab.RawValue == String {
    @Binding var selectedTab: Tab
    let tabs: [(tab: Tab, icon: String, iconFilled: String, label: String)]
    @Namespace private var animation
    
    var body: some View {
        HStack(spacing: 0) {
            ForEach(tabs, id: \.tab.rawValue) { item in
                FloatingDockTabItem(
                    icon: item.icon,
                    iconFilled: item.iconFilled,
                    label: item.label,
                    isSelected: selectedTab == item.tab,
                    namespace: animation
                ) {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        selectedTab = item.tab
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background {
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay {
                    Capsule()
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.25),
                                    Color.white.opacity(0.08),
                                    Color.ironPurple.opacity(0.15)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                }
                .shadow(color: Color.black.opacity(0.3), radius: 20, x: 0, y: 10)
        }
        .padding(.horizontal, 40)
        .padding(.bottom, 20)
    }
}

struct FloatingDockTabItem: View {
    let icon: String
    let iconFilled: String
    let label: String
    let isSelected: Bool
    var namespace: Namespace.ID
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                ZStack {
                    // Neon underglow for active tab
                    if isSelected {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.ironPurple)
                            .frame(width: 40, height: 4)
                            .blur(radius: 6)
                            .offset(y: 14)
                            .matchedGeometryEffect(id: "underglow", in: namespace)
                        
                        // Additional glow
                        Circle()
                            .fill(Color.ironPurple.opacity(0.4))
                            .frame(width: 50, height: 50)
                            .blur(radius: 15)
                            .matchedGeometryEffect(id: "glow", in: namespace)
                    }
                    
                    Image(systemName: isSelected ? iconFilled : icon)
                        .font(.system(size: 22, weight: isSelected ? .semibold : .regular))
                        .foregroundColor(isSelected ? .white : Color.white.opacity(0.4))
                        .shadow(color: isSelected ? Color.ironPurple.opacity(0.8) : .clear, radius: 8)
                }
                .frame(height: 28)
                
                Text(label)
                    .font(.system(size: 10, weight: isSelected ? .semibold : .regular))
                    .foregroundColor(isSelected ? .white : Color.white.opacity(0.4))
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }
}
