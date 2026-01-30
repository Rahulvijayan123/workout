import Foundation

// MARK: - Pilot Telemetry Service
/// Handles trajectory collection and sparse label requests for the friend pilot.
/// 
/// Design principles:
/// - Auto-collect EVERY decision with full context (no user burden)
/// - Only prompt for labels at high-leverage moments (triggers)
/// - Link prescriptions to outcomes in next session
/// - Log all manual overrides for learning
///
/// HARD DISABLED:
/// This system is currently disabled due to internal inconsistencies:
/// 1. Session IDs: onSessionStart creates a UUID but recordTrajectory uses activeSession?.id (different IDs)
/// 2. userOverrodePrescription compares actualWeight to prescribedWeight (both are the actual weight after user edit)
/// 3. Trajectories are keyed by exerciseId but sessions can have duplicate exercises
/// 4. No stable join keys between trajectories and the canonical ML data path (recommendation_events)
///
/// Use the canonical ML data path instead:
/// - DataSyncService.syncRecommendationEvent() for immutable recommendations
/// - DataSyncService.syncPlannedSets() for planned prescriptions
/// - session_exercises/session_sets with outcome fields for performed data
///
/// To re-enable pilot telemetry, set isHardDisabled = false after fixing the above issues.
@MainActor
final class PilotTelemetryService: ObservableObject {
    
    // MARK: - Hard Disable Flag
    
    /// Set to false to re-enable pilot telemetry after fixing consistency issues.
    /// See class documentation for required fixes.
    private static let isHardDisabled: Bool = true
    
    // MARK: - Published State
    
    @Published private(set) var isPilotUser: Bool = false
    @Published private(set) var pendingLabelRequest: PendingLabelRequest?
    @Published private(set) var pilotSettings: PilotSettings = .conservative
    
    // MARK: - Dependencies
    
    private let supabaseService: SupabaseService?
    private let userId: String?
    
    // MARK: - In-Memory Caches
    
    /// Recent trajectories awaiting outcome linkage (keyed by exercise_id)
    private var awaitingOutcome: [String: EngineTrajectory] = [:]
    
    /// Trajectories from current session (for batch upload)
    private var currentSessionTrajectories: [EngineTrajectory] = []
    
    // MARK: - Initialization
    
    init(supabaseService: SupabaseService? = nil, userId: String? = nil) {
        self.supabaseService = supabaseService
        self.userId = userId
    }
    
    /// Check if user is enrolled in pilot
    func checkPilotEnrollment() async {
        // Hard disabled - always report not enrolled
        guard !Self.isHardDisabled else {
            isPilotUser = false
            return
        }
        
        guard let userId = userId else {
            isPilotUser = false
            return
        }
        
        // TODO: Fetch from Supabase pilot_participants table
        // For now, default to true for development
        isPilotUser = true
        pilotSettings = .conservative
    }
    
    // MARK: - Trajectory Recording (Auto-collect every decision)
    
