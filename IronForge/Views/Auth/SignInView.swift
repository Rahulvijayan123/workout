import SwiftUI

struct SignInView: View {
    @ObservedObject var viewModel: AuthViewModel
    var onSwitchToSignUp: () -> Void
    
    let neonPurple = Color(red: 0.6, green: 0.3, blue: 1.0)
    
    var body: some View {
        VStack(spacing: 20) {
            // Title
            Text("Welcome back")
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
                Text("Password")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white.opacity(0.6))
                
                SecureField("", text: $viewModel.password)
                    .textFieldStyle(AuthTextFieldStyle())
                    .textContentType(.password)
            }
            
            // Error message
            if let error = viewModel.errorMessage {
                Text(error)
                    .font(.system(size: 13))
                    .foregroundColor(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .transition(.opacity)
            }
            
            // Sign In button
            Button {
                Task {
                    await viewModel.signIn()
                }
            } label: {
                HStack {
                    if viewModel.isLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(0.9)
                    } else {
                        Text("Sign In")
                            .font(.system(size: 16, weight: .semibold))
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(
                    LinearGradient(
                        colors: viewModel.isFormValid ? [neonPurple, neonPurple.opacity(0.8)] : [Color.gray.opacity(0.3), Color.gray.opacity(0.2)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .foregroundColor(.white)
                .cornerRadius(14)
                .shadow(color: viewModel.isFormValid ? neonPurple.opacity(0.4) : .clear, radius: 12, y: 4)
            }
            .disabled(!viewModel.isFormValid || viewModel.isLoading)
            .padding(.top, 8)
            
            // Switch to sign up
            HStack(spacing: 4) {
                Text("Don't have an account?")
                    .foregroundColor(.white.opacity(0.6))
                
                Button {
                    onSwitchToSignUp()
                } label: {
                    Text("Sign Up")
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
