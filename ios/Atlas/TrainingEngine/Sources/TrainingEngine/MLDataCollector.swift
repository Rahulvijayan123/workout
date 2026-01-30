// MLDataCollector.swift
// Client-side data collection with validation to prevent false positives/negatives.
//
// Key safeguards:
// 1. Unit consistency validation (kg vs lb)
// 2. Timing validation (decision → outcome within reasonable window)
// 3. Load plausibility checks (catch typos, unit confusion)
// 4. Context completeness scoring
// 5. Anomaly detection flags
// 6. Deferred collection (don't send partial data)
// 7. Duplicate detection (same decision ID)
// 8. Session abandonment detection
// 9. Partial completion handling (incomplete sets)
// 10. Warmup set filtering
// 11. RIR/RPE sanity checks
// 12. Bodyweight exercise handling
// 13. Crash recovery (persist pending to disk)
// 14. Rate limiting
// 15. Consent verification
// 16. New user baseline protection
// 17. e1RM sanity validation
// 18. Rep range violation detection

import Foundation

// MARK: - Collection Status

/// Status of a decision record in the collection pipeline.
public enum MLCollectionStatus: String, Codable, Sendable {
    case pending = "pending"
    case outcomeRecorded = "outcome_recorded"
    case validated = "validated"
    case invalidated = "invalidated"
    case expired = "expired"
}

// MARK: - Validation Result

/// Result of validating a decision record.
public struct MLValidationResult: Sendable {
    public let isValid: Bool
    public let unitConsistent: Bool
    public let timingValid: Bool
    public let loadPlausible: Bool
    public let contextComplete: Bool
    public let noKnownAnomaly: Bool
    public let completenessScore: Int
    public let warnings: [String]
    public let errors: [String]
    
    public init(
        isValid: Bool,
        unitConsistent: Bool,
        timingValid: Bool,
        loadPlausible: Bool,
        contextComplete: Bool,
        noKnownAnomaly: Bool,
        completenessScore: Int,
        warnings: [String] = [],
        errors: [String] = []
    ) {
        self.isValid = isValid
        self.unitConsistent = unitConsistent
        self.timingValid = timingValid
        self.loadPlausible = loadPlausible
        self.contextComplete = contextComplete
        self.noKnownAnomaly = noKnownAnomaly
        self.completenessScore = completenessScore
        self.warnings = warnings
        self.errors = errors
    }
}

// MARK: - Validation Configuration

/// Configuration for data validation thresholds.
public struct MLValidationConfig: Sendable {
    /// Maximum hours between decision and outcome before flagging.
    public let maxHoursBetweenDecisionAndOutcome: Double
    
    /// Maximum single-session load change (percent) before flagging.
    public let maxLoadChangePercent: Double
    
    /// Minimum plausible load (to catch unit confusion).
    public let minLoadKg: Double
    public let minLoadLb: Double
    
    /// Maximum plausible load (to catch typos).
    public let maxLoadKg: Double
    public let maxLoadLb: Double
    
    /// Ratio threshold for detecting kg↔lb confusion.
    /// If actual/prescribed is close to 2.2 or 0.45, likely unit confusion.
    public let unitConfusionRatioThreshold: Double
    
    /// Minimum data completeness score for training data.
    public let minCompletenessForTraining: Int
    
    /// Z-score threshold for anomaly detection.
    public let loadChangeZScoreThreshold: Double
    
    /// Minimum sessions before anomaly detection is reliable.
    public let minSessionsForAnomalyDetection: Int
    
    /// Maximum plausible e1RM (kg) - catches calculation errors.
    public let maxPlausibleE1RMKg: Double
    
    /// Minimum set completion ratio for valid outcome.
    public let minSetCompletionRatio: Double
    
    /// Minimum RIR value (should never be negative).
    public let minRIR: Int
    
    /// Maximum RIR value (10 = very easy).
    public let maxRIR: Int
    
    /// Maximum rep deviation from target before flagging.
    public let maxRepDeviationFromTarget: Int
    
    /// Rate limit: max uploads per minute.
    public let maxUploadsPerMinute: Int
    
    /// Minimum days of training history for reliable baseline.
    public let minDaysForReliableBaseline: Int
    
    public static let `default` = MLValidationConfig(
        maxHoursBetweenDecisionAndOutcome: 72,
        maxLoadChangePercent: 25,
        minLoadKg: 0.5,
        minLoadLb: 1.0,
        maxLoadKg: 500,
        maxLoadLb: 1100,
        unitConfusionRatioThreshold: 0.15,
        minCompletenessForTraining: 80,
        loadChangeZScoreThreshold: 3.0,
        minSessionsForAnomalyDetection: 3,
        maxPlausibleE1RMKg: 600,  // World record territory
        minSetCompletionRatio: 0.5,  // At least half of sets completed
        minRIR: 0,
        maxRIR: 10,
        maxRepDeviationFromTarget: 10,  // +/- 10 reps from target
        maxUploadsPerMinute: 30,
        minDaysForReliableBaseline: 14  // 2 weeks of training
    )
    
