// ProgressionDirection.swift
// Direction-first progression decision system.
//
// This separates "what direction should load go?" from "by how much?"
// to improve deload timing, plateau detection, and overall accuracy.

import Foundation

// MARK: - Decision Trace (Interpretability)

/// Complete trace of all factors that influenced a progression decision.
/// Used for debugging, testing, and understanding why the engine made a particular choice.
public struct DecisionTrace: Codable, Sendable, Hashable {
    /// The exercise this decision is for.
    public let exerciseId: String
    
    /// The final direction decision.
    public let direction: ProgressionDirection
    
    /// Primary reason for the decision.
    public let primaryReason: DirectionReason
    
    /// All contributing reasons.
    public let contributingReasons: [DirectionReason]
    
    /// Human-readable explanation.
    public let explanation: String
    
    /// Confidence score (0-1).
    public let confidence: Double
    
    // MARK: - Input Signals (what the policy saw)
    
    /// Today's readiness score.
    public let inputReadiness: Int
    
    /// Failure streak count.
    public let inputFailStreak: Int
    
    /// High RPE (grinder) streak count.
    public let inputHighRpeStreak: Int
    
    /// Success streak count.
    public let inputSuccessStreak: Int
    
    /// Days since last exposure (nil if never exposed).
    public let inputDaysSinceExposure: Int?
    
    /// Whether the last session was a failure.
    public let inputLastSessionWasFailure: Bool
    
    /// Whether the last session was a grinder.
    public let inputLastSessionWasGrinder: Bool
    
    /// Average observed RIR from last session (nil if not recorded).
    public let inputLastSessionAvgRIR: Double?
    
    /// Reps achieved in last session.
    public let inputLastSessionReps: [Int]
    
    /// Target RIR from prescription.
    public let inputTargetRIR: Int
    
    /// Target rep range from prescription.
    public let inputTargetRepRange: ClosedRange<Int>
    
    /// Load strategy (absolute, %e1RM, etc.).
    public let inputLoadStrategy: String
    
    /// Last working weight (lb).
    public let inputLastWorkingWeightLb: Double
    
    /// Rolling E1RM estimate.
    public let inputRollingE1RM: Double
    
    /// Whether session-level deload was triggered.
    public let inputSessionDeloadTriggered: Bool
    
    /// Session deload reason if any.
    public let inputSessionDeloadReason: String?
    
    /// Experience level.
    public let inputExperienceLevel: String
    
    // MARK: - Policy Checks (what rules were evaluated)
    
    /// Ordered list of policy checks performed and their results.
    public let policyChecks: [PolicyCheckResult]
    
    // MARK: - Output (what was decided)
    
    /// Baseline load before direction/magnitude (lb).
    public let outputBaselineLoadLb: Double
    
    /// Final prescribed load (lb).
    public let outputFinalLoadLb: Double
    
    /// Load multiplier applied.
    public let outputLoadMultiplier: Double
    
    /// Absolute increment applied (lb).
    public let outputAbsoluteIncrementLb: Double
    
    /// Volume adjustment (sets added/removed).
    public let outputVolumeAdjustment: Int
    
    public init(
        exerciseId: String,
        direction: ProgressionDirection,
        primaryReason: DirectionReason,
        contributingReasons: [DirectionReason] = [],
        explanation: String,
        confidence: Double,
        inputReadiness: Int,
        inputFailStreak: Int,
        inputHighRpeStreak: Int,
        inputSuccessStreak: Int,
        inputDaysSinceExposure: Int?,
        inputLastSessionWasFailure: Bool,
        inputLastSessionWasGrinder: Bool,
        inputLastSessionAvgRIR: Double?,
        inputLastSessionReps: [Int],
        inputTargetRIR: Int,
        inputTargetRepRange: ClosedRange<Int>,
        inputLoadStrategy: String,
        inputLastWorkingWeightLb: Double,
        inputRollingE1RM: Double,
        inputSessionDeloadTriggered: Bool,
        inputSessionDeloadReason: String?,
        inputExperienceLevel: String,
        policyChecks: [PolicyCheckResult],
        outputBaselineLoadLb: Double,
        outputFinalLoadLb: Double,
        outputLoadMultiplier: Double,
        outputAbsoluteIncrementLb: Double,
        outputVolumeAdjustment: Int
    ) {
        self.exerciseId = exerciseId
        self.direction = direction
        self.primaryReason = primaryReason
        self.contributingReasons = contributingReasons
        self.explanation = explanation
        self.confidence = confidence
        self.inputReadiness = inputReadiness
        self.inputFailStreak = inputFailStreak
        self.inputHighRpeStreak = inputHighRpeStreak
        self.inputSuccessStreak = inputSuccessStreak
        self.inputDaysSinceExposure = inputDaysSinceExposure
        self.inputLastSessionWasFailure = inputLastSessionWasFailure
        self.inputLastSessionWasGrinder = inputLastSessionWasGrinder
        self.inputLastSessionAvgRIR = inputLastSessionAvgRIR
        self.inputLastSessionReps = inputLastSessionReps
        self.inputTargetRIR = inputTargetRIR
        self.inputTargetRepRange = inputTargetRepRange
        self.inputLoadStrategy = inputLoadStrategy
        self.inputLastWorkingWeightLb = inputLastWorkingWeightLb
        self.inputRollingE1RM = inputRollingE1RM
        self.inputSessionDeloadTriggered = inputSessionDeloadTriggered
        self.inputSessionDeloadReason = inputSessionDeloadReason
        self.inputExperienceLevel = inputExperienceLevel
        self.policyChecks = policyChecks
        self.outputBaselineLoadLb = outputBaselineLoadLb
        self.outputFinalLoadLb = outputFinalLoadLb
        self.outputLoadMultiplier = outputLoadMultiplier
        self.outputAbsoluteIncrementLb = outputAbsoluteIncrementLb
        self.outputVolumeAdjustment = outputVolumeAdjustment
    }
    
    /// Compact single-line summary for logging.
    public var summary: String {
        let readyFlag = inputReadiness < 50 ? "LOW" : (inputReadiness >= 75 ? "GOOD" : "OK")
        let streaks = "fail=\(inputFailStreak) grind=\(inputHighRpeStreak) succ=\(inputSuccessStreak)"
        let load = "base=\(String(format: "%.1f", outputBaselineLoadLb)) final=\(String(format: "%.1f", outputFinalLoadLb))"
        return "\(exerciseId): \(direction.rawValue)(\(primaryReason.rawValue)) ready=\(inputReadiness)(\(readyFlag)) \(streaks) \(load)"
    }
}

