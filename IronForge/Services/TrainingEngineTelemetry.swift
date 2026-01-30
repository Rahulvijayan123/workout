// TrainingEngineTelemetry.swift
// Configures TrainingEngine ML data logging and bandit learning updates.

import Foundation
import TrainingEngine

/// Configures TrainingEngine telemetry for ML data collection and bandit learning.
///
/// This class bridges:
/// 1. TrainingEngine decision logging → PolicySelectionSnapshotStore (for UI model construction)
/// 2. TrainingEngine outcome logging → PolicySelector.recordOutcome (for bandit learning)
///
/// Usage:
/// ```swift
/// // At app startup (composition root)
/// TrainingEngineTelemetry.configure(policySelector: mySelector)
/// ```
public enum TrainingEngineTelemetry {
    
    /// Whether telemetry has been configured.
    private static var isConfigured = false
    
    /// The policy selector to call for outcome recording.
    /// Note: nonisolated(unsafe) because this is accessed from TrainingEngine callbacks
    /// which may run on different threads.
    nonisolated(unsafe) private static var policySelector: (any ProgressionPolicySelector)?
    
    /// Configures TrainingEngine logging and learning updates.
    ///
    /// Call this once at app startup (in the composition root) with the policy selector
    /// that should receive outcome updates for bandit learning.
    ///
    /// - Parameter policySelector: The policy selector to call for outcome recording.
    public static func configure(policySelector: any ProgressionPolicySelector) {
        guard !isConfigured else {
            print("[TrainingEngineTelemetry] Already configured, skipping.")
            return
        }
        
        self.policySelector = policySelector
        
        // Enable TrainingEngine ML data logging
        TrainingEngine.Engine.setLoggingEnabled(true)
        
        // Install the log handler
        TrainingEngine.Engine.setLogHandler { entry in
            handleLogEntry(entry)
        }
        
        isConfigured = true
        print("[TrainingEngineTelemetry] Configured with logging enabled.")
        
        // Best-effort: if the user is already authenticated (stored auth), flush any queued logs.
        flushQueuedPolicyDecisionLogs()
    }
    
    /// Handles a decision log entry from TrainingEngine.
    ///
    /// This is called for:
    /// 1. New decisions (when a session plan is generated) - entry.outcome is nil
    /// 2. Updated decisions (when outcome is recorded) - entry.outcome is non-nil
    private static func handleLogEntry(_ entry: DecisionLogEntry) {
        // Always store the policy selection snapshot for UI model construction
        PolicySelectionSnapshotStore.shared.upsert(entry: entry)
        
        // Persist decision-level log (features/action/propensity/context) for offline evaluation.
        // This is intentionally decoupled from session sync so we don't have to reconstruct
        // attribution later from inferred state.
        Task { @MainActor in
            // IMPORTANT: do not drop telemetry just because auth isn't present yet.
            // Buffer locally and flush on login.
            let decidedAt: Date = entry.timestamp
            let outcomeRecordedAt: Date? = entry.outcome != nil ? Date() : nil
            
            let outcomeContextTag: String? = entry.outcome.map { outcome in
                executionContextTag(outcome.executionContext)
            }
            
            // userId is overwritten by DataSyncService.syncPolicyDecisionLog() when authenticated.
            // We still provide a placeholder to satisfy the non-optional field.
            let row = DataSyncService.DBPolicyDecisionLog(
                id: entry.id.uuidString,
                userId: "pending_auth",
                stableUserId: entry.userId,
                sessionId: entry.sessionId.uuidString,
                exerciseId: entry.exerciseId,
                familyReferenceKey: entry.variationContext.familyReferenceKey,
                executedPolicyId: entry.executedPolicyId,
                executedActionProbability: entry.executedActionProbability,
                explorationMode: entry.explorationMode,
                shadowPolicyId: entry.shadowPolicyId,
                shadowActionProbability: entry.shadowActionProbability,
                decidedAt: decidedAt,
                outcomeWasSuccess: entry.outcome?.wasSuccess,
                outcomeWasGrinder: entry.outcome?.wasGrinder,
                outcomeExecutionContext: outcomeContextTag,
                outcomeRecordedAt: outcomeRecordedAt
            )
            
            do {
                guard SupabaseService.shared.isAuthenticated else {
                    PolicyDecisionLogQueue.enqueue(row)
                    return
                }
                try await DataSyncService.shared.syncPolicyDecisionLog(row)
            } catch {
                // Best-effort: do not block planning/execution on telemetry failures.
                print("[TrainingEngineTelemetry] Failed to sync policy decision log: \(error)")
                DataSyncService.shared.syncError = error
                PolicyDecisionLogQueue.enqueue(row)
            }
        }
        
        // If outcome is present, this is an outcome update - trigger bandit learning
        if entry.outcome != nil {
            policySelector?.recordOutcome(entry, userId: entry.userId)
        }
    }
    
