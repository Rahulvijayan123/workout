import Foundation
import TrainingEngine

// MARK: - Type Aliases for TrainingEngine ML Types

typealias TEDecisionLogEntry = TrainingEngine.DecisionLogEntry
typealias TEOutcomeRecord = TrainingEngine.OutcomeRecord
typealias TEMLDataCollector = TrainingEngine.MLDataCollector
typealias TEMLDecisionRecord = TrainingEngine.MLDecisionRecord
typealias TEMLDataQualityAlert = TrainingEngine.MLDataQualityAlert
typealias TEMLCollectionStatus = TrainingEngine.MLCollectionStatus
typealias TEExecutionContext = TrainingEngine.ExecutionContext
typealias TETrainingDataLogger = TrainingEngine.TrainingDataLogger
typealias TEPolicyCheckResult = TrainingEngine.PolicyCheckResult
typealias TECounterfactualRecord = TrainingEngine.CounterfactualRecord
typealias TEExposureRecord = TrainingEngine.ExposureRecord
typealias TEProgressionDirection = TrainingEngine.ProgressionDirection

// MARK: - ML Data Service Extension

/// Extension to SupabaseService for ML training data collection and upload.
/// Implements proper validation, batching, and error handling to ensure data quality.
extension SupabaseService {
    
    // MARK: - Configuration
    
