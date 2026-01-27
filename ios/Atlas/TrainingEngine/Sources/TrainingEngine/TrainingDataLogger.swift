// TrainingDataLogger.swift
// Structured logging for ML training data collection.
//
// This module provides a comprehensive logging system for:
// 1. Features (inputs): history summaries, exposures, trends, readiness, constraints
// 2. Actions (decisions): direction, delta, absolute load, deload flags
// 3. Outcomes (results): reps achieved, RPE/RIR, next-session performance
// 4. Counterfactual labels: what alternative policies would have prescribed

import Foundation

// MARK: - Feature Vectors

/// History summary capturing aggregated statistics from recent sessions.
public struct HistorySummary: Codable, Sendable, Hashable {
    /// Total sessions in history window.
    public let sessionCount: Int
    
    /// Sessions in the last 7 days.
    public let sessionsLast7Days: Int
    
    /// Sessions in the last 14 days.
    public let sessionsLast14Days: Int
    
    /// Sessions in the last 28 days.
    public let sessionsLast28Days: Int
    
    /// Total volume in the last 7 days.
    public let volumeLast7Days: Double
    
    /// Total volume in the last 14 days.
    public let volumeLast14Days: Double
    
    /// Average session duration (minutes) in last 14 days.
    public let avgSessionDurationMinutes: Double?
    
    /// Number of deload sessions in last 28 days.
    public let deloadSessionsLast28Days: Int
    
    /// Days since last workout.
    public let daysSinceLastWorkout: Int?
    
    /// Current training streak (consecutive weeks with >= minSessionsPerWeek).
    public let trainingStreakWeeks: Int
    
    public init(
        sessionCount: Int,
        sessionsLast7Days: Int,
        sessionsLast14Days: Int,
        sessionsLast28Days: Int,
        volumeLast7Days: Double,
        volumeLast14Days: Double,
        avgSessionDurationMinutes: Double?,
        deloadSessionsLast28Days: Int,
        daysSinceLastWorkout: Int?,
        trainingStreakWeeks: Int
    ) {
        self.sessionCount = sessionCount
        self.sessionsLast7Days = sessionsLast7Days
        self.sessionsLast14Days = sessionsLast14Days
        self.sessionsLast28Days = sessionsLast28Days
        self.volumeLast7Days = volumeLast7Days
        self.volumeLast14Days = volumeLast14Days
        self.avgSessionDurationMinutes = avgSessionDurationMinutes
        self.deloadSessionsLast28Days = deloadSessionsLast28Days
        self.daysSinceLastWorkout = daysSinceLastWorkout
        self.trainingStreakWeeks = trainingStreakWeeks
    }
}

/// Recent exposure record for a single lift occurrence.
public struct ExposureRecord: Codable, Sendable, Hashable {
    /// Date of the exposure.
    public let date: Date
    
    /// Days ago from reference date.
    public let daysAgo: Int
    
    /// Load used (in plan's unit).
    public let loadValue: Double
    
    /// Unit of the load.
    public let loadUnit: LoadUnit
    
    /// Reps achieved (average across working sets).
    public let avgReps: Double
    
    /// Observed RIR (average across working sets, nil if not recorded).
    public let avgRIR: Double?
    
    /// Whether the session was a success (all sets in range).
    public let wasSuccess: Bool
    
    /// Whether the session was a failure (any set below range).
    public let wasFailure: Bool
    
    /// Whether the session was a grinder (success but RIR below target).
    public let wasGrinder: Bool
    
    /// Estimated 1RM from this session.
    public let sessionE1RM: Double
    
    /// Readiness score at time of exposure.
    public let readinessScore: Int?
    
    /// Session adjustment kind.
    public let adjustmentKind: SessionAdjustmentKind
    
    public init(
        date: Date,
        daysAgo: Int,
        loadValue: Double,
        loadUnit: LoadUnit,
        avgReps: Double,
        avgRIR: Double?,
        wasSuccess: Bool,
        wasFailure: Bool,
        wasGrinder: Bool,
        sessionE1RM: Double,
        readinessScore: Int?,
        adjustmentKind: SessionAdjustmentKind
    ) {
        self.date = date
        self.daysAgo = daysAgo
        self.loadValue = loadValue
        self.loadUnit = loadUnit
        self.avgReps = avgReps
        self.avgRIR = avgRIR
        self.wasSuccess = wasSuccess
        self.wasFailure = wasFailure
        self.wasGrinder = wasGrinder
        self.sessionE1RM = sessionE1RM
        self.readinessScore = readinessScore
        self.adjustmentKind = adjustmentKind
    }
}

/// Trend statistics computed from e1RM history.
public struct TrendStatistics: Codable, Sendable, Hashable {
    /// Current trend direction.
    public let trend: PerformanceTrend
    
    /// Linear regression slope (normalized, per session).
    public let slopePerSession: Double?
    
    /// Slope as percentage of average e1RM.
    public let slopePercentage: Double?
    
    /// R-squared of the linear fit (goodness of fit).
    public let rSquared: Double?
    
    /// Number of data points used.
    public let dataPoints: Int
    
    /// Days spanned by the data.
    public let daysSpanned: Int?
    
    /// Recent volatility (stddev of last 5 e1RM values).
    public let recentVolatility: Double?
    
    /// Whether there's a 2-session decline pattern.
    public let hasTwoSessionDecline: Bool
    
    public init(
        trend: PerformanceTrend,
        slopePerSession: Double?,
        slopePercentage: Double?,
        rSquared: Double?,
        dataPoints: Int,
        daysSpanned: Int?,
        recentVolatility: Double?,
        hasTwoSessionDecline: Bool
    ) {
        self.trend = trend
        self.slopePerSession = slopePerSession
        self.slopePercentage = slopePercentage
        self.rSquared = rSquared
        self.dataPoints = dataPoints
        self.daysSpanned = daysSpanned
        self.recentVolatility = recentVolatility
        self.hasTwoSessionDecline = hasTwoSessionDecline
    }
}

/// Readiness distribution statistics.
public struct ReadinessDistribution: Codable, Sendable, Hashable {
    /// Current readiness score.
    public let current: Int
    
    /// Mean of recent readiness scores.
    public let mean: Double?
    
    /// Median of recent readiness scores.
    public let median: Double?
    
    /// Standard deviation of recent readiness scores.
    public let stdDev: Double?
    
    /// Minimum in recent window.
    public let min: Int?
    
    /// Maximum in recent window.
    public let max: Int?
    
