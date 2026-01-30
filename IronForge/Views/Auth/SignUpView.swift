import SwiftUI
import AuthenticationServices

struct SignUpView: View {
    @ObservedObject var viewModel: AuthViewModel
    var onSwitchToSignIn: () -> Void
    
    let neonPurple = Color(red: 0.6, green: 0.3, blue: 1.0)
    
    var body: some View {
        VStack(spacing: 20) {
            // Title
            Text("Create account")
                .font(.system(size: 24, weight: .semibold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            // Email field
            VStack(alignment: .leading, spacing: 8) {
                Text("Email")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white.opacity(0.6))
                
                TextField("", text: $viewModel.email)
                    .textFieldStyle(AuthTextFieldStyle())
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .autocapitalization(.none)
                    .autocorrectionDisabled()
            }
            
            // Password field
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Password")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white.opacity(0.6))
                    
                    Spacer()
                    
                    if !viewModel.password.isEmpty {
                        Text(viewModel.passwordStrength)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(viewModel.passwordStrengthColor)
                    }
                }
                
                SecureField("", text: $viewModel.password)
                    .textFieldStyle(AuthTextFieldStyle())
                    .textContentType(.newPassword)
                
                // Password requirements
                if !viewModel.password.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        PasswordRequirementRow(
                            text: "At least 8 characters",
                            isMet: viewModel.password.count >= 8
                        )
                    }
                    .padding(.top, 4)
                }
            }
            
            // Confirm Password field
            VStack(alignment: .leading, spacing: 8) {
                Text("Confirm Password")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white.opacity(0.6))
                
                SecureField("", text: $viewModel.confirmPassword)
                    .textFieldStyle(AuthTextFieldStyle())
                    .textContentType(.newPassword)
                
                if !viewModel.confirmPassword.isEmpty && viewModel.password != viewModel.confirmPassword {
                    Text("Passwords don't match")
                        .font(.system(size: 12))
                        .foregroundColor(.red.opacity(0.8))
                }
            }
            
            // Error message
            if let error = viewModel.errorMessage {
                Text(error)
                    .font(.system(size: 13))
                    .foregroundColor(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .transition(.opacity)
            }
            
            // Sign Up button
            Button {
                Task {
                    await viewModel.signUp()
                }
            } label: {
                HStack {
                    if viewModel.isLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(0.9)
                    } else {
                        Text("Create Account")
                            .font(.system(size: 16, weight: .semibold))
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(
                    LinearGradient(
                        colors: viewModel.isSignUpFormValid ? [neonPurple, neonPurple.opacity(0.8)] : [Color.gray.opacity(0.3), Color.gray.opacity(0.2)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .foregroundColor(.white)
                .cornerRadius(14)
                .shadow(color: viewModel.isSignUpFormValid ? neonPurple.opacity(0.4) : .clear, radius: 12, y: 4)
            }
            .disabled(!viewModel.isSignUpFormValid || viewModel.isLoading)
            .padding(.top, 8)
            
            // Divider
            HStack(spacing: 16) {
                Rectangle()
                    .fill(Color.white.opacity(0.2))
                    .frame(height: 1)
                
                Text("or")
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.5))
                
                Rectangle()
                    .fill(Color.white.opacity(0.2))
                    .frame(height: 1)
            }
            .padding(.vertical, 8)
            
            // Sign up with Apple
            SignInWithAppleButton(.signUp) { request in
                request.requestedScopes = [.email, .fullName]
                request.nonce = viewModel.getHashedNonce()
            } onCompletion: { result in
                Task {
                    await viewModel.handleAppleSignIn(result)
                }
            }
            .signInWithAppleButtonStyle(.white)
            .frame(height: 52)
            .cornerRadius(14)
            .onAppear {
                _ = viewModel.prepareAppleSignIn()
            }
            
            // Switch to sign in
            HStack(spacing: 4) {
                Text("Already have an account?")
                    .foregroundColor(.white.opacity(0.6))
                
                Button {
                    onSwitchToSignIn()
                } label: {
                    Text("Sign In")
                        .fontWeight(.semibold)
                        .foregroundColor(neonPurple)
                }
            }
            .font(.system(size: 14))
            .padding(.top, 12)
        }
        .animation(.easeInOut(duration: 0.2), value: viewModel.errorMessage)
    }
}

// MARK: - Password Requirement Row

struct PasswordRequirementRow: View {
    let text: String
    let isMet: Bool
    
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: isMet ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 12))
                .foregroundColor(isMet ? .green : .white.opacity(0.4))
            
            Text(text)
                .font(.system(size: 12))
                .foregroundColor(isMet ? .white.opacity(0.8) : .white.opacity(0.4))
        }
    }
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        SignUpView(viewModel: AuthViewModel(), onSwitchToSignIn: {})
            .padding()
    }
}
