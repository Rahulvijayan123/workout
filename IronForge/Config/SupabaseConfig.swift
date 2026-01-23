import Foundation

/// Supabase configuration
/// IMPORTANT: In production, these should come from environment variables or secure storage
enum SupabaseConfig {
    static let url = "https://euhtvcptjkgvivaeunze.supabase.co"
    static let anonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImV1aHR2Y3B0amtndml2YWV1bnplIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjkxMTY1NjksImV4cCI6MjA4NDY5MjU2OX0.BIRcac0RJbiTAfGt5usnR1u_VZWOJ3ZZtH8FtNbP_qQ"
    
    // Service key should NEVER be in client code in production
    // Only use for local development/testing
    #if DEBUG
    static let serviceKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImV1aHR2Y3B0amtndml2YWV1bnplIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc2OTExNjU2OSwiZXhwIjoyMDg0NjkyNTY5fQ.7MYNuqkckjSqELge7kupD-lRCgvclB_yyfskcw3izgA"
    #endif
}
