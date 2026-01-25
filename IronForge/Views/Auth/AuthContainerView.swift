import SwiftUI

struct AuthContainerView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var viewModel = AuthViewModel()
    @State private var showSignUp = false
    
    let neonPurple = Color(red: 0.6, green: 0.3, blue: 1.0)
    
    var body: some View {
        ZStack {
            // Deep charcoal background
            Color(red: 0.02, green: 0.02, blue: 0.02)
                .ignoresSafeArea()
            
            // Ambient light blobs for liquid glass effect
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
                Spacer()
                    .frame(height: 60)
                
                // Logo / App Name
                VStack(spacing: 12) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 60))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [neonPurple, neonPurple.opacity(0.6)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .shadow(color: neonPurple.opacity(0.6), radius: 20)
                    
                    Text("IronForge")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    
                    Text("Intelligent strength training")
                        .font(.system(size: 15))
                        .foregroundColor(.white.opacity(0.6))
                }
                .padding(.bottom, 50)
                
                // Auth Form
                if showSignUp {
                    SignUpView(viewModel: viewModel, onSwitchToSignIn: {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                            showSignUp = false
                        }
                    })
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))
                } else {
                    SignInView(viewModel: viewModel, onSwitchToSignUp: {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                            showSignUp = true
                        }
                    })
                    .transition(.asymmetric(
                        insertion: .move(edge: .leading).combined(with: .opacity),
                        removal: .move(edge: .trailing).combined(with: .opacity)
                    ))
                }
                
                Spacer()
            }
            .padding(.horizontal, 24)
        }
        .onChange(of: viewModel.isAuthenticated) { _, isAuthenticated in
            if isAuthenticated {
                appState.isAuthenticated = true
            }
        }
    }
}

#Preview {
    AuthContainerView()
        .environmentObject(AppState())
}
