import SwiftUI

// MARK: - Pilot Login View
/// Simple sign-in only view for pilot users.
/// No signup - users are manually created via Supabase dashboard.

struct PilotLoginView: View {
    @StateObject private var viewModel = AuthViewModel()
    @State private var showDisclaimer = false
    
    var onAuthenticated: () -> Void
    
    var body: some View {
        ZStack {
            // Background
            Color.black.ignoresSafeArea()
            
            VStack(spacing: 0) {
                Spacer()
                
                // Logo/Title area
                VStack(spacing: 12) {
                    Image(systemName: "dumbbell.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.purple, .purple.opacity(0.7)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    
                    Text("IronForge")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    
                    Text("Friend Pilot")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white.opacity(0.5))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                        .background(Color.purple.opacity(0.2))
                        .clipShape(Capsule())
                }
                .padding(.bottom, 48)
                
                // Login form
                VStack(spacing: 20) {
                    // Email field
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Email")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.white.opacity(0.6))
                        
                        TextField("", text: $viewModel.email)
                            .textFieldStyle(PilotTextFieldStyle())
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
                            .textFieldStyle(PilotTextFieldStyle())
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
                            if viewModel.isAuthenticated {
                                onAuthenticated()
                            }
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
                                colors: viewModel.isFormValid 
                                    ? [Color.purple, Color.purple.opacity(0.8)] 
                                    : [Color.gray.opacity(0.3), Color.gray.opacity(0.2)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .foregroundColor(.white)
                        .cornerRadius(14)
                        .shadow(color: viewModel.isFormValid ? Color.purple.opacity(0.4) : .clear, radius: 12, y: 4)
                    }
                    .disabled(!viewModel.isFormValid || viewModel.isLoading)
                    .padding(.top, 8)
                }
                .padding(.horizontal, 24)
                
                Spacer()
                
                // Disclaimer link
                Button {
                    showDisclaimer = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "info.circle")
                        Text("Pilot Program Info")
                    }
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.5))
                }
                .padding(.bottom, 24)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: viewModel.errorMessage)
        .sheet(isPresented: $showDisclaimer) {
            PilotDisclaimerSheet()
        }
    }
}

// MARK: - Text Field Style

struct PilotTextFieldStyle: TextFieldStyle {
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

// MARK: - Disclaimer Sheet

struct PilotDisclaimerSheet: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Header
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Friend Pilot Program")
                            .font(.title2.weight(.bold))
                        
                        Text("Thank you for being part of this early test!")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    
                    Divider()
                    
                    // What this is
                    section(title: "What is this?", icon: "questionmark.circle.fill") {
                        Text("IronForge is an experimental training app that recommends weights and progressions based on your history and recovery. This pilot helps us collect real feedback to make it better.")
                    }
                    
                    // Safety
                    section(title: "Your Safety", icon: "shield.checkmark.fill", color: .green) {
                        VStack(alignment: .leading, spacing: 8) {
                            bulletPoint("Recommendations are suggestions, not medical advice")
                            bulletPoint("Always listen to your body")
                            bulletPoint("You can override any recommendation")
                            bulletPoint("Report any concerns immediately")
                        }
                    }
                    
                    // What we collect
                    section(title: "What We Collect", icon: "doc.text.fill", color: .blue) {
                        VStack(alignment: .leading, spacing: 8) {
                            bulletPoint("Your workout data (weights, reps, sets)")
                            bulletPoint("Readiness and recovery metrics")
                            bulletPoint("Occasional feedback on recommendations")
                            bulletPoint("Never shared or sold")
                        }
                    }
                    
                    // Conservative mode
                    section(title: "Conservative Mode", icon: "tortoise.fill", color: .orange) {
                        Text("The app runs in conservative mode by default. This means smaller increases, more safety checks, and a bias toward holding steady rather than pushing hard.")
                    }
                    
                    Spacer(minLength: 40)
                }
                .padding(24)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Got it") {
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
    
    private func section(title: String, icon: String, color: Color = .purple, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundStyle(color)
                Text(title)
                    .font(.headline)
            }
            
            content()
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
    
    private func bulletPoint(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("•")
            Text(text)
        }
    }
}

// MARK: - Preview

#Preview("Login") {
    PilotLoginView(onAuthenticated: {})
}

#Preview("Disclaimer") {
    PilotDisclaimerSheet()
}
