import Foundation
import SwiftUI
import AuthenticationServices
import CryptoKit

@MainActor
final class AuthViewModel: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published var email = ""
    @Published var password = ""
    @Published var confirmPassword = ""
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var isAuthenticated = false
    
    // MARK: - Apple Sign-In
    
    private var currentNonce: String?
    
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
    
    // MARK: - Apple Sign-In
    
    /// Generate a random nonce for Apple Sign-In
    func generateNonce() -> String {
        let nonce = randomNonceString()
        currentNonce = nonce
        return nonce
    }
    
    /// Get the SHA256 hash of the nonce for Apple's request
    func sha256(_ input: String) -> String {
        let inputData = Data(input.utf8)
        let hashedData = SHA256.hash(data: inputData)
        return hashedData.compactMap { String(format: "%02x", $0) }.joined()
    }
    
    /// Handle the Apple Sign-In authorization result
    func handleAppleSignIn(_ result: Result<ASAuthorization, Error>) async {
        isLoading = true
        errorMessage = nil
        
        switch result {
        case .success(let authorization):
            guard let appleCredential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let identityTokenData = appleCredential.identityToken,
                  let identityToken = String(data: identityTokenData, encoding: .utf8),
                  let nonce = currentNonce else {
                errorMessage = "Failed to get Apple credentials"
                isLoading = false
                return
            }
            
            do {
                _ = try await SupabaseService.shared.signInWithApple(idToken: identityToken, nonce: nonce)
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
                errorMessage = "Apple sign-in failed. Please try again."
            }
            
        case .failure(let error):
            // Don't show error for user cancellation
            if (error as NSError).code != ASAuthorizationError.canceled.rawValue {
                errorMessage = "Apple sign-in failed: \(error.localizedDescription)"
            }
        }
        
        isLoading = false
    }
    
    /// Generate a cryptographically secure random string
    private func randomNonceString(length: Int = 32) -> String {
        precondition(length > 0)
        var randomBytes = [UInt8](repeating: 0, count: length)
        let errorCode = SecRandomCopyBytes(kSecRandomDefault, randomBytes.count, &randomBytes)
        if errorCode != errSecSuccess {
            fatalError("Unable to generate nonce. SecRandomCopyBytes failed with OSStatus \(errorCode)")
        }
        
        let charset: [Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        return String(randomBytes.map { byte in
            charset[Int(byte) % charset.count]
        })
    }
}