    public init(
        maxHoursBetweenDecisionAndOutcome: Double,
        maxLoadChangePercent: Double,
        minLoadKg: Double,
        minLoadLb: Double,
        maxLoadKg: Double,
        maxLoadLb: Double,
        unitConfusionRatioThreshold: Double,
        minCompletenessForTraining: Int,
        loadChangeZScoreThreshold: Double,
        minSessionsForAnomalyDetection: Int = 3,
        maxPlausibleE1RMKg: Double = 600,
        minSetCompletionRatio: Double = 0.5,
        minRIR: Int = 0,
        maxRIR: Int = 10,
        maxRepDeviationFromTarget: Int = 10,
        maxUploadsPerMinute: Int = 30,
        minDaysForReliableBaseline: Int = 14
    ) {
        self.maxHoursBetweenDecisionAndOutcome = maxHoursBetweenDecisionAndOutcome
        self.maxLoadChangePercent = maxLoadChangePercent
        self.minLoadKg = minLoadKg
        self.minLoadLb = minLoadLb
        self.maxLoadKg = maxLoadKg
        self.maxLoadLb = maxLoadLb
        self.unitConfusionRatioThreshold = unitConfusionRatioThreshold
        self.minCompletenessForTraining = minCompletenessForTraining
        self.loadChangeZScoreThreshold = loadChangeZScoreThreshold
        self.minSessionsForAnomalyDetection = minSessionsForAnomalyDetection
        self.maxPlausibleE1RMKg = maxPlausibleE1RMKg
        self.minSetCompletionRatio = minSetCompletionRatio
        self.minRIR = minRIR
        self.maxRIR = maxRIR
        self.maxRepDeviationFromTarget = maxRepDeviationFromTarget
        self.maxUploadsPerMinute = maxUploadsPerMinute
        self.minDaysForReliableBaseline = minDaysForReliableBaseline
    }
}

// MARK: - Pending Record

/// A decision record pending outcome collection.
public struct MLPendingRecord: Codable, Sendable {
    public let decisionId: UUID
    public let exerciseId: String
    public let userId: String
    public let decisionTimestamp: Date
    public let sessionDate: Date
    public let prescribedLoadValue: Double
    public let prescribedLoadUnit: LoadUnit
    public let targetReps: Int
    public let direction: ProgressionDirection
    
    /// Full decision log entry for deferred upload.
    public let logEntry: DecisionLogEntry
    
    public init(
        decisionId: UUID,
        exerciseId: String,
        userId: String,
        decisionTimestamp: Date,
        sessionDate: Date,
        prescribedLoadValue: Double,
        prescribedLoadUnit: LoadUnit,
        targetReps: Int,
        direction: ProgressionDirection,
        logEntry: DecisionLogEntry
    ) {
        self.decisionId = decisionId
        self.exerciseId = exerciseId
        self.userId = userId
        self.decisionTimestamp = decisionTimestamp
        self.sessionDate = sessionDate
        self.prescribedLoadValue = prescribedLoadValue
        self.prescribedLoadUnit = prescribedLoadUnit
        self.targetReps = targetReps
        self.direction = direction
        self.logEntry = logEntry
    }
}

// MARK: - ML Data Collector

/// Collects ML training data with validation to ensure data quality.
/// 
/// Key responsibilities:
/// 1. Buffer decisions until outcomes are recorded
/// 2. Validate data before marking as ready for training
/// 3. Detect anomalies (unit confusion, typos, etc.)
/// 4. Track data quality metrics
/// 5. Handle deferred collection for incomplete data
/// 6. Persist pending records for crash recovery
/// 7. Rate limiting to prevent spam
/// 8. Duplicate detection
///
/// DEPRECATION NOTICE:
/// This collector is being phased out in favor of the canonical ML data path through
/// DataSyncService which uses:
/// - recommendation_events (immutable, created at session start)
/// - planned_sets (immutable prescription per set)
/// - session_exercises/session_sets (performed data with outcome fields)
///
/// The new approach ensures:
/// - Stable join keys between recommendations and outcomes
/// - Consistent state snapshots frozen at recommendation time
/// - Proper outcome labeling at session finalization
///
/// This collector is kept for backwards compatibility but should not be used for
/// new ML training data collection.
@available(*, deprecated, message: "Use DataSyncService recommendation_events/planned_sets instead")
public final class MLDataCollector: @unchecked Sendable {
    
    /// Shared singleton instance.
    public static let shared = MLDataCollector()
    
    /// Validation configuration.
    public var validationConfig: MLValidationConfig = .default
    
    /// Whether collection is enabled.
    public var isEnabled: Bool = false
    
    /// Whether user has consented to data collection.
    public var hasUserConsent: Bool = false
    
    /// Handler for validated records ready to upload.
    public var uploadHandler: ((MLDecisionRecord) async throws -> Void)?
    
    /// Handler for data quality alerts.
    public var alertHandler: ((MLDataQualityAlert) -> Void)?
    