/// Result of a single policy check.
public struct PolicyCheckResult: Codable, Sendable, Hashable {
    /// Name of the policy check (e.g., "session_deload", "extended_break", "fail_streak").
    public let checkName: String
    
    /// Whether this check triggered.
    public let triggered: Bool
    
    /// The threshold or condition evaluated.
    public let condition: String
    
    /// The actual value observed.
    public let observed: String
    
    /// Direction this check would produce if triggered.
    public let wouldProduce: ProgressionDirection?
    
    public init(
        checkName: String,
        triggered: Bool,
        condition: String,
        observed: String,
        wouldProduce: ProgressionDirection? = nil
    ) {
        self.checkName = checkName
        self.triggered = triggered
        self.condition = condition
        self.observed = observed
        self.wouldProduce = wouldProduce
    }
}

// MARK: - Direction Decision

/// The direction of load change for a lift.
public enum ProgressionDirection: String, Codable, Sendable, Hashable {
    /// Increase load (normal progression).
    case increase = "increase"
    
    /// Hold load at current level (grinder, consolidation, or low confidence).
    case hold = "hold"
    
    /// Small temporary reduction for acute low readiness (not a true deload).
    case decreaseSlightly = "decrease_slightly"
    
    /// True deload: meaningful reduction with fatigue reset intent.
    case deload = "deload"
    
    /// Reset after extended break: conservative re-entry with ramp-back.
    case resetAfterBreak = "reset_after_break"
}

/// Reason why a particular direction was chosen.
public enum DirectionReason: String, Codable, Sendable, Hashable {
    // Increase reasons
    case successfulProgression = "successful_progression"
    case allRepsAtTop = "all_reps_at_top"
    
    // Hold reasons
    case grinderSuccess = "grinder_success"
    case consolidating = "consolidating"
    case insufficientData = "insufficient_data"
    case acuteLowReadinessSingleDay = "acute_low_readiness_single_day"
    case recentMiss = "recent_miss"
    
    // Decrease slightly reasons
    case lowReadinessAcute = "low_readiness_acute"
    case minorFatigueSignal = "minor_fatigue_signal"
    
    // Deload reasons
    case scheduledDeload = "scheduled_deload"
    case failStreakThreshold = "fail_streak_threshold"
    case highRpeStreakThreshold = "high_rpe_streak_threshold"
    case persistentLowReadiness = "persistent_low_readiness"
    case performanceDecline = "performance_decline"
    case accumulatedFatigue = "accumulated_fatigue"
    case plateauDetected = "plateau_detected"
    
    // Reset reasons
    case extendedBreak = "extended_break"
    case longHiatus = "long_hiatus"
    case postInjuryReturn = "post_injury_return"
}

/// Complete decision about progression direction for a lift.
public struct DirectionDecision: Codable, Sendable, Hashable {
    /// The chosen direction.
    public let direction: ProgressionDirection
    
    /// Primary reason for the decision.
    public let primaryReason: DirectionReason
    
    /// Additional contributing reasons (for transparency/debugging).
    public let contributingReasons: [DirectionReason]
    
    /// Human-readable explanation.
    public let explanation: String
    
    /// Confidence in this decision (0-1). Lower confidence may warrant more conservative magnitude.
    public let confidence: Double
    
    public init(
        direction: ProgressionDirection,
        primaryReason: DirectionReason,
        contributingReasons: [DirectionReason] = [],
        explanation: String,
        confidence: Double = 1.0
    ) {
        self.direction = direction
        self.primaryReason = primaryReason
        self.contributingReasons = contributingReasons
        self.explanation = explanation
        self.confidence = max(0, min(1, confidence))
    }
    
    /// Default "increase" decision for normal progression.
    public static func increase(reason: DirectionReason = .successfulProgression, explanation: String = "Normal progression") -> DirectionDecision {
        DirectionDecision(direction: .increase, primaryReason: reason, explanation: explanation)
    }
    
    /// Default "hold" decision.
    public static func hold(reason: DirectionReason, explanation: String) -> DirectionDecision {
        DirectionDecision(direction: .hold, primaryReason: reason, explanation: explanation)
    }
    
    /// Default "deload" decision.
    public static func deload(reason: DirectionReason, explanation: String) -> DirectionDecision {
        DirectionDecision(direction: .deload, primaryReason: reason, explanation: explanation)
    }
}

// MARK: - Lift Signals

/// Aggregated signals for a single lift used to determine progression direction.
/// Computed from `WorkoutHistory`, `LiftState`, and current session context.
public struct LiftSignals: Sendable {
    /// Exercise identifier.
    public let exerciseId: String
    
    /// Movement pattern (for policy selection).
    public let movementPattern: MovementPattern
    
    /// Equipment type (for rounding/increment selection).
    public let equipment: Equipment
    
    // MARK: - State signals
    
    /// Current working weight baseline.
    public let lastWorkingWeight: Load
    
    /// Rolling estimated 1RM.
    public let rollingE1RM: Double
    
    /// Consecutive session failures (reps below lower bound).
    public let failStreak: Int
    
    /// Consecutive sessions with grinder success (RIR below target).
    public let highRpeStreak: Int
    
    /// Days since last exposure to this lift.
    public let daysSinceLastExposure: Int?
    
    /// Days since last deload for this lift.
    public let daysSinceDeload: Int?
    
    /// Current performance trend.
    public let trend: PerformanceTrend
    
    /// Total successful sessions count (for plateau detection).
    public let successfulSessionsCount: Int
    
    /// Consecutive clean success sessions (no failure, no grinder).
    /// Used for fixed-rep progression gating.
    public let successStreak: Int
    
    // MARK: - Recent session signals
    
    /// Whether last session was a failure (any set below lower bound).
    public let lastSessionWasFailure: Bool
    
    /// Whether last session was a grinder (success but RIR below target).
    public let lastSessionWasGrinder: Bool
    
    /// Average observed RIR from last session (nil if not recorded).
    public let lastSessionAvgRIR: Double?
    
    /// Reps achieved in last session (working sets).
    public let lastSessionReps: [Int]
    
    // MARK: - Readiness signals
    
    /// Today's readiness score.
    public let todayReadiness: Int
    
    /// Recent readiness scores for this lift's exposures (most recent first, bounded).
    public let recentReadinessScores: [Int]
    
    /// Average readiness over recent exposures.
    public var averageRecentReadiness: Double? {
        guard !recentReadinessScores.isEmpty else { return nil }
        return Double(recentReadinessScores.reduce(0, +)) / Double(recentReadinessScores.count)
    }
    
    /// Count of recent low-readiness exposures (below threshold).
    public func lowReadinessCount(threshold: Int) -> Int {
        recentReadinessScores.filter { $0 < threshold }.count
    }
    
