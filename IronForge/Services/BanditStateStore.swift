// BanditStateStore.swift
// UserDefaults-backed persistence for bandit state (Beta priors).
//
// Keys are stored as: "bandit_prior_{userId}_{familyKey}_{armId}"

import Foundation

/// Protocol for bandit state storage.
public protocol BanditStateStore: AnyObject, Sendable {
    /// Gets the Beta priors for all arms for a given user and family.
    ///
    /// - Parameters:
    ///   - userId: The user ID.
    ///   - familyKey: The exercise family reference key.
    ///   - armIds: The IDs of arms to retrieve priors for.
    /// - Returns: Dictionary mapping arm ID to Beta prior (defaults to uniform prior if not found).
    func getPriors(userId: String, familyKey: String, armIds: [String]) -> [String: BetaPrior]
    
    /// Gets the Beta prior for a specific arm.
    ///
    /// - Parameters:
    ///   - userId: The user ID.
    ///   - familyKey: The exercise family reference key.
    ///   - armId: The arm ID.
    /// - Returns: The Beta prior (defaults to uniform prior if not found).
    func getPrior(userId: String, familyKey: String, armId: String) -> BetaPrior
    
    /// Updates the Beta prior for a specific arm with a reward observation.
    ///
    /// - Parameters:
    ///   - userId: The user ID.
    ///   - familyKey: The exercise family reference key.
    ///   - armId: The arm ID.
    ///   - reward: The reward value (0 or 1).
    func updatePrior(userId: String, familyKey: String, armId: String, reward: Double)
    
    /// Sets the Beta prior for a specific arm directly.
    ///
    /// - Parameters:
    ///   - userId: The user ID.
    ///   - familyKey: The exercise family reference key.
    ///   - armId: The arm ID.
    ///   - prior: The Beta prior to set.
    func setPrior(userId: String, familyKey: String, armId: String, prior: BetaPrior)
    
    /// Resets priors for a specific user and family.
    ///
    /// - Parameters:
    ///   - userId: The user ID.
    ///   - familyKey: The exercise family reference key.
    func reset(userId: String, familyKey: String)
    
    /// Resets all priors for a user.
    ///
    /// - Parameter userId: The user ID.
    func resetAll(userId: String)
    
    /// Resets all priors for all users.
    func resetAll()
}

/// UserDefaults-backed bandit state store.
public final class UserDefaultsBanditStateStore: BanditStateStore, @unchecked Sendable {
    
    /// Shared singleton instance.
    public static let shared = UserDefaultsBanditStateStore()
    
    /// UserDefaults instance to use.
    private let defaults: UserDefaults
    
    /// Key prefix for bandit priors.
    private let keyPrefix: String
    
    /// Lock for thread safety.
    private let lock = NSLock()
    
    /// Creates a UserDefaults-backed bandit state store.
    ///
    /// - Parameters:
    ///   - defaults: The UserDefaults instance to use (default: standard).
    ///   - keyPrefix: Prefix for UserDefaults keys (default: "bandit_prior").
    public init(defaults: UserDefaults = .standard, keyPrefix: String = "bandit_prior") {
        self.defaults = defaults
        self.keyPrefix = keyPrefix
    }
    
    // MARK: - BanditStateStore
    
    public func getPriors(userId: String, familyKey: String, armIds: [String]) -> [String: BetaPrior] {
        var priors: [String: BetaPrior] = [:]
        
        for armId in armIds {
            priors[armId] = getPrior(userId: userId, familyKey: familyKey, armId: armId)
        }
        
        return priors
    }
    
    public func getPrior(userId: String, familyKey: String, armId: String) -> BetaPrior {
        let key = makeKey(userId: userId, familyKey: familyKey, armId: armId)
        
        lock.lock()
        defer { lock.unlock() }
        
        guard let data = defaults.data(forKey: key),
              let prior = try? JSONDecoder().decode(BetaPrior.self, from: data) else {
            return BetaPrior() // Default uniform prior
        }
        
        return prior
    }
    
