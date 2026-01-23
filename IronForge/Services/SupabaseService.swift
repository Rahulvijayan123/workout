import Foundation

// MARK: - Supabase Service
/// Handles all Supabase REST API interactions for data persistence and sync
@MainActor
final class SupabaseService: ObservableObject {
    
    static let shared = SupabaseService()
    
    // MARK: - Properties
    
    private let baseURL: URL
    private let anonKey: String
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    
    @Published private(set) var isAuthenticated = false
    @Published private(set) var currentUserId: String?
    @Published private(set) var authToken: String?
    
    // MARK: - Init
    
    private init() {
        self.baseURL = URL(string: SupabaseConfig.url)!
        self.anonKey = SupabaseConfig.anonKey
        
        self.encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.dateEncodingStrategy = .iso8601
        
        self.decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        
        // Check for stored auth
        loadStoredAuth()
    }
    
    // MARK: - Auth Storage
    
    private let authTokenKey = "supabase.authToken"
    private let userIdKey = "supabase.userId"
    private let refreshTokenKey = "supabase.refreshToken"
    
    private func loadStoredAuth() {
        if let token = UserDefaults.standard.string(forKey: authTokenKey),
           let userId = UserDefaults.standard.string(forKey: userIdKey) {
            self.authToken = token
            self.currentUserId = userId
            self.isAuthenticated = true
        }
    }
    
    private func storeAuth(token: String, userId: String, refreshToken: String?) {
        UserDefaults.standard.set(token, forKey: authTokenKey)
        UserDefaults.standard.set(userId, forKey: userIdKey)
        if let refreshToken {
            UserDefaults.standard.set(refreshToken, forKey: refreshTokenKey)
        }
        self.authToken = token
        self.currentUserId = userId
        self.isAuthenticated = true
    }
    
    func clearAuth() {
        UserDefaults.standard.removeObject(forKey: authTokenKey)
        UserDefaults.standard.removeObject(forKey: userIdKey)
        UserDefaults.standard.removeObject(forKey: refreshTokenKey)
        self.authToken = nil
        self.currentUserId = nil
        self.isAuthenticated = false
    }
    
    // MARK: - Authentication
    
    struct AuthResponse: Codable {
        let accessToken: String
        let tokenType: String
        let expiresIn: Int
        let refreshToken: String?
        let user: AuthUser
    }
    
    struct AuthUser: Codable {
        let id: String
        let email: String?
        let phone: String?
        let createdAt: String?
    }
    
    struct AuthError: Codable, Error {
        let error: String?
        let errorDescription: String?
        let message: String?
    }
    
    /// Sign up with email and password
    func signUp(email: String, password: String) async throws -> AuthUser {
        let url = baseURL.appendingPathComponent("auth/v1/signup")
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(anonKey)", forHTTPHeaderField: "Authorization")
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        
        let body: [String: Any] = [
            "email": email,
            "password": password
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SupabaseError.invalidResponse
        }
        
        if httpResponse.statusCode >= 400 {
            if let error = try? decoder.decode(AuthError.self, from: data) {
                throw SupabaseError.authError(error.message ?? error.errorDescription ?? "Unknown error")
            }
            throw SupabaseError.httpError(httpResponse.statusCode)
        }
        
        let authResponse = try decoder.decode(AuthResponse.self, from: data)
        storeAuth(token: authResponse.accessToken, userId: authResponse.user.id, refreshToken: authResponse.refreshToken)
        
        return authResponse.user
    }
    
