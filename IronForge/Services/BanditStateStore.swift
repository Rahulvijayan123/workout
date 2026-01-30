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