    // MARK: - Session context
    
    /// Target prescription for this exercise.
    public let prescription: SetPrescription
    
    /// User's experience level.
    public let experienceLevel: ExperienceLevel
    
    /// User's body weight (for relative strength calculations).
    public let bodyWeight: Load?
    
    /// Whether a session-level deload was already triggered (scheduled, systemic).
    public let sessionDeloadTriggered: Bool
    
    /// Session deload reason (if any).
    public let sessionDeloadReason: DeloadReason?
    
    /// Session intent (heavy/volume/light/general) for DUP-aware progression.
    public let sessionIntent: SessionIntent
    
    // MARK: - Derived properties
    
    /// Relative strength (e1RM / bodyweight) if available.
    public var relativeStrength: Double? {
        guard let bw = bodyWeight?.converted(to: lastWorkingWeight.unit).value, bw > 0, rollingE1RM > 0 else {
            return nil
        }
        return rollingE1RM / bw
    }
    
    /// Whether this is a compound movement.
    public var isCompound: Bool {
        movementPattern.isCompound
    }
    
    /// Whether this is an upper body pressing movement (for microloading).
    public var isUpperBodyPress: Bool {
        movementPattern == .horizontalPush || movementPattern == .verticalPush
    }
    
    /// Whether there's a meaningful gap since last exposure (potential detraining).
    public var hasTrainingGap: Bool {
        guard let days = daysSinceLastExposure else { return false }
        return days > 7
    }
    
    /// Whether there's an extended break (>14 days).
    public var hasExtendedBreak: Bool {
        guard let days = daysSinceLastExposure else { return false }
        return days >= 14
    }
    
    public init(
        exerciseId: String,
        movementPattern: MovementPattern,
        equipment: Equipment,
        lastWorkingWeight: Load,
        rollingE1RM: Double,
        failStreak: Int,
        highRpeStreak: Int,
        daysSinceLastExposure: Int?,
        daysSinceDeload: Int?,
        trend: PerformanceTrend,
        successfulSessionsCount: Int,
        successStreak: Int = 0,
        lastSessionWasFailure: Bool,
        lastSessionWasGrinder: Bool,
        lastSessionAvgRIR: Double?,
        lastSessionReps: [Int],
        todayReadiness: Int,
        recentReadinessScores: [Int],
        prescription: SetPrescription,
        experienceLevel: ExperienceLevel,
        bodyWeight: Load?,
        sessionDeloadTriggered: Bool,
        sessionDeloadReason: DeloadReason?,
        sessionIntent: SessionIntent = .general
    ) {
        self.exerciseId = exerciseId
        self.movementPattern = movementPattern
        self.equipment = equipment
        self.lastWorkingWeight = lastWorkingWeight
        self.rollingE1RM = rollingE1RM
        self.failStreak = failStreak
        self.highRpeStreak = highRpeStreak
        self.daysSinceLastExposure = daysSinceLastExposure
        self.daysSinceDeload = daysSinceDeload
        self.trend = trend
        self.successfulSessionsCount = successfulSessionsCount
        self.successStreak = successStreak
        self.lastSessionWasFailure = lastSessionWasFailure
        self.lastSessionWasGrinder = lastSessionWasGrinder
        self.lastSessionAvgRIR = lastSessionAvgRIR
        self.lastSessionReps = lastSessionReps
        self.todayReadiness = todayReadiness
        self.recentReadinessScores = recentReadinessScores
        self.prescription = prescription
        self.experienceLevel = experienceLevel
        self.bodyWeight = bodyWeight
        self.sessionDeloadTriggered = sessionDeloadTriggered
        self.sessionDeloadReason = sessionDeloadReason
        self.sessionIntent = sessionIntent
    }
}

// MARK: - Direction Policy

/// Policy for determining progression direction based on lift signals.
public enum DirectionPolicy {
    
    /// Determines the progression direction for a lift based on its signals.
    ///
    /// Priority order (highest to lowest):
    /// 1. Session-level deload (scheduled, systemic triggers)
    /// 2. Extended break reset (>14 days since last exposure)
    /// 3. Lift-level deload (fail streak, high RPE streak, persistent low readiness)
    /// 4. Training gap reset (8-14 days)
    /// 5. Acute low readiness with %1RM program (small decrease for readiness adjustment)
    /// 6. Acute low readiness (single day)
    /// 7. Grinder hold (success but too hard)
    /// 8. Normal progression (increase or hold based on last session)
    public static func decide(
        signals: LiftSignals,
        config: DirectionPolicyConfig = .default
    ) -> DirectionDecision {
        decideWithTrace(signals: signals, config: config).decision
    }
    
