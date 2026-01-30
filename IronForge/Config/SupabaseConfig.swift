import Foundation

/// Supabase configuration
/// Keys are loaded from Secrets.plist which should NOT be committed to version control
enum SupabaseConfig {
    
    /// Error message if Secrets.plist is missing (for debugging)
    static var loadError: String?
    
    private static let secrets: [String: Any] = {
        guard let url = Bundle.main.url(forResource: "Secrets", withExtension: "plist") else {
            loadError = "Secrets.plist not found in app bundle. Make sure it's added to the Xcode project and included in 'Copy Bundle Resources'."
            print("⚠️ FATAL CONFIG ERROR: \(loadError!)")
            // Return empty dict - app will show error UI instead of crashing
            return [:]
        }
        guard let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            loadError = "Secrets.plist exists but could not be parsed. Check the file format."
            print("⚠️ FATAL CONFIG ERROR: \(loadError!)")
            return [:]
        }
        return plist
    }()
    
    /// Returns true if configuration is valid and ready to use
    static var isConfigured: Bool {
        return loadError == nil && !url.isEmpty && !anonKey.isEmpty && !anonKey.contains("PASTE_")
    }
    
    static var url: String {
        secrets["SUPABASE_URL"] as? String ?? ""
    }
    
    static var anonKey: String {
        secrets["SUPABASE_ANON_KEY"] as? String ?? ""
    }
    
    // Service key should NEVER be in client code in production
    // Only use for local development/testing
    #if DEBUG
    static var serviceKey: String {
        secrets["SUPABASE_SERVICE_KEY"] as? String ?? ""
    }
    #endif
}
