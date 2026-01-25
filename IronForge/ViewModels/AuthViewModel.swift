import Foundation
import SwiftUI

@MainActor
final class AuthViewModel: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published var email = ""
    @Published var password = ""
    @Published var confirmPassword = ""
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var isAuthenticated = false
    
    // MARK: - Validation
    
    var isFormValid: Bool {
        !email.isEmpty && email.contains("@") && password.count >= 6
    }
    
    var isSignUpFormValid: Bool {
        isFormValid && password == confirmPassword && password.count >= 8
    }
    
    var passwordStrength: String {
        let length = password.count
        if length < 8 {
            return "Weak"
        } else if length < 12 {
            return "Good"
        } else {
            return "Strong"
        }
    }
    
    var passwordStrengthColor: Color {
        let length = password.count
        if length < 8 {
            return .red
        } else if length < 12 {
            return .yellow
        } else {
            return .green
        }
    }
    
    // MARK: - Auth Actions
    
    func signIn() async {
        guard isFormValid else {
            errorMessage = "Please enter a valid email and password"
            return
        }
        
        isLoading = true
        errorMessage = nil
        
        do {
            _ = try await SupabaseService.shared.signIn(email: email, password: password)
            isAuthenticated = true
            clearForm()
        } catch let error as SupabaseError {
            switch error {
            case .authError(let message):
                errorMessage = message
            default:
                errorMessage = error.localizedDescription
            }
        } catch {
            errorMessage = "An unexpected error occurred. Please try again."
        }
        
        isLoading = false
    }
    
    func signUp() async {
        guard isSignUpFormValid else {
            if password != confirmPassword {
                errorMessage = "Passwords don't match"
            } else if password.count < 8 {
                errorMessage = "Password must be at least 8 characters"
            } else {
                errorMessage = "Please fill in all fields correctly"
            }
            return
        }
        
        isLoading = true
        errorMessage = nil
        
        do {
            _ = try await SupabaseService.shared.signUp(email: email, password: password)
            isAuthenticated = true
            clearForm()
        } catch let error as SupabaseError {
            switch error {
            case .authError(let message):
                // Handle common Supabase auth errors
                if message.contains("already registered") {
                    errorMessage = "An account with this email already exists"
                } else {
                    errorMessage = message
                }
            default:
                errorMessage = error.localizedDescription
            }
        } catch {
            errorMessage = "An unexpected error occurred. Please try again."
        }
        
        isLoading = false
    }
    
    func clearForm() {
        email = ""
        password = ""
        confirmPassword = ""
        errorMessage = nil
    }
}
