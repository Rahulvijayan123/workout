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
        // Allow updating the selector reference even after initial configuration.
        // This prevents subtle bugs where planning uses a new selector instance (mode switch),
        // but telemetry still records outcomes into an old instance.
        if isConfigured {
            self.policySelector = policySelector
            print("[TrainingEngineTelemetry] Already configured; updated policy selector reference.")
            flushQueuedPolicyDecisionLogs()
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
        //
        // IMPORTANT:
        // - Never run network sync on the MainActor.
        // - Queue writes must be synchronous and immediate so we don't lose telemetry if the app
        //   backgrounds/terminates before async work runs.
        //
        // The flush happens asynchronously on a dedicated serial actor.
        let row = PolicyDecisionLogRow.from(entry: entry)
        PolicyDecisionLogQueue.enqueue(row)
        flushQueuedPolicyDecisionLogs()
        
        // If outcome is present, this is an outcome update - trigger bandit learning
        if entry.outcome != nil {
            policySelector?.recordOutcome(entry, userId: entry.userId)
        }
    }
    
    fileprivate static func executionContextTag(_ ctx: TrainingEngine.ExecutionContext) -> String {
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
        Task.detached(priority: .utility) {
            await PolicyDecisionLogFlushWorker.shared.requestFlush()
        }
    }
    
    /// Resets telemetry configuration (for testing).
    public static func reset() {
        isConfigured = false
        policySelector = nil
        TrainingEngine.Engine.setLoggingEnabled(false)
    }
}

// MARK: - Policy decision log telemetry (durable queue + background uploader)

private struct PolicyDecisionLogRow: Codable, Hashable, Sendable {
    var id: String
    var userId: String
    var stableUserId: String
    
    var sessionId: String
    var exerciseId: String
    var familyReferenceKey: String?
    
    var executedPolicyId: String
    var executedActionProbability: Double
    var explorationMode: String?
    var shadowPolicyId: String?
    var shadowActionProbability: Double?
    
    var decidedAt: Date
    
    var outcomeWasSuccess: Bool?
    var outcomeWasGrinder: Bool?
    var outcomeExecutionContext: String?
    var outcomeRecordedAt: Date?
    
    static func from(entry: DecisionLogEntry) -> PolicyDecisionLogRow {
        let authUserId = SupabaseAuthSnapshot.current()?.userId
        
        let outcomeContextTag: String? = entry.outcome.map { outcome in
            TrainingEngineTelemetry.executionContextTag(outcome.executionContext)
        }
        
        return PolicyDecisionLogRow(
            id: entry.id.uuidString,
            userId: authUserId ?? SupabaseAuthSnapshot.placeholderUserId,
            stableUserId: entry.userId,
            sessionId: entry.sessionId.uuidString,
            exerciseId: entry.exerciseId,
            familyReferenceKey: entry.variationContext.familyReferenceKey,
            executedPolicyId: entry.executedPolicyId,
            executedActionProbability: entry.executedActionProbability,
            explorationMode: entry.explorationMode,
            shadowPolicyId: entry.shadowPolicyId,
            shadowActionProbability: entry.shadowActionProbability,
            decidedAt: entry.timestamp,
            outcomeWasSuccess: entry.outcome?.wasSuccess,
            outcomeWasGrinder: entry.outcome?.wasGrinder,
            outcomeExecutionContext: outcomeContextTag,
            outcomeRecordedAt: entry.outcome != nil ? Date() : nil
        )
    }
}

private struct SupabaseAuthSnapshot: Sendable {
    static let placeholderUserId = "pending_auth"
    
    let token: String
    let userId: String
    
    static func current() -> SupabaseAuthSnapshot? {
        guard let token = UserDefaults.standard.string(forKey: "supabase.authToken"),
              let userId = UserDefaults.standard.string(forKey: "supabase.userId"),
              !token.isEmpty, !userId.isEmpty
        else {
            return nil
        }
        return SupabaseAuthSnapshot(token: token, userId: userId)
    }
}

/// Durable local queue for policy decision logs (bounded ring buffer).
///
/// Storage approach:
/// - Store an ordered list of ids (UserDefaults string array)
/// - Store each row payload as `Data` under its own key
///
/// This avoids re-encoding the entire queue blob on each enqueue (important if a log burst happens).
private enum PolicyDecisionLogQueue {
    private static let lock = NSLock()
    
    private static let idsKey = "ironforge.telemetry.policy_decision_logs.queue.v2.ids"
    private static let itemKeyPrefix = "ironforge.telemetry.policy_decision_logs.queue.v2.item."
    private static let maxItems = 5_000
    
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
    
    static func enqueue(_ row: PolicyDecisionLogRow) {
        guard !row.id.isEmpty else { return }
        
        lock.lock()
        defer { lock.unlock() }
        
        // Persist row payload.
        if let data = try? encoder().encode(row) {
            UserDefaults.standard.set(data, forKey: itemKeyPrefix + row.id)
        } else {
            return
        }
        
        // Update ordered ids (oldest → newest).
        var orderedIds = UserDefaults.standard.stringArray(forKey: idsKey) ?? []
        if let idx = orderedIds.firstIndex(of: row.id) {
            orderedIds.remove(at: idx)
        }
        orderedIds.append(row.id)
        
        // Enforce max size (drop oldest).
        while orderedIds.count > maxItems {
            let dropId = orderedIds.removeFirst()
            UserDefaults.standard.removeObject(forKey: itemKeyPrefix + dropId)
        }
        
        UserDefaults.standard.set(orderedIds, forKey: idsKey)
    }
    