    /// Count of low-readiness days (below threshold).
    public let lowReadinessCount: Int
    
    /// Consecutive low-readiness days.
    public let consecutiveLowDays: Int
    
    /// Trend direction of readiness (improving, stable, declining).
    public let trend: String?
    
    /// Number of samples in the distribution.
    public let sampleCount: Int
    
    public init(
        current: Int,
        mean: Double?,
        median: Double?,
        stdDev: Double?,
        min: Int?,
        max: Int?,
        lowReadinessCount: Int,
        consecutiveLowDays: Int,
        trend: String?,
        sampleCount: Int
    ) {
        self.current = current
        self.mean = mean
        self.median = median
        self.stdDev = stdDev
        self.min = min
        self.max = max
        self.lowReadinessCount = lowReadinessCount
        self.consecutiveLowDays = consecutiveLowDays
        self.trend = trend
        self.sampleCount = sampleCount
    }
}

/// Constraint information affecting the decision.
public struct ConstraintInfo: Codable, Sendable, Hashable {
    /// Equipment available for this exercise.
    public let equipmentAvailable: Bool
    
    /// Rounding policy increment.
    public let roundingIncrement: Double
    
    /// Rounding unit.
    public let roundingUnit: LoadUnit
    
    /// Whether microloading is enabled.
    public let microloadingEnabled: Bool
    
    /// Minimum load floor (equipment-based).
    public let minLoadFloor: Double?
    
    /// Maximum load ceiling (safety-based).
    public let maxLoadCeiling: Double?
    
    /// Time constraint (session duration limit).
    public let sessionTimeLimit: Int?
    
    /// Whether this is a planned deload week.
    public let isPlannedDeloadWeek: Bool
    
    public init(
        equipmentAvailable: Bool,
        roundingIncrement: Double,
        roundingUnit: LoadUnit,
        microloadingEnabled: Bool,
        minLoadFloor: Double?,
        maxLoadCeiling: Double?,
        sessionTimeLimit: Int?,
        isPlannedDeloadWeek: Bool
    ) {
        self.equipmentAvailable = equipmentAvailable
        self.roundingIncrement = roundingIncrement
        self.roundingUnit = roundingUnit
        self.microloadingEnabled = microloadingEnabled
        self.minLoadFloor = minLoadFloor
        self.maxLoadCeiling = maxLoadCeiling
        self.sessionTimeLimit = sessionTimeLimit
        self.isPlannedDeloadWeek = isPlannedDeloadWeek
    }
}

/// Exercise variation context.
public struct VariationContext: Codable, Sendable, Hashable {
    /// Whether this is the primary (template) exercise.
    public let isPrimaryExercise: Bool
    
    /// Whether this is a substitution.
    public let isSubstitution: Bool
    
    /// Original exercise ID (if substituted).
    public let originalExerciseId: String?
    
    /// Family reference key (for lift families).
    public let familyReferenceKey: String
    
    /// Family update key.
    public let familyUpdateKey: String
    
    /// Family coefficient (for load scaling).
    public let familyCoefficient: Double
    
    /// Movement pattern.
    public let movementPattern: MovementPattern
    
    /// Equipment type.
    public let equipment: Equipment
    
    /// Whether state is exercise-specific vs family-derived.
    public let stateIsExerciseSpecific: Bool
    
    public init(
        isPrimaryExercise: Bool,
        isSubstitution: Bool,
        originalExerciseId: String?,
        familyReferenceKey: String,
        familyUpdateKey: String,
        familyCoefficient: Double,
        movementPattern: MovementPattern,
        equipment: Equipment,
        stateIsExerciseSpecific: Bool
    ) {
        self.isPrimaryExercise = isPrimaryExercise
        self.isSubstitution = isSubstitution
        self.originalExerciseId = originalExerciseId
        self.familyReferenceKey = familyReferenceKey
        self.familyUpdateKey = familyUpdateKey
        self.familyCoefficient = familyCoefficient
        self.movementPattern = movementPattern
        self.equipment = equipment
        self.stateIsExerciseSpecific = stateIsExerciseSpecific
    }
}

// MARK: - Action Record

/// Complete action record capturing what the engine decided.
public struct ActionRecord: Codable, Sendable, Hashable {
    /// Direction decision.
    public let direction: ProgressionDirection
    
    /// Primary reason for the decision.
    public let primaryReason: DirectionReason
    
    /// Contributing reasons.
    public let contributingReasons: [DirectionReason]
    
    /// Delta (absolute increment, can be negative).
    public let deltaLoadValue: Double
    
    /// Delta unit.
    public let deltaLoadUnit: LoadUnit
    
    /// Load multiplier applied.
    public let loadMultiplier: Double
    
    /// Final prescribed load.
    public let absoluteLoadValue: Double
    
    /// Load unit.
    public let absoluteLoadUnit: LoadUnit
    
    /// Baseline load (before direction/magnitude adjustments).
    public let baselineLoadValue: Double
    
    /// Target reps prescribed.
    public let targetReps: Int
    
    /// Target RIR prescribed.
    public let targetRIR: Int
    
    /// Set count prescribed.
    public let setCount: Int
    
    /// Volume adjustment (sets added/removed).
    public let volumeAdjustment: Int
    
    /// Whether session-level deload is active.
    public let isSessionDeload: Bool
    
    /// Whether exercise-level deload is active.
    public let isExerciseDeload: Bool
    
    /// Adjustment kind (none, deload, readiness_cut, break_reset).
    public let adjustmentKind: SessionAdjustmentKind
    
    /// Human-readable explanation.
    public let explanation: String
    
    /// Confidence score (0-1).
    public let confidence: Double
    
    public init(
        direction: ProgressionDirection,
        primaryReason: DirectionReason,
        contributingReasons: [DirectionReason],
        deltaLoadValue: Double,
        deltaLoadUnit: LoadUnit,
        loadMultiplier: Double,
        absoluteLoadValue: Double,
        absoluteLoadUnit: LoadUnit,
        baselineLoadValue: Double,
        targetReps: Int,
        targetRIR: Int,
        setCount: Int,
        volumeAdjustment: Int,
        isSessionDeload: Bool,
        isExerciseDeload: Bool,
        adjustmentKind: SessionAdjustmentKind,
        explanation: String,
        confidence: Double
    ) {
        self.direction = direction
        self.primaryReason = primaryReason
        self.contributingReasons = contributingReasons
        self.deltaLoadValue = deltaLoadValue
        self.deltaLoadUnit = deltaLoadUnit
        self.loadMultiplier = loadMultiplier
        self.absoluteLoadValue = absoluteLoadValue
        self.absoluteLoadUnit = absoluteLoadUnit
        self.baselineLoadValue = baselineLoadValue
        self.targetReps = targetReps
        self.targetRIR = targetRIR
        self.setCount = setCount
        self.volumeAdjustment = volumeAdjustment
        self.isSessionDeload = isSessionDeload
        self.isExerciseDeload = isExerciseDeload
        self.adjustmentKind = adjustmentKind
        self.explanation = explanation
        self.confidence = confidence
    }
}