    /// Determines progression direction and returns a full trace for debugging.
    public static func decideWithTrace(
        signals: LiftSignals,
        config: DirectionPolicyConfig = .default
    ) -> (decision: DirectionDecision, checks: [PolicyCheckResult]) {
        var checks: [PolicyCheckResult] = []
        
        // 1) Session-level deload takes precedence
        let sessionDeloadCheck = PolicyCheckResult(
            checkName: "session_deload",
            triggered: signals.sessionDeloadTriggered,
            condition: "sessionDeloadTriggered == true",
            observed: "\(signals.sessionDeloadTriggered)",
            wouldProduce: .deload
        )
        checks.append(sessionDeloadCheck)
        
        if signals.sessionDeloadTriggered {
            let reason: DirectionReason = {
                switch signals.sessionDeloadReason {
                case .scheduledDeload: return .scheduledDeload
                case .performanceDecline: return .performanceDecline
                case .lowReadiness: return .persistentLowReadiness
                case .highAccumulatedFatigue: return .accumulatedFatigue
                default: return .scheduledDeload
                }
            }()
            return (DirectionDecision(
                direction: .deload,
                primaryReason: reason,
                explanation: "Session-level deload triggered: \(signals.sessionDeloadReason?.rawValue ?? "unknown")"
            ), checks)
        }
        
        // 2) Extended break reset (>14 days)
        let extendedBreakTriggered = (signals.daysSinceLastExposure ?? 0) >= config.extendedBreakDays
        let extendedBreakCheck = PolicyCheckResult(
            checkName: "extended_break",
            triggered: extendedBreakTriggered,
            condition: "daysSinceExposure >= \(config.extendedBreakDays)",
            observed: "\(signals.daysSinceLastExposure ?? 0)",
            wouldProduce: .resetAfterBreak
        )
        checks.append(extendedBreakCheck)
        
        if let days = signals.daysSinceLastExposure, days >= config.extendedBreakDays {
            return (DirectionDecision(
                direction: .resetAfterBreak,
                primaryReason: .extendedBreak,
                explanation: "Extended break (\(days) days since last exposure). Reset with conservative load."
            ), checks)
        }
        
        // 3) Lift-level deload triggers - COMPOSITE APPROACH (2-of-N)
        let failThreshold = config.failStreakThreshold(for: signals.experienceLevel)
        let rpeThreshold = config.highRpeStreakThreshold(for: signals.experienceLevel, intent: signals.sessionIntent)
        let lowReadinessCount = signals.lowReadinessCount(threshold: config.readinessThreshold)
        
        var deloadSignals: [(reason: DirectionReason, weight: Int)] = []
        var deloadExplanations: [String] = []
        
        let failStreakTriggered = signals.failStreak >= failThreshold
        let failStreakCheck = PolicyCheckResult(
            checkName: "fail_streak",
            triggered: failStreakTriggered,
            condition: "failStreak >= \(failThreshold)",
            observed: "\(signals.failStreak)",
            wouldProduce: .deload
        )
        checks.append(failStreakCheck)
        
        if failStreakTriggered {
            deloadSignals.append((.failStreakThreshold, 2))
            deloadExplanations.append("failed \(signals.failStreak)x")
        }
        
        let rpeStreakTriggered = signals.highRpeStreak >= rpeThreshold
        let rpeStreakCheck = PolicyCheckResult(
            checkName: "high_rpe_streak",
            triggered: rpeStreakTriggered,
            condition: "highRpeStreak >= \(rpeThreshold)",
            observed: "\(signals.highRpeStreak)",
            wouldProduce: .deload
        )
        checks.append(rpeStreakCheck)
        
        if rpeStreakTriggered {
            deloadSignals.append((.highRpeStreakThreshold, 1))
            deloadExplanations.append("grinders \(signals.highRpeStreak)x")
        }
        
        let persistentLowReadinessTriggered = lowReadinessCount >= config.persistentLowReadinessExposures
        let persistentLowReadinessCheck = PolicyCheckResult(
            checkName: "persistent_low_readiness",
            triggered: persistentLowReadinessTriggered,
            condition: "lowReadinessCount >= \(config.persistentLowReadinessExposures)",
            observed: "\(lowReadinessCount)",
            wouldProduce: .deload
        )
        checks.append(persistentLowReadinessCheck)
        
        if persistentLowReadinessTriggered {
            deloadSignals.append((.persistentLowReadiness, 1))
            deloadExplanations.append("low readiness \(lowReadinessCount)x")
        }
        
        let performanceDeclineTriggered = signals.trend == .declining && signals.successfulSessionsCount >= 8
        let performanceDeclineCheck = PolicyCheckResult(
            checkName: "performance_decline",
            triggered: performanceDeclineTriggered,
            condition: "trend == declining AND successfulSessions >= 8",
            observed: "trend=\(signals.trend.rawValue) sessions=\(signals.successfulSessionsCount)",
            wouldProduce: .deload
        )
        checks.append(performanceDeclineCheck)
        
        if performanceDeclineTriggered {
            deloadSignals.append((.performanceDecline, 1))
            deloadExplanations.append("declining trend")
        }
        
        let totalDeloadWeight = deloadSignals.reduce(0) { $0 + $1.weight }
        let compositeDeloadTriggered = totalDeloadWeight >= 2
        let compositeDeloadCheck = PolicyCheckResult(
            checkName: "composite_deload",
            triggered: compositeDeloadTriggered,
            condition: "totalDeloadWeight >= 2",
            observed: "weight=\(totalDeloadWeight) signals=\(deloadSignals.count)",
            wouldProduce: .deload
        )
        checks.append(compositeDeloadCheck)
        
        if compositeDeloadTriggered {
            let primaryReason = deloadSignals.max(by: { $0.weight < $1.weight })?.reason ?? .accumulatedFatigue
            let contributingReasons = deloadSignals.filter { $0.reason != primaryReason }.map { $0.reason }
            
            return (DirectionDecision(
                direction: .deload,
                primaryReason: primaryReason,
                contributingReasons: contributingReasons,
                explanation: "Deload triggered: \(deloadExplanations.joined(separator: ", "))."
            ), checks)
        }
        
        // 4) Training gap reset (8-14 days)
        let trainingGapTriggered = (signals.daysSinceLastExposure ?? 0) >= config.trainingGapDays && 
                                   (signals.daysSinceLastExposure ?? 0) < config.extendedBreakDays
        let trainingGapCheck = PolicyCheckResult(
            checkName: "training_gap",
            triggered: trainingGapTriggered,
            condition: "daysSinceExposure in [\(config.trainingGapDays), \(config.extendedBreakDays))",
            observed: "\(signals.daysSinceLastExposure ?? 0)",
            wouldProduce: .resetAfterBreak
        )
        checks.append(trainingGapCheck)
        
        if let days = signals.daysSinceLastExposure, days >= config.trainingGapDays && days < config.extendedBreakDays {
            return (DirectionDecision(
                direction: .resetAfterBreak,
                primaryReason: .extendedBreak,
                explanation: "Training gap (\(days) days). Conservative reset."
            ), checks)
        }
        
        // 5) Acute low readiness (single day, but not persistent)
        // 
        // Dataset alignment: The dataset uses a higher threshold for "low readiness" (~70) and
        // expects small decreases even for moderately low readiness. We use a tiered approach:
        // - Severe low (<= 40): decrease_slightly
        // - Moderate low (41-65): decrease_slightly for intermediate+, hold for beginners
        // - Borderline (66-69): hold (let other factors decide)
        //
        // Cold start handling: When we have no prior session data and readiness is <= 65,
        // apply decrease_slightly to match the dataset's %1RM + readiness adjustment model.
        let moderateLowReadinessThreshold = 65 // Matches dataset's "low" readiness flag range
        let isModeratelyLowReadiness = signals.todayReadiness <= moderateLowReadinessThreshold && 
                                       lowReadinessCount < config.persistentLowReadinessExposures
        let isSevereLowReadiness = signals.todayReadiness < config.severeLowReadinessThreshold
        let isColdStart = signals.lastSessionReps.isEmpty
        
        let acuteLowReadinessCheck = PolicyCheckResult(
            checkName: "acute_low_readiness",
            triggered: isModeratelyLowReadiness,
            condition: "readiness <= \(moderateLowReadinessThreshold) AND lowReadinessCount < \(config.persistentLowReadinessExposures)",
            observed: "readiness=\(signals.todayReadiness) count=\(lowReadinessCount) cold=\(isColdStart)",
            wouldProduce: .decreaseSlightly
        )
        checks.append(acuteLowReadinessCheck)
        
        if isModeratelyLowReadiness {
            // For low readiness (65 or below): apply decrease_slightly for better alignment with
            // %1RM program expectations. The dataset expects readiness adjustments to loads.
            //
            // Decision matrix:
            // - Severe low (< 40): always decrease_slightly 
            // - Cold start + low: decrease_slightly (no history to build on)
            // - Moderately low (40-60) with history: decrease_slightly (dataset expects adjustment)
            // - Borderline low (61-65): hold for beginners, decrease_slightly for others
            let shouldDecrease = isSevereLowReadiness || 
                                 isColdStart || 
                                 signals.todayReadiness <= 60 ||
                                 (signals.experienceLevel != .beginner)
            
            if shouldDecrease {
                return (DirectionDecision(
                    direction: .decreaseSlightly,
                    primaryReason: .lowReadinessAcute,
                    explanation: isColdStart 
                        ? "Cold start with low readiness (\(signals.todayReadiness)). Small reduction from baseline."
                        : "Acute low readiness (\(signals.todayReadiness)). Small temporary reduction."
                ), checks)
            } else {
                return (DirectionDecision(
                    direction: .hold,
                    primaryReason: .acuteLowReadinessSingleDay,
                    explanation: "Borderline low readiness today (\(signals.todayReadiness)). Hold weight."
                ), checks)
            }
        }
        
        // 6) Grinder (last session was a grinder - success but too hard)
        let isGrinder = signals.lastSessionWasGrinder && !signals.lastSessionWasFailure
        let grinderCheck = PolicyCheckResult(
            checkName: "grinder",
            triggered: isGrinder,
            condition: "lastSessionWasGrinder AND NOT lastSessionWasFailure",
            observed: "grinder=\(signals.lastSessionWasGrinder) failure=\(signals.lastSessionWasFailure)",
            wouldProduce: signals.experienceLevel == .beginner ? .hold : .decreaseSlightly
        )
        checks.append(grinderCheck)
        
        if isGrinder {
            if signals.experienceLevel == .beginner {
                return (DirectionDecision(
                    direction: .hold,
                    primaryReason: .grinderSuccess,
                    explanation: "Last session was a grinder (success but harder than target). Hold weight to consolidate."
                ), checks)
            }
            
            if signals.sessionIntent == .volume && signals.highRpeStreak < 2 {
                return (DirectionDecision(
                    direction: .hold,
                    primaryReason: .grinderSuccess,
                    explanation: "Volume day grinder (success but harder than target). Hold to consolidate."
                ), checks)
            }
            
            return (DirectionDecision(
                direction: .decreaseSlightly,
                primaryReason: .minorFatigueSignal,
                explanation: "Last session was a grinder (success but harder than target). Small decrease to consolidate."
            ), checks)
        }
        
        // 7) Recent miss (single failure, not yet a streak)
        let isRecentMiss = signals.lastSessionWasFailure && signals.failStreak < failThreshold
        let recentMissCheck = PolicyCheckResult(
            checkName: "recent_miss",
            triggered: isRecentMiss,
            condition: "lastSessionWasFailure AND failStreak < \(failThreshold)",
            observed: "failure=\(signals.lastSessionWasFailure) streak=\(signals.failStreak)",
            wouldProduce: signals.experienceLevel != .beginner ? .decreaseSlightly : .hold
        )
        checks.append(recentMissCheck)
        
        if isRecentMiss {
            if signals.experienceLevel != .beginner {
                return (DirectionDecision(
                    direction: .decreaseSlightly,
                    primaryReason: .minorFatigueSignal,
                    explanation: "Missed reps last session. Small decrease (~2.5-5%) to recalibrate."
                ), checks)
            } else {
                return (DirectionDecision(
                    direction: .hold,
                    primaryReason: .recentMiss,
                    explanation: "Missed reps last session. Hold weight to retry."
                ), checks)
            }
        }
        
        // 8) Normal progression - GATED BY EFFORT AND SUCCESS STREAK
        let repRange = signals.prescription.targetRepsRange
        let isFixedRepRange = repRange.lowerBound == repRange.upperBound
        let allAtTop = !signals.lastSessionReps.isEmpty && signals.lastSessionReps.allSatisfy { $0 >= repRange.upperBound }
        let allInRange = !signals.lastSessionReps.isEmpty && signals.lastSessionReps.allSatisfy { $0 >= repRange.lowerBound }
        
        let targetRIR = signals.prescription.targetRIR
        let observedRIR = signals.lastSessionAvgRIR
        let rirMargin: Double = {
            switch signals.sessionIntent {
            case .heavy: return 1.5
            case .volume: return 0.5
            case .light, .general: return 1.0
            }
        }()
        
        let hasRIRData = observedRIR != nil
        let sessionWasEasyByRIR = observedRIR.map { $0 >= Double(targetRIR) + rirMargin } ?? false
        let sessionWasHarderThanTarget = observedRIR.map { $0 < Double(targetRIR) } ?? false
        
        let successStreakThreshold: Int = {
            switch signals.experienceLevel {
            case .beginner: return 1
            case .intermediate: return 2
            case .advanced, .elite: return 3
            }
        }()
        let hasSuccessStreak = signals.successStreak >= successStreakThreshold
        
        // Insufficient data or first exposure
        // NOTE: Cold starts with low readiness are handled earlier (in acute_low_readiness check)
        // This branch only triggers for cold starts with good readiness.
        let hasNoData = signals.lastSessionReps.isEmpty
        let noDataCheck = PolicyCheckResult(
            checkName: "insufficient_data",
            triggered: hasNoData,
            condition: "lastSessionReps.isEmpty",
            observed: "reps=\(signals.lastSessionReps)",
            wouldProduce: .hold
        )
        checks.append(noDataCheck)
        
        if hasNoData {
            // Even with good readiness, cold starts should be conservative
            // Return hold to use the baseline estimate without increase
            return (DirectionDecision(
                direction: .hold,
                primaryReason: .insufficientData,
                explanation: "No prior session data. Maintain baseline load.",
                confidence: 0.7
            ), checks)
        }
        
        // RIR-based effort check
        let harderThanTargetCheck = PolicyCheckResult(
            checkName: "harder_than_target_rir",
            triggered: sessionWasHarderThanTarget && allInRange,
            condition: "observedRIR < targetRIR AND allInRange",
            observed: "observedRIR=\(observedRIR.map { String(format: "%.1f", $0) } ?? "nil") target=\(targetRIR)",
            wouldProduce: .hold
        )
        checks.append(harderThanTargetCheck)
        
        if sessionWasHarderThanTarget && allInRange {
            let rirShortfall = Double(targetRIR) - (observedRIR ?? Double(targetRIR))
            if signals.sessionIntent == .heavy || rirShortfall >= 1.0 {
                return (DirectionDecision(
                    direction: .hold,
                    primaryReason: .consolidating,
                    explanation: "RIR indicates harder-than-target effort (observed \(String(format: "%.1f", observedRIR ?? 0)) vs target \(targetRIR)). Hold to consolidate."
                ), checks)
            }
        }
        
        // All reps at top (variable rep range)
        let allAtTopCheck = PolicyCheckResult(
            checkName: "all_at_top",
            triggered: allAtTop && !isFixedRepRange,
            condition: "allAtTop AND NOT fixedRepRange",
            observed: "allAtTop=\(allAtTop) fixed=\(isFixedRepRange) reps=\(signals.lastSessionReps)",
            wouldProduce: sessionWasHarderThanTarget ? .hold : .increase
        )
        checks.append(allAtTopCheck)
        
        if allAtTop && !isFixedRepRange {
            if sessionWasHarderThanTarget {
                return (DirectionDecision(
                    direction: .hold,
                    primaryReason: .consolidating,
                    explanation: "All reps at top but effort was harder than target. Hold to consolidate."
                ), checks)
            }
            return (DirectionDecision(
                direction: .increase,
                primaryReason: .allRepsAtTop,
                explanation: "All sets at top of rep range (\(repRange.upperBound)+ reps). Ready to increase load."
            ), checks)
        }
        
        // All in range - check for progression
        let easyByRIRCheck = PolicyCheckResult(
            checkName: "easy_by_rir",
            triggered: sessionWasEasyByRIR && allInRange,
            condition: "observedRIR >= targetRIR + \(rirMargin) AND allInRange",
            observed: "observedRIR=\(observedRIR.map { String(format: "%.1f", $0) } ?? "nil") target=\(targetRIR)",
            wouldProduce: .increase
        )
        checks.append(easyByRIRCheck)
        
        if allInRange && sessionWasEasyByRIR {
            return (DirectionDecision(
                direction: .increase,
                primaryReason: .successfulProgression,
                explanation: "All sets within range with room to spare (observed RIR > target). Progressing."
            ), checks)
        }
        
        // Fixed-rep with success streak (no RIR data)
        let successStreakCheck = PolicyCheckResult(
            checkName: "success_streak_gate",
            triggered: isFixedRepRange && hasSuccessStreak && !hasRIRData && allInRange,
            condition: "fixedRep AND successStreak >= \(successStreakThreshold) AND noRIR",
            observed: "fixed=\(isFixedRepRange) streak=\(signals.successStreak) hasRIR=\(hasRIRData)",
            wouldProduce: .increase
        )
        checks.append(successStreakCheck)
        
        if isFixedRepRange && hasSuccessStreak && !hasRIRData && allInRange {
            return (DirectionDecision(
                direction: .increase,
                primaryReason: .successfulProgression,
                explanation: "Fixed-rep prescription with \(signals.successStreak) clean sessions (no RIR data). Ready to progress."
            ), checks)
        }
        
        // Variable rep at top without concerning RIR
        if allAtTop && !sessionWasHarderThanTarget && allInRange {
            return (DirectionDecision(
                direction: .increase,
                primaryReason: .allRepsAtTop,
                explanation: "All sets at top of rep range (\(repRange.upperBound)+ reps). Ready to increase load."
            ), checks)
        }
        
        // Default: consolidate
        let consolidateCheck = PolicyCheckResult(
            checkName: "consolidate_default",
            triggered: true,
            condition: "no other condition triggered",
            observed: "allInRange=\(allInRange) allAtTop=\(allAtTop)",
            wouldProduce: .hold
        )
        checks.append(consolidateCheck)
        
        return (DirectionDecision(
            direction: .hold,
            primaryReason: .consolidating,
            explanation: allInRange 
                ? "All sets within range but at target effort. Hold to consolidate before progressing."
                : "Consolidating at current weight."
        ), checks)
    }
}

