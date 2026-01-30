import Foundation

// MARK: - Recommendation Event (Immutable Policy Log)

/// Immutable record of a recommendation made by the training engine.
/// This is CRITICAL for ML training - never update, only append.
struct RecommendationEvent: Codable, Identifiable {
    var id: UUID = UUID()
    var sessionId: UUID?
    var sessionExerciseId: UUID?
    var exerciseId: String
    
    // What was recommended (the chosen action)
    var recommendedWeightLbs: Double
    var recommendedReps: Int
    var recommendedSets: Int
    var recommendedRIR: Int
    
    // Policy metadata (CRITICAL for evaluation)
    var policyVersion: String = "v1.0"
    var policyType: PolicyType = .deterministic
    
    // Action classification
    var actionType: RecommendationActionType
    
    // Reasoning
    var reasonCodes: [ReasonCode] = []
    
    // MARK: - Prediction & Confidence (Required for policy evaluation)
    
    /// Predicted probability of success for this recommendation (even if heuristic)
    /// Range: 0.0 to 1.0
    var predictedPSuccess: Double?
    
    /// Model confidence in the prediction (separate from p_success)
    /// Range: 0.0 to 1.0
    var modelConfidence: Double?
    
    // MARK: - Exploration (Required for off-policy learning)
    
    /// Whether this recommendation involved exploration
    var isExploration: Bool = false
    
    /// Probability of selecting this action (REQUIRED if exploring)
    /// For deterministic: 1.0. For stochastic: actual probability.
    var actionProbability: Double = 1.0
    
    /// Delta from deterministic policy (for exploration)
    var explorationDeltaLbs: Double?
    
    // MARK: - Candidate Actions (Optional but valuable)
    
    /// All actions considered and their predicted outcomes
    /// Enables counterfactual analysis and off-policy learning
    var candidateActions: [CandidateAction]?
    
    // MARK: - Counterfactual (What deterministic would have done)
    
    var deterministicWeightLbs: Double?
    var deterministicReps: Int?
    var deterministicPSuccess: Double?
    
    // MARK: - Exploration Safety Constraints
    
    /// Whether exploration was eligible (all safety checks passed)
    var explorationEligible: Bool = false
    
    /// Why exploration was blocked (if blocked)
    var explorationBlockedReason: ExplorationBlockReason?
    
    // State snapshot at recommendation time (prevents leakage)
    var stateSnapshot: LiftStateSnapshot
    
    // MARK: - Policy Selection (Bandit/Shadow Mode)
    
    /// ID of the executed policy (e.g., "baseline", "conservative", "aggressive")
    var executedPolicyId: String?
    
    /// Probability of selecting the executed action given the policy state
    var executedActionProbability: Double?
    
    /// Exploration mode: "baseline", "explore", "shadow"
    var explorationModeTag: String?
    
    /// ID of the shadow policy (if shadow mode)
    var shadowPolicyId: String?
    
    /// Probability of the shadow action
    var shadowActionProbability: Double?
    
    var generatedAt: Date = Date()
    
    // MARK: - Candidate Action
    
    struct CandidateAction: Codable {
        var weightLbs: Double
        var reps: Int
        var predictedPSuccess: Double
        var actionProbability: Double  // Probability of selection (for stochastic policies)
        var isChosen: Bool
    }
    
    enum ExplorationBlockReason: String, Codable {
        case recentFailures = "recent_failures"
        case painAboveThreshold = "pain_above_threshold"
        case lowPredictedSuccess = "low_predicted_success"
        case outsideSafeBand = "outside_safe_band"
        case userOptOut = "user_opt_out"
    }
    
    // MARK: - Nested Types
    
    enum PolicyType: String, Codable {
        case deterministic = "deterministic"
        case mlV1 = "ml_v1"
        case exploration = "exploration"
    }
    
    enum RecommendationActionType: String, Codable {
        case increaseLoad = "increase_load"
        case decreaseLoad = "decrease_load"
        case holdLoad = "hold_load"
        case increaseReps = "increase_reps"
        case decreaseReps = "decrease_reps"
        case holdReps = "hold_reps"
        case deload = "deload"
        case reset = "reset"
    }
    
    enum ReasonCode: String, Codable {
        // Success reasons
        case hitRepCeiling = "hit_rep_ceiling"
        case twoCleanSessions = "two_clean_sessions"
        case noFailures = "no_failures"
        case e1rmImproving = "e1rm_improving"
        