    /// Sign in with email and password
    func signIn(email: String, password: String) async throws -> AuthUser {
        let url = baseURL.appendingPathComponent("auth/v1/token")
        
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "grant_type", value: "password")]
        
        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(anonKey)", forHTTPHeaderField: "Authorization")
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        
        let body: [String: Any] = [
            "email": email,
            "password": password
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SupabaseError.invalidResponse
        }
        
        if httpResponse.statusCode >= 400 {
            if let error = try? decoder.decode(AuthError.self, from: data) {
                throw SupabaseError.authError(error.message ?? error.errorDescription ?? "Unknown error")
            }
            throw SupabaseError.httpError(httpResponse.statusCode)
        }
        
        let authResponse = try decoder.decode(AuthResponse.self, from: data)
        storeAuth(token: authResponse.accessToken, userId: authResponse.user.id, refreshToken: authResponse.refreshToken)
        
        return authResponse.user
    }
    
    /// Sign out
    func signOut() async throws {
        guard let token = authToken else { return }
        
        let url = baseURL.appendingPathComponent("auth/v1/logout")
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        
        _ = try? await URLSession.shared.data(for: request)
        clearAuth()
    }
    
    // MARK: - REST API
    
    /// Generic fetch from a table
    func fetch<T: Codable>(
        from table: String,
        select: String = "*",
        filter: [String: Any]? = nil,
        order: String? = nil,
        ascending: Bool = true,
        limit: Int? = nil,
        single: Bool = false
    ) async throws -> T {
        var components = URLComponents(url: baseURL.appendingPathComponent("rest/v1/\(table)"), resolvingAgainstBaseURL: false)!
        
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "select", value: select)
        ]
        
        if let filter {
            for (key, value) in filter {
                queryItems.append(URLQueryItem(name: key, value: "eq.\(value)"))
            }
        }
        
        if let order {
            queryItems.append(URLQueryItem(name: "order", value: "\(order).\(ascending ? "asc" : "desc")"))
        }
        
        if let limit {
            queryItems.append(URLQueryItem(name: "limit", value: "\(limit)"))
        }
        
        components.queryItems = queryItems
        
        var request = URLRequest(url: components.url!)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        
        if let token = authToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        
        if single {
            request.setValue("application/vnd.pgrst.object+json", forHTTPHeaderField: "Accept")
        }
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SupabaseError.invalidResponse
        }
        
        if httpResponse.statusCode >= 400 {
            throw SupabaseError.httpError(httpResponse.statusCode)
        }
        
        return try decoder.decode(T.self, from: data)
    }
    
    /// Insert into a table
    func insert<T: Codable, R: Codable>(
        into table: String,
        values: T,
        returning: Bool = true
    ) async throws -> R? {
        let url = baseURL.appendingPathComponent("rest/v1/\(table)")
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        
        if let token = authToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        
        if returning {
            request.setValue("return=representation", forHTTPHeaderField: "Prefer")
            request.setValue("application/vnd.pgrst.object+json", forHTTPHeaderField: "Accept")
        }
        
        request.httpBody = try encoder.encode(values)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SupabaseError.invalidResponse
        }
        
        if httpResponse.statusCode >= 400 {
            let errorText = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw SupabaseError.apiError(errorText)
        }
        
        if returning && !data.isEmpty {
            return try decoder.decode(R.self, from: data)
        }
        
        return nil
    }
    
    /// Update a row in a table
    func update<T: Codable, R: Codable>(
        table: String,
        values: T,
        filter: [String: Any],
        returning: Bool = true
    ) async throws -> R? {
        var components = URLComponents(url: baseURL.appendingPathComponent("rest/v1/\(table)"), resolvingAgainstBaseURL: false)!
        
        var queryItems: [URLQueryItem] = []
        for (key, value) in filter {
            queryItems.append(URLQueryItem(name: key, value: "eq.\(value)"))
        }
        components.queryItems = queryItems
        
        var request = URLRequest(url: components.url!)
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        
        if let token = authToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        
        if returning {
            request.setValue("return=representation", forHTTPHeaderField: "Prefer")
            request.setValue("application/vnd.pgrst.object+json", forHTTPHeaderField: "Accept")
        }
        
        request.httpBody = try encoder.encode(values)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SupabaseError.invalidResponse
        }
        
        if httpResponse.statusCode >= 400 {
            let errorText = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw SupabaseError.apiError(errorText)
        }
        
        if returning && !data.isEmpty {
            return try decoder.decode(R.self, from: data)
        }
        
        return nil
    }
    
    /// Upsert (insert or update) into a table
    func upsert<T: Codable, R: Codable>(
        into table: String,
        values: T,
        onConflict: String? = nil,
        returning: Bool = true
    ) async throws -> R? {
        let url = baseURL.appendingPathComponent("rest/v1/\(table)")
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        
        if let token = authToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        
        var prefer = "resolution=merge-duplicates"
        if returning {
            prefer += ",return=representation"
        }
        request.setValue(prefer, forHTTPHeaderField: "Prefer")
        
        if returning {
            request.setValue("application/vnd.pgrst.object+json", forHTTPHeaderField: "Accept")
        }
        
        request.httpBody = try encoder.encode(values)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SupabaseError.invalidResponse
        }
        
        if httpResponse.statusCode >= 400 {
            let errorText = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw SupabaseError.apiError(errorText)
        }
        
        if returning && !data.isEmpty {
            return try decoder.decode(R.self, from: data)
        }
        
        return nil
    }
    
    /// Delete from a table
    func delete(
        from table: String,
        filter: [String: Any]
    ) async throws {
        var components = URLComponents(url: baseURL.appendingPathComponent("rest/v1/\(table)"), resolvingAgainstBaseURL: false)!
        
        var queryItems: [URLQueryItem] = []
        for (key, value) in filter {
            queryItems.append(URLQueryItem(name: key, value: "eq.\(value)"))
        }
        components.queryItems = queryItems
        
        var request = URLRequest(url: components.url!)
        request.httpMethod = "DELETE"
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        
        if let token = authToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SupabaseError.invalidResponse
        }
        
        if httpResponse.statusCode >= 400 {
            let errorText = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw SupabaseError.apiError(errorText)
        }
    }
    
    // MARK: - Batch Operations
    
    /// Insert multiple rows
    func insertBatch<T: Codable>(
        into table: String,
        values: [T]
    ) async throws {
        let url = baseURL.appendingPathComponent("rest/v1/\(table)")
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        
        if let token = authToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        
        request.httpBody = try encoder.encode(values)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SupabaseError.invalidResponse
        }
        
        if httpResponse.statusCode >= 400 {
            let errorText = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw SupabaseError.apiError(errorText)
        }
    }
}

// MARK: - Errors

enum SupabaseError: LocalizedError {
    case invalidResponse
    case httpError(Int)
    case authError(String)
    case apiError(String)
    case notAuthenticated
    
    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from server"
        case .httpError(let code):
            return "HTTP error: \(code)"
        case .authError(let message):
            return "Authentication error: \(message)"
        case .apiError(let message):
            return "API error: \(message)"
        case .notAuthenticated:
            return "Not authenticated"
        }
    }
}