    /// Record an engine decision trajectory. Called after every recommendation.
    func recordTrajectory(
        exerciseId: String,
        exerciseName: String,
        sessionId: UUID?,
        priorState: ExerciseState?,
        readiness: Int,
        prescription: PrescriptionContext,
        decision: EngineDecision,
        guardrailIntervention: GuardrailIntervention? = nil
    ) {
        // Hard disabled - no-op
        guard !Self.isHardDisabled else { return }
        
        let trajectory = EngineTrajectory(
            id: UUID(),
            userId: userId ?? "unknown",
            sessionId: sessionId,
            decidedAt: Date(),
            exerciseId: exerciseId,
            exerciseName: exerciseName,
            
            // Prior state
            priorWorkingWeightKg: priorState?.currentWorkingWeight.poundsToKg(),
            priorE1RMKg: priorState?.rollingE1RM?.poundsToKg(),
            priorFailureCount: priorState?.failuresCount,
            priorTrend: priorState?.e1rmTrend.rawValue,
            priorSuccessfulSessions: priorState?.successfulSessionsCount,
            daysSinceLastSession: priorState?.updatedAt.daysAgo(),
            
            // Context
            readinessScore: readiness,
            wasBreakReturn: decision.wasBreakReturn,
            breakDurationDays: decision.breakDurationDays,
            
            // Prescription
            setsTarget: prescription.setsTarget,
            repRangeMin: prescription.repRangeMin,
            repRangeMax: prescription.repRangeMax,
            targetRIR: prescription.targetRIR,
            incrementKg: prescription.increment.poundsToKg(),
            
            // Decision
            decisionType: decision.type,
            prescribedWeightKg: decision.prescribedWeight.poundsToKg(),
            prescribedReps: decision.prescribedReps,
            weightDeltaKg: decision.weightDelta?.poundsToKg(),
            weightDeltaPercent: decision.weightDeltaPercent,
            
            // Deload
            isDeload: decision.isDeload,
            deloadReason: decision.deloadReason,
            deloadIntensityReductionPercent: decision.deloadIntensityReduction,
            deloadVolumeReductionSets: decision.deloadVolumeReduction,
            
            // Reasoning
            decisionReasons: decision.reasons,
            
            // Guardrail
            guardrailTriggered: guardrailIntervention != nil,
            guardrailType: guardrailIntervention?.type,
            originalDecisionType: guardrailIntervention?.originalDecisionType,
            originalPrescribedWeightKg: guardrailIntervention?.originalWeight?.poundsToKg()
        )
        
        // Cache for outcome linkage
        awaitingOutcome[exerciseId] = trajectory
        currentSessionTrajectories.append(trajectory)
        
        // Check if this decision triggers a label request
        if let trigger = detectLabelTrigger(decision: decision, readiness: readiness) {
            queueLabelRequest(trajectory: trajectory, trigger: trigger)
        }
        
        // Persist asynchronously
        Task {
            await persistTrajectory(trajectory)
        }
    }
    
    // MARK: - Outcome Recording (Link prescription → actual performance)
    
    /// Record what actually happened when the user performed the exercise.
    /// Called after each exercise is completed.
    func recordOutcome(
        exerciseId: String,
        sessionId: UUID,
        actualWeightLbs: Double,
        actualReps: [Int],
        observedRIR: Int?,
        observedRPE: Double?,
        wasCompleted: Bool,
        wasSkipped: Bool = false,
        wasSubstituted: Bool = false,
        substitutedWith: String? = nil,
        painReported: Bool = false,
        painLocation: String? = nil,
        userOverrode: Bool = false,
        overrideType: String? = nil
    ) {
        // Hard disabled - no-op
        guard !Self.isHardDisabled else { return }
        
        guard let trajectory = awaitingOutcome[exerciseId] else { return }
        
        let actualWeightKg = actualWeightLbs.poundsToKg()
        let avgReps = actualReps.isEmpty ? 0 : actualReps.reduce(0, +) / actualReps.count
        
        let outcome = TrajectoryOutcome(
            id: UUID(),
            trajectoryId: trajectory.id,
            outcomeSessionId: sessionId,
            recordedAt: Date(),
            
            // Actuals
            followedPrescription: !userOverrode && abs(actualWeightKg - trajectory.prescribedWeightKg) < 1.0,
            actualWeightKg: actualWeightKg,
            actualRepsAchieved: actualReps,
            actualSetsCompleted: actualReps.count,
            
            // Effort
            observedRIR: observedRIR,
            observedRPE: observedRPE,
            wasGrinder: (observedRPE ?? 0) >= 9.5 || (observedRIR ?? 10) == 0,
            wasFailure: actualReps.contains(where: { $0 < trajectory.repRangeMin }),
            
            // Completion
            exerciseCompleted: wasCompleted,
            exerciseSkipped: wasSkipped,
            
            // Substitution
            wasSubstituted: wasSubstituted,
            substitutedWithExerciseId: substitutedWith,
            
            // Pain
            painReported: painReported,
            painLocation: painLocation,
            
            // Override
            userOverrodePrescription: userOverrode,
            overrideType: overrideType,
            
            // Deviations
            weightDeviationKg: actualWeightKg - trajectory.prescribedWeightKg,
            weightDeviationPercent: trajectory.prescribedWeightKg > 0 
                ? ((actualWeightKg - trajectory.prescribedWeightKg) / trajectory.prescribedWeightKg) * 100 
                : nil,
            repsVsTarget: avgReps < trajectory.prescribedReps ? "below" 
                : avgReps > trajectory.prescribedReps ? "above" : "at"
        )
        
        // Clear from awaiting
        awaitingOutcome.removeValue(forKey: exerciseId)
        
        // Additional label triggers based on outcome
        if outcome.wasGrinder {
            queueLabelRequest(trajectory: trajectory, trigger: .afterGrinder(rpe: observedRPE ?? 10))
        }
        if outcome.wasFailure {
            queueLabelRequest(trajectory: trajectory, trigger: .afterFailedSet)
        }
        if outcome.painReported {
            recordSafetyEvent(type: .painReported, description: "Pain at \(painLocation ?? "unknown")", exerciseId: exerciseId)
        }
        
        // Persist
        Task {
            await persistOutcome(outcome)
        }
    }
    