// MARK: - Outcome Record

/// Outcome record capturing what happened during the session.
public struct OutcomeRecord: Codable, Sendable, Hashable {
    /// Reps achieved per set.
    public let repsPerSet: [Int]
    
    /// Average reps achieved.
    public let avgReps: Double
    
    /// Total reps achieved.
    public let totalReps: Int
    
    /// RIR observed per set (nil if not recorded).
    public let rirPerSet: [Int?]
    
    /// Average RIR observed.
    public let avgRIR: Double?
    
    /// Load actually used (may differ from prescribed due to in-session adjustments).
    public let actualLoadValue: Double
    
    /// Load unit.
    public let actualLoadUnit: LoadUnit
    
    /// Session e1RM (best estimated 1RM from any set).
    public let sessionE1RM: Double
    
    /// Whether the outcome was a success (all sets in range).
    public let wasSuccess: Bool
    
    /// Whether the outcome was a failure (any set below range).
    public let wasFailure: Bool
    
    /// Whether the outcome was a grinder (success but RIR below target).
    public let wasGrinder: Bool
    
    /// Total volume (load × reps).
    public let totalVolume: Double
    
    /// In-session adjustments applied (load changes between sets).
    public let inSessionAdjustments: [InSessionAdjustmentLog]
    
    /// Readiness score at session time.
    public let readinessScore: Int?
    
    public init(
        repsPerSet: [Int],
        avgReps: Double,
        totalReps: Int,
        rirPerSet: [Int?],
        avgRIR: Double?,
        actualLoadValue: Double,
        actualLoadUnit: LoadUnit,
        sessionE1RM: Double,
        wasSuccess: Bool,
        wasFailure: Bool,
        wasGrinder: Bool,
        totalVolume: Double,
        inSessionAdjustments: [InSessionAdjustmentLog],
        readinessScore: Int?
    ) {
        self.repsPerSet = repsPerSet
        self.avgReps = avgReps
        self.totalReps = totalReps
        self.rirPerSet = rirPerSet
        self.avgRIR = avgRIR
        self.actualLoadValue = actualLoadValue
        self.actualLoadUnit = actualLoadUnit
        self.sessionE1RM = sessionE1RM
        self.wasSuccess = wasSuccess
        self.wasFailure = wasFailure
        self.wasGrinder = wasGrinder
        self.totalVolume = totalVolume
        self.inSessionAdjustments = inSessionAdjustments
        self.readinessScore = readinessScore
    }
}

/// Log of an in-session adjustment.
public struct InSessionAdjustmentLog: Codable, Sendable, Hashable {
    /// Set index where adjustment was applied.
    public let setIndex: Int
    
    /// Previous load.
    public let previousLoadValue: Double
    
    /// New load.
    public let newLoadValue: Double
    
    /// Load unit.
    public let loadUnit: LoadUnit
    
    /// Reason for adjustment.
    public let reason: String
    
    public init(
        setIndex: Int,
        previousLoadValue: Double,
        newLoadValue: Double,
        loadUnit: LoadUnit,
        reason: String
    ) {
        self.setIndex = setIndex
        self.previousLoadValue = previousLoadValue
        self.newLoadValue = newLoadValue
        self.loadUnit = loadUnit
        self.reason = reason
    }
}

/// Next-session performance metrics (computed when next session is logged).
public struct NextSessionPerformance: Codable, Sendable, Hashable {
    /// Days until next exposure.
    public let daysUntilNextExposure: Int
    
    /// Load used in next session.
    public let nextLoadValue: Double
    
    /// Load unit.
    public let nextLoadUnit: LoadUnit
    
    /// Load delta from this session to next.
    public let loadDeltaValue: Double
    
    /// Load delta as percentage.
    public let loadDeltaPercentage: Double
    
    /// Whether next session was a success.
    public let nextWasSuccess: Bool
    
    /// Whether next session was a failure.
    public let nextWasFailure: Bool
    
    /// e1RM delta from this session to next.
    public let e1rmDelta: Double
    
    /// e1RM delta as percentage.
    public let e1rmDeltaPercentage: Double
    
    public init(
        daysUntilNextExposure: Int,
        nextLoadValue: Double,
        nextLoadUnit: LoadUnit,
        loadDeltaValue: Double,
        loadDeltaPercentage: Double,
        nextWasSuccess: Bool,
        nextWasFailure: Bool,
        e1rmDelta: Double,
        e1rmDeltaPercentage: Double
    ) {
        self.daysUntilNextExposure = daysUntilNextExposure
        self.nextLoadValue = nextLoadValue
        self.nextLoadUnit = nextLoadUnit
        self.loadDeltaValue = loadDeltaValue
        self.loadDeltaPercentage = loadDeltaPercentage
        self.nextWasSuccess = nextWasSuccess
        self.nextWasFailure = nextWasFailure
        self.e1rmDelta = e1rmDelta
        self.e1rmDeltaPercentage = e1rmDeltaPercentage
    }
}

// MARK: - Counterfactual Record

/// Counterfactual record: what alternative policies would have prescribed.
/// Used for off-policy learning and policy comparison.
public struct CounterfactualRecord: Codable, Sendable, Hashable {
    /// Policy identifier.
    public let policyId: String
    
    /// Policy description.
    public let policyDescription: String
    
    /// Direction that would have been chosen.
    public let direction: ProgressionDirection
    
    /// Primary reason.
    public let primaryReason: DirectionReason
    
    /// Load that would have been prescribed.
    public let prescribedLoadValue: Double
    
    /// Load unit.
    public let prescribedLoadUnit: LoadUnit
    
    /// Load multiplier that would have been applied.
    public let loadMultiplier: Double
    
    /// Absolute increment that would have been applied.
    public let absoluteIncrementValue: Double
    
    /// Volume adjustment that would have been applied.
    public let volumeAdjustment: Int
    