        // Hold reasons
        case withinRepRange = "within_rep_range"
        case recentIncrease = "recent_increase"
        case lowConfidence = "low_confidence"
        
        // Failure/deload reasons
        case hitFailureThreshold = "hit_failure_threshold"
        case highRPEStreak = "high_rpe_streak"
        case e1rmDeclining = "e1rm_declining"
        case lowReadiness = "low_readiness"
        case extendedBreak = "extended_break"
        
        // Pain/safety
        case painReported = "pain_reported"
        case safetyOverride = "safety_override"
    }
    
    /// Snapshot of lift state at the moment of recommendation
    /// CRITICAL: These values must be frozen at recommendation time to prevent leakage
    struct LiftStateSnapshot: Codable {
        // Core state
        var rollingE1rmLbs: Double?
        var rawE1rmLbs: Double?  // Last session's e1RM (unsmoothed)
        var consecutiveFailures: Int
        var consecutiveSuccesses: Int
        var highRPEStreak: Int  // Sessions where effort was higher than target
        
        // Temporal
        var daysSinceLastExposure: Int?
        var daysSinceLastDeload: Int?
        
        // Last session performance
        var lastSessionWeightLbs: Double?
        var lastSessionReps: Int?
        var lastSessionRIR: Int?
        var lastSessionOutcome: String?  // SetOutcome raw value
        
        // Volume/frequency context
        var exposuresLast14Days: Int
        var volumeLast7DaysLbs: Double?
        var avgRestDays: Double?
        
        // Counts
        var successfulSessionsCount: Int
        var totalSessionsCount: Int
        
        // Trend
        var e1rmTrend: String?
        var e1rmSlopePerWeek: Double?  // Lbs per week from linear regression
        
        // Template context (for confounder control)
        var templateVersion: Int?  // Increment when template changes
        var templateLastChangedAt: Date?
        
        init(
            rollingE1rmLbs: Double? = nil,
            rawE1rmLbs: Double? = nil,
            consecutiveFailures: Int = 0,
            consecutiveSuccesses: Int = 0,
            highRPEStreak: Int = 0,
            daysSinceLastExposure: Int? = nil,
            daysSinceLastDeload: Int? = nil,
            lastSessionWeightLbs: Double? = nil,
            lastSessionReps: Int? = nil,
            lastSessionRIR: Int? = nil,
            lastSessionOutcome: String? = nil,
            exposuresLast14Days: Int = 0,
            volumeLast7DaysLbs: Double? = nil,
            avgRestDays: Double? = nil,
            successfulSessionsCount: Int = 0,
            totalSessionsCount: Int = 0,
            e1rmTrend: String? = nil,
            e1rmSlopePerWeek: Double? = nil,
            templateVersion: Int? = nil,
            templateLastChangedAt: Date? = nil
        ) {
            self.rollingE1rmLbs = rollingE1rmLbs
            self.rawE1rmLbs = rawE1rmLbs
            self.consecutiveFailures = consecutiveFailures
            self.consecutiveSuccesses = consecutiveSuccesses
            self.highRPEStreak = highRPEStreak
            self.daysSinceLastExposure = daysSinceLastExposure
            self.daysSinceLastDeload = daysSinceLastDeload
            self.lastSessionWeightLbs = lastSessionWeightLbs
            self.lastSessionReps = lastSessionReps
            self.lastSessionRIR = lastSessionRIR
            self.lastSessionOutcome = lastSessionOutcome
            self.exposuresLast14Days = exposuresLast14Days
            self.volumeLast7DaysLbs = volumeLast7DaysLbs
            self.avgRestDays = avgRestDays
            self.successfulSessionsCount = successfulSessionsCount
            self.totalSessionsCount = totalSessionsCount
            self.e1rmTrend = e1rmTrend
            self.e1rmSlopePerWeek = e1rmSlopePerWeek
            self.templateVersion = templateVersion
            self.templateLastChangedAt = templateLastChangedAt
        }
    }
}

// MARK: - Planned Set (Immutable Prescription)

/// What was prescribed at session start. Immutable once created.
struct PlannedSet: Codable, Identifiable {
    var id: UUID = UUID()
    var sessionExerciseId: UUID
    var recommendationEventId: UUID?
    