// MARK: - Direction Policy Config

/// Configuration for direction policy thresholds.
public struct DirectionPolicyConfig: Sendable {
    /// Days since last exposure to trigger extended break reset.
    public let extendedBreakDays: Int
    
    /// Days since last exposure to trigger training gap (smaller reset).
    public let trainingGapDays: Int
    
    /// Readiness threshold for low readiness detection.
    public let readinessThreshold: Int
    
    /// Severe low readiness threshold (triggers decrease vs hold).
    public let severeLowReadinessThreshold: Int
    
    /// Number of low-readiness exposures before escalating to deload (needs corroboration).
    public let persistentLowReadinessExposures: Int
    
    /// Base fail streak threshold (adjusted by experience).
    public let baseFailStreakThreshold: Int
    
    /// Base high RPE streak threshold (adjusted by experience and intent).
    /// Raised to reduce over-deloading - grinders need to be repeated to trigger deload.
    public let baseHighRpeStreakThreshold: Int
    
    /// Minimum RIR shortfall to count as a "true grinder" (vs just a hard set).
    /// If observed RIR is within this delta of target, it's not a grinder.
    /// E.g., if grinderRirDelta=1 and target RIR=2, observed RIR of 1 is NOT a grinder;
    /// only observed RIR of 0 would be a grinder.
    public let grinderRirDelta: Int
    