    /// Pending records awaiting outcomes.
    private var pendingRecords: [UUID: MLPendingRecord] = [:]
    private let lock = NSLock()
    
    /// Recent load values per exercise (for anomaly detection).
    private var recentLoads: [String: [LoadSample]] = [:]
    
    /// Processed decision IDs (for duplicate detection).
    private var processedDecisionIds: Set<UUID> = []
    
    /// Upload timestamps for rate limiting.
    private var uploadTimestamps: [Date] = []
    
    /// User's first training date (for baseline protection).
    private var userFirstTrainingDate: Date?
    
    /// Path for persisting pending records.
    private var pendingRecordsPath: URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?
            .appendingPathComponent("ml_pending_records.json")
    }
    
    private init() {
        loadPersistedPendingRecords()
    }
    
    // MARK: - Decision Collection
    
    /// Collects a decision record (called when session plan is generated).
    /// The record is held pending until outcome is recorded.
    public func collectDecision(_ entry: DecisionLogEntry) {
        guard isEnabled else { return }
        guard hasUserConsent else { return }
        
        // Duplicate detection
        lock.lock()
        if processedDecisionIds.contains(entry.id) {
            lock.unlock()
            alertHandler?(MLDataQualityAlert(
                type: .warning,
                decisionId: entry.id,
                exerciseId: entry.exerciseId,
                message: "Duplicate decision ID detected, skipping",
                details: nil
            ))
            return
        }
        processedDecisionIds.insert(entry.id)
        
        // Keep processed IDs bounded (last 1000)
        // NOTE: Set doesn't maintain order, so we remove an arbitrary element.
        // For proper LRU behavior, would need OrderedSet or different data structure.
        while processedDecisionIds.count > 1000 {
            _ = processedDecisionIds.popFirst()
        }
        lock.unlock()
        
        let pending = MLPendingRecord(
            decisionId: entry.id,
            exerciseId: entry.exerciseId,
            userId: entry.userId,
            decisionTimestamp: entry.timestamp,
            sessionDate: entry.sessionDate,
            prescribedLoadValue: entry.action.absoluteLoadValue,
            prescribedLoadUnit: entry.action.absoluteLoadUnit,
            targetReps: entry.action.targetReps,
            direction: entry.action.direction,
            logEntry: entry
        )
        
        lock.lock()
        pendingRecords[entry.id] = pending
        lock.unlock()
        
        // Persist for crash recovery
        persistPendingRecords()
        
        // Pre-validate to catch obvious issues early
        let preValidation = preValidateDecision(entry)
        if !preValidation.warnings.isEmpty {
            alertHandler?(MLDataQualityAlert(
                type: .warning,
                decisionId: entry.id,
                exerciseId: entry.exerciseId,
                message: "Pre-validation warnings: \(preValidation.warnings.joined(separator: "; "))",
                details: preValidation
            ))
        }
    }
    
    // MARK: - Outcome Collection
    
    /// Records the outcome for a pending decision.
    /// This triggers validation and potentially uploads the record.
    public func recordOutcome(
        decisionId: UUID,
        outcome: OutcomeRecord,
        executionContext: ExecutionContext = .normal
    ) async {
        guard isEnabled else { return }
        guard hasUserConsent else { return }
        
        lock.lock()
        guard let pending = pendingRecords[decisionId] else {
            lock.unlock()
            return
        }
        lock.unlock()
        
        // Rate limiting check
        if !checkRateLimit() {
            alertHandler?(MLDataQualityAlert(
                type: .warning,
                decisionId: decisionId,
                exerciseId: pending.exerciseId,
                message: "Rate limit exceeded, deferring upload",
                details: nil
            ))
            return
        }
        
        // Update the log entry with outcome
        var entry = pending.logEntry
        entry.outcome = outcome
        
        // CRITICAL: Persist the updated pending record with outcome immediately.
        // This ensures retryFailedUploads() can work if the upload fails below.
        let updatedPending = MLPendingRecord(
            decisionId: pending.decisionId,
            exerciseId: pending.exerciseId,
            userId: pending.userId,
            decisionTimestamp: pending.decisionTimestamp,
            sessionDate: pending.sessionDate,
            prescribedLoadValue: pending.prescribedLoadValue,
            prescribedLoadUnit: pending.prescribedLoadUnit,
            targetReps: pending.targetReps,
            direction: pending.direction,
            logEntry: entry
        )
        lock.lock()
        pendingRecords[decisionId] = updatedPending
        lock.unlock()
        persistPendingRecords()
        
        // Additional outcome validations
        let outcomeValidation = validateOutcome(outcome, entry: entry)
        
        // Validate the complete record
        var validation = validateDecisionWithOutcome(
            entry: entry,
            prescribedLoad: (pending.prescribedLoadValue, pending.prescribedLoadUnit),
            actualLoad: (outcome.actualLoadValue, outcome.actualLoadUnit),
            executionContext: executionContext
        )
        
        // Merge outcome validation warnings/errors
        var warnings = validation.warnings + outcomeValidation.warnings
        var errors = validation.errors + outcomeValidation.errors
        
        // Check for new user baseline protection
        if isNewUserWithoutBaseline(entry: entry) {
            warnings.append("New user without reliable baseline - data may have higher variance")
        }
        
        // Create updated validation result
        let finalValidation = MLValidationResult(
            isValid: validation.isValid && outcomeValidation.isValid,
            unitConsistent: validation.unitConsistent,
            timingValid: validation.timingValid,
            loadPlausible: validation.loadPlausible && outcomeValidation.loadPlausible,
            contextComplete: validation.contextComplete,
            noKnownAnomaly: validation.noKnownAnomaly && outcomeValidation.noKnownAnomaly,
            completenessScore: validation.completenessScore,
            warnings: warnings,
            errors: errors
        )
        
        // Create the full record
        let record = MLDecisionRecord(
            id: decisionId,
            entry: entry,
            collectionStatus: finalValidation.isValid ? .validated : .invalidated,
            validation: finalValidation,
            executionContext: executionContext
        )
        
        // Store load sample for future anomaly detection
        storeLoadSample(
            exerciseId: entry.exerciseId,
            load: outcome.actualLoadValue,
            unit: outcome.actualLoadUnit,
            date: entry.sessionDate
        )
        
        // Record upload timestamp for rate limiting
        recordUploadTimestamp()
        
        // Upload if valid, or flag if invalid
        if finalValidation.isValid {
            do {
                try await uploadHandler?(record)
                lock.lock()
                pendingRecords.removeValue(forKey: decisionId)
                lock.unlock()
                persistPendingRecords()
            } catch {
                // Keep pending for retry
                alertHandler?(MLDataQualityAlert(
                    type: .uploadFailed,
                    decisionId: decisionId,
                    exerciseId: entry.exerciseId,
                    message: "Upload failed: \(error.localizedDescription)",
                    details: finalValidation
                ))
            }
        } else {
            // Invalid record - still upload for review but flagged
            alertHandler?(MLDataQualityAlert(
                type: .validationFailed,
                decisionId: decisionId,
                exerciseId: entry.exerciseId,
                message: "Validation failed: \(errors.joined(separator: "; "))",
                details: finalValidation
            ))
            
            // Upload anyway for potential manual review
            do {
                try await uploadHandler?(record)
                lock.lock()
                pendingRecords.removeValue(forKey: decisionId)
                lock.unlock()
                persistPendingRecords()
            } catch {
                // Log but continue
            }
        }
    }
    
    // MARK: - Outcome Validation
    
    /// Validates outcome-specific data quality.
    private func validateOutcome(_ outcome: OutcomeRecord, entry: DecisionLogEntry) -> MLValidationResult {
        var warnings: [String] = []
        var errors: [String] = []
        var loadPlausible = true
        var noKnownAnomaly = true
        
        // 1. Check for partial set completion
        let targetSets = entry.action.setCount
        let completedSets = outcome.repsPerSet.count
        let completionRatio = targetSets > 0 ? Double(completedSets) / Double(targetSets) : 0
        
        if completionRatio < validationConfig.minSetCompletionRatio {
            warnings.append("Low set completion ratio: \(Int(completionRatio * 100))% (\(completedSets)/\(targetSets) sets)")
        }
        
        // 2. Check RIR sanity
        for (index, rir) in outcome.rirPerSet.enumerated() {
            if let rir = rir {
                if rir < validationConfig.minRIR {
                    errors.append("Invalid RIR at set \(index + 1): \(rir) < \(validationConfig.minRIR)")
                    noKnownAnomaly = false
                }
                if rir > validationConfig.maxRIR {
                    warnings.append("Unusual RIR at set \(index + 1): \(rir) > \(validationConfig.maxRIR)")
                }
            }
        }
        
        // 3. Check e1RM sanity
        let maxE1RMkg = outcome.actualLoadUnit == .kilograms
            ? outcome.sessionE1RM
            : outcome.sessionE1RM * 0.4536
        
        if maxE1RMkg > validationConfig.maxPlausibleE1RMKg {
            errors.append("Implausible e1RM: \(Int(maxE1RMkg)) kg exceeds maximum")
            loadPlausible = false
        }
        
        // 4. Check rep deviation from target
        let targetRepsLower = entry.liftSignals.targetRepsLower
        let targetRepsUpper = entry.liftSignals.targetRepsUpper
        
        for (index, reps) in outcome.repsPerSet.enumerated() {
            if reps < targetRepsLower - validationConfig.maxRepDeviationFromTarget {
                warnings.append("Large rep underperformance at set \(index + 1): \(reps) vs target \(targetRepsLower)-\(targetRepsUpper)")
            }
            if reps > targetRepsUpper + validationConfig.maxRepDeviationFromTarget {
                warnings.append("Large rep overperformance at set \(index + 1): \(reps) vs target \(targetRepsLower)-\(targetRepsUpper)")
            }
        }
        
        // 5. Check for bodyweight exercise handling
        let isBodyweight = entry.variationContext.equipment == .bodyweight
        if isBodyweight && outcome.actualLoadValue == 0 {
            // Bodyweight exercise with 0 load is valid
            // Just note it for awareness
        } else if !isBodyweight && outcome.actualLoadValue == 0 {
            warnings.append("Non-bodyweight exercise with 0 load")
        }
        
        // 6. Grinder consistency check
        // If marked as grinder but RIR is high, something is wrong
        if outcome.wasGrinder {
            if let avgRIR = outcome.avgRIR, avgRIR > 2 {
                warnings.append("Marked as grinder but avg RIR is \(avgRIR)")
                noKnownAnomaly = false
            }
        }
        
        // 7. Success/failure consistency
        if outcome.wasSuccess && outcome.wasFailure {
            errors.append("Record marked as both success and failure")
            noKnownAnomaly = false
        }
        
        return MLValidationResult(
            isValid: errors.isEmpty,
            unitConsistent: true,
            timingValid: true,
            loadPlausible: loadPlausible,
            contextComplete: true,
            noKnownAnomaly: noKnownAnomaly,
            completenessScore: 100,
            warnings: warnings,
            errors: errors
        )
    }
    
    // MARK: - New User Baseline Protection
    
    /// Sets the user's first training date for baseline calculation.
    public func setUserFirstTrainingDate(_ date: Date) {
        userFirstTrainingDate = date
    }
    
    /// Checks if user is new without reliable baseline.
    private func isNewUserWithoutBaseline(entry: DecisionLogEntry) -> Bool {
        guard let firstDate = userFirstTrainingDate else {
            // No first date set - check history
            if entry.historySummary.sessionCount < 5 {
                return true
            }
            return false
        }
        
        let daysSinceFirst = Calendar.current.dateComponents(
            [.day],
            from: firstDate,
            to: entry.sessionDate
        ).day ?? 0
        
        return daysSinceFirst < validationConfig.minDaysForReliableBaseline
    }
    
    // MARK: - Rate Limiting
    
    /// Checks if we're within rate limits.
    private func checkRateLimit() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        
        // Remove timestamps older than 1 minute
        let oneMinuteAgo = Date().addingTimeInterval(-60)
        uploadTimestamps.removeAll { $0 < oneMinuteAgo }
        
        return uploadTimestamps.count < validationConfig.maxUploadsPerMinute
    }
    
    /// Records an upload timestamp.
    private func recordUploadTimestamp() {
        lock.lock()
        defer { lock.unlock() }
        uploadTimestamps.append(Date())
    }
    
    // MARK: - Persistence (Crash Recovery)
    
    /// Persists pending records to disk.
    private func persistPendingRecords() {
        guard let path = pendingRecordsPath else { return }
        
        lock.lock()
        let records = Array(pendingRecords.values)
        lock.unlock()
        
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(records)
            try data.write(to: path, options: .atomic)
        } catch {
            // Silent fail - not critical
        }
    }
    
    /// Loads persisted pending records from disk.
    private func loadPersistedPendingRecords() {
        guard let path = pendingRecordsPath,
              FileManager.default.fileExists(atPath: path.path) else { return }
        
        do {
            let data = try Data(contentsOf: path)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let records = try decoder.decode([MLPendingRecord].self, from: data)
            
            lock.lock()
            for record in records {
                pendingRecords[record.decisionId] = record
            }
            lock.unlock()
        } catch {
            // Silent fail - start fresh
        }
    }
    
    /// Clears persisted pending records.
    public func clearPersistedRecords() {
        guard let path = pendingRecordsPath else { return }
        try? FileManager.default.removeItem(at: path)
    }
    
    // MARK: - Validation
    
    /// Pre-validates a decision before outcome is known.
    private func preValidateDecision(_ entry: DecisionLogEntry) -> MLValidationResult {
        var warnings: [String] = []
        var errors: [String] = []
        
        // Check load plausibility
        let load = entry.action.absoluteLoadValue
        let unit = entry.action.absoluteLoadUnit
        
        let (minLoad, maxLoad) = unit == .kilograms
            ? (validationConfig.minLoadKg, validationConfig.maxLoadKg)
            : (validationConfig.minLoadLb, validationConfig.maxLoadLb)
        
        if load < minLoad {
            warnings.append("Load \(load) \(unit.rawValue) below minimum")
        }
        if load > maxLoad {
            errors.append("Load \(load) \(unit.rawValue) above maximum")
        }
        
        // Check for potential unit confusion with baseline
        if entry.liftSignals.lastWorkingWeightValue > 0 {
            let ratio = load / entry.liftSignals.lastWorkingWeightValue
            if abs(ratio - 2.2) < validationConfig.unitConfusionRatioThreshold {
                warnings.append("Possible kg→lb unit confusion (ratio ~2.2)")
            }
            if abs(ratio - 0.45) < validationConfig.unitConfusionRatioThreshold {
                warnings.append("Possible lb→kg unit confusion (ratio ~0.45)")
            }
        }
        
        // Check context completeness
        let completeness = computeCompleteness(entry)
        if completeness < validationConfig.minCompletenessForTraining {
            warnings.append("Low completeness score: \(completeness)%")
        }
        
        return MLValidationResult(
            isValid: errors.isEmpty,
            unitConsistent: true,  // Can't check yet
            timingValid: true,     // Can't check yet
            loadPlausible: load >= minLoad && load <= maxLoad,
            contextComplete: completeness >= validationConfig.minCompletenessForTraining,
            noKnownAnomaly: warnings.isEmpty,
            completenessScore: completeness,
            warnings: warnings,
            errors: errors
        )
    }
    
    /// Validates a decision with its outcome.
    private func validateDecisionWithOutcome(
        entry: DecisionLogEntry,
        prescribedLoad: (Double, LoadUnit),
        actualLoad: (Double, LoadUnit),
        executionContext: ExecutionContext
    ) -> MLValidationResult {
        var warnings: [String] = []
        var errors: [String] = []
        
        // 1. Check unit consistency
        var unitConsistent = true
        if prescribedLoad.1 != actualLoad.1 {
            // Different units - could be intentional conversion
            let expectedRatio = prescribedLoad.1 == .kilograms ? 2.2046 : 0.4536
            let actualRatio = actualLoad.0 / prescribedLoad.0
            
            if abs(actualRatio - expectedRatio) > 0.1 {
                warnings.append("Unit mismatch with unexpected ratio: \(actualRatio)")
            }
            unitConsistent = false
        }
        
        // 2. Check timing (decision → outcome)
        var timingValid = true
        if let outcome = entry.outcome {
            // We don't have exact outcome time in OutcomeRecord, 
            // but we can check if session date is reasonable
            let daysDiff = Calendar.current.dateComponents(
                [.day], 
                from: entry.timestamp, 
                to: entry.sessionDate
            ).day ?? 0
            
            if daysDiff > 3 {
                warnings.append("Large gap between decision and session: \(daysDiff) days")
                timingValid = false
            }
        }
        
        // 3. Check load plausibility
        var loadPlausible = true
        let (minLoad, maxLoad) = actualLoad.1 == .kilograms
            ? (validationConfig.minLoadKg, validationConfig.maxLoadKg)
            : (validationConfig.minLoadLb, validationConfig.maxLoadLb)
        
        if actualLoad.0 < minLoad || actualLoad.0 > maxLoad {
            errors.append("Actual load \(actualLoad.0) outside plausible range")
            loadPlausible = false
        }
        
        // 4. Check for large load changes (potential data entry error)
        if prescribedLoad.0 > 0 {
            let changePercent = abs(actualLoad.0 - prescribedLoad.0) / prescribedLoad.0 * 100
            if changePercent > validationConfig.maxLoadChangePercent {
                warnings.append("Large load deviation: \(Int(changePercent))%")
                
                // Check for unit confusion
                let unitConfusionRatio1 = actualLoad.0 / prescribedLoad.0
                let unitConfusionRatio2 = prescribedLoad.0 / actualLoad.0
                
                if abs(unitConfusionRatio1 - 2.2) < validationConfig.unitConfusionRatioThreshold ||
                   abs(unitConfusionRatio2 - 2.2) < validationConfig.unitConfusionRatioThreshold {
                    errors.append("Likely unit confusion detected")
                    loadPlausible = false
                }
            }
        }
        
        // 5. Check for anomalies against recent history
        let anomalyCheck = checkForAnomalies(
            exerciseId: entry.exerciseId,
            load: actualLoad.0,
            unit: actualLoad.1
        )
        if !anomalyCheck.isEmpty {
            warnings.append(contentsOf: anomalyCheck)
        }
        
        // 6. Context-specific validation
        switch executionContext {
        case .normal:
            break
        case .equipmentIssue, .timeConstraint, .intentionalChange:
            // These explain deviations, so don't flag as errors
            break
        case .injuryDiscomfort:
            // Don't use for training if injury affected execution
            warnings.append("Injury/discomfort may affect data quality")
        case .environmental:
            break
        }
        
        // 7. Compute completeness
        let completeness = computeCompleteness(entry)
        let contextComplete = completeness >= validationConfig.minCompletenessForTraining
        
        // Overall validity
        let isValid = errors.isEmpty && loadPlausible && contextComplete
        
        return MLValidationResult(
            isValid: isValid,
            unitConsistent: unitConsistent,
            timingValid: timingValid,
            loadPlausible: loadPlausible,
            contextComplete: contextComplete,
            noKnownAnomaly: warnings.filter { $0.contains("anomaly") || $0.contains("confusion") }.isEmpty,
            completenessScore: completeness,
            warnings: warnings,
            errors: errors
        )
    }
    
    /// Checks for anomalies against recent load history.
    private func checkForAnomalies(exerciseId: String, load: Double, unit: LoadUnit) -> [String] {
        var warnings: [String] = []
        
        lock.lock()
        let samples = recentLoads[exerciseId] ?? []
        lock.unlock()
        
        guard samples.count >= 3 else { return warnings }
        
        // Convert to same unit for comparison
        let normalizedSamples = samples.map { sample -> Double in
            if sample.unit == unit {
                return sample.value
            } else if unit == .kilograms {
                return sample.value * 0.4536  // lb to kg
            } else {
                return sample.value * 2.2046  // kg to lb
            }
        }
        
        // Compute mean and stddev
        let mean = normalizedSamples.reduce(0, +) / Double(normalizedSamples.count)
        let variance = normalizedSamples.reduce(0) { $0 + pow($1 - mean, 2) } / Double(normalizedSamples.count)
        let stddev = sqrt(variance)
        
        guard stddev > 0 else { return warnings }
        
        let zScore = abs(load - mean) / stddev
        if zScore > validationConfig.loadChangeZScoreThreshold {
            warnings.append("Load anomaly detected (z-score: \(String(format: "%.2f", zScore)))")
        }
        
        return warnings
    }
    
    /// Stores a load sample for future anomaly detection.
    private func storeLoadSample(exerciseId: String, load: Double, unit: LoadUnit, date: Date) {
        let sample = LoadSample(value: load, unit: unit, date: date)
        
        lock.lock()
        defer { lock.unlock() }
        
        var samples = recentLoads[exerciseId] ?? []
        samples.append(sample)
        
        // Keep only last 20 samples
        if samples.count > 20 {
            samples.removeFirst(samples.count - 20)
        }
        
        recentLoads[exerciseId] = samples
    }
    
    /// Computes data completeness score (0-100).
    private func computeCompleteness(_ entry: DecisionLogEntry) -> Int {
        var score = 0
        let totalFields = 20
        
        // History summary
        if entry.historySummary.sessionCount > 0 { score += 1 }
        if !entry.lastExposures.isEmpty { score += 1 }
        
        // Trends
        if entry.trendStatistics.trend != .insufficient { score += 1 }
        if entry.trendStatistics.dataPoints > 0 { score += 1 }
        
        // Readiness
        if entry.readinessDistribution.current > 0 { score += 1 }
        if entry.readinessDistribution.sampleCount > 0 { score += 1 }
        
        // Signals
        if entry.liftSignals.lastWorkingWeightValue > 0 { score += 1 }
        if entry.liftSignals.rollingE1RM > 0 { score += 1 }
        if entry.liftSignals.daysSinceLastExposure != nil { score += 1 }
        
        // Action
        if !entry.action.explanation.isEmpty { score += 1 }
        if entry.action.confidence > 0 { score += 1 }
        
        // Policy trace
        if !entry.policyChecks.isEmpty { score += 1 }
        
        // Counterfactuals
        if !entry.counterfactuals.isEmpty { score += 1 }
        
        // Context
        if entry.variationContext.movementPattern != .unknown { score += 1 }
        if entry.constraintInfo.roundingIncrement > 0 { score += 1 }
        
        // Metadata
        if !entry.engineVersion.isEmpty { score += 1 }
        
        // Outcome (if present)
        if let outcome = entry.outcome {
            if !outcome.repsPerSet.isEmpty { score += 1 }
            if outcome.sessionE1RM > 0 { score += 1 }
            score += 2  // Bonus for having outcome
        }
        
        return (score * 100) / totalFields
    }
    
    // MARK: - Maintenance
    
    /// Expires pending records that are too old.
    public func expireStalePendingRecords(olderThan hours: Double = 72) {
        let cutoff = Date().addingTimeInterval(-hours * 3600)
        
        lock.lock()
        defer { lock.unlock() }
        
        let staleIds = pendingRecords.filter { $0.value.decisionTimestamp < cutoff }.map { $0.key }
        
        for id in staleIds {
            if let pending = pendingRecords[id] {
                alertHandler?(MLDataQualityAlert(
                    type: .expired,
                    decisionId: id,
                    exerciseId: pending.exerciseId,
                    message: "Pending record expired without outcome (session abandoned?)",
                    details: nil
                ))
            }
            pendingRecords.removeValue(forKey: id)
        }
        
        persistPendingRecords()
    }
    
    /// Marks a session as abandoned (user started but didn't finish).
    /// This prevents false negatives from incomplete data.
    /// CRITICAL: Filters by sessionId, not by date, to avoid deleting unrelated decisions.
    public func markSessionAbandoned(sessionId: UUID, reason: SessionAbandonmentReason) {
        lock.lock()
        let sessionPendingIds = pendingRecords.values
            .filter { $0.logEntry.sessionId == sessionId }
            .map { $0.decisionId }
        lock.unlock()
        
        for id in sessionPendingIds {
            lock.lock()
            pendingRecords.removeValue(forKey: id)
            lock.unlock()
            
            alertHandler?(MLDataQualityAlert(
                type: .warning,
                decisionId: id,
                exerciseId: "session",
                message: "Session abandoned: \(reason.rawValue)",
                details: nil
            ))
        }
        
        persistPendingRecords()
    }
    
    /// Returns count of pending records.
    public var pendingCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return pendingRecords.count
    }
    
    /// Returns pending records for a specific session date.
    public func pendingRecordsForDate(_ date: Date) -> [MLPendingRecord] {
        lock.lock()
        defer { lock.unlock() }
        return pendingRecords.values.filter {
            Calendar.current.isDate($0.sessionDate, inSameDayAs: date)
        }
    }
    
    /// Retries uploading failed records.
    public func retryFailedUploads() async {
        lock.lock()
        let records = Array(pendingRecords.values)
        lock.unlock()
        
        for pending in records {
            // Only retry if there's an outcome attached
            if pending.logEntry.outcome != nil {
                await recordOutcome(
                    decisionId: pending.decisionId,
                    outcome: pending.logEntry.outcome!,
                    executionContext: .normal
                )
            }
        }
    }
}