    /// Confidence score.
    public let confidence: Double
    
    public init(
        policyId: String,
        policyDescription: String,
        direction: ProgressionDirection,
        primaryReason: DirectionReason,
        prescribedLoadValue: Double,
        prescribedLoadUnit: LoadUnit,
        loadMultiplier: Double,
        absoluteIncrementValue: Double,
        volumeAdjustment: Int,
        confidence: Double
    ) {
        self.policyId = policyId
        self.policyDescription = policyDescription
        self.direction = direction
        self.primaryReason = primaryReason
        self.prescribedLoadValue = prescribedLoadValue
        self.prescribedLoadUnit = prescribedLoadUnit
        self.loadMultiplier = loadMultiplier
        self.absoluteIncrementValue = absoluteIncrementValue
        self.volumeAdjustment = volumeAdjustment
        self.confidence = confidence
    }
}

// MARK: - Complete Decision Log Entry

/// Complete decision log entry for a single exercise in a session.
/// This is the primary output format for ML training data.
public struct DecisionLogEntry: Codable, Sendable, Hashable {
    // MARK: - Identifiers
    
    /// Unique identifier for this log entry.
    public let id: UUID
    
    /// Session ID this entry belongs to.
    public let sessionId: UUID
    
    /// Exercise ID.
    public let exerciseId: String
    
    /// User ID (anonymized).
    public let userId: String
    
    /// Timestamp when the decision was made.
    public let timestamp: Date
    
    /// Session date (may differ from timestamp due to planning ahead).
    public let sessionDate: Date
    
    // MARK: - Features
    
    /// History summary.
    public let historySummary: HistorySummary
    
    /// Last N exposures for this exercise.
    public let lastExposures: [ExposureRecord]
    
    /// Trend statistics.
    public let trendStatistics: TrendStatistics
    
    /// Readiness distribution.
    public let readinessDistribution: ReadinessDistribution
    
    /// Constraint info.
    public let constraintInfo: ConstraintInfo
    
    /// Variation context.
    public let variationContext: VariationContext
    
    /// Session intent.
    public let sessionIntent: SessionIntent
    
    /// User experience level.
    public let experienceLevel: ExperienceLevel
    
    /// Lift signals (raw input to direction policy).
    public let liftSignals: LiftSignalsSnapshot
    
    // MARK: - Action
    
    /// The action taken by the engine.
    public let action: ActionRecord
    
    /// Policy checks performed (for interpretability).
    public let policyChecks: [PolicyCheckResult]
    
    // MARK: - Counterfactuals
    
    /// What alternative policies would have prescribed.
    public let counterfactuals: [CounterfactualRecord]
    
    // MARK: - Outcome (filled after session completion)
    
    /// Outcome of the session (nil until session is completed).
    public var outcome: OutcomeRecord?
    
    /// Next-session performance (nil until next session is completed).
    public var nextSessionPerformance: NextSessionPerformance?
    
    // MARK: - Metadata
    
    /// Engine version.
    public let engineVersion: String
    
    /// Any flags or tags for filtering.
    public let tags: [String]
    
    public init(
        id: UUID = UUID(),
        sessionId: UUID,
        exerciseId: String,
        userId: String,
        timestamp: Date,
        sessionDate: Date,
        historySummary: HistorySummary,
        lastExposures: [ExposureRecord],
        trendStatistics: TrendStatistics,
        readinessDistribution: ReadinessDistribution,
        constraintInfo: ConstraintInfo,
        variationContext: VariationContext,
        sessionIntent: SessionIntent,
        experienceLevel: ExperienceLevel,
        liftSignals: LiftSignalsSnapshot,
        action: ActionRecord,
        policyChecks: [PolicyCheckResult],
        counterfactuals: [CounterfactualRecord],
        outcome: OutcomeRecord? = nil,
        nextSessionPerformance: NextSessionPerformance? = nil,
        engineVersion: String,
        tags: [String] = []
    ) {
        self.id = id
        self.sessionId = sessionId
        self.exerciseId = exerciseId
        self.userId = userId
        self.timestamp = timestamp
        self.sessionDate = sessionDate
        self.historySummary = historySummary
        self.lastExposures = lastExposures
        self.trendStatistics = trendStatistics
        self.readinessDistribution = readinessDistribution
        self.constraintInfo = constraintInfo
        self.variationContext = variationContext
        self.sessionIntent = sessionIntent
        self.experienceLevel = experienceLevel
        self.liftSignals = liftSignals
        self.action = action
        self.policyChecks = policyChecks
        self.counterfactuals = counterfactuals
        self.outcome = outcome
        self.nextSessionPerformance = nextSessionPerformance
        self.engineVersion = engineVersion
        self.tags = tags
    }
}

/// Snapshot of LiftSignals for logging (subset of fields, all Codable).
public struct LiftSignalsSnapshot: Codable, Sendable, Hashable {
    public let exerciseId: String
    public let movementPattern: MovementPattern
    public let equipment: Equipment
    public let lastWorkingWeightValue: Double
    public let lastWorkingWeightUnit: LoadUnit
    public let rollingE1RM: Double
    public let failStreak: Int
    public let highRpeStreak: Int
    public let successStreak: Int
    public let daysSinceLastExposure: Int?
    public let daysSinceDeload: Int?
    public let trend: PerformanceTrend
    public let successfulSessionsCount: Int
    public let lastSessionWasFailure: Bool
    public let lastSessionWasGrinder: Bool
    public let lastSessionAvgRIR: Double?
    public let lastSessionReps: [Int]
    public let todayReadiness: Int
    public let recentReadinessScores: [Int]
    public let targetRepsLower: Int
    public let targetRepsUpper: Int
    public let targetRIR: Int
    public let loadStrategy: String
    public let experienceLevel: ExperienceLevel
    public let sessionDeloadTriggered: Bool
    public let sessionDeloadReason: String?
    public let sessionIntent: SessionIntent
    public let isCompound: Bool
    public let isUpperBodyPress: Bool
    public let hasTrainingGap: Bool
    public let hasExtendedBreak: Bool
    public let relativeStrength: Double?
    
