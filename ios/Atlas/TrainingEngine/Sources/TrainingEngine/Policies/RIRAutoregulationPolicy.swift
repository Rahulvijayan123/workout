// RIRAutoregulationPolicy.swift
// RIR-based autoregulation: adjust load based on observed RIR.

import Foundation

/// Configuration for RIR-based autoregulation.
public struct RIRAutoregulationConfig: Codable, Sendable, Hashable {
    /// Target RIR for sets.
    public let targetRIR: Int
    
    /// Percentage adjustment per RIR deviation.
    public let adjustmentPerRIR: Double
    
    /// Maximum adjustment per set (percentage).
    public let maxAdjustmentPerSet: Double
    
    /// Minimum load (won't go below this).
    public let minimumLoad: Load
    
    /// Whether to adjust load up if RIR is higher than target.
    public let allowUpwardAdjustment: Bool
    
    public init(
        targetRIR: Int = 2,
        adjustmentPerRIR: Double = 0.025,
        maxAdjustmentPerSet: Double = 0.10,
        minimumLoad: Load = .pounds(20),
        allowUpwardAdjustment: Bool = true
    ) {
        self.targetRIR = max(0, min(5, targetRIR))
        self.adjustmentPerRIR = max(0.01, min(0.05, adjustmentPerRIR))
        self.maxAdjustmentPerSet = max(0.05, min(0.20, maxAdjustmentPerSet))
        self.minimumLoad = minimumLoad
        self.allowUpwardAdjustment = allowUpwardAdjustment
    }
    
    /// Default configuration.
    public static let `default` = RIRAutoregulationConfig()
    
    /// Conservative configuration (smaller adjustments).
    public static let conservative = RIRAutoregulationConfig(
        targetRIR: 2,
        adjustmentPerRIR: 0.02,
        maxAdjustmentPerSet: 0.05,
        minimumLoad: .pounds(20),
        allowUpwardAdjustment: false
    )
}

/// RIR-based autoregulation policy implementation.
///
/// Algorithm:
/// 1. After each set, compare observed RIR to target RIR
/// 2. If RIR is lower than target (harder than expected), reduce next set load
/// 3. If RIR is higher than target (easier than expected), optionally increase
/// 4. Adjustments are capped to prevent large swings
public enum RIRAutoregulationPolicy {
    
    /// Computes the next session's starting load.
    public static func computeNextLoad(
        config: RIRAutoregulationConfig,
        prescription: SetPrescription,
        liftState: LiftState,
        context: ProgressionContext? = nil
    ) -> Load {
        // For autoregulation, we typically maintain the same starting load
        // and adjust during the session based on feel
        return liftState.lastWorkingWeight
    }
    
    /// Adjusts the next set based on current set performance.
    public static func adjustInSession(
        config: RIRAutoregulationConfig,
        currentResult: SetResult,
        plannedNext: SetPlan,
        roundingPolicy: LoadRoundingPolicy
    ) -> SetPlan {
        guard let observedRIR = currentResult.rirObserved else {
            // No RIR data, keep planned load
            return plannedNext
        }
        
        let targetRIR = config.targetRIR
        let rirDifference = observedRIR - targetRIR
        
        // Positive = easier than expected, negative = harder than expected
        var adjustmentFactor = Double(rirDifference) * config.adjustmentPerRIR
        
        // Cap adjustment
        adjustmentFactor = max(-config.maxAdjustmentPerSet, min(config.maxAdjustmentPerSet, adjustmentFactor))
        
        // Don't increase if not allowed
        if !config.allowUpwardAdjustment && adjustmentFactor > 0 {
            adjustmentFactor = 0
        }
        
        // Calculate new load.
        // Use the load actually lifted for the current set as the base so adjustments carry forward
        // even if prior sets were already adjusted (more realistic autoregulation).
        let baseLoad = currentResult.isWarmup ? plannedNext.targetLoad : currentResult.load
        let newLoadValue = baseLoad.value * (1.0 + adjustmentFactor)
        var newLoad = Load(value: newLoadValue, unit: baseLoad.unit)
        
        // Apply minimum
        if newLoad < config.minimumLoad {
            newLoad = config.minimumLoad
        }
        
        // Round
        newLoad = newLoad.rounded(using: roundingPolicy)
        
        var adjustedPlan = plannedNext
        adjustedPlan.targetLoad = newLoad
        
        // Optionally adjust RIR target based on fatigue
        if rirDifference < -1 {
            // Much harder than expected, allow higher RIR
            adjustedPlan.targetRIR = min(5, plannedNext.targetRIR + 1)
        }
        
        return adjustedPlan
    }
    
    /// Computes RIR-based load from target percentage.
    public static func computeLoadFromRIR(
        targetRIR: Int,
        e1rm: Double,
        targetReps: Int,
        unit: LoadUnit
    ) -> Load {
        // RIR effectively adds to rep count for percentage calculation
        let effectiveReps = targetReps + targetRIR
        let workingWeight = E1RMCalculator.workingWeight(fromE1RM: e1rm, targetReps: effectiveReps)
        return Load(value: workingWeight, unit: unit)
    }
    
    /// Evaluates RIR deviation and suggests adjustment.
    public static func evaluateRIRDeviation(
        config: RIRAutoregulationConfig,
        observedRIR: Int,
        targetRIR: Int
    ) -> RIRAdjustment {
        let deviation = observedRIR - targetRIR
        
        if deviation == 0 {
            return .onTarget
        } else if deviation > 0 {
            // Easier than expected
            let suggestedIncrease = config.adjustmentPerRIR * Double(deviation)
            return .easierThanExpected(
                rirOver: deviation,
                suggestedLoadIncrease: min(suggestedIncrease, config.maxAdjustmentPerSet)
            )
        } else {
            // Harder than expected
            let suggestedDecrease = config.adjustmentPerRIR * Double(abs(deviation))
            return .harderThanExpected(
                rirUnder: abs(deviation),
                suggestedLoadDecrease: min(suggestedDecrease, config.maxAdjustmentPerSet)
            )
        }
    }
}

/// Result of RIR evaluation.
public enum RIRAdjustment: Sendable, Hashable {
    case onTarget
    case easierThanExpected(rirOver: Int, suggestedLoadIncrease: Double)
    case harderThanExpected(rirUnder: Int, suggestedLoadDecrease: Double)
}