    var setNumber: Int
    var targetWeightLbs: Double
    var targetReps: Int
    var targetRIR: Int = 2
    var targetRestSeconds: Int?
    
    // Tempo (optional)
    var targetTempo: TempoSpec?
    
    var isWarmup: Bool = false
    
    var createdAt: Date = Date()
}

// MARK: - Set Outcome (Computed Label)

/// 3-state label for training: SUCCESS, FAIL, UNKNOWN_DIFFICULTY
/// CRITICAL: Do NOT treat UNKNOWN_DIFFICULTY as success for training.
/// RIR missingness is correlated with failure risk (users skip logging when rushing/tired).
enum SetOutcome: String, Codable, Hashable {
    case success = "success"              // Hit reps AND effort confirmed acceptable
    case failure = "failure"              // Missed reps OR confirmed too hard OR is_failure flag
    case grinder = "grinder"              // Hit reps but RIR confirmed too low (still usable as weak failure signal)
    case unknownDifficulty = "unknown_difficulty"  // Hit reps but RIR missing - DO NOT USE AS CLEAN SUCCESS
    case painStop = "pain_stop"           // Stopped due to pain - exclude from training
    case skipped = "skipped"              // Did not attempt
    
    /// Whether this outcome is usable for binary success/fail training
    var isCleanLabel: Bool {
        switch self {
        case .success, .failure, .grinder:
            return true
        case .unknownDifficulty, .painStop, .skipped:
            return false  // Use as unlabeled or weak supervision only
        }
    }
    
    /// For binary classification: is this a "positive" (success) outcome?
    /// ONLY valid when isCleanLabel == true
    var isSuccess: Bool {
        self == .success
    }
    
    /// Compute outcome based on performance vs targets
    /// Returns UNKNOWN_DIFFICULTY when reps are hit but RIR is missing
    static func compute(
        repsAchieved: Int,
        targetReps: Int,
        rirObserved: Int?,
        targetRIR: Int,
        isFailure: Bool,
        painStop: Bool
    ) -> SetOutcome {
        // Pain stop - exclude from training
        if painStop {
            return .painStop
        }
        
        // Explicit failure flag
        if isFailure {
            return .failure
        }
        
        // Missed reps = definite failure
        if repsAchieved < targetReps {
            return .failure
        }
        
        // Reps achieved - now check effort
        if let rir = rirObserved {
            // RIR present - we have clean labels
            if rir < (targetRIR - 1) {
                return .grinder  // Too hard, use as failure signal
            } else {
                return .success  // Clean success
            }
        } else {
            // RIR missing - DO NOT assume success
            // This is correlated with failure risk
            return .unknownDifficulty
        }
    }
}

// MARK: - Exposure Outcome (Exercise-level label)

/// 3-state exposure outcome for training
/// UNKNOWN_DIFFICULTY exposures should NOT be used as clean success labels
enum ExposureOutcome: String, Codable, Hashable {
    case success = "success"              // All clean sets succeeded
    case partial = "partial"              // Mixed results (some success, some fail)
    case failure = "failure"              // Majority failed
    case unknownDifficulty = "unknown_difficulty"  // Hit targets but effort uncertain
    case painStop = "pain_stop"           // Stopped due to pain
    case skipped = "skipped"              // Did not perform
    
    /// Whether this outcome is usable for binary success/fail training
    var isCleanLabel: Bool {
        switch self {
        case .success, .failure:
            return true
        case .partial:
            return true  // Can use as weak failure signal
        case .unknownDifficulty, .painStop, .skipped:
            return false
        }
    }
    
    /// Compute from set outcomes
    /// Only counts sets with clean labels for success/failure determination
    static func compute(
        setOutcomes: [SetOutcome],
        stoppedDueToPain: Bool
    ) -> ExposureOutcome {
        if stoppedDueToPain {
            return .painStop
        }
        
        let cleanSets = setOutcomes.filter { $0.isCleanLabel }
        let unknownSets = setOutcomes.filter { $0 == .unknownDifficulty }
        
        // If no clean labels, check if we have unknown difficulty sets
        if cleanSets.isEmpty {
            if !unknownSets.isEmpty {
                return .unknownDifficulty
            }
            return .skipped
        }
        
        let successCount = cleanSets.filter { $0.isSuccess }.count
        let failCount = cleanSets.count - successCount
        
        // If all clean sets succeeded
        if failCount == 0 {
            // But if we also have unknown sets, mark as unknown
            if !unknownSets.isEmpty {
                return .unknownDifficulty
            }
            return .success
        }
        
        // If all clean sets failed
        if successCount == 0 {
            return .failure
        }
        
        // Mixed - count as partial (weak failure signal)
        return .partial
    }
}


