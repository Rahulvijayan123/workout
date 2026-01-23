// TopSetBackoffPolicy.swift
// Top set + backoff: perform a top set, then backoff sets at percentage.

import Foundation

/// Configuration for top set + backoff progression.
public struct TopSetBackoffConfig: Codable, Sendable, Hashable {
    /// Number of backoff sets after the top set.
    public let backoffSetCount: Int
    
    /// Percentage of top set weight for backoff sets (0-1).
    public let backoffPercentage: Double
    
    /// Load increment for top set progression.
    public let loadIncrement: Load
    
    /// Whether to use daily max (autoregulated) or planned weight.
    public let useDailyMax: Bool
    
    /// Minimum reps on top set to count as success.
    public let minimumTopSetReps: Int
    
    public init(
        backoffSetCount: Int = 3,
        backoffPercentage: Double = 0.85,
        loadIncrement: Load = .pounds(5),
        useDailyMax: Bool = false,
        minimumTopSetReps: Int = 1
    ) {
        self.backoffSetCount = max(1, backoffSetCount)
        self.backoffPercentage = max(0.5, min(0.95, backoffPercentage))
        self.loadIncrement = loadIncrement
        self.useDailyMax = useDailyMax
        self.minimumTopSetReps = max(1, minimumTopSetReps)
    }
    
    /// Default configuration.
    public static let `default` = TopSetBackoffConfig()
    
    /// Configuration for strength-focused training.
    public static let strength = TopSetBackoffConfig(
        backoffSetCount: 4,
        backoffPercentage: 0.80,
        loadIncrement: .pounds(5),
        useDailyMax: true,
        minimumTopSetReps: 1
    )
    
    /// Configuration for powerlifting-style training.
    public static let powerlifting = TopSetBackoffConfig(
        backoffSetCount: 3,
        backoffPercentage: 0.75,
        loadIncrement: .pounds(5),
        useDailyMax: true,
        minimumTopSetReps: 1
    )
}

/// Top set + backoff policy implementation.
///
/// Algorithm:
/// 1. Perform a top set at target load
/// 2. Compute daily estimated strength from top set result
/// 3. Set backoff loads as percentage of top set
/// 4. If top set successful, increase target next session
public enum TopSetBackoffPolicy {
    
    /// Computes the top set target load.
    public static func computeTopSetLoad(
        config: TopSetBackoffConfig,
        prescription: SetPrescription,
        liftState: LiftState,
        history: WorkoutHistory,
        exerciseId: String,
        context: ProgressionContext? = nil
    ) -> Load {
        // Get last session's top set result
        guard let lastResult = history.exerciseResults(forExercise: exerciseId, limit: 1).first else {
            // No history, use last working weight
            return liftState.lastWorkingWeight
        }
        
        // Find the top set (first non-warmup set, usually heaviest)
        let workingSets = lastResult.workingSets
        guard let topSet = workingSets.first else {
            return liftState.lastWorkingWeight
        }
        
        // Check if top set was successful.
        // Use the prescription's target reps as the primary success criteria; config can enforce a higher minimum.
        let targetReps = prescription.targetRepsRange.lowerBound
        let requiredReps = max(targetReps, config.minimumTopSetReps)
        let wasSuccessful = topSet.reps >= requiredReps
        
        if wasSuccessful {
            // Increase load for next session
            return topSet.load + config.loadIncrement
        } else {
            // Maintain or slightly reduce
            return topSet.load
        }
    }
    
    /// Computes load for a specific set (top set or backoff).
    public static func computeSetLoad(
        config: TopSetBackoffConfig,
        setIndex: Int,
        totalSets: Int,
        topSetLoad: Load,
        roundingPolicy: LoadRoundingPolicy
    ) -> Load {
        if setIndex == 0 {
            // First set is the top set
            return topSetLoad.rounded(using: roundingPolicy)
        }
        
        // Backoff sets
        let backoffLoad = topSetLoad * config.backoffPercentage
        return backoffLoad.rounded(using: roundingPolicy)
    }
    
    /// Computes daily estimated max from top set performance.
    public static func computeDailyMax(
        topSetResult: SetResult,
        targetReps: Int
    ) -> Double {
        // Use Brzycki formula to estimate 1RM
        return E1RMCalculator.brzycki(
            weight: topSetResult.load.value,
            reps: topSetResult.reps
        )
    }
    
    /// Adjusts backoff sets based on top set performance.
    public static func adjustBackoffSets(
        config: TopSetBackoffConfig,
        topSetResult: SetResult,
        plannedBackoffSets: [SetPlan],
        roundingPolicy: LoadRoundingPolicy
    ) -> [SetPlan] {
        // Compute daily max from actual top set
        let dailyMax = computeDailyMax(topSetResult: topSetResult, targetReps: 1)
        
        // Backoff percentage of daily max
        let backoffWeight = dailyMax * config.backoffPercentage
        let backoffLoad = Load(value: backoffWeight, unit: topSetResult.load.unit)
            .rounded(using: roundingPolicy)
        
        return plannedBackoffSets.map { plan in
            var adjusted = plan
            adjusted.targetLoad = backoffLoad
            return adjusted
        }
    }
    
    /// Evaluates top set performance for progression.
    public static func evaluateTopSet(
        config: TopSetBackoffConfig,
        result: SetResult,
        targetReps: Int
    ) -> TopSetEvaluation {
        let actualReps = result.reps
        let requiredReps = max(targetReps, config.minimumTopSetReps)
        let targetMet = actualReps >= requiredReps
        let exceededTarget = actualReps > targetReps
        
        if exceededTarget {
            return .exceededTarget(
                repsOver: actualReps - targetReps,
                suggestedIncrease: config.loadIncrement
            )
        } else if targetMet {
            return .metTarget
        } else {
            return .missedTarget(repsMissed: requiredReps - actualReps)
        }
    }
}

/// Result of top set evaluation.
public enum TopSetEvaluation: Sendable, Hashable {
    case exceededTarget(repsOver: Int, suggestedIncrease: Load)
    case metTarget
    case missedTarget(repsMissed: Int)
}
