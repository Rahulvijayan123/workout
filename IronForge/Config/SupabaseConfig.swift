import Foundation

/// Supabase configuration
/// Keys are loaded from Secrets.plist which should NOT be committed to version control
enum SupabaseConfig {
    
    private static let secrets: [String: Any] = {
        guard let url = Bundle.main.url(forResource: "Secrets", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            fatalError("Secrets.plist not found. Copy Secrets.plist.template to Secrets.plist and add your keys.")
        }
        return plist
    }()
    
    static var url: String {
        guard let url = secrets["SUPABASE_URL"] as? String, !url.isEmpty else {
            fatalError("SUPABASE_URL not found in Secrets.plist")
        }
        return url
    }
    
    static var anonKey: String {
        guard let key = secrets["SUPABASE_ANON_KEY"] as? String, !key.isEmpty else {
            fatalError("SUPABASE_ANON_KEY not found in Secrets.plist")
        }
        return key
    }
    
    // Service key should NEVER be in client code in production
    // Only use for local development/testing
    #if DEBUG
    static var serviceKey: String {
        guard let key = secrets["SUPABASE_SERVICE_KEY"] as? String, !key.isEmpty else {
            fatalError("SUPABASE_SERVICE_KEY not found in Secrets.plist")
        }
        return key
    }
    #endif
}