// MARK: - Lift State Snapshot for Session Exercise

/// Snapshot of lift state at session start - stored on session_exercise to prevent leakage
/// CRITICAL: These values are frozen at session start and NEVER updated
struct LiftStateSessionSnapshot: Codable, Hashable {
    // Core state (same as RecommendationEvent.LiftStateSnapshot)
    var rollingE1rmLbs: Double?
    var rawE1rmLbs: Double?
    var consecutiveFailures: Int = 0
    var consecutiveSuccesses: Int = 0
    var highRPEStreak: Int = 0
    
    // Temporal
    var daysSinceLastExposure: Int?
    var daysSinceLastDeload: Int?
    
    // Last session
    var lastWeightLbs: Double?
    var lastReps: Int?
    var lastRIR: Int?
    var lastOutcome: String?
    
    // Volume context
    var exposuresLast14Days: Int = 0
    var volumeLast7DaysLbs: Double?
    
    // Counts
    var successfulSessionsCount: Int = 0
    var totalSessionsCount: Int = 0
    
    // Trend
    var e1rmTrend: String?
    
    // Template version (for confounder control)
    var templateVersion: Int?
    
    /// Create snapshot from current ExerciseState and history
    static func from(
        state: ExerciseState?,
        lastPerformance: ExercisePerformance?,
        daysSinceLast: Int?,
        daysSinceDeload: Int? = nil,
        exposuresLast14Days: Int = 0,
        volumeLast7Days: Double? = nil,
        templateVersion: Int? = nil
    ) -> LiftStateSessionSnapshot {
        var snapshot = LiftStateSessionSnapshot()
        snapshot.daysSinceLastExposure = daysSinceLast
        snapshot.daysSinceLastDeload = daysSinceDeload
        snapshot.exposuresLast14Days = exposuresLast14Days
        snapshot.volumeLast7DaysLbs = volumeLast7Days
        snapshot.templateVersion = templateVersion
        
        if let state = state {
            snapshot.rollingE1rmLbs = state.rollingE1RM
            snapshot.consecutiveFailures = state.failuresCount
            snapshot.successfulSessionsCount = state.successfulSessionsCount
            snapshot.lastWeightLbs = state.currentWorkingWeight
            snapshot.e1rmTrend = state.e1rmTrend.rawValue
            
            // Get raw e1RM from history if available
            if let lastSample = state.e1rmHistory.first {
                snapshot.rawE1rmLbs = lastSample.value
            }
        }
        
        if let lastPerf = lastPerformance {
            let workingSets = lastPerf.sets.filter { !$0.isWarmup && $0.isCompleted }
            if let topSet = workingSets.max(by: { $0.weight < $1.weight }) {
                snapshot.lastWeightLbs = topSet.weight
                snapshot.lastReps = topSet.reps
                snapshot.lastRIR = topSet.rirObserved
            }
            snapshot.lastOutcome = lastPerf.exposureOutcome?.rawValue
        }
        
        return snapshot
    }
}

// MARK: - Exposure Role Definition

/// Defines the structure of an exercise exposure for consistent modeling
enum ExposureRole: String, Codable, CaseIterable, Hashable {
    case topSetOnly = "top_set_only"      // Single heavy set (e.g., 1x5)
    case straightSets = "straight_sets"   // Multiple sets at same weight (e.g., 3x8)
    case rampUp = "ramp_up"               // Progressive warmup to top set
    case backoffSets = "backoff_sets"     // Top set + lighter backoff sets
    case pyramid = "pyramid"              // Ascending then descending
    case dropSets = "drop_sets"           // Continuous with weight drops
    
    var description: String {
        switch self {
        case .topSetOnly: return "Single top set"
        case .straightSets: return "Straight sets (same weight)"
        case .rampUp: return "Ramp to top set"
        case .backoffSets: return "Top set + backoffs"
        case .pyramid: return "Pyramid"
        case .dropSets: return "Drop sets"
        }
    }
}

// MARK: - Near-Failure Auxiliary Label