    static func all() -> [PolicyDecisionLogRow] {
        lock.lock()
        let orderedIds = UserDefaults.standard.stringArray(forKey: idsKey) ?? []
        lock.unlock()
        
        guard !orderedIds.isEmpty else { return [] }
        
        var rows: [PolicyDecisionLogRow] = []
        rows.reserveCapacity(orderedIds.count)
        
        let dec = decoder()
        for id in orderedIds {
            guard let data = UserDefaults.standard.data(forKey: itemKeyPrefix + id),
                  let row = try? dec.decode(PolicyDecisionLogRow.self, from: data)
            else {
                continue
            }
            rows.append(row)
        }
        
        return rows
    }
    
    static func remove(ids: Set<String>) {
        guard !ids.isEmpty else { return }
        
        lock.lock()
        defer { lock.unlock() }
        
        var orderedIds = UserDefaults.standard.stringArray(forKey: idsKey) ?? []
        orderedIds.removeAll { ids.contains($0) }
        
        for id in ids {
            UserDefaults.standard.removeObject(forKey: itemKeyPrefix + id)
        }
        
        UserDefaults.standard.set(orderedIds, forKey: idsKey)
    }

    /// Removes a queued row **only if** it still matches the expected payload.
    ///
    /// This prevents a race where a row is updated (e.g., outcome attached) while a flush is in-flight:
    /// the flusher may successfully upload the older version, but must not delete the newer payload.
    static func removeIfUnchanged(id: String, expected: PolicyDecisionLogRow) {
        guard !id.isEmpty else { return }

        lock.lock()
        defer { lock.unlock() }

        let key = itemKeyPrefix + id
        guard let data = UserDefaults.standard.data(forKey: key),
              let current = try? decoder().decode(PolicyDecisionLogRow.self, from: data),
              current == expected
        else {
            return
        }

        var orderedIds = UserDefaults.standard.stringArray(forKey: idsKey) ?? []
        orderedIds.removeAll { $0 == id }
        UserDefaults.standard.removeObject(forKey: key)
        UserDefaults.standard.set(orderedIds, forKey: idsKey)
    }
}

private enum PolicyDecisionLogUploader {
    struct UploadError: Error, CustomStringConvertible {
        let description: String
    }
    
    static func upsert(_ row: PolicyDecisionLogRow, auth: SupabaseAuthSnapshot) async throws {
        guard SupabaseConfig.isConfigured else {
            throw UploadError(description: "Supabase config missing/invalid")
        }
        guard let baseURL = URL(string: SupabaseConfig.url) else {
            throw UploadError(description: "Invalid Supabase URL")
        }
        
        var components = URLComponents(
            url: baseURL.appendingPathComponent("rest/v1/policy_decision_logs"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [
            URLQueryItem(name: "on_conflict", value: "id")
        ]
        
        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(auth.token)", forHTTPHeaderField: "Authorization")
        request.setValue("resolution=merge-duplicates", forHTTPHeaderField: "Prefer")
        
        let enc = JSONEncoder()
        enc.keyEncodingStrategy = .convertToSnakeCase
        enc.dateEncodingStrategy = .iso8601
        request.httpBody = try enc.encode(row)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw UploadError(description: "Invalid HTTP response")
        }
        if http.statusCode >= 400 {
            let body = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw UploadError(description: "HTTP \(http.statusCode): \(body)")
        }
    }
}

private actor PolicyDecisionLogFlushWorker {
    static let shared = PolicyDecisionLogFlushWorker()
    
    private var isFlushing = false
    private var needsFlush = false
    
    func requestFlush() async {
        // Coalesce flush requests; if a flush is already in-flight, ensure we run at least one
        // additional pass afterwards to pick up rows enqueued during the flush.
        needsFlush = true
        guard !isFlushing else { return }

        isFlushing = true
        defer { isFlushing = false }

        while needsFlush {
            needsFlush = false
            await flushOnce()
        }
    }
    
    private func flushOnce() async {
        guard let auth = SupabaseAuthSnapshot.current() else { return }
        guard SupabaseConfig.isConfigured else { return }
        
        let queued = PolicyDecisionLogQueue.all()
        guard !queued.isEmpty else { return }
        
        for row in queued {
            var toSend = row
            
            // If we queued before auth was available, attribute to the current auth user.
            if toSend.userId == SupabaseAuthSnapshot.placeholderUserId {
                toSend.userId = auth.userId
            } else if toSend.userId != auth.userId {
                // Avoid mis-attribution if multiple accounts are used on the same device.
                // Keep the row queued until the matching user logs in again.
                continue
            }
            
            do {
                try await PolicyDecisionLogUploader.upsert(toSend, auth: auth)
                // Only delete the queued payload if it hasn't changed since we read it.
                // If an updated version (e.g., with outcome) was enqueued mid-flush, keep it.
                PolicyDecisionLogQueue.removeIfUnchanged(id: row.id, expected: row)
            } catch {
                // Stop early to avoid hammering; we'll retry later.
                print("[TrainingEngineTelemetry] Flush failed (will retry later): \(error)")
                break
            }
        }
    }
}