    public func updatePrior(userId: String, familyKey: String, armId: String, reward: Double) {
        let key = makeKey(userId: userId, familyKey: familyKey, armId: armId)
        
        lock.lock()
        defer { lock.unlock() }
        
        var prior = loadPriorUnsafe(key: key)
        prior.update(reward: reward)
        savePriorUnsafe(key: key, prior: prior)
    }
    
    public func setPrior(userId: String, familyKey: String, armId: String, prior: BetaPrior) {
        let key = makeKey(userId: userId, familyKey: familyKey, armId: armId)
        
        lock.lock()
        defer { lock.unlock() }
        
        savePriorUnsafe(key: key, prior: prior)
    }
    
    public func reset(userId: String, familyKey: String) {
        lock.lock()
        defer { lock.unlock() }
        
        let prefix = "\(keyPrefix)_\(sanitize(userId))_\(sanitize(familyKey))_"
        
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(prefix) {
            defaults.removeObject(forKey: key)
        }
    }
    
    public func resetAll(userId: String) {
        lock.lock()
        defer { lock.unlock() }
        
        let prefix = "\(keyPrefix)_\(sanitize(userId))_"
        
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(prefix) {
            defaults.removeObject(forKey: key)
        }
    }
    
    public func resetAll() {
        lock.lock()
        defer { lock.unlock() }
        
        let prefix = "\(keyPrefix)_"
        
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(prefix) {
            defaults.removeObject(forKey: key)
        }
    }

    // MARK: - Schema / Versioning
    
    /// Ensures persisted priors are compatible with the current bandit schema.
    ///
    /// If the schema version or arm signature changes, all priors are reset to avoid silently
    /// mixing incompatible arm definitions (which would corrupt learning).
    public func ensureSchema(version: Int, armIds: [String]) {
        lock.lock()
        defer { lock.unlock() }
        
        let versionKey = "\(keyPrefix).schema_version"
        let signatureKey = "\(keyPrefix).arms_signature"
        
        let currentSignature = armIds.sorted().joined(separator: "|")
        let existingVersion = defaults.integer(forKey: versionKey)
        let existingSignature = defaults.string(forKey: signatureKey)
        
        guard existingVersion == version, existingSignature == currentSignature else {
            // Reset ALL priors (all users) because arm identities changed.
            let priorPrefix = "\(keyPrefix)_"
            for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(priorPrefix) {
                defaults.removeObject(forKey: key)
            }
            
            defaults.set(version, forKey: versionKey)
            defaults.set(currentSignature, forKey: signatureKey)
            return
        }
    }
    
    // MARK: - Identity Migration (local → auth)
    
    /// Migrate bandit priors from one userId namespace to another.
    ///
    /// This is used when a user logs in: we move/merge priors accrued under the
    /// offline local user id into the Supabase auth user id, so learning continues
    /// seamlessly after authentication.
    ///
    /// - Parameters:
    ///   - from: Source user id (typically local UUID).
    ///   - to: Target user id (typically Supabase auth id).
    ///   - deleteSource: If true, remove source priors after migration to avoid double-counting on future merges.
    public func migrateUserId(from: String, to: String, deleteSource: Bool) {
        lock.lock()
        defer { lock.unlock() }
        
        let sourcePrefix = "\(keyPrefix)_\(sanitize(from))_"
        let targetPrefix = "\(keyPrefix)_\(sanitize(to))_"
        
        let keys = defaults.dictionaryRepresentation().keys.filter { $0.hasPrefix(sourcePrefix) }
        guard !keys.isEmpty else { return }
        
        for key in keys {
            let suffix = String(key.dropFirst(sourcePrefix.count))
            let targetKey = targetPrefix + suffix
            
            let sourcePrior = loadPriorUnsafe(key: key)
            let existingTargetPrior: BetaPrior? = defaults.data(forKey: targetKey).flatMap { data in
                try? JSONDecoder().decode(BetaPrior.self, from: data)
            }
            
            let merged: BetaPrior = {
                guard let existingTargetPrior else { return sourcePrior }
                
                // Combine posteriors without double-counting the (1,1) prior:
                // Beta(a1,b1) ⊕ Beta(a2,b2) = Beta(a1+a2-1, b1+b2-1)
                return BetaPrior(
                    alpha: max(1.0, sourcePrior.alpha + existingTargetPrior.alpha - 1.0),
                    beta: max(1.0, sourcePrior.beta + existingTargetPrior.beta - 1.0)
                )
            }()
            
            savePriorUnsafe(key: targetKey, prior: merged)
            
            if deleteSource {
                defaults.removeObject(forKey: key)
            }
        }
    }
    