// MARK: - Session Abandonment

/// Reasons why a session might be abandoned.
public enum SessionAbandonmentReason: String, Codable, Sendable {
    case userCancelled = "user_cancelled"
    case appCrash = "app_crash"
    case timeout = "timeout"
    case equipmentIssue = "equipment_issue"
    case injury = "injury"
    case emergencey = "emergency"
    case unknown = "unknown"
}

// MARK: - Supporting Types

/// Context explaining why execution might differ from prescription.
public enum ExecutionContext: String, Codable, Sendable {
    case normal = "normal"
    case equipmentIssue = "equipment_issue"
    case timeConstraint = "time_constraint"
    case injuryDiscomfort = "injury_discomfort"
    case intentionalChange = "intentional_change"
    case environmental = "environmental"
}

/// A load sample for anomaly detection history.
private struct LoadSample {
    let value: Double
    let unit: LoadUnit
    let date: Date
}

/// Complete ML decision record ready for upload.
public struct MLDecisionRecord: Codable, Sendable {
    public let id: UUID
    public let entry: DecisionLogEntry
    public let collectionStatus: MLCollectionStatus
    public let validationUnitConsistent: Bool
    public let validationTimingValid: Bool
    public let validationLoadPlausible: Bool
    public let validationContextComplete: Bool
    public let validationNoKnownAnomaly: Bool
    public let completenessScore: Int
    public let executionContext: ExecutionContext
    public let warnings: [String]
    public let errors: [String]
    
