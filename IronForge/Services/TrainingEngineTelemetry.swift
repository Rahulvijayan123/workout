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
            guard SupabaseService.shared.isAuthenticated,
                  let authUserId = SupabaseService.shared.currentUserId else {
                return
            }
            
            let decidedAt: Date? = entry.outcome == nil ? Date() : nil
            let outcomeRecordedAt: Date? = entry.outcome != nil ? Date() : nil
            
            let outcomeContextTag: String? = entry.outcome.map { outcome in
                executionContextTag(outcome.executionContext)
            }
            
            let row = DataSyncService.DBPolicyDecisionLog(
                id: entry.id.uuidString,
                userId: authUserId,
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
                try await DataSyncService.shared.syncPolicyDecisionLog(row)
            } catch {
                // Best-effort: do not block planning/execution on telemetry failures.
                print("[TrainingEngineTelemetry] Failed to sync policy decision log: \(error)")
                DataSyncService.shared.syncError = error
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
        case .injuryDiscomfort:
            return "injury_discomfort"
        @unknown default:
            return String(describing: ctx)
        }
    }
    
    /// Resets telemetry configuration (for testing).
    public static func reset() {
        isConfigured = false
        policySelector = nil
        TrainingEngine.Engine.setLoggingEnabled(false)
    }
}