/// Auxiliary label for "too aggressive" prescriptions
/// Use when actual failures are rare for better early training
struct NearFailureSignals: Codable, Hashable {
    /// Missed target reps (definite failure indicator)
    var missedReps: Bool = false
    
    /// User toggled "last rep was a grind"
    var lastRepGrind: Bool = false
    
    /// Rest was much longer than prescribed (>150% of target)
    var unusuallyLongRest: Bool = false
    
    /// Session ended early on this exercise
    var sessionEndedEarly: Bool = false
    
    /// User reduced load on next exposure (>5% drop)
    var nextExposureLoadReduced: Bool?  // Computed later, after next session
    
    /// Composite near-failure score (0.0 to 1.0)
    var nearFailureScore: Double {
        var score = 0.0
        if missedReps { score += 0.4 }
        if lastRepGrind { score += 0.25 }
        if unusuallyLongRest { score += 0.15 }
        if sessionEndedEarly { score += 0.15 }
        if nextExposureLoadReduced == true { score += 0.3 }
        return min(1.0, score)
    }
    
    /// Whether this should be treated as "too aggressive" for training
    var isTooAggressive: Bool {
        missedReps || nearFailureScore >= 0.4
    }
}

// MARK: - Modification Details (Numeric)

/// Numeric modification tracking for learning when users override
struct ModificationDetails: Codable, Hashable {
    /// Delta from recommended weight (performed - recommended), in lbs
    var deltaWeightLbs: Double
    
    /// Delta from recommended reps (performed - recommended)
    var deltaReps: Int
    
    /// Direction of modification
    var direction: ModificationDirection
    
    /// Reason code (if provided)
    var reasonCode: ComplianceReasonCode?
    
    /// Free-form notes
    var notes: String?
    
    enum ModificationDirection: String, Codable, Hashable {
        case up = "up"        // User went heavier/more reps
        case down = "down"    // User went lighter/fewer reps
        case same = "same"    // No modification (should have is_user_modified = false)
        case mixed = "mixed"  // Weight up but reps down, or vice versa
    }
    
    /// Compute modification details from prescription vs actual
    static func compute(
        recommendedWeightLbs: Double,
        recommendedReps: Int,
        actualWeightLbs: Double,
        actualReps: Int,
        reasonCode: ComplianceReasonCode? = nil,
        notes: String? = nil
    ) -> ModificationDetails {
        let deltaWeight = actualWeightLbs - recommendedWeightLbs
        let deltaReps = actualReps - recommendedReps
        
        let direction: ModificationDirection
        if abs(deltaWeight) < 0.1 && deltaReps == 0 {
            direction = .same
        } else if deltaWeight > 0 && deltaReps >= 0 {
            direction = .up
        } else if deltaWeight < 0 && deltaReps <= 0 {
            direction = .down
        } else {
            direction = .mixed
        }
        
        return ModificationDetails(
            deltaWeightLbs: deltaWeight,
            deltaReps: deltaReps,
            direction: direction,
            reasonCode: reasonCode,
            notes: notes
        )
    }
}

// MARK: - e1RM Computation Guards

/// Guards for e1RM computation to prevent noisy estimates
struct E1RMComputationConfig {
    /// Maximum reps for e1RM calculation (Brzycki degrades above this)
    static let maxReps: Int = 12
    
    /// Minimum reps (single rep maxes are unstable)
    static let minReps: Int = 1
    
    /// Minimum intensity threshold as fraction of rolling e1RM
    /// Sets below this are too light for reliable e1RM
    static let minIntensityThreshold: Double = 0.5  // 50% of e1RM
    
    /// EMA alpha for smoothing (0.3 = recent sessions weighted more)
    static let emaAlpha: Double = 0.3
    
    /// Compute e1RM from weight and reps using Brzycki formula
    /// Returns nil if outside valid rep range or below intensity threshold
    static func computeE1RM(
        weightLbs: Double,
        reps: Int,
        currentE1rmLbs: Double? = nil,
        isFailure: Bool = false,
        isWarmup: Bool = false
    ) -> Double? {
        // Reject invalid cases
        guard !isWarmup else { return nil }
        guard !isFailure else { return nil }  // Failure sets are unreliable
        guard reps >= minReps && reps <= maxReps else { return nil }
        
        // Check intensity threshold if we have a baseline
        if let currentE1rm = currentE1rmLbs {
            let intensity = weightLbs / currentE1rm
            guard intensity >= minIntensityThreshold else { return nil }
        }
        
        // Brzycki formula
        let e1rm = weightLbs / (1.0278 - 0.0278 * Double(reps))
        return e1rm
    }
    