    public init(
        extendedBreakDays: Int = 14,
        trainingGapDays: Int = 8,
        readinessThreshold: Int = 50,
        severeLowReadinessThreshold: Int = 40,
        persistentLowReadinessExposures: Int = 4, // Raised from 3 to require more exposures
        baseFailStreakThreshold: Int = 2,
        baseHighRpeStreakThreshold: Int = 3, // Raised from 2 - grinders need more repetition
        grinderRirDelta: Int = 1 // Only count as grinder if RIR shortfall >= 2
    ) {
        self.extendedBreakDays = extendedBreakDays
        self.trainingGapDays = trainingGapDays
        self.readinessThreshold = readinessThreshold
        self.severeLowReadinessThreshold = severeLowReadinessThreshold
        self.persistentLowReadinessExposures = persistentLowReadinessExposures
        self.baseFailStreakThreshold = baseFailStreakThreshold
        self.baseHighRpeStreakThreshold = baseHighRpeStreakThreshold
        self.grinderRirDelta = grinderRirDelta
    }
    
    public static let `default` = DirectionPolicyConfig()
    
    /// Fail streak threshold adjusted for experience level.
    public func failStreakThreshold(for experience: ExperienceLevel) -> Int {
        switch experience {
        case .beginner:
            return baseFailStreakThreshold
        case .intermediate:
            return baseFailStreakThreshold
        case .advanced:
            return baseFailStreakThreshold + 1
        case .elite:
            return baseFailStreakThreshold + 1
        }
    }
    