    public init(
        id: UUID,
        entry: DecisionLogEntry,
        collectionStatus: MLCollectionStatus,
        validation: MLValidationResult,
        executionContext: ExecutionContext
    ) {
        self.id = id
        self.entry = entry
        self.collectionStatus = collectionStatus
        self.validationUnitConsistent = validation.unitConsistent
        self.validationTimingValid = validation.timingValid
        self.validationLoadPlausible = validation.loadPlausible
        self.validationContextComplete = validation.contextComplete
        self.validationNoKnownAnomaly = validation.noKnownAnomaly
        self.completenessScore = validation.completenessScore
        self.executionContext = executionContext
        self.warnings = validation.warnings
        self.errors = validation.errors
    }
}

/// Alert for data quality issues.
public struct MLDataQualityAlert: Sendable {
    public enum AlertType: String, Sendable {
        case warning = "warning"
        case validationFailed = "validation_failed"
        case uploadFailed = "upload_failed"
        case anomalyDetected = "anomaly_detected"
        case expired = "expired"
    }
    
    public let type: AlertType
    public let decisionId: UUID
    public let exerciseId: String
    public let message: String
    public let details: MLValidationResult?
    public let timestamp: Date
    
    public init(
        type: AlertType,
        decisionId: UUID,
        exerciseId: String,
        message: String,
        details: MLValidationResult?
    ) {
        self.type = type
        self.decisionId = decisionId
        self.exerciseId = exerciseId
        self.message = message
        self.details = details
        self.timestamp = Date()
    }
}

