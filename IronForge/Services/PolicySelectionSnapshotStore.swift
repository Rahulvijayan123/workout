// PolicySelectionSnapshotStore.swift
// Thread-safe store for policy selection snapshots keyed by (sessionId, exerciseId).
//
// Used to bridge between TrainingEngine decision logging and UI model construction.

import Foundation
import TrainingEngine

/// Thread-safe store for policy selection snapshots.
///
/// The TrainingEngine logs decisions as they're computed, but the UI model is constructed
/// separately. This store bridges the two by caching policy selection data so it can be
/// attached to `ExercisePerformance.policySelectionSnapshot` during `convertSessionPlanToUIModel`.
public final class PolicySelectionSnapshotStore: @unchecked Sendable {
    
    /// Shared singleton instance.
    public static let shared = PolicySelectionSnapshotStore()
    
    /// Composite key for snapshot lookup.
    private struct SnapshotKey: Hashable {
        let sessionId: UUID
        let exerciseId: String
    }
    
    /// In-memory cache of policy selection snapshots.
    private var snapshots: [SnapshotKey: PolicySelectionSnapshot] = [:]
    
    /// Lock for thread safety.
    private let lock = NSLock()
    
    private init() {}
    
    // MARK: - Public API
    
    /// Upserts a policy selection snapshot from a DecisionLogEntry.
    ///
    /// - Parameter entry: The decision log entry containing policy selection data.
    public func upsert(entry: DecisionLogEntry) {
        let key = SnapshotKey(sessionId: entry.sessionId, exerciseId: entry.exerciseId)
        
        let snapshot = PolicySelectionSnapshot(
            executedPolicyId: entry.executedPolicyId,
            executedActionProbability: entry.executedActionProbability,
            explorationMode: entry.explorationMode,
            shadowPolicyId: entry.shadowPolicyId,
            shadowActionProbability: entry.shadowActionProbability
        )
        
        lock.lock()
        defer { lock.unlock() }
        snapshots[key] = snapshot
    }
    
    /// Retrieves a policy selection snapshot for a given session and exercise.
    ///
    /// - Parameters:
    ///   - sessionId: The session ID.
    ///   - exerciseId: The exercise ID.
    /// - Returns: The cached snapshot, or nil if not found.
    public func snapshot(sessionId: UUID, exerciseId: String) -> PolicySelectionSnapshot? {
        let key = SnapshotKey(sessionId: sessionId, exerciseId: exerciseId)
        
        lock.lock()
        defer { lock.unlock() }
        return snapshots[key]
    }
    
    /// Removes all snapshots for a given session.
    ///
    /// Call this after the session is synced to Supabase to prevent memory growth.
    ///
    /// - Parameter sessionId: The session ID to remove.
    public func removeSession(_ sessionId: UUID) {
        lock.lock()
        defer { lock.unlock() }
        
        let keysToRemove = snapshots.keys.filter { $0.sessionId == sessionId }
        for key in keysToRemove {
            snapshots.removeValue(forKey: key)
        }
    }
    
    /// Clears all cached snapshots.
    ///
    /// Useful for testing or when resetting app state.
    public func clear() {
        lock.lock()
        defer { lock.unlock() }
        snapshots.removeAll()
    }
    
    /// Returns the number of cached snapshots (for debugging/testing).
    public var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return snapshots.count
    }
}