    /// High RPE streak threshold adjusted for experience level AND session intent.
    /// Heavy days have tighter thresholds; volume days are more lenient.
    public func highRpeStreakThreshold(for experience: ExperienceLevel, intent: SessionIntent = .general) -> Int {
        // Base threshold by experience
        var threshold: Int
        switch experience {
        case .beginner:
            threshold = baseHighRpeStreakThreshold
        case .intermediate:
            threshold = baseHighRpeStreakThreshold
        case .advanced:
            threshold = baseHighRpeStreakThreshold + 1
        case .elite:
            threshold = baseHighRpeStreakThreshold + 1
        }
        
        // Adjust by intent
        switch intent {
        case .heavy:
            // Heavy days: keep threshold as-is (more sensitive)
            break
        case .volume:
            // Volume days: raise threshold (grinders more expected)
            threshold += 1
        case .light, .general:
            break
        }
        
        return threshold
    }
    
    /// Legacy method without intent parameter
    @available(*, deprecated, message: "Use highRpeStreakThreshold(for:intent:)")
    public func highRpeStreakThreshold(for experience: ExperienceLevel) -> Int {
        highRpeStreakThreshold(for: experience, intent: .general)
    }
}

// MARK: - Magnitude Policy

/// Computed magnitude parameters based on direction and signals.
public struct MagnitudeParams: Sendable {
    /// Load multiplier (1.0 = no change, <1.0 = decrease, >1.0 = increase).
    public let loadMultiplier: Double
    
    /// Absolute increment to add (after multiplier, before rounding). Can be negative.
    public let absoluteIncrement: Load
    
    /// Volume adjustment (sets to add or remove).
    public let volumeAdjustment: Int
    
    /// Rounding policy to use.
    public let roundingPolicy: LoadRoundingPolicy
    
    /// Explanation for the magnitude choice.
    public let explanation: String
    
    public init(
        loadMultiplier: Double = 1.0,
        absoluteIncrement: Load = .zero,
        volumeAdjustment: Int = 0,
        roundingPolicy: LoadRoundingPolicy = .standardPounds,
        explanation: String = ""
    ) {
        self.loadMultiplier = loadMultiplier
        self.absoluteIncrement = absoluteIncrement
        self.volumeAdjustment = volumeAdjustment
        self.roundingPolicy = roundingPolicy
        self.explanation = explanation
    }
    
    /// No change magnitude.
    public static func noChange(rounding: LoadRoundingPolicy) -> MagnitudeParams {
        MagnitudeParams(roundingPolicy: rounding, explanation: "No change")
    }
}

/// Policy for determining magnitude of load change.
public enum MagnitudePolicy {
    
    /// Computes magnitude parameters based on direction and signals.
    public static func compute(
        direction: DirectionDecision,
        signals: LiftSignals,
        baseRoundingPolicy: LoadRoundingPolicy,
        config: MagnitudePolicyConfig = .default
    ) -> MagnitudeParams {
        
        // Select appropriate rounding policy (microloading for upper body presses)
        let roundingPolicy = selectRoundingPolicy(
            signals: signals,
            basePolicy: baseRoundingPolicy,
            config: config
        )
        
        switch direction.direction {
        case .increase:
            let increment = computeIncrement(signals: signals, roundingPolicy: roundingPolicy, config: config)
            return MagnitudeParams(
                absoluteIncrement: increment,
                roundingPolicy: roundingPolicy,
                explanation: "Increase by \(increment.description)"
            )
            
        case .hold:
            return MagnitudeParams(
                roundingPolicy: roundingPolicy,
                explanation: "Hold at current weight"
            )
            
        case .decreaseSlightly:
            let reduction = config.acuteReadinessReduction(for: signals.experienceLevel)
            let volumeAdj = config.acuteReadinessVolumeReduction ? -1 : 0
            return MagnitudeParams(
                loadMultiplier: 1.0 - reduction,
                volumeAdjustment: volumeAdj,
                roundingPolicy: roundingPolicy,
                explanation: "Temporary \(Int(reduction * 100))% reduction for low readiness"
            )
            
        case .deload:
            let reduction = computeDeloadReduction(signals: signals, reason: direction.primaryReason, config: config)
            let volumeAdj = config.deloadVolumeReduction
            return MagnitudeParams(
                loadMultiplier: 1.0 - reduction,
                volumeAdjustment: -volumeAdj,
                roundingPolicy: roundingPolicy,
                explanation: "Deload: \(Int(reduction * 100))% reduction, -\(volumeAdj) sets"
            )
            
        case .resetAfterBreak:
            let reduction = computeBreakResetReduction(signals: signals, config: config)
            return MagnitudeParams(
                loadMultiplier: 1.0 - reduction,
                roundingPolicy: roundingPolicy,
                explanation: "Break reset: \(Int(reduction * 100))% reduction with ramp-back"
            )
        }
    }
    
    /// Selects appropriate rounding policy, enabling microloading for upper body presses.
    private static func selectRoundingPolicy(
        signals: LiftSignals,
        basePolicy: LoadRoundingPolicy,
        config: MagnitudePolicyConfig
    ) -> LoadRoundingPolicy {
        guard config.enableMicroloading else { return basePolicy }
        
        // Microloading for upper body barbell presses (bench, OHP)
        let isBarbellLike = signals.equipment == .barbell || signals.equipment == .ezBar
        if signals.isUpperBodyPress && isBarbellLike {
            // Use 1.25 lb (or 0.5 kg) increments for intermediate+ lifters
            if signals.experienceLevel != .beginner {
                return LoadRoundingPolicy(
                    increment: basePolicy.unit == .pounds ? 1.25 : 0.5,
                    unit: basePolicy.unit,
                    mode: basePolicy.mode
                )
            }
        }
        
        // Smaller increments for advanced/elite lifters on all compounds
        if signals.isCompound && (signals.experienceLevel == .advanced || signals.experienceLevel == .elite) {
            let smallerIncrement = basePolicy.unit == .pounds ? 2.5 : 1.25
            if basePolicy.increment > smallerIncrement {
                return LoadRoundingPolicy(
                    increment: smallerIncrement,
                    unit: basePolicy.unit,
                    mode: basePolicy.mode
                )
            }
        }
        
        return basePolicy
    }
    