    // MARK: - Label Trigger Detection
    
    private func detectLabelTrigger(decision: EngineDecision, readiness: Int) -> LabelTrigger? {
        // Priority order (only return first trigger)
        
        if decision.type == .increaseWeight {
            return .increaseRecommended(delta: decision.weightDelta ?? 0)
        }
        
        if decision.isDeload {
            return .deloadRecommended(reason: decision.deloadReason)
        }
        
        if decision.wasBreakReturn, let days = decision.breakDurationDays, days >= 7 {
            return .afterBreak(days: days)
        }
        
        if readiness < 40 {
            return .acuteLowReadiness(score: readiness)
        }
        
        // Note: afterGrinder and afterFailedSet are detected in recordOutcome
        // substitutionChange would be detected when user swaps exercise
        
        return nil
    }
    
    // MARK: - Label Request Management
    
    private func queueLabelRequest(trajectory: EngineTrajectory, trigger: LabelTrigger) {
        // Debounce: don't queue if we already have a pending request for this exercise in this session
        if let existing = pendingLabelRequest, 
           existing.trajectory.exerciseId == trajectory.exerciseId {
            return
        }
        
        let request = PendingLabelRequest(
            id: UUID(),
            trajectory: trajectory,
            trigger: trigger,
            promptAfter: Date(), // Immediate
            expiresAt: Date().addingTimeInterval(60 * 60 * 24), // 24 hours
            priority: trigger.priority
        )
        
        // Replace if higher priority, otherwise queue
        if let existing = pendingLabelRequest {
            if request.priority < existing.priority {
                pendingLabelRequest = request
            }
        } else {
            pendingLabelRequest = request
        }
        
        // Also persist to Supabase for cross-session retrieval
        Task {
            await persistPendingLabel(request)
        }
    }
    
    /// Submit a reasonableness label from the user
    func submitLabel(
        wasReasonable: Bool,
        unreasonableReason: UnreasonableReason? = nil,
        comment: String? = nil,
        confidence: LabelConfidence = .medium
    ) {
        guard let request = pendingLabelRequest else { return }
        
        let label = ReasonablenessLabel(
            id: UUID(),
            userId: userId ?? "unknown",
            trajectoryId: request.trajectory.id,
            labeledAt: Date(),
            
            triggerType: request.trigger.rawType,
            triggerContext: request.trigger.context,
            
            wasReasonable: wasReasonable,
            unreasonableReason: unreasonableReason?.rawValue,
            userComment: comment,
            confidence: confidence.rawValue,
            
            promptShownAt: request.promptShownAt,
            responseTimeSeconds: request.promptShownAt.map { 
                Int(Date().timeIntervalSince($0)) 
            },
            labelSource: .prompted,
            wasSkipped: false
        )
        
        // Clear pending
        pendingLabelRequest = nil
        
        // Persist
        Task {
            await persistLabel(label)
        }
    }
    
    /// Skip the current label request
    func skipLabel() {
        guard let request = pendingLabelRequest else { return }
        
        let label = ReasonablenessLabel(
            id: UUID(),
            userId: userId ?? "unknown",
            trajectoryId: request.trajectory.id,
            labeledAt: Date(),
            triggerType: request.trigger.rawType,
            triggerContext: request.trigger.context,
            wasReasonable: true, // Default to reasonable when skipped
            confidence: "low",
            labelSource: .prompted,
            wasSkipped: true
        )
        
        pendingLabelRequest = nil
        
        Task {
            await persistLabel(label)
        }
    }
    
    /// Mark the label prompt as shown (for response time tracking)
    func markLabelPromptShown() {
        pendingLabelRequest?.promptShownAt = Date()
    }
    