    /// Whether ML data collection is enabled.
    private static var mlCollectionEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "ml.collection.enabled") }
        set { UserDefaults.standard.set(newValue, forKey: "ml.collection.enabled") }
    }
    
    /// Batch size for uploads (reduces API calls).
    private static let batchSize = 10
    
    /// Retry configuration.
    private static let maxRetries = 3
    private static let retryDelaySeconds: Double = 2.0
    
    // MARK: - Public API
    
    /// Enables ML data collection with proper handlers configured.
    func enableMLDataCollection() {
        Self.mlCollectionEnabled = true
        
        // Configure the TrainingDataLogger to use MLDataCollector
        TrainingDataLogger.shared.isEnabled = true
        TrainingDataLogger.shared.useMLDataCollector()
        
        // Set up upload handler
        TrainingDataLogger.shared.setMLUploadHandler { [weak self] record in
            try await self?.uploadMLDecisionRecord(record)
        }
        
        // Set up alert handler
        TrainingDataLogger.shared.setMLAlertHandler { [weak self] alert in
            self?.handleMLDataQualityAlert(alert)
        }
        
        print("[MLData] Collection enabled")
    }
    
    /// Disables ML data collection.
    func disableMLDataCollection() {
        Self.mlCollectionEnabled = false
        TrainingDataLogger.shared.isEnabled = false
        MLDataCollector.shared.isEnabled = false
        print("[MLData] Collection disabled")
    }
    
    /// Records an outcome for a decision (call after session completion).
    func recordMLOutcome(
        decisionId: UUID,
        exerciseResult: ExerciseSessionResult,
        readinessScore: Int?,
        executionContext: ExecutionContext = .normal
    ) async {
        guard Self.mlCollectionEnabled else { return }
        
        // Build outcome from exercise result
        let workingSets = exerciseResult.workingSets
        let prescription = exerciseResult.prescription
        
        let repsPerSet = workingSets.map(\.reps)
        let avgReps = repsPerSet.isEmpty ? 0 : Double(repsPerSet.reduce(0, +)) / Double(repsPerSet.count)
        let totalReps = repsPerSet.reduce(0, +)
        
        let rirPerSet = workingSets.map(\.rirObserved)
        let observedRIRs = rirPerSet.compactMap { $0 }
        let avgRIR = observedRIRs.isEmpty ? nil : Double(observedRIRs.reduce(0, +)) / Double(observedRIRs.count)
        
        let maxLoad = workingSets.map(\.load).max() ?? .zero
        let sessionE1RM = workingSets.map(\.estimatedE1RM).max() ?? 0
        
        let targetRepsLower = prescription.targetRepsRange.lowerBound
        let targetRIR = prescription.targetRIR
        
        let wasFailure = workingSets.contains { $0.reps < targetRepsLower }
        let wasSuccess = !wasFailure && workingSets.allSatisfy { $0.reps >= targetRepsLower }
        
        // Check for grinder (using same logic as engine)
        let grinderRirDelta = 1
        let wasGrinder: Bool = {
            guard !observedRIRs.isEmpty, !wasFailure, targetRIR > 0 else { return false }
            let minObserved = observedRIRs.min() ?? targetRIR
            return minObserved <= (targetRIR - grinderRirDelta - 1)
        }()
        
        let outcome = OutcomeRecord(
            repsPerSet: repsPerSet,
            avgReps: avgReps,
            totalReps: totalReps,
            rirPerSet: rirPerSet,
            avgRIR: avgRIR,
            actualLoadValue: maxLoad.value,
            actualLoadUnit: maxLoad.unit,
            sessionE1RM: sessionE1RM,
            wasSuccess: wasSuccess,
            wasFailure: wasFailure,
            wasGrinder: wasGrinder,
            totalVolume: exerciseResult.totalVolume,
            inSessionAdjustments: [],
            readinessScore: readinessScore
        )
        
        await MLDataCollector.shared.recordOutcome(
            decisionId: decisionId,
            outcome: outcome,
            executionContext: executionContext
        )
    }
    
    // MARK: - Upload Implementation
    
    /// Uploads a validated ML decision record to Supabase.
    private func uploadMLDecisionRecord(_ record: MLDecisionRecord) async throws {
        guard isAuthenticated, let userId = currentUserId else {
            throw SupabaseError.notAuthenticated
        }
        
        // Convert to Supabase format
        let payload = buildMLDecisionPayload(record, userId: userId)
        
        // Upload with retry
        var lastError: Error?
        for attempt in 1...Self.maxRetries {
            do {
                try await insertMLDecision(payload)
                
                // Upload outcome if present
                if record.entry.outcome != nil {
                    let outcomePayload = buildMLOutcomePayload(record, decisionId: record.id)
                    try await insertMLOutcome(outcomePayload)
                }
                
                print("[MLData] Uploaded decision \(record.id) (attempt \(attempt))")
                return
            } catch {
                lastError = error
                if attempt < Self.maxRetries {
                    try await Task.sleep(nanoseconds: UInt64(Self.retryDelaySeconds * 1_000_000_000) * UInt64(attempt))
                }
            }
        }
        
        throw lastError ?? SupabaseError.uploadFailed("Unknown error after \(Self.maxRetries) attempts")
    }
    
    /// Inserts an ML decision record.
    private func insertMLDecision(_ payload: [String: Any]) async throws {
        let url = baseURL.appendingPathComponent("rest/v1/ml_decision_records")
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(authToken ?? anonKey)", forHTTPHeaderField: "Authorization")
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("return=minimal", forHTTPHeaderField: "Prefer")
        
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SupabaseError.invalidResponse
        }
        
        if httpResponse.statusCode >= 400 {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw SupabaseError.apiError("HTTP \(httpResponse.statusCode): \(errorMessage)")
        }
    }
    
    /// Inserts an ML outcome record.
    private func insertMLOutcome(_ payload: [String: Any]) async throws {
        let url = baseURL.appendingPathComponent("rest/v1/ml_outcome_records")
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(authToken ?? anonKey)", forHTTPHeaderField: "Authorization")
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("return=minimal", forHTTPHeaderField: "Prefer")
        
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SupabaseError.invalidResponse
        }
        
        if httpResponse.statusCode >= 400 {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw SupabaseError.apiError("HTTP \(httpResponse.statusCode): \(errorMessage)")
        }
    }
    
    // MARK: - Payload Builders
    
    /// Builds the payload for ml_decision_records table.
    private func buildMLDecisionPayload(_ record: MLDecisionRecord, userId: String) -> [String: Any] {
        let entry = record.entry
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        var payload: [String: Any] = [
            "id": record.id.uuidString,
            "user_id": userId,
            "exercise_id": entry.exerciseId,
            "decision_timestamp": formatter.string(from: entry.timestamp),
            "session_date": formatDate(entry.sessionDate),
            
            // Data quality flags
            "collection_status": record.collectionStatus.rawValue,
            "validation_unit_consistent": record.validationUnitConsistent,
            "validation_timing_valid": record.validationTimingValid,
            "validation_load_plausible": record.validationLoadPlausible,
            "validation_context_complete": record.validationContextComplete,
            "validation_no_known_anomaly": record.validationNoKnownAnomaly,
            "data_completeness_score": record.completenessScore,
            
            // History summary
            "hist_session_count": entry.historySummary.sessionCount,
            "hist_sessions_last_7d": entry.historySummary.sessionsLast7Days,
            "hist_sessions_last_14d": entry.historySummary.sessionsLast14Days,
            "hist_sessions_last_28d": entry.historySummary.sessionsLast28Days,
            "hist_volume_last_7d": entry.historySummary.volumeLast7Days,
            "hist_volume_last_14d": entry.historySummary.volumeLast14Days,
            "hist_deload_sessions_last_28d": entry.historySummary.deloadSessionsLast28Days,
            "hist_training_streak_weeks": entry.historySummary.trainingStreakWeeks,
            
            // Trend statistics
            "trend_direction": entry.trendStatistics.trend.rawValue,
            "trend_data_points": entry.trendStatistics.dataPoints,
            "trend_has_two_session_decline": entry.trendStatistics.hasTwoSessionDecline,
            
            // Readiness
            "readiness_current": entry.readinessDistribution.current,
            "readiness_low_count": entry.readinessDistribution.lowReadinessCount,
            "readiness_consecutive_low_days": entry.readinessDistribution.consecutiveLowDays,
            "readiness_sample_count": entry.readinessDistribution.sampleCount,
            
            // Constraints
            "constraint_equipment_available": entry.constraintInfo.equipmentAvailable,
            "constraint_rounding_increment": entry.constraintInfo.roundingIncrement,
            "constraint_rounding_unit": entry.constraintInfo.roundingUnit.rawValue,
            "constraint_microloading_enabled": entry.constraintInfo.microloadingEnabled,
            "constraint_is_planned_deload_week": entry.constraintInfo.isPlannedDeloadWeek,
            
            // Variation context
            "variation_is_primary": entry.variationContext.isPrimaryExercise,
            "variation_is_substitution": entry.variationContext.isSubstitution,
            "variation_family_reference_key": entry.variationContext.familyReferenceKey,
            "variation_family_update_key": entry.variationContext.familyUpdateKey,
            "variation_family_coefficient": entry.variationContext.familyCoefficient,
            "variation_movement_pattern": entry.variationContext.movementPattern.rawValue,
            "variation_equipment": entry.variationContext.equipment.rawValue,
            "variation_state_is_exercise_specific": entry.variationContext.stateIsExerciseSpecific,
            
            // Session/experience
            "session_intent": entry.sessionIntent.rawValue,
            "experience_level": entry.experienceLevel.rawValue,
            
            // Lift signals
            "signals_last_working_weight_value": entry.liftSignals.lastWorkingWeightValue,
            "signals_last_working_weight_unit": entry.liftSignals.lastWorkingWeightUnit.rawValue,
            "signals_rolling_e1rm": entry.liftSignals.rollingE1RM,
            "signals_fail_streak": entry.liftSignals.failStreak,
            "signals_high_rpe_streak": entry.liftSignals.highRpeStreak,
            "signals_success_streak": entry.liftSignals.successStreak,
            "signals_successful_sessions_count": entry.liftSignals.successfulSessionsCount,
            "signals_last_session_was_failure": entry.liftSignals.lastSessionWasFailure,
            "signals_last_session_was_grinder": entry.liftSignals.lastSessionWasGrinder,
            "signals_last_session_reps": entry.liftSignals.lastSessionReps,
            "signals_target_reps_lower": entry.liftSignals.targetRepsLower,
            "signals_target_reps_upper": entry.liftSignals.targetRepsUpper,
            "signals_target_rir": entry.liftSignals.targetRIR,
            "signals_load_strategy": entry.liftSignals.loadStrategy,
            "signals_session_deload_triggered": entry.liftSignals.sessionDeloadTriggered,
            "signals_is_compound": entry.liftSignals.isCompound,
            "signals_is_upper_body_press": entry.liftSignals.isUpperBodyPress,
            "signals_has_training_gap": entry.liftSignals.hasTrainingGap,
            "signals_has_extended_break": entry.liftSignals.hasExtendedBreak,
            
            // Action
            "action_direction": entry.action.direction.rawValue,
            "action_primary_reason": entry.action.primaryReason.rawValue,
            "action_delta_load_value": entry.action.deltaLoadValue,
            "action_delta_load_unit": entry.action.deltaLoadUnit.rawValue,
            "action_load_multiplier": entry.action.loadMultiplier,
            "action_absolute_load_value": entry.action.absoluteLoadValue,
            "action_absolute_load_unit": entry.action.absoluteLoadUnit.rawValue,
            "action_baseline_load_value": entry.action.baselineLoadValue,
            "action_target_reps": entry.action.targetReps,
            "action_target_rir": entry.action.targetRIR,
            "action_set_count": entry.action.setCount,
            "action_volume_adjustment": entry.action.volumeAdjustment,
            "action_is_session_deload": entry.action.isSessionDeload,
            "action_is_exercise_deload": entry.action.isExerciseDeload,
            "action_adjustment_kind": entry.action.adjustmentKind.rawValue,
            "action_explanation": entry.action.explanation,
            "action_confidence": entry.action.confidence,
            
            // Policy checks and counterfactuals as JSONB
            "policy_checks": encodePolicyChecks(entry.policyChecks),
            "counterfactuals": encodeCounterfactuals(entry.counterfactuals),
            
            // Metadata
            "engine_version": entry.engineVersion
        ]
        
        // Optional fields
        if let avgDuration = entry.historySummary.avgSessionDurationMinutes {
            payload["hist_avg_session_duration_min"] = avgDuration
        }
        if let daysSince = entry.historySummary.daysSinceLastWorkout {
            payload["hist_days_since_last_workout"] = daysSince
        }
        if let slope = entry.trendStatistics.slopePerSession {
            payload["trend_slope_per_session"] = slope
        }
        if let slopePct = entry.trendStatistics.slopePercentage {
            payload["trend_slope_percentage"] = slopePct
        }
        if let rSquared = entry.trendStatistics.rSquared {
            payload["trend_r_squared"] = rSquared
        }
        if let volatility = entry.trendStatistics.recentVolatility {
            payload["trend_recent_volatility"] = volatility
        }
        if let daysSpanned = entry.trendStatistics.daysSpanned {
            payload["trend_days_spanned"] = daysSpanned
        }
        if let mean = entry.readinessDistribution.mean {
            payload["readiness_mean"] = mean
        }
        if let median = entry.readinessDistribution.median {
            payload["readiness_median"] = median
        }
        if let stddev = entry.readinessDistribution.stdDev {
            payload["readiness_stddev"] = stddev
        }
        if let min = entry.readinessDistribution.min {
            payload["readiness_min"] = min
        }
        if let max = entry.readinessDistribution.max {
            payload["readiness_max"] = max
        }
        if let trend = entry.readinessDistribution.trend {
            payload["readiness_trend"] = trend
        }
        if let daysSince = entry.liftSignals.daysSinceLastExposure {
            payload["signals_days_since_exposure"] = daysSince
        }
        if let daysSince = entry.liftSignals.daysSinceDeload {
            payload["signals_days_since_deload"] = daysSince
        }
        if let avgRIR = entry.liftSignals.lastSessionAvgRIR {
            payload["signals_last_session_avg_rir"] = avgRIR
        }
        if let reason = entry.liftSignals.sessionDeloadReason {
            payload["signals_session_deload_reason"] = reason
        }
        if let strength = entry.liftSignals.relativeStrength {
            payload["signals_relative_strength"] = strength
        }
        if let originalId = entry.variationContext.originalExerciseId {
            payload["variation_original_exercise_id"] = originalId
        }
        if !entry.action.contributingReasons.isEmpty {
            payload["action_contributing_reasons"] = entry.action.contributingReasons.map { $0.rawValue }
        }
        
        // Last exposures as JSONB
        payload["last_exposures"] = encodeExposures(entry.lastExposures)
        payload["last_exposures_count"] = entry.lastExposures.count
        
        return payload
    }
    
    /// Builds the payload for ml_outcome_records table.
    private func buildMLOutcomePayload(_ record: MLDecisionRecord, decisionId: UUID) -> [String: Any] {
        guard let outcome = record.entry.outcome else {
            return [:]
        }
        
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        var payload: [String: Any] = [
            "decision_id": decisionId.uuidString,
            "recorded_at": formatter.string(from: Date()),
            "outcome_source": "session_completion",
            "execution_context": record.executionContext.rawValue,
            
            "outcome_reps_per_set": outcome.repsPerSet,
            "outcome_avg_reps": outcome.avgReps,
            "outcome_total_reps": outcome.totalReps,
            "outcome_actual_load_value": outcome.actualLoadValue,
            "outcome_actual_load_unit": outcome.actualLoadUnit.rawValue,
            "outcome_was_success": outcome.wasSuccess,
            "outcome_was_failure": outcome.wasFailure,
            "outcome_was_grinder": outcome.wasGrinder,
            "outcome_total_volume": outcome.totalVolume
        ]
        
        if !outcome.rirPerSet.isEmpty {
            // Convert [Int?] to array that can be JSON encoded
            let rirValues = outcome.rirPerSet.map { $0 as Any? }
            payload["outcome_rir_per_set"] = rirValues
        }
        if let avgRIR = outcome.avgRIR {
            payload["outcome_avg_rir"] = avgRIR
        }
        if outcome.sessionE1RM > 0 {
            payload["outcome_session_e1rm"] = outcome.sessionE1RM
        }
        if let readiness = outcome.readinessScore {
            payload["readiness_at_execution"] = readiness
        }
        
        return payload
    }
    
    // MARK: - JSONB Encoding Helpers
    
    private func encodePolicyChecks(_ checks: [PolicyCheckResult]) -> [[String: Any]] {
        checks.map { check in
            var dict: [String: Any] = [
                "check_name": check.checkName,
                "triggered": check.triggered,
                "condition": check.condition,
                "observed": check.observed
            ]
            if let wouldProduce = check.wouldProduce {
                dict["would_produce"] = wouldProduce.rawValue
            }
            return dict
        }
    }
    
    private func encodeCounterfactuals(_ counterfactuals: [CounterfactualRecord]) -> [[String: Any]] {
        counterfactuals.map { cf in
            [
                "policy_id": cf.policyId,
                "policy_description": cf.policyDescription,
                "direction": cf.direction.rawValue,
                "primary_reason": cf.primaryReason.rawValue,
                "prescribed_load_value": cf.prescribedLoadValue,
                "prescribed_load_unit": cf.prescribedLoadUnit.rawValue,
                "load_multiplier": cf.loadMultiplier,
                "absolute_increment_value": cf.absoluteIncrementValue,
                "volume_adjustment": cf.volumeAdjustment,
                "confidence": cf.confidence
            ]
        }
    }
    
    private func encodeExposures(_ exposures: [ExposureRecord]) -> [[String: Any]] {
        let formatter = ISO8601DateFormatter()
        
        return exposures.map { exp in
            var dict: [String: Any] = [
                "date": formatter.string(from: exp.date),
                "days_ago": exp.daysAgo,
                "load_value": exp.loadValue,
                "load_unit": exp.loadUnit.rawValue,
                "avg_reps": exp.avgReps,
                "was_success": exp.wasSuccess,
                "was_failure": exp.wasFailure,
                "was_grinder": exp.wasGrinder,
                "session_e1rm": exp.sessionE1RM,
                "adjustment_kind": exp.adjustmentKind.rawValue
            ]
            if let avgRIR = exp.avgRIR {
                dict["avg_rir"] = avgRIR
            }
            if let readiness = exp.readinessScore {
                dict["readiness_score"] = readiness
            }
            return dict
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
    
    // MARK: - Alert Handling
    
    /// Handles data quality alerts.
    private func handleMLDataQualityAlert(_ alert: MLDataQualityAlert) {
        // Log the alert
        print("[MLData] Alert [\(alert.type.rawValue)]: \(alert.message)")
        
        // For certain alert types, upload to safety_events table
        switch alert.type {
        case .validationFailed:
            // Don't spam the safety table, just log
            break
        case .anomalyDetected:
            // This could indicate a data quality issue worth tracking
            Task {
                await uploadDataQualityEvent(alert)
            }
        case .uploadFailed:
            // Could retry later or store locally
            break
        case .expired:
            // Clean up
            break
        case .warning:
            break
        }
    }
    
    /// Uploads a data quality event for tracking.
    private func uploadDataQualityEvent(_ alert: MLDataQualityAlert) async {
        guard isAuthenticated, let userId = currentUserId else { return }
        
        let formatter = ISO8601DateFormatter()
        
        let payload: [String: Any] = [
            "user_id": userId,
            "occurred_at": formatter.string(from: alert.timestamp),
            "event_type": "system_alert",
            "severity": alert.type == .anomalyDetected ? "medium" : "low",
            "description": alert.message,
            "exercise_id": alert.exerciseId
        ]
        
        do {
            let url = baseURL.appendingPathComponent("rest/v1/pilot_safety_events")
            
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(authToken ?? anonKey)", forHTTPHeaderField: "Authorization")
            request.setValue(anonKey, forHTTPHeaderField: "apikey")
            request.setValue("return=minimal", forHTTPHeaderField: "Prefer")
            
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
            
            let (_, _) = try await URLSession.shared.data(for: request)
        } catch {
            print("[MLData] Failed to upload quality event: \(error)")
        }
    }
}

// MARK: - Extended Errors

extension SupabaseError {
    static func uploadFailed(_ message: String) -> SupabaseError {
        .apiError("Upload failed: \(message)")
    }
}
