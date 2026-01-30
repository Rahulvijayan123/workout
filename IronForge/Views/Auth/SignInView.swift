import SwiftUI
import AuthenticationServices

struct SignInView: View {
    @ObservedObject var viewModel: AuthViewModel
    var onSwitchToSignUp: () -> Void
    
    let neonPurple = Color(red: 0.6, green: 0.3, blue: 1.0)
    
    var body: some View {
        VStack(spacing: 24) {
            // Title
            Text("Get Started")
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(.white)
            
            Text("Sign in to begin your training journey")
                .font(.system(size: 15))
                .foregroundColor(.white.opacity(0.6))
                .multilineTextAlignment(.center)
            
            Spacer()
                .frame(height: 20)
            
            // Error message
            if let error = viewModel.errorMessage {
                Text(error)
                    .font(.system(size: 13))
                    .foregroundColor(.red)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.horizontal)
                    .transition(.opacity)
            }
            
            // Sign in with Apple - main action
            SignInWithAppleButton(.signIn) { request in
                request.requestedScopes = [.email, .fullName]
                // Use getHashedNonce() to ensure the same nonce is used
                // even if this closure is called multiple times
                request.nonce = viewModel.getHashedNonce()
            } onCompletion: { result in
                Task {
                    await viewModel.handleAppleSignIn(result)
                }
            }
            .signInWithAppleButtonStyle(.white)
            .frame(height: 56)
            .cornerRadius(14)
            .shadow(color: .white.opacity(0.1), radius: 10, y: 4)
            .onAppear {
                // Prepare fresh nonce when view appears
                _ = viewModel.prepareAppleSignIn()
            }
            
            // Loading indicator
            if viewModel.isLoading {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: neonPurple))
                    .scaleEffect(1.2)
                    .padding(.top, 20)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: viewModel.errorMessage)
        .animation(.easeInOut(duration: 0.2), value: viewModel.isLoading)
    }
}

// MARK: - Custom Text Field Style

struct AuthTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white.opacity(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    )
            )
            .foregroundColor(.white)
            .font(.system(size: 16))
    }
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        SignInView(viewModel: AuthViewModel(), onSwitchToSignUp: {})
            .padding()
    }
}