    // MARK: - Manual Override Recording
    
    func recordManualOverride(
        exerciseId: String,
        exerciseName: String,
        sessionId: UUID?,
        enginePrescribedWeightLbs: Double,
        enginePrescribedReps: Int,
        engineDecisionType: String,
        userChosenWeightLbs: Double,
        userChosenReps: Int,
        reason: OverrideReason,
        notes: String? = nil
    ) {
        // Hard disabled - no-op
        guard !Self.isHardDisabled else { return }
        
        let override = ManualOverride(
            id: UUID(),
            userId: userId ?? "unknown",
            sessionId: sessionId,
            trajectoryId: awaitingOutcome[exerciseId]?.id,
            overriddenAt: Date(),
            exerciseId: exerciseId,
            exerciseName: exerciseName,
            enginePrescribedWeightKg: enginePrescribedWeightLbs.poundsToKg(),
            enginePrescribedReps: enginePrescribedReps,
            engineDecisionType: engineDecisionType,
            userChosenWeightKg: userChosenWeightLbs.poundsToKg(),
            userChosenReps: userChosenReps,
            weightOverrideKg: (userChosenWeightLbs - enginePrescribedWeightLbs).poundsToKg(),
            weightOverridePercent: enginePrescribedWeightLbs > 0 
                ? ((userChosenWeightLbs - enginePrescribedWeightLbs) / enginePrescribedWeightLbs) * 100 
                : nil,
            overrideReason: reason.rawValue,
            overrideNotes: notes
        )
        
        Task {
            await persistOverride(override)
        }
    }
    
    // MARK: - Safety Event Recording
    
    func recordSafetyEvent(
        type: SafetyEventType,
        severity: SafetySeverity = .low,
        description: String?,
        exerciseId: String? = nil,
        exerciseName: String? = nil
    ) {
        // Hard disabled - no-op
        guard !Self.isHardDisabled else { return }
        
        let event = PilotSafetyEvent(
            id: UUID(),
            userId: userId ?? "unknown",
            sessionId: currentSessionTrajectories.first?.sessionId,
            occurredAt: Date(),
            eventType: type.rawValue,
            severity: severity.rawValue,
            description: description,
            exerciseId: exerciseId,
            exerciseName: exerciseName,
            requiresFollowup: severity == .high || severity == .critical
        )
        
        Task {
            await persistSafetyEvent(event)
        }
    }
    
    // MARK: - Session Lifecycle
    
    func onSessionStart(sessionId: UUID) {
        // Hard disabled - no-op
        guard !Self.isHardDisabled else { return }
        currentSessionTrajectories.removeAll()
    }
    
    func onSessionEnd(sessionId: UUID) {
        // Hard disabled - no-op
        guard !Self.isHardDisabled else { return }
        // Batch upload any remaining trajectories
        // Clear session-specific caches
        currentSessionTrajectories.removeAll()
    }
    
    // MARK: - Persistence (Supabase)
    
    private func persistTrajectory(_ trajectory: EngineTrajectory) async {
        // TODO: Implement Supabase insert
        // For now, log locally
        print("[Pilot] Trajectory recorded: \(trajectory.exerciseName) - \(trajectory.decisionType)")
    }
    
    private func persistOutcome(_ outcome: TrajectoryOutcome) async {
        print("[Pilot] Outcome recorded: trajectory=\(outcome.trajectoryId)")
    }
    
    private func persistLabel(_ label: ReasonablenessLabel) async {
        print("[Pilot] Label recorded: \(label.wasReasonable ? "reasonable" : "unreasonable") - \(label.triggerType)")
    }
    
    private func persistOverride(_ override: ManualOverride) async {
        print("[Pilot] Override recorded: \(override.exerciseName) - \(override.overrideReason)")
    }
    
    private func persistSafetyEvent(_ event: PilotSafetyEvent) async {
        print("[Pilot] Safety event: \(event.eventType) - \(event.severity)")
    }
    
    private func persistPendingLabel(_ request: PendingLabelRequest) async {
        print("[Pilot] Label request queued: \(request.trigger.rawType)")
    }
}

// MARK: - Data Models

struct PilotSettings {
    var conservativeMode: Bool
    var maxWeeklyIncreasePercent: Double
    var allowIncreaseAfterGrinder: Bool
    var allowIncreaseLowReadiness: Bool
    