    public init(from signals: LiftSignals) {
        self.exerciseId = signals.exerciseId
        self.movementPattern = signals.movementPattern
        self.equipment = signals.equipment
        self.lastWorkingWeightValue = signals.lastWorkingWeight.value
        self.lastWorkingWeightUnit = signals.lastWorkingWeight.unit
        self.rollingE1RM = signals.rollingE1RM
        self.failStreak = signals.failStreak
        self.highRpeStreak = signals.highRpeStreak
        self.successStreak = signals.successStreak
        self.daysSinceLastExposure = signals.daysSinceLastExposure
        self.daysSinceDeload = signals.daysSinceDeload
        self.trend = signals.trend
        self.successfulSessionsCount = signals.successfulSessionsCount
        self.lastSessionWasFailure = signals.lastSessionWasFailure
        self.lastSessionWasGrinder = signals.lastSessionWasGrinder
        self.lastSessionAvgRIR = signals.lastSessionAvgRIR
        self.lastSessionReps = signals.lastSessionReps
        self.todayReadiness = signals.todayReadiness
        self.recentReadinessScores = signals.recentReadinessScores
        self.targetRepsLower = signals.prescription.targetRepsRange.lowerBound
        self.targetRepsUpper = signals.prescription.targetRepsRange.upperBound
        self.targetRIR = signals.prescription.targetRIR
        self.loadStrategy = signals.prescription.loadStrategy.rawValue
        self.experienceLevel = signals.experienceLevel
        self.sessionDeloadTriggered = signals.sessionDeloadTriggered
        self.sessionDeloadReason = signals.sessionDeloadReason?.rawValue
        self.sessionIntent = signals.sessionIntent
        self.isCompound = signals.isCompound
        self.isUpperBodyPress = signals.isUpperBodyPress
        self.hasTrainingGap = signals.hasTrainingGap
        self.hasExtendedBreak = signals.hasExtendedBreak
        self.relativeStrength = signals.relativeStrength
    }
}

// MARK: - Training Data Logger

/// Logger for collecting ML training data during engine operations.
public final class TrainingDataLogger: @unchecked Sendable {
    
    /// Shared singleton instance.
    public static let shared = TrainingDataLogger()
    
    /// Current engine version for tagging.
    public static let engineVersion = "1.0.0"
    
    /// Whether logging is enabled.
    public var isEnabled: Bool = false
    
    /// Handler for log entries (can be set to write to file, send to server, etc.).
    public var logHandler: ((DecisionLogEntry) -> Void)?
    
    /// Alternative policies to evaluate for counterfactual logging.
    public var counterfactualPolicies: [CounterfactualPolicy] = []
    
    /// Pending entries awaiting outcome data.
    private var pendingEntries: [UUID: DecisionLogEntry] = [:]
    private let lock = NSLock()
    
    private init() {
        // Register default counterfactual policies
        registerDefaultCounterfactualPolicies()
    }
    
    /// Registers the default set of counterfactual policies for comparison.
    private func registerDefaultCounterfactualPolicies() {
        counterfactualPolicies = [
            // Conservative policy: higher thresholds, more holds
            CounterfactualPolicy(
                id: "conservative",
                description: "Conservative policy with higher deload thresholds",
                directionConfig: DirectionPolicyConfig(
                    extendedBreakDays: 14,
                    trainingGapDays: 10,
                    readinessThreshold: 55,
                    severeLowReadinessThreshold: 45,
                    moderateLowReadinessThreshold: 70,
                    clearLowReadinessThreshold: 65,
                    persistentLowReadinessExposures: 5,
                    baseFailStreakThreshold: 3,
                    baseHighRpeStreakThreshold: 4,
                    grinderRirDelta: 1
                ),
                magnitudeConfig: .default
            ),
            
            // Aggressive policy: lower thresholds, more progression
            CounterfactualPolicy(
                id: "aggressive",
                description: "Aggressive policy with lower deload thresholds",
                directionConfig: DirectionPolicyConfig(
                    extendedBreakDays: 14,
                    trainingGapDays: 7,
                    readinessThreshold: 45,
                    severeLowReadinessThreshold: 35,
                    moderateLowReadinessThreshold: 55,
                    clearLowReadinessThreshold: 50,
                    persistentLowReadinessExposures: 3,
                    baseFailStreakThreshold: 2,
                    baseHighRpeStreakThreshold: 2,
                    grinderRirDelta: 0
                ),
                magnitudeConfig: MagnitudePolicyConfig(
                    enableMicroloading: true,
                    baseDeloadReduction: 0.08,
                    deloadVolumeReduction: 1,
                    baseBreakResetReduction: 0.08,
                    acuteReadinessVolumeReduction: false
                )
            ),
            
            // Linear-only policy: always increase unless failure
            CounterfactualPolicy(
                id: "linear_only",
                description: "Simple linear progression (increase unless failure)",
                directionConfig: DirectionPolicyConfig(
                    extendedBreakDays: 21,
                    trainingGapDays: 14,
                    readinessThreshold: 30,
                    severeLowReadinessThreshold: 20,
                    moderateLowReadinessThreshold: 40,
                    clearLowReadinessThreshold: 35,
                    persistentLowReadinessExposures: 6,
                    baseFailStreakThreshold: 2,
                    baseHighRpeStreakThreshold: 5,
                    grinderRirDelta: 2
                ),
                magnitudeConfig: .default
            )
        ]
    }
    
