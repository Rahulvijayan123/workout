// InSessionAdjustmentPolicy.swift
// In-session adjustment policies (e.g., RIR autoregulation).
//
// This is intentionally split from between-session progression policies so an exercise can
// use (for example) double progression across sessions AND RIR-based autoregulation within a session.

import Foundation

/// Type of in-session adjustment policy.
/// Determines how to adjust the *next* set given the result of the current set.
public enum InSessionAdjustmentPolicyType: Codable, Sendable, Hashable {
    /// RIR-based autoregulation: adjust next set load by RIR deviation.
    case rirAutoregulation(config: RIRAutoregulationConfig)

    /// Top set + backoff: after completing the top set, adjust backoff loads using daily max.
    /// This enables true "top set drives backoffs" behavior within a session.
    case topSetBackoff(config: TopSetBackoffConfig)
    
    /// No in-session adjustment.
    case none
    
    /// Default in-session policy derived from a prescription.
    /// If the prescription is marked as autoregulated, use RIR autoregulation; otherwise none.
    public static func defaultFor(prescription: SetPrescription) -> InSessionAdjustmentPolicyType {
        switch prescription.loadStrategy {
        case .rpeAutoregulated:
            return .rirAutoregulation(config: .from(prescription: prescription))
        case .topSetBackoff:
            return .topSetBackoff(config: .default)
        default:
            return .none
        }
    }
    
    /// Applies an in-session adjustment to the next set plan.
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
        case .topSetBackoff(let config):
            // Only backoff sets are adjusted.
            // - When moving from top set (set 0) -> first backoff (set 1), compute daily max from top set.
            // - For subsequent backoff sets, propagate the previous set's load so all backoffs match.
            guard config.useDailyMax else {
                return plannedNext
            }
            // If the top set wasn't actually completed (or had zero reps), do not reshape the rest
            // of the workout based on it.
            guard currentResult.completed, currentResult.reps > 0, !currentResult.isWarmup else {
                return plannedNext
            }
            guard let pct = plannedNext.backoffPercentage else {
                return plannedNext
            }
            
            var adjusted = plannedNext
            
            if plannedNext.setIndex == 1 {
                // Current set is the top set.
                let dailyMax = TopSetBackoffPolicy.computeDailyMax(
                    topSetResult: currentResult,
                    targetReps: plannedNext.targetReps
                )
                let backoffWeight = dailyMax * pct
                adjusted.targetLoad = Load(value: backoffWeight, unit: currentResult.load.unit)
                    .rounded(using: roundingPolicy)
            } else {
                // Propagate backoff load forward so all backoff sets match.
                adjusted.targetLoad = currentResult.load.rounded(using: roundingPolicy)
            }
            
            return adjusted
        case .none:
            return plannedNext
        }
    }
}

// MARK: - Codable

extension InSessionAdjustmentPolicyType {
    enum CodingKeys: String, CodingKey {
        case type
        case config
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        
        switch type {
        case "rirAutoregulation":
            let config = try container.decode(RIRAutoregulationConfig.self, forKey: .config)
            self = .rirAutoregulation(config: config)
        case "topSetBackoff":
            let config = try container.decode(TopSetBackoffConfig.self, forKey: .config)
            self = .topSetBackoff(config: config)
        case "none":
            self = .none
        default:
            self = .none
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        switch self {
        case .rirAutoregulation(let config):
            try container.encode("rirAutoregulation", forKey: .type)
            try container.encode(config, forKey: .config)
        case .topSetBackoff(let config):
            try container.encode("topSetBackoff", forKey: .type)
            try container.encode(config, forKey: .config)
        case .none:
            try container.encode("none", forKey: .type)
        }
    }
}

// MARK: - RIRAutoregulationConfig convenience

public extension RIRAutoregulationConfig {
    /// Builds a RIR autoregulation config derived from a set prescription.
    static func from(prescription: SetPrescription) -> RIRAutoregulationConfig {
        RIRAutoregulationConfig(
            targetRIR: prescription.targetRIR,
            adjustmentPerRIR: RIRAutoregulationConfig.default.adjustmentPerRIR,
            maxAdjustmentPerSet: RIRAutoregulationConfig.default.maxAdjustmentPerSet,
            minimumLoad: RIRAutoregulationConfig.default.minimumLoad,
            allowUpwardAdjustment: RIRAutoregulationConfig.default.allowUpwardAdjustment
        )
    }
}