    private static func executionContextTag(_ ctx: TrainingEngine.ExecutionContext) -> String {
        switch ctx {
        case .normal:
            return "normal"
        case .equipmentIssue:
            return "equipment_issue"
        case .timeConstraint:
            return "time_constraint"
        case .injuryDiscomfort:
            return "injury_discomfort"
        case .intentionalChange:
            return "intentional_change"
        case .environmental:
            return "environmental"
        @unknown default:
            return String(describing: ctx)
        }
    }
    
    /// Flushes any queued policy decision logs if the user is authenticated.
    ///
    /// This is safe to call repeatedly; it no-ops when not authenticated.
    public static func flushQueuedPolicyDecisionLogs() {
        Task { @MainActor in
            guard SupabaseService.shared.isAuthenticated else { return }
            
            let queued = PolicyDecisionLogQueue.all()
            guard !queued.isEmpty else { return }
            
            var succeeded = Set<String>()
            for row in queued {
                guard let id = row.id else { continue }
                do {
                    try await DataSyncService.shared.syncPolicyDecisionLog(row)
                    succeeded.insert(id)
                } catch {
                    // Stop early on errors to avoid hammering.
                    print("[TrainingEngineTelemetry] Flush failed (will retry later): \(error)")
                    break
                }
            }
            
            if !succeeded.isEmpty {
                PolicyDecisionLogQueue.remove(ids: succeeded)
            }
        }
    }
    
    /// Resets telemetry configuration (for testing).
    public static func reset() {
        isConfigured = false
        policySelector = nil
        TrainingEngine.Engine.setLoggingEnabled(false)
    }
}

// MARK: - Local queue (unauthenticated telemetry buffering)

/// Local persistence queue for policy decision logs.
///
/// Why this exists:
/// - `TrainingEngineTelemetry` emits decision logs even when the user is not authenticated.
/// - `DataSyncService.syncPolicyDecisionLog` requires auth, so we buffer locally and flush on login.
///
/// Storage:
/// - UserDefaults-backed ring buffer keyed by log id (dedup) + ordered ids for bounded size.
private enum PolicyDecisionLogQueue {
    private static let lock = NSLock()
    private static let storageKey = "ironforge.telemetry.policy_decision_logs.queue.v1"
    private static let maxItems = 5_000
    
    private struct QueueState: Codable {
        var orderedIds: [String]
        var itemsById: [String: DataSyncService.DBPolicyDecisionLog]
        
        init(orderedIds: [String] = [], itemsById: [String: DataSyncService.DBPolicyDecisionLog] = [:]) {
            self.orderedIds = orderedIds
            self.itemsById = itemsById
        }
    }
    
    private static func encoder() -> JSONEncoder {
        let enc = JSONEncoder()
        enc.keyEncodingStrategy = .convertToSnakeCase
        enc.dateEncodingStrategy = .iso8601
        return enc
    }
    
    private static func decoder() -> JSONDecoder {
        let dec = JSONDecoder()
        dec.keyDecodingStrategy = .convertFromSnakeCase
        dec.dateDecodingStrategy = .iso8601
        return dec
    }
    
    private static func loadStateUnsafe() -> QueueState {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else {
            return QueueState()
        }
        return (try? decoder().decode(QueueState.self, from: data)) ?? QueueState()
    }
    
    private static func saveStateUnsafe(_ state: QueueState) {
        guard let data = try? encoder().encode(state) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
    
    static func enqueue(_ log: DataSyncService.DBPolicyDecisionLog) {
        guard let id = log.id, !id.isEmpty else { return }
        
        lock.lock()
        var state = loadStateUnsafe()
        
        // Upsert row by id.
        state.itemsById[id] = log
        
        // Maintain recency ordering (move id to the end).
        if let idx = state.orderedIds.firstIndex(of: id) {
            state.orderedIds.remove(at: idx)
        }
        state.orderedIds.append(id)
        
        // Enforce max size (drop oldest).
        while state.orderedIds.count > maxItems {
            let dropId = state.orderedIds.removeFirst()
            state.itemsById.removeValue(forKey: dropId)
        }
        
        saveStateUnsafe(state)
        lock.unlock()
    }
    
    static func all() -> [DataSyncService.DBPolicyDecisionLog] {
        lock.lock()
        let state = loadStateUnsafe()
        lock.unlock()
        return state.orderedIds.compactMap { state.itemsById[$0] }
    }
    
    static func remove(ids: Set<String>) {
        guard !ids.isEmpty else { return }
        
        lock.lock()
        var state = loadStateUnsafe()
        state.orderedIds.removeAll { ids.contains($0) }
        for id in ids {
            state.itemsById.removeValue(forKey: id)
        }
        saveStateUnsafe(state)
        lock.unlock()
    }
}