    /// Logs a decision when a session plan is generated.
    public func logDecision(
        sessionId: UUID,
        exerciseId: String,
        userId: String,
        sessionDate: Date,
        history: WorkoutHistory,
        liftState: LiftState,
        signals: LiftSignals,
        direction: DirectionDecision,
        magnitude: MagnitudeParams,
        baselineLoad: Load,
        finalLoad: Load,
        targetReps: Int,
        targetRIR: Int,
        setCount: Int,
        volumeAdjustment: Int,
        isSessionDeload: Bool,
        adjustmentKind: SessionAdjustmentKind,
        policyChecks: [PolicyCheckResult],
        plan: TrainingPlan,
        userProfile: UserProfile,
        variationContext: VariationContext,
        isPlannedDeloadWeek: Bool,
        calendar: Calendar = .current
    ) {
        guard isEnabled else { return }
        
        let now = Date()
        
        // Build feature vectors
        let historySummary = buildHistorySummary(history: history, from: sessionDate, calendar: calendar)
        let lastExposures = buildExposureRecords(
            exerciseId: exerciseId,
            history: history,
            from: sessionDate,
            calendar: calendar,
            limit: 10
        )
        let trendStatistics = buildTrendStatistics(liftState: liftState)
        let readinessDistribution = buildReadinessDistribution(
            current: signals.todayReadiness,
            recentScores: signals.recentReadinessScores,
            history: history,
            from: sessionDate,
            calendar: calendar
        )
        let constraintInfo = ConstraintInfo(
            equipmentAvailable: true,
            roundingIncrement: magnitude.roundingPolicy.increment,
            roundingUnit: magnitude.roundingPolicy.unit,
            microloadingEnabled: MagnitudePolicyConfig.default.enableMicroloading,
            minLoadFloor: nil,
            maxLoadCeiling: nil,
            sessionTimeLimit: nil,
            isPlannedDeloadWeek: isPlannedDeloadWeek
        )
        
        // Build action record
        let action = ActionRecord(
            direction: direction.direction,
            primaryReason: direction.primaryReason,
            contributingReasons: direction.contributingReasons,
            deltaLoadValue: magnitude.absoluteIncrement.value,
            deltaLoadUnit: magnitude.absoluteIncrement.unit,
            loadMultiplier: magnitude.loadMultiplier,
            absoluteLoadValue: finalLoad.value,
            absoluteLoadUnit: finalLoad.unit,
            baselineLoadValue: baselineLoad.value,
            targetReps: targetReps,
            targetRIR: targetRIR,
            setCount: setCount,
            volumeAdjustment: volumeAdjustment,
            isSessionDeload: isSessionDeload,
            isExerciseDeload: direction.direction == .deload,
            adjustmentKind: adjustmentKind,
            explanation: direction.explanation,
            confidence: direction.confidence
        )
        
        // Compute counterfactuals
        let counterfactuals = computeCounterfactuals(
            signals: signals,
            baselineLoad: baselineLoad,
            plan: plan
        )
        
        let entry = DecisionLogEntry(
            sessionId: sessionId,
            exerciseId: exerciseId,
            userId: userId,
            timestamp: now,
            sessionDate: sessionDate,
            historySummary: historySummary,
            lastExposures: lastExposures,
            trendStatistics: trendStatistics,
            readinessDistribution: readinessDistribution,
            constraintInfo: constraintInfo,
            variationContext: variationContext,
            sessionIntent: signals.sessionIntent,
            experienceLevel: signals.experienceLevel,
            liftSignals: LiftSignalsSnapshot(from: signals),
            action: action,
            policyChecks: policyChecks,
            counterfactuals: counterfactuals,
            engineVersion: Self.engineVersion
        )
        
        // Store pending entry for outcome linkage
        lock.lock()
        pendingEntries[entry.id] = entry
        lock.unlock()
        
        // Emit the entry (handler can decide to batch or stream)
        logHandler?(entry)
    }
    
    /// Records the outcome when a session is completed.
    public func recordOutcome(
        sessionId: UUID,
        exerciseId: String,
        exerciseResult: ExerciseSessionResult,
        readinessScore: Int?,
        inSessionAdjustments: [InSessionAdjustmentLog] = []
    ) {
        guard isEnabled else { return }
        
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
        let grinderRirDelta = DirectionPolicyConfig.default.grinderRirDelta
        
        let wasFailure = workingSets.contains { $0.reps < targetRepsLower }
        let wasSuccess = !wasFailure && workingSets.allSatisfy { $0.reps >= targetRepsLower }
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
            inSessionAdjustments: inSessionAdjustments,
            readinessScore: readinessScore
        )
        
        // Find and update matching pending entry
        lock.lock()
        defer { lock.unlock() }
        
