// LinearProgressionPolicy.swift
// Linear progression: add fixed load each session if successful.
// Inspired by Liftosaur's `lp` built-in progression mode.

import Foundation

/// Configuration for linear progression.
public struct LinearProgressionConfig: Codable, Sendable, Hashable {
    /// Load increment on success.
    public let successIncrement: Load
    
    /// Load decrement on failure (if any).
    public let failureDecrement: Load?
    
    /// Deload percentage after consecutive failures.
    public let deloadPercentage: Double
    
    /// Number of consecutive failures before deload.
    public let failuresBeforeDeload: Int
    
    public init(
        successIncrement: Load = .pounds(5),
        failureDecrement: Load? = nil,
        deloadPercentage: Double = FailureThresholdDefaults.deloadPercentage,
        failuresBeforeDeload: Int = FailureThresholdDefaults.failuresBeforeDeload
    ) {
        self.successIncrement = successIncrement
        self.failureDecrement = failureDecrement
        self.deloadPercentage = FailureThresholdDefaults.clampedDeloadPercentage(deloadPercentage)
        self.failuresBeforeDeload = FailureThresholdDefaults.clampedFailureThreshold(failuresBeforeDeload)
    }
    
    /// Default configuration.
    public static let `default` = LinearProgressionConfig()
    
    /// Configuration for beginners (larger increments).
    public static let beginner = LinearProgressionConfig(
        successIncrement: .pounds(5),
        failureDecrement: nil,
        deloadPercentage: FailureThresholdDefaults.deloadPercentage,
        failuresBeforeDeload: 3
    )
    
    /// Configuration for smaller increments.
    public static let smallIncrement = LinearProgressionConfig(
        successIncrement: .pounds(2.5),
        failureDecrement: nil,
        deloadPercentage: FailureThresholdDefaults.deloadPercentage,
        failuresBeforeDeload: 3
    )
    
    /// Configuration for upper body lifts.
    public static let upperBody = LinearProgressionConfig(
        successIncrement: .pounds(2.5),
        failureDecrement: nil,
        deloadPercentage: FailureThresholdDefaults.deloadPercentage,
        failuresBeforeDeload: FailureThresholdDefaults.failuresBeforeDeload
    )
    
    /// Configuration for lower body lifts.
    public static let lowerBody = LinearProgressionConfig(
        successIncrement: .pounds(5),
        failureDecrement: nil,
        deloadPercentage: FailureThresholdDefaults.deloadPercentage,
        failuresBeforeDeload: FailureThresholdDefaults.failuresBeforeDeload
    )
}

/// Linear progression policy implementation.
///
/// Algorithm (inspired by Liftosaur's `lp`):
/// 1. If all sets completed at target reps → increase load by increment
/// 2. If failed (below target) → count failure
/// 3. After N failures → deload by percentage, reset failure count
public enum LinearProgressionPolicy {
    
    /// Computes the next session's target load.
    public static func computeNextLoad(
        config: LinearProgressionConfig,
        prescription: SetPrescription,
        liftState: LiftState,
        history: WorkoutHistory,
        exerciseId: String,
        context: ProgressionContext? = nil
    ) -> Load {
        // Get last session results
        guard let lastResult = history.exerciseResults(forExercise: exerciseId, limit: 1).first else {
            // No history, use last working weight
            return liftState.lastWorkingWeight
        }
        
        let workingSets = lastResult.workingSets
        guard !workingSets.isEmpty else {
            return liftState.lastWorkingWeight
        }
        
        // Determine success/failure
        let targetReps = prescription.targetRepsRange.lowerBound
        let allSuccessful = workingSets.allSatisfy { $0.reps >= targetReps }
        
        // Current load (average)
        let avgLoad = workingSets.map(\.load.value).reduce(0, +) / Double(workingSets.count)
        let currentLoad = Load(value: avgLoad, unit: liftState.lastWorkingWeight.unit)
        
        if allSuccessful {
            // Success - increase load
            return currentLoad + config.successIncrement
        }
        
        // Check failure count
        if liftState.failureCount >= config.failuresBeforeDeload {
            // Deload
            let deloadedValue = currentLoad.value * (1.0 - config.deloadPercentage)
            return Load(value: max(0, deloadedValue), unit: currentLoad.unit)
        }
        
        // Failed but not enough for deload
        if let decrement = config.failureDecrement {
            return currentLoad - decrement
        }
        
        // Maintain same load
        return currentLoad
    }
    
    /// Evaluates session for linear progression.
    public static func evaluateSession(
        config: LinearProgressionConfig,
        prescription: SetPrescription,
        sessionResult: ExerciseSessionResult,
        currentFailureCount: Int
    ) -> LinearProgressionDecision {
        let workingSets = sessionResult.workingSets
        guard !workingSets.isEmpty else {
            return .hold(reason: "No working sets completed")
        }
        
        let targetReps = prescription.targetRepsRange.lowerBound
        let allSuccessful = workingSets.allSatisfy { $0.reps >= targetReps }
        
        if allSuccessful {
            return .increase(
                amount: config.successIncrement,
                reason: "All sets completed at \(targetReps)+ reps"
            )
        }
        
        let newFailureCount = currentFailureCount + 1
        
        if newFailureCount >= config.failuresBeforeDeload {
            let deloadAmount = Load(
                value: workingSets.first!.load.value * config.deloadPercentage,
                unit: workingSets.first!.load.unit
            )
            return .deload(
                amount: deloadAmount,
                reason: "Failed \(newFailureCount) consecutive sessions"
            )
        }
        
        return .failure(
            currentCount: newFailureCount,
            deloadAt: config.failuresBeforeDeload,
            reason: "Failed to complete all sets at \(targetReps) reps"
        )
    }
}

/// Decision from linear progression evaluation.
public enum LinearProgressionDecision: Sendable, Hashable {
    case increase(amount: Load, reason: String)
    case hold(reason: String)
    case failure(currentCount: Int, deloadAt: Int, reason: String)
    case deload(amount: Load, reason: String)
}