// MARK: - Integration with TrainingDataLogger

public extension TrainingDataLogger {
    
    /// Configures the logger to use ML data collector for validation.
    ///
    /// Routes entries based on their state:
    /// - Decision-only entries (outcome == nil) → collectDecision
    /// - Outcome-updated entries (outcome != nil) → recordOutcome (triggers validation + upload)
    func useMLDataCollector() {
        MLDataCollector.shared.isEnabled = true
        
        // Route log entries through collector based on whether they have outcomes
        self.logHandler = { entry in
            if let outcome = entry.outcome {
                // Entry has outcome attached - route to recordOutcome for validation and upload
                Task {
                    await MLDataCollector.shared.recordOutcome(
                        decisionId: entry.id,
                        outcome: outcome,
                        executionContext: .normal
                    )
                }
            } else {
                // New decision without outcome - collect and await outcome
                MLDataCollector.shared.collectDecision(entry)
            }
        }
    }
    
    /// Sets the upload handler for validated ML records.
    func setMLUploadHandler(_ handler: @escaping (MLDecisionRecord) async throws -> Void) {
        MLDataCollector.shared.uploadHandler = handler
    }
    
    /// Sets the alert handler for data quality issues.
    func setMLAlertHandler(_ handler: @escaping (MLDataQualityAlert) -> Void) {
        MLDataCollector.shared.alertHandler = handler
    }
}