        for (id, var entry) in pendingEntries where entry.sessionId == sessionId && entry.exerciseId == exerciseId {
            entry.outcome = outcome
            pendingEntries[id] = entry
            logHandler?(entry)
        }
    }
    
    /// Links next-session performance to a previous entry.
    /// Call this when the next session for an exercise is completed.
    public func linkNextSessionPerformance(
        previousSessionId: UUID,
        exerciseId: String,
        nextSessionDate: Date,
        nextExerciseResult: ExerciseSessionResult,
        previousSessionDate: Date,
        previousE1RM: Double,
        calendar: Calendar = .current
    ) {
        guard isEnabled else { return }
        
        let daysUntilNext = calendar.dateComponents([.day], from: previousSessionDate, to: nextSessionDate).day ?? 0
        
        let workingSets = nextExerciseResult.workingSets
        let nextLoad = workingSets.map(\.load).max() ?? .zero
        let nextE1RM = workingSets.map(\.estimatedE1RM).max() ?? 0
        
        let prescription = nextExerciseResult.prescription
        let targetRepsLower = prescription.targetRepsRange.lowerBound
        let wasFailure = workingSets.contains { $0.reps < targetRepsLower }
        let wasSuccess = !wasFailure
        
        lock.lock()
        defer { lock.unlock() }
        
        for (id, var entry) in pendingEntries where entry.sessionId == previousSessionId && entry.exerciseId == exerciseId {
            guard let outcome = entry.outcome else { continue }
            
            let loadDelta = nextLoad.value - outcome.actualLoadValue
            let loadDeltaPct = outcome.actualLoadValue > 0 ? (loadDelta / outcome.actualLoadValue) * 100 : 0
            let e1rmDelta = nextE1RM - previousE1RM
            let e1rmDeltaPct = previousE1RM > 0 ? (e1rmDelta / previousE1RM) * 100 : 0
            
            entry.nextSessionPerformance = NextSessionPerformance(
                daysUntilNextExposure: daysUntilNext,
                nextLoadValue: nextLoad.value,
                nextLoadUnit: nextLoad.unit,
                loadDeltaValue: loadDelta,
                loadDeltaPercentage: loadDeltaPct,
                nextWasSuccess: wasSuccess,
                nextWasFailure: wasFailure,
                e1rmDelta: e1rmDelta,
                e1rmDeltaPercentage: e1rmDeltaPct
            )
            
            pendingEntries[id] = entry
            logHandler?(entry)
            
            // Remove from pending after full linkage
            pendingEntries.removeValue(forKey: id)
        }
    }
    
    /// Cleans up old pending entries that were never completed.
    public func cleanupStaleEntries(olderThan days: Int = 14, calendar: Calendar = .current) {
        let cutoff = calendar.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        
        lock.lock()
        defer { lock.unlock() }
        
        pendingEntries = pendingEntries.filter { $0.value.timestamp > cutoff }
    }
    
    // MARK: - Feature Building Helpers
    
    private func buildHistorySummary(
        history: WorkoutHistory,
        from date: Date,
        calendar: Calendar
    ) -> HistorySummary {
        let sessions = history.sessions
        
        func sessionsInDays(_ days: Int) -> Int {
            let cutoff = calendar.date(byAdding: .day, value: -days, to: date) ?? date
            return sessions.filter { $0.date >= cutoff }.count
        }
        
        let sessionsLast7 = sessionsInDays(7)
        let sessionsLast14 = sessionsInDays(14)
        let sessionsLast28 = sessionsInDays(28)
        
        let volumeLast7 = history.totalVolume(lastDays: 7, from: date, calendar: calendar)
        let volumeLast14 = history.totalVolume(lastDays: 14, from: date, calendar: calendar)
        
        let cutoff14 = calendar.date(byAdding: .day, value: -14, to: date) ?? date
        let recentSessions = sessions.filter { $0.date >= cutoff14 }
        let avgDuration: Double? = {
            let durations = recentSessions.compactMap(\.durationMinutes)
            guard !durations.isEmpty else { return nil }
            return Double(durations.reduce(0, +)) / Double(durations.count)
        }()
        
        let cutoff28 = calendar.date(byAdding: .day, value: -28, to: date) ?? date
        let deloadsLast28 = sessions.filter { $0.date >= cutoff28 && $0.wasDeload }.count
        
        let daysSinceLast = sessions.first.flatMap {
            calendar.dateComponents([.day], from: $0.date, to: date).day
        }
        
        // Training streak (simplified: count consecutive weeks with >= 2 sessions)
        var streakWeeks = 0
        var checkDate = date
        while true {
            let weekStart = calendar.date(byAdding: .day, value: -7, to: checkDate) ?? checkDate
            let weekSessions = sessions.filter { $0.date >= weekStart && $0.date < checkDate }
            if weekSessions.count >= 2 {
                streakWeeks += 1
                checkDate = weekStart
            } else {
                break
            }
            if streakWeeks > 52 { break } // Cap at 1 year
        }
        
        return HistorySummary(
            sessionCount: sessions.count,
            sessionsLast7Days: sessionsLast7,
            sessionsLast14Days: sessionsLast14,
            sessionsLast28Days: sessionsLast28,
            volumeLast7Days: volumeLast7,
            volumeLast14Days: volumeLast14,
            avgSessionDurationMinutes: avgDuration,
            deloadSessionsLast28Days: deloadsLast28,
            daysSinceLastWorkout: daysSinceLast,
            trainingStreakWeeks: streakWeeks
        )
    }
    
    private func buildExposureRecords(
        exerciseId: String,
        history: WorkoutHistory,
        from date: Date,
        calendar: Calendar,
        limit: Int
    ) -> [ExposureRecord] {
        let results = history.exerciseResults(forExercise: exerciseId, limit: limit)
        
        return results.enumerated().compactMap { index, result -> ExposureRecord? in
            let session = history.sessions.first { $0.exerciseResults.contains { $0.id == result.id } }
            guard let session = session else { return nil }
            
            let daysAgo = calendar.dateComponents([.day], from: session.date, to: date).day ?? 0
            let workingSets = result.workingSets
            guard !workingSets.isEmpty else { return nil }
            
            let maxLoad = workingSets.map(\.load).max() ?? .zero
            let avgReps = Double(workingSets.map(\.reps).reduce(0, +)) / Double(workingSets.count)
            let observedRIRs = workingSets.compactMap(\.rirObserved)
            let avgRIR = observedRIRs.isEmpty ? nil : Double(observedRIRs.reduce(0, +)) / Double(observedRIRs.count)
            
            let prescription = result.prescription
            let targetRepsLower = prescription.targetRepsRange.lowerBound
            let targetRIR = prescription.targetRIR
            let grinderRirDelta = DirectionPolicyConfig.default.grinderRirDelta
            
            let wasFailure = workingSets.contains { $0.reps < targetRepsLower }
            let wasSuccess = !wasFailure
            let wasGrinder: Bool = {
                guard !observedRIRs.isEmpty, !wasFailure, targetRIR > 0 else { return false }
                let minObserved = observedRIRs.min() ?? targetRIR
                return minObserved <= (targetRIR - grinderRirDelta - 1)
            }()
            
            return ExposureRecord(
                date: session.date,
                daysAgo: daysAgo,
                loadValue: maxLoad.value,
                loadUnit: maxLoad.unit,
                avgReps: avgReps,
                avgRIR: avgRIR,
                wasSuccess: wasSuccess,
                wasFailure: wasFailure,
                wasGrinder: wasGrinder,
                sessionE1RM: result.bestE1RM,
                readinessScore: session.readinessScore,
                adjustmentKind: result.adjustmentKind ?? session.adjustmentKind
            )
        }
    }
    
    private func buildTrendStatistics(liftState: LiftState) -> TrendStatistics {
        let samples = liftState.e1rmHistory
        let trend = liftState.trend
        let hasTwoSessionDecline = TrendCalculator.hasTwoSessionDecline(samples: samples)
        
        guard samples.count >= 3 else {
            return TrendStatistics(
                trend: trend,
                slopePerSession: nil,
                slopePercentage: nil,
                rSquared: nil,
                dataPoints: samples.count,
                daysSpanned: nil,
                recentVolatility: nil,
                hasTwoSessionDecline: hasTwoSessionDecline
            )
        }
        
        // Compute linear regression
        let recent = Array(samples.suffix(5))
        let n = Double(recent.count)
        var sumX = 0.0, sumY = 0.0, sumXY = 0.0, sumX2 = 0.0, sumY2 = 0.0
        
        for (i, sample) in recent.enumerated() {
            let x = Double(i)
            let y = sample.value
            sumX += x
            sumY += y
            sumXY += x * y
            sumX2 += x * x
            sumY2 += y * y
        }
        
        let denominator = n * sumX2 - sumX * sumX
        guard denominator != 0 else {
            return TrendStatistics(
                trend: trend,
                slopePerSession: 0,
                slopePercentage: 0,
                rSquared: nil,
                dataPoints: samples.count,
                daysSpanned: nil,
                recentVolatility: nil,
                hasTwoSessionDecline: hasTwoSessionDecline
            )
        }
        
        let slope = (n * sumXY - sumX * sumY) / denominator
        let avgValue = sumY / n
        let slopePercentage = avgValue > 0 ? (slope / avgValue) * 100 : 0
        
        // R-squared
        let ssRes = recent.enumerated().reduce(0.0) { acc, pair in
            let (i, sample) = pair
            let predicted = slope * Double(i) + (sumY - slope * sumX) / n
            return acc + pow(sample.value - predicted, 2)
        }
        let ssTot = recent.reduce(0.0) { acc, sample in
            acc + pow(sample.value - avgValue, 2)
        }
        let rSquared = ssTot > 0 ? 1 - (ssRes / ssTot) : nil
        
        // Volatility (standard deviation)
        let recentVolatility: Double? = {
            guard recent.count >= 2 else { return nil }
            let variance = recent.reduce(0.0) { acc, sample in
                acc + pow(sample.value - avgValue, 2)
            } / Double(recent.count - 1)
            return sqrt(variance)
        }()
        
        // Days spanned
        let daysSpanned: Int? = {
            guard let first = samples.first, let last = samples.last else { return nil }
            return Calendar.current.dateComponents([.day], from: first.date, to: last.date).day
        }()
        
        return TrendStatistics(
            trend: trend,
            slopePerSession: slope,
            slopePercentage: slopePercentage,
            rSquared: rSquared,
            dataPoints: samples.count,
            daysSpanned: daysSpanned,
            recentVolatility: recentVolatility,
            hasTwoSessionDecline: hasTwoSessionDecline
        )
    }
    
    private func buildReadinessDistribution(
        current: Int,
        recentScores: [Int],
        history: WorkoutHistory,
        from date: Date,
        calendar: Calendar
    ) -> ReadinessDistribution {
        let scores = recentScores
        let sampleCount = scores.count
        
        guard sampleCount >= 2 else {
            return ReadinessDistribution(
                current: current,
                mean: scores.isEmpty ? nil : Double(scores.reduce(0, +)) / Double(scores.count),
                median: scores.isEmpty ? nil : Double(scores.sorted()[scores.count / 2]),
                stdDev: nil,
                min: scores.min(),
                max: scores.max(),
                lowReadinessCount: scores.filter { $0 < 50 }.count,
                consecutiveLowDays: history.consecutiveLowReadinessDays(threshold: 50, from: date, calendar: calendar),
                trend: nil,
                sampleCount: sampleCount
            )
        }
        
        let mean = Double(scores.reduce(0, +)) / Double(sampleCount)
        let sorted = scores.sorted()
        let median = Double(sorted[sampleCount / 2])
        let variance = scores.reduce(0.0) { acc, score in
            acc + pow(Double(score) - mean, 2)
        } / Double(sampleCount - 1)
        let stdDev = sqrt(variance)
        
        // Simple trend: compare first half mean to second half mean
        let trend: String? = {
            guard sampleCount >= 4 else { return nil }
            let half = sampleCount / 2
            let firstHalf = scores.prefix(half)
            let secondHalf = scores.suffix(half)
            let firstMean = Double(firstHalf.reduce(0, +)) / Double(firstHalf.count)
            let secondMean = Double(secondHalf.reduce(0, +)) / Double(secondHalf.count)
            
            let diff = secondMean - firstMean
            if diff > 5 { return "improving" }
            if diff < -5 { return "declining" }
            return "stable"
        }()
        
        return ReadinessDistribution(
            current: current,
            mean: mean,
            median: median,
            stdDev: stdDev,
            min: sorted.first,
            max: sorted.last,
            lowReadinessCount: scores.filter { $0 < 50 }.count,
            consecutiveLowDays: history.consecutiveLowReadinessDays(threshold: 50, from: date, calendar: calendar),
            trend: trend,
            sampleCount: sampleCount
        )
    }
    
    // MARK: - Counterfactual Computation
    
    private func computeCounterfactuals(
        signals: LiftSignals,
        baselineLoad: Load,
        plan: TrainingPlan
    ) -> [CounterfactualRecord] {
        return counterfactualPolicies.map { policy in
            let (direction, _) = DirectionPolicy.decideWithTrace(
                signals: signals,
                config: policy.directionConfig
            )
            
            let magnitude = MagnitudePolicy.compute(
                direction: direction,
                signals: signals,
                baseRoundingPolicy: plan.loadRoundingPolicy,
                config: policy.magnitudeConfig
            )
            
            var finalLoad = baselineLoad
            if magnitude.loadMultiplier != 1.0 {
                finalLoad = finalLoad * magnitude.loadMultiplier
            }
            if magnitude.absoluteIncrement.value != 0 {
                finalLoad = finalLoad + magnitude.absoluteIncrement
            }
            finalLoad = finalLoad.rounded(using: magnitude.roundingPolicy)
            
            return CounterfactualRecord(
                policyId: policy.id,
                policyDescription: policy.description,
                direction: direction.direction,
                primaryReason: direction.primaryReason,
                prescribedLoadValue: finalLoad.value,
                prescribedLoadUnit: finalLoad.unit,
                loadMultiplier: magnitude.loadMultiplier,
                absoluteIncrementValue: magnitude.absoluteIncrement.value,
                volumeAdjustment: magnitude.volumeAdjustment,
                confidence: direction.confidence
            )
        }
    }
}