    /// Apply EMA smoothing to e1RM
    static func smoothE1RM(newValue: Double, previousSmoothed: Double?) -> Double {
        guard let prev = previousSmoothed else { return newValue }
        return emaAlpha * newValue + (1 - emaAlpha) * prev
    }
}

// MARK: - Exploration Policy Constraints

/// Constraints for safe exploration
struct ExplorationPolicy {
    /// Minimum exploration band (percentage of deterministic)
    static let minBandPercent: Double = 0.0  // Can't go below deterministic
    
    /// Maximum exploration band (percentage of deterministic)
    static let maxBandPercent: Double = 0.05  // Max +5%
    
    /// Maximum pain level for exploration eligibility
    static let maxPainForExploration: Int = 3
    
    /// Minimum predicted p_success for exploration
    static let minPSuccessForExploration: Double = 0.6
    
    /// Maximum consecutive failures for exploration eligibility
    static let maxFailuresForExploration: Int = 1
    
    /// Check if exploration is eligible given current state
    static func isExplorationEligible(
        predictedPSuccess: Double,
        recentPainLevel: Int?,
        consecutiveFailures: Int,
        userOptedIn: Bool = true
    ) -> (eligible: Bool, blockReason: RecommendationEvent.ExplorationBlockReason?) {
        guard userOptedIn else {
            return (false, .userOptOut)
        }
        
        if let pain = recentPainLevel, pain > maxPainForExploration {
            return (false, .painAboveThreshold)
        }
        
        if consecutiveFailures > maxFailuresForExploration {
            return (false, .recentFailures)
        }
        
        if predictedPSuccess < minPSuccessForExploration {
            return (false, .lowPredictedSuccess)
        }
        
        return (true, nil)
    }
    
    /// Generate exploration delta within safe band
    static func generateExplorationDelta(
        deterministicWeightLbs: Double,
        random: Double  // 0.0 to 1.0
    ) -> Double {
        let maxDelta = deterministicWeightLbs * maxBandPercent
        return random * maxDelta  // Always positive (never below deterministic)
    }
}

// MARK: - Pain Event (Normalized)

/// Normalized pain tracking - one row per pain report
struct PainEvent: Codable, Identifiable {
    var id: UUID = UUID()
    var sessionId: UUID?
    var sessionExerciseId: UUID?
    var sessionSetId: UUID?
    
    var bodyRegion: BodyRegion
    var severity: Int // 0-10
    var painType: PainType?
    var causedStop: Bool = false
    var notes: String?
    
    var reportedAt: Date = Date()
    
    enum PainType: String, Codable {
        case sharp = "sharp"
        case dull = "dull"
        case burning = "burning"
        case aching = "aching"
        case other = "other"
    }
    
    init(id: UUID = UUID(), sessionId: UUID? = nil, sessionExerciseId: UUID? = nil,
         sessionSetId: UUID? = nil, bodyRegion: BodyRegion, severity: Int,
         painType: PainType? = nil, causedStop: Bool = false, notes: String? = nil,
         reportedAt: Date = Date()) {
        self.id = id
        self.sessionId = sessionId
        self.sessionExerciseId = sessionExerciseId
        self.sessionSetId = sessionSetId
        self.bodyRegion = bodyRegion
        self.severity = max(0, min(10, severity))
        self.painType = painType
        self.causedStop = causedStop
        self.notes = notes
        self.reportedAt = reportedAt
    }
}

// MARK: - User Sensitive Context (Opt-in)

/// Sensitive user data stored separately with explicit consent
struct UserSensitiveContext: Codable {
    var date: Date
    
    // Menstrual cycle (opt-in)
    var cyclePhase: CyclePhase?
    var cycleDayNumber: Int?
    var onHormonalBirthControl: Bool?
    
    // Nutrition (opt-in)
    var nutritionBucket: NutritionBucket?
    var proteinBucket: ProteinBucket?
    
    // Mood/stress (opt-in)
    var moodScore: Int?  // 1-5
    var stressLevel: Int?  // 1-5
    
    // Consent tracking
    var consentedToMLTraining: Bool = false
    var consentTimestamp: Date?
}
