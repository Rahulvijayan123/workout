import Foundation

/// Supabase configuration
/// Keys are loaded from Secrets.plist which should NOT be committed to version control
enum SupabaseConfig {
    
    /// Error message if Secrets.plist is missing (for debugging)
    static var loadError: String?

    private static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }
    
    private static let secrets: [String: Any] = {
        guard let url = Bundle.main.url(forResource: "Secrets", withExtension: "plist") else {
            loadError = "Secrets.plist not found in app bundle. Make sure it's added to the Xcode project and included in 'Copy Bundle Resources'."
            print("⚠️ CONFIG ERROR: \(loadError!)")
            // Return empty dict - app will show error UI instead of crashing
            #if DEBUG
            if !isRunningTests {
                assertionFailure(loadError!)
            }
            #endif
            return [:]
        }
        guard let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            loadError = "Secrets.plist exists but could not be parsed. Check the file format."
            print("⚠️ CONFIG ERROR: \(loadError!)")
            #if DEBUG
            if !isRunningTests {
                assertionFailure(loadError!)
            }
            #endif
            return [:]
        }
        return plist
    }()
    
    private static func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private static func isPlaceholderValue(_ value: String) -> Bool {
        let v = normalized(value)
        guard !v.isEmpty else { return true }
        
        let upper = v.uppercased()
        return upper.contains("YOUR_") ||
            upper.contains("PASTE_") ||
            upper.contains("REPLACE_") ||
            upper.contains("INSERT_") ||
            upper.contains("CHANGEME") ||
            upper.contains("_HERE")
    }
    
    /// A user-presentable validation error for missing/invalid config.
    /// Nil means config looks valid.
    static var validationError: String? {
        if let loadError { return loadError }
        
        let u = normalized(url)
        if isPlaceholderValue(u) {
            return "Secrets.plist contains placeholder values. Please set SUPABASE_URL and SUPABASE_ANON_KEY."
        }
        if let comps = URLComponents(string: u),
           let scheme = comps.scheme,
           let host = comps.host,
           !scheme.isEmpty,
           !host.isEmpty,
           scheme == "https" || scheme == "http" {
            // ok
        } else {
            return "SUPABASE_URL is invalid. Expected a full URL like https://xyz.supabase.co"
        }
        
        let anon = normalized(anonKey)
        if isPlaceholderValue(anon) {
            return "SUPABASE_ANON_KEY is missing or placeholder. Please paste the Supabase anon key."
        }
        
        return nil
    }
    
    /// Returns true if configuration is valid and ready to use
    static var isConfigured: Bool {
        return validationError == nil
    }
    
    static var url: String {
        normalized(secrets["SUPABASE_URL"] as? String ?? "")
    }
    
    static var anonKey: String {
        normalized(secrets["SUPABASE_ANON_KEY"] as? String ?? "")
    }
}