// MARK: - Counterfactual Policy Definition

/// Definition of an alternative policy for counterfactual evaluation.
public struct CounterfactualPolicy: Sendable {
    public let id: String
    public let description: String
    public let directionConfig: DirectionPolicyConfig
    public let magnitudeConfig: MagnitudePolicyConfig
    
    public init(
        id: String,
        description: String,
        directionConfig: DirectionPolicyConfig,
        magnitudeConfig: MagnitudePolicyConfig
    ) {
        self.id = id
        self.description = description
        self.directionConfig = directionConfig
        self.magnitudeConfig = magnitudeConfig
    }
}

// MARK: - JSONL Export Helper

public extension TrainingDataLogger {
    
    /// Exports a log entry to JSONL format.
    static func toJSONL(_ entry: DecisionLogEntry) -> String? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        
        guard let data = try? encoder.encode(entry) else { return nil }
        return String(data: data, encoding: .utf8)
    }
    
    /// Creates a file-based log handler that appends entries to a JSONL file.
    static func fileLogHandler(path: String) -> (DecisionLogEntry) -> Void {
        return { entry in
            guard let jsonl = toJSONL(entry) else { return }
            let line = jsonl + "\n"
            
            let fileManager = FileManager.default
            if !fileManager.fileExists(atPath: path) {
                fileManager.createFile(atPath: path, contents: nil, attributes: nil)
            }
            
            guard let fileHandle = FileHandle(forWritingAtPath: path) else { return }
            defer { try? fileHandle.close() }
            
            fileHandle.seekToEndOfFile()
            if let data = line.data(using: .utf8) {
                fileHandle.write(data)
            }
        }
    }
}
