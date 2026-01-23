// ProgressionPolicy.swift
// Progression policy types and implementations.
// Inspired by Liftosaur's per-exercise state-based progression logic.

import Foundation

/// Type of progression policy.
/// Each policy defines how load/reps should progress between and within sessions.
public enum ProgressionPolicyType: Codable, Sendable, Hashable {
    /// Double progression: add reps until top of range, then add load and reset reps.
    /// Inspired by Liftosaur's `dp` (double progression) built-in.
    case doubleProgression(config: DoubleProgressionConfig)
    
    /// Top set + backoff: perform a top set, then backoff sets at percentage.
    case topSetBackoff(config: TopSetBackoffConfig)
    
    /// RIR-based autoregulation: adjust load based on observed RIR.
    case rirAutoregulation(config: RIRAutoregulationConfig)
    
    /// Linear progression: add fixed load each session if successful.
    /// Inspired by Liftosaur's `lp` (linear progression) built-in.
    case linearProgression(config: LinearProgressionConfig)
    
    /// No progression (maintain current load).
    case none
    
    /// Default policy based on movement pattern and goals.
    public static func defaultPolicy(
        for movementPattern: MovementPattern,
        goals: [TrainingGoal]
    ) -> ProgressionPolicyType {
        let primaryGoal = goals.first ?? .generalFitness
        
        // Compound movements with strength goals → linear or top-set/backoff
        if movementPattern.isCompound {
            switch primaryGoal {
            case .strength, .powerlifting:
                return .topSetBackoff(config: .default)
            case .hypertrophy:
                return .doubleProgression(config: .hypertrophy)
            default:
                return .doubleProgression(config: .default)
            }
        }
        
        // Isolation movements → double progression
        return .doubleProgression(config: .hypertrophy)
    }
    
    // MARK: - Policy Logic
    
    /// Computes the target load for next session (baseline).
    /// This does **not** apply a global deload intensity reduction (that is handled at the engine level).
    public func computeNextLoad(
        prescription: SetPrescription,
        liftState: LiftState,
        history: WorkoutHistory,
        exerciseId: String,
        context: ProgressionContext? = nil
    ) -> Load {
        switch self {
        case .doubleProgression(let config):
            return DoubleProgressionPolicy.computeNextLoad(
                config: config,
                prescription: prescription,
                liftState: liftState,
                history: history,
                exerciseId: exerciseId,
                context: context
            )
            
        case .topSetBackoff(let config):
            return TopSetBackoffPolicy.computeTopSetLoad(
                config: config,
                prescription: prescription,
                liftState: liftState,
                history: history,
                exerciseId: exerciseId,
                context: context
            )
            
        case .rirAutoregulation(let config):
            return RIRAutoregulationPolicy.computeNextLoad(
                config: config,
                prescription: prescription,
                liftState: liftState,
                context: context
            )
            
        case .linearProgression(let config):
            return LinearProgressionPolicy.computeNextLoad(
                config: config,
                prescription: prescription,
                liftState: liftState,
                history: history,
                exerciseId: exerciseId,
                context: context
            )
            
        case .none:
            return liftState.lastWorkingWeight
        }
    }

    /// Computes the target load for next session, optionally applying a simple deload reduction.
    /// Prefer using the engine-level deload config for deload intensity/volume; this is retained for convenience.
    public func computeNextLoad(
        prescription: SetPrescription,
        liftState: LiftState,
        history: WorkoutHistory,
        exerciseId: String,
        isDeload: Bool,
        context: ProgressionContext? = nil
    ) -> Load {
        let base = computeNextLoad(
            prescription: prescription,
            liftState: liftState,
            history: history,
            exerciseId: exerciseId,
            context: context
        )
        
        guard isDeload else { return base }
        return base * 0.90
    }

    /// Computes the target reps for the next session for this exercise.
    /// For most policies this is the lower bound of the rep range; for double progression it progresses reps.
    public func computeNextTargetReps(
        prescription: SetPrescription,
        history: WorkoutHistory,
        exerciseId: String
    ) -> Int {
        switch self {
        case .doubleProgression(let config):
            return DoubleProgressionPolicy.computeTargetReps(
                config: config,
                prescription: prescription,
                history: history,
                exerciseId: exerciseId
            )
        default:
            return prescription.targetRepsRange.lowerBound
        }
    }
    
    /// Computes load for a specific set within a session.
    public func computeSetLoad(
        setIndex: Int,
        totalSets: Int,
        baseLoad: Load,
        prescription: SetPrescription,
        roundingPolicy: LoadRoundingPolicy
    ) -> Load {
        switch self {
        case .topSetBackoff(let config):
            return TopSetBackoffPolicy.computeSetLoad(
                config: config,
                setIndex: setIndex,
                totalSets: totalSets,
                topSetLoad: baseLoad,
                roundingPolicy: roundingPolicy
            )
            
        default:
            // Most policies use same load for all working sets
            return baseLoad.rounded(using: roundingPolicy)
        }
    }
    
    /// Adjusts the next set during a session based on current performance.
    public func adjustInSession(
        currentResult: SetResult,
        plannedNext: SetPlan,
        roundingPolicy: LoadRoundingPolicy
    ) -> SetPlan {
        switch self {
        case .rirAutoregulation(let config):
            return RIRAutoregulationPolicy.adjustInSession(
                config: config,
                currentResult: currentResult,
                plannedNext: plannedNext,
                roundingPolicy: roundingPolicy
            )
            
        default:
            // Other policies don't adjust mid-session by default
            return plannedNext
        }
    }
}

// MARK: - ProgressionPolicyType Codable

extension ProgressionPolicyType {
    enum CodingKeys: String, CodingKey {
        case type
        case config
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        
        switch type {
        case "doubleProgression":
            let config = try container.decode(DoubleProgressionConfig.self, forKey: .config)
            self = .doubleProgression(config: config)
        case "topSetBackoff":
            let config = try container.decode(TopSetBackoffConfig.self, forKey: .config)
            self = .topSetBackoff(config: config)
        case "rirAutoregulation":
            let config = try container.decode(RIRAutoregulationConfig.self, forKey: .config)
            self = .rirAutoregulation(config: config)
        case "linearProgression":
            let config = try container.decode(LinearProgressionConfig.self, forKey: .config)
            self = .linearProgression(config: config)
        case "none":
            self = .none
        default:
            self = .none
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        switch self {
        case .doubleProgression(let config):
            try container.encode("doubleProgression", forKey: .type)
            try container.encode(config, forKey: .config)
        case .topSetBackoff(let config):
            try container.encode("topSetBackoff", forKey: .type)
            try container.encode(config, forKey: .config)
        case .rirAutoregulation(let config):
            try container.encode("rirAutoregulation", forKey: .type)
            try container.encode(config, forKey: .config)
        case .linearProgression(let config):
            try container.encode("linearProgression", forKey: .type)
            try container.encode(config, forKey: .config)
        case .none:
            try container.encode("none", forKey: .type)
        }
    }
}