    // MARK: - Helpers
    
    private func makeKey(userId: String, familyKey: String, armId: String) -> String {
        "\(keyPrefix)_\(sanitize(userId))_\(sanitize(familyKey))_\(sanitize(armId))"
    }
    
    private func sanitize(_ string: String) -> String {
        // Replace characters that might cause issues in UserDefaults keys
        string
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ".", with: "_")
            .replacingOccurrences(of: " ", with: "_")
    }
    
    /// Loads prior without lock (caller must hold lock).
    private func loadPriorUnsafe(key: String) -> BetaPrior {
        guard let data = defaults.data(forKey: key),
              let prior = try? JSONDecoder().decode(BetaPrior.self, from: data) else {
            return BetaPrior()
        }
        return prior
    }
    
    /// Saves prior without lock (caller must hold lock).
    private func savePriorUnsafe(key: String, prior: BetaPrior) {
        if let data = try? JSONEncoder().encode(prior) {
            defaults.set(data, forKey: key)
        }
    }
}

// MARK: - In-Memory Store (for Testing)

/// In-memory bandit state store (for testing).
public final class InMemoryBanditStateStore: BanditStateStore, @unchecked Sendable {
    
    private var priors: [String: BetaPrior] = [:]
    private let lock = NSLock()
    
    public init() {}
    
    public func getPriors(userId: String, familyKey: String, armIds: [String]) -> [String: BetaPrior] {
        var result: [String: BetaPrior] = [:]
        for armId in armIds {
            result[armId] = getPrior(userId: userId, familyKey: familyKey, armId: armId)
        }
        return result
    }
    
    public func getPrior(userId: String, familyKey: String, armId: String) -> BetaPrior {
        let key = makeKey(userId: userId, familyKey: familyKey, armId: armId)
        lock.lock()
        defer { lock.unlock() }
        return priors[key] ?? BetaPrior()
    }
    
    public func updatePrior(userId: String, familyKey: String, armId: String, reward: Double) {
        let key = makeKey(userId: userId, familyKey: familyKey, armId: armId)
        lock.lock()
        defer { lock.unlock() }
        var prior = priors[key] ?? BetaPrior()
        prior.update(reward: reward)
        priors[key] = prior
    }
    
    public func setPrior(userId: String, familyKey: String, armId: String, prior: BetaPrior) {
        let key = makeKey(userId: userId, familyKey: familyKey, armId: armId)
        lock.lock()
        defer { lock.unlock() }
        priors[key] = prior
    }
    
    public func reset(userId: String, familyKey: String) {
        let prefix = makeKey(userId: userId, familyKey: familyKey, armId: "")
        lock.lock()
        defer { lock.unlock() }
        priors = priors.filter { !$0.key.hasPrefix(prefix) }
    }
    
    public func resetAll(userId: String) {
        let prefix = "\(userId)_"
        lock.lock()
        defer { lock.unlock() }
        priors = priors.filter { !$0.key.hasPrefix(prefix) }
    }
    
    public func resetAll() {
        lock.lock()
        defer { lock.unlock() }
        priors = [:]
    }
    
    private func makeKey(userId: String, familyKey: String, armId: String) -> String {
        "\(userId)_\(familyKey)_\(armId)"
    }
    
    /// Returns all stored priors (for debugging/testing).
    public func allPriors() -> [String: BetaPrior] {
        lock.lock()
        defer { lock.unlock() }
        return priors
    }
}