    static let conservative = PilotSettings(
        conservativeMode: true,
        maxWeeklyIncreasePercent: 5.0,
        allowIncreaseAfterGrinder: false,
        allowIncreaseLowReadiness: false
    )
}

struct EngineTrajectory: Identifiable {
    let id: UUID
    let userId: String
    let sessionId: UUID?
    let decidedAt: Date
    let exerciseId: String
    let exerciseName: String
    
    // Prior state
    let priorWorkingWeightKg: Double?
    let priorE1RMKg: Double?
    let priorFailureCount: Int?
    let priorTrend: String?
    let priorSuccessfulSessions: Int?
    let daysSinceLastSession: Int?
    
    // Context
    let readinessScore: Int
    let wasBreakReturn: Bool
    let breakDurationDays: Int?
    
    // Prescription
    let setsTarget: Int
    let repRangeMin: Int
    let repRangeMax: Int
    let targetRIR: Int
    let incrementKg: Double
    
    // Decision
    let decisionType: DecisionType
    let prescribedWeightKg: Double
    let prescribedReps: Int
    let weightDeltaKg: Double?
    let weightDeltaPercent: Double?
    
    // Deload
    let isDeload: Bool
    let deloadReason: String?
    let deloadIntensityReductionPercent: Double?
    let deloadVolumeReductionSets: Int?
    
    // Reasoning
    let decisionReasons: [String]
    
    // Guardrail
    let guardrailTriggered: Bool
    let guardrailType: String?
    let originalDecisionType: DecisionType?
    let originalPrescribedWeightKg: Double?
}

struct TrajectoryOutcome: Identifiable {
    let id: UUID
    let trajectoryId: UUID
    let outcomeSessionId: UUID?
    let recordedAt: Date
    
    let followedPrescription: Bool
    let actualWeightKg: Double
    let actualRepsAchieved: [Int]
    let actualSetsCompleted: Int
    
    let observedRIR: Int?
    let observedRPE: Double?
    let wasGrinder: Bool
    let wasFailure: Bool
    
    let exerciseCompleted: Bool
    let exerciseSkipped: Bool
    let skipReason: String? = nil
    
    let wasSubstituted: Bool
    let substitutedWithExerciseId: String?
    let substitutionReason: String? = nil
    
    let painReported: Bool
    let painLocation: String?
    let painSeverity: Int? = nil
    
    let userOverrodePrescription: Bool
    let overrideType: String?
    let overrideReason: String? = nil
    
    let weightDeviationKg: Double
    let weightDeviationPercent: Double?
    let repsVsTarget: String
}

struct ReasonablenessLabel: Identifiable {
    let id: UUID
    let userId: String
    let trajectoryId: UUID
    let labeledAt: Date
    
    let triggerType: String
    let triggerContext: [String: Any]
    
    let wasReasonable: Bool
    let unreasonableReason: String?
    let userComment: String?
    let confidence: String
    
    let promptShownAt: Date?
    let responseTimeSeconds: Int?
    let labelSource: LabelSource
    let wasSkipped: Bool
}

struct PendingLabelRequest: Identifiable {
    let id: UUID
    let trajectory: EngineTrajectory
    let trigger: LabelTrigger
    let promptAfter: Date
    let expiresAt: Date
    let priority: Int
    var promptShownAt: Date?
}

struct ManualOverride: Identifiable {
    let id: UUID
    let userId: String
    let sessionId: UUID?
    let trajectoryId: UUID?
    let overriddenAt: Date
    let exerciseId: String
    let exerciseName: String
    let enginePrescribedWeightKg: Double
    let enginePrescribedReps: Int
    let engineDecisionType: String
    let userChosenWeightKg: Double
    let userChosenReps: Int
    let weightOverrideKg: Double
    let weightOverridePercent: Double?
    let overrideReason: String
    let overrideNotes: String?
}

struct PilotSafetyEvent: Identifiable {
    let id: UUID
    let userId: String
    let sessionId: UUID?
    let occurredAt: Date
    let eventType: String
    let severity: String
    let description: String?
    let exerciseId: String?
    let exerciseName: String?
    let requiresFollowup: Bool
}

// MARK: - Supporting Types