    /// Computes appropriate increment based on signals.
    private static func computeIncrement(
        signals: LiftSignals,
        roundingPolicy: LoadRoundingPolicy,
        config: MagnitudePolicyConfig
    ) -> Load {
        let unit = roundingPolicy.unit
        
        // Base increment from prescription
        let baseIncrement = signals.prescription.increment.converted(to: unit).value
        
        // Scale by experience level
        let experienceScale: Double = {
            switch signals.experienceLevel {
            case .beginner: return 1.0
            case .intermediate: return 0.8
            case .advanced: return 0.6
            case .elite: return 0.5
            }
        }()
        
        // Scale by relative strength (stronger = smaller increments)
        var strengthScale = 1.0
        if let relativeStrength = signals.relativeStrength {
            let thresholds = config.strengthScalingThresholds(for: signals.movementPattern)
            if relativeStrength >= thresholds.high {
                strengthScale = 0.6
            } else if relativeStrength >= thresholds.medium {
                strengthScale = 0.8
            }
        }
        
        // Compute final increment
        var increment = baseIncrement * experienceScale * strengthScale
        
        // Clamp to minimum meaningful increment
        let minIncrement = roundingPolicy.increment
        increment = max(minIncrement, increment)
        
        // Round to nearest valid increment
        increment = (increment / minIncrement).rounded() * minIncrement
        
        // Apply movement-specific caps
        let maxIncrement: Double = {
            if signals.isUpperBodyPress {
                return unit == .pounds ? 5.0 : 2.5
            } else if signals.movementPattern == .squat || signals.movementPattern == .hipHinge {
                return unit == .pounds ? 10.0 : 5.0
            }
            return unit == .pounds ? 5.0 : 2.5
        }()
        
        increment = min(maxIncrement, increment)
        
        return Load(value: increment, unit: unit)
    }
    
    /// Computes deload reduction based on severity.
    private static func computeDeloadReduction(
        signals: LiftSignals,
        reason: DirectionReason,
        config: MagnitudePolicyConfig
    ) -> Double {
        // Base deload percentage
        var reduction = config.baseDeloadReduction
        
        // Adjust based on severity
        switch reason {
        case .failStreakThreshold:
            // Scale by fail streak severity
            let severity = min(4, signals.failStreak)
            reduction = config.baseDeloadReduction + Double(severity - 2) * 0.02
            
        case .highRpeStreakThreshold:
            // Grinder deloads are slightly smaller (fatigue, not actual failure)
            reduction = config.baseDeloadReduction - 0.02
            
        case .persistentLowReadiness:
            reduction = config.baseDeloadReduction
            
        case .performanceDecline, .plateauDetected:
            // More aggressive for true performance decline
            reduction = config.baseDeloadReduction + 0.02
            
        default:
            break
        }
        
        // Clamp to reasonable range
        return max(0.08, min(0.15, reduction))
    }
    
    /// Computes break reset reduction based on gap length and ramp progress.
    private static func computeBreakResetReduction(
        signals: LiftSignals,
        config: MagnitudePolicyConfig
    ) -> Double {
        guard let days = signals.daysSinceLastExposure else {
            return config.baseBreakResetReduction
        }
        
        // Base reduction by gap length
        let baseReduction: Double = {
            switch days {
            case 8..<14:
                return 0.05
            case 14..<28:
                return 0.08
            case 28..<56:
                return 0.12
            case 56..<84:
                return 0.18
            default:
                return 0.25
            }
        }()
        
        return baseReduction
    }
}

// MARK: - Ramp Back Helper

public extension MagnitudePolicy {
    
    /// Computes the ramp-back load for a lift currently in post-break ramp.
    /// 
    /// - Parameters:
    ///   - currentWeight: The current session's target weight (after break reduction).
    ///   - rampState: The current ramp state.
    ///   - roundingPolicy: Policy for rounding the result.
    /// - Returns: The adjusted load accounting for ramp progress.
    static func computeRampBackLoad(
        targetWeight: Load,
        rampState: PostBreakRampState,
        roundingPolicy: LoadRoundingPolicy
    ) -> Load {
        guard rampState.totalSessions > 0 else { return targetWeight }
        
        // Ramp linearly from current reduced weight back to target
        // Session 0 (first after break): use the reduced weight
        // Session N (last ramp session): approach target weight
        
        // If ramp is complete, return target
        if rampState.isComplete {
            return targetWeight
        }
        
        // Otherwise, interpolate between reduced and target based on progress
        // For a 2-session ramp:
        // - Session 0 (progress=0): stay at reduced weight
        // - Session 1 (progress=0.5): halfway to target
        // Final session is when progress reaches 1.0, which means ramp is complete
        
        // The reduced weight is what was prescribed when the break was detected
        // We want to gradually increase back toward the pre-break baseline
        // Use the progress to interpolate
        let progress = rampState.progress
        let reducedWeight = targetWeight * (1.0 - progress * 0.5) // Gradually approach target
        return reducedWeight.rounded(using: roundingPolicy)
    }
}

// MARK: - Magnitude Policy Config

/// Configuration for magnitude policy.
public struct MagnitudePolicyConfig: Sendable {
    /// Whether to enable microloading for upper body presses.
    public let enableMicroloading: Bool
    
    /// Base deload reduction (8-12%).
    public let baseDeloadReduction: Double
    
    /// Volume reduction during deload (sets to remove).
    public let deloadVolumeReduction: Int
    
    /// Base break reset reduction.
    public let baseBreakResetReduction: Double
    
    /// Whether to reduce volume on acute low readiness.
    public let acuteReadinessVolumeReduction: Bool
    
    public init(
        enableMicroloading: Bool = true,
        baseDeloadReduction: Double = 0.10,
        deloadVolumeReduction: Int = 1,
        baseBreakResetReduction: Double = 0.10,
        acuteReadinessVolumeReduction: Bool = true
    ) {
        self.enableMicroloading = enableMicroloading
        self.baseDeloadReduction = max(0.05, min(0.20, baseDeloadReduction))
        self.deloadVolumeReduction = max(0, min(2, deloadVolumeReduction))
        self.baseBreakResetReduction = baseBreakResetReduction
        self.acuteReadinessVolumeReduction = acuteReadinessVolumeReduction
    }
    
    public static let `default` = MagnitudePolicyConfig()
    
    /// Acute readiness reduction by experience level.
    public func acuteReadinessReduction(for experience: ExperienceLevel) -> Double {
        switch experience {
        case .beginner: return 0.025
        case .intermediate: return 0.03
        case .advanced: return 0.04
        case .elite: return 0.05
        }
    }
    
    /// Strength scaling thresholds by movement pattern.
    public func strengthScalingThresholds(for pattern: MovementPattern) -> (medium: Double, high: Double) {
        switch pattern {
        case .horizontalPush, .verticalPush:
            return (medium: 1.25, high: 1.75)
        case .squat:
            return (medium: 2.0, high: 2.5)
        case .hipHinge:
            return (medium: 2.25, high: 2.75)
        default:
            return (medium: 1.5, high: 2.0)
        }
    }
}