struct PrescriptionContext {
    let setsTarget: Int
    let repRangeMin: Int
    let repRangeMax: Int
    let targetRIR: Int
    let increment: Double
}

struct EngineDecision {
    let type: DecisionType
    let prescribedWeight: Double
    let prescribedReps: Int
    let weightDelta: Double?
    let weightDeltaPercent: Double?
    let isDeload: Bool
    let deloadReason: String?
    let deloadIntensityReduction: Double?
    let deloadVolumeReduction: Int?
    let wasBreakReturn: Bool
    let breakDurationDays: Int?
    let reasons: [String]
}

struct GuardrailIntervention {
    let type: String
    let originalDecisionType: DecisionType
    let originalWeight: Double?
}

enum DecisionType: String, Codable {
    case increaseWeight = "increase_weight"
    case increaseReps = "increase_reps"
    case hold = "hold"
    case deload = "deload"
    case breakReset = "break_reset"
}

enum LabelTrigger {
    case increaseRecommended(delta: Double)
    case deloadRecommended(reason: String?)
    case afterMissedSession
    case afterBreak(days: Int)
    case afterFailedSet
    case afterGrinder(rpe: Double)
    case substitutionChange
    case acuteLowReadiness(score: Int)
    case manualRequest
    
    var rawType: String {
        switch self {
        case .increaseRecommended: return "increase_recommended"
        case .deloadRecommended: return "deload_recommended"
        case .afterMissedSession: return "after_missed_session"
        case .afterBreak: return "after_break"
        case .afterFailedSet: return "after_failed_set"
        case .afterGrinder: return "after_grinder"
        case .substitutionChange: return "substitution_change"
        case .acuteLowReadiness: return "acute_low_readiness"
        case .manualRequest: return "manual_request"
        }
    }
    
    var context: [String: Any] {
        switch self {
        case .increaseRecommended(let delta): return ["delta_lbs": delta]
        case .deloadRecommended(let reason): return ["reason": reason ?? "unknown"]
        case .afterBreak(let days): return ["break_days": days]
        case .afterGrinder(let rpe): return ["grinder_rpe": rpe]
        case .acuteLowReadiness(let score): return ["readiness_score": score]
        default: return [:]
        }
    }
    
    /// Lower = higher priority
    var priority: Int {
        switch self {
        case .deloadRecommended: return 1
        case .increaseRecommended: return 2
        case .afterBreak: return 3
        case .afterGrinder: return 4
        case .afterFailedSet: return 5
        case .acuteLowReadiness: return 6
        case .substitutionChange: return 7
        case .afterMissedSession: return 8
        case .manualRequest: return 10
        }
    }
}

enum UnreasonableReason: String, CaseIterable {
    case tooHeavy = "too_heavy"
    case tooLight = "too_light"
    case wrongDirection = "wrong_direction"
    case wrongTiming = "wrong_timing"
    case other = "other"
    
    var displayText: String {
        switch self {
        case .tooHeavy: return "Too heavy"
        case .tooLight: return "Too light"
        case .wrongDirection: return "Wrong direction"
        case .wrongTiming: return "Wrong timing"
        case .other: return "Other"
        }
    }
}

enum LabelConfidence: String {
    case low, medium, high
}

enum LabelSource: String {
    case prompted, volunteered
}

enum OverrideReason: String, CaseIterable {
    case tooHeavy = "too_heavy"
    case tooLight = "too_light"
    case equipmentUnavailable = "equipment_unavailable"
    case timeConstraint = "time_constraint"
    case feelingGood = "feeling_good"
    case feelingBad = "feeling_bad"
    case testingMax = "testing_max"
    case other = "other"
}

enum SafetyEventType: String {
    case painReported = "pain_reported"
    case injuryReported = "injury_reported"
    case excessiveFatigue = "excessive_fatigue"
    case nearMiss = "near_miss"
    case userConcern = "user_concern"
    case guardrailOverride = "guardrail_override"
    case systemAlert = "system_alert"
}

enum SafetySeverity: String {
    case low, medium, high, critical
}

// MARK: - Extensions

private extension Double {
    func poundsToKg() -> Double {
        self * 0.453592
    }
}

private extension Date {
    func daysAgo() -> Int {
        Calendar.current.dateComponents([.day], from: self, to: Date()).day ?? 0
    }
}
