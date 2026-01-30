// PolicySelection.swift
// Represents a policy selection for direction/magnitude decisions.
//
// Used by the policy selector layer to communicate:
// 1. Which policy configs to use for the actual decision (executed policy)
// 2. What exploration mode is active (control, shadow, explore)
// 3. Shadow policy info for counterfactual logging

import Foundation

/// Exploration mode for policy selection.
public enum ExplorationMode: String, Codable, Sendable {
    /// Control: baseline policy only, no exploration or shadow logging.
    case control = "control"
    
    /// Shadow: baseline policy executed, but alternative policy logged for offline evaluation.
    case shadow = "shadow"
    
    /// Explore: alternative policy actually executed (bandit mode).
    case explore = "explore"
}

/// Represents a policy selection made by the policy selector layer.
///
/// This is passed into the TrainingEngine to control which direction/magnitude
/// configs are used, and to provide metadata for logging.
public struct PolicySelection: Sendable {
    /// Identifier for the executed policy (e.g., "baseline", "conservative", "aggressive").
    public let executedPolicyId: String
    
    /// Direction config to use (nil = use default).
    public let directionConfig: DirectionPolicyConfig?
    
    /// Magnitude config to use (nil = use default).
    public let magnitudeConfig: MagnitudePolicyConfig?
    
    /// Probability of selecting this action (for importance weighting).
    /// For deterministic policies, this is 1.0.
    public let executedActionProbability: Double
    
    /// Current exploration mode.
    public let explorationMode: ExplorationMode
    
    /// Shadow policy ID (for shadow mode - what would have been chosen if exploring).
    public let shadowPolicyId: String?
    
    /// Shadow policy's action probability (for importance weighting in offline evaluation).
    public let shadowActionProbability: Double?
    
    /// Shadow policy's direction config (for counterfactual computation).
    public let shadowDirectionConfig: DirectionPolicyConfig?
    
    /// Shadow policy's magnitude config (for counterfactual computation).
    public let shadowMagnitudeConfig: MagnitudePolicyConfig?
    
    public init(
        executedPolicyId: String,
        directionConfig: DirectionPolicyConfig? = nil,
        magnitudeConfig: MagnitudePolicyConfig? = nil,
        executedActionProbability: Double = 1.0,
        explorationMode: ExplorationMode = .control,
        shadowPolicyId: String? = nil,
        shadowActionProbability: Double? = nil,
        shadowDirectionConfig: DirectionPolicyConfig? = nil,
        shadowMagnitudeConfig: MagnitudePolicyConfig? = nil
    ) {
        self.executedPolicyId = executedPolicyId
        self.directionConfig = directionConfig
        self.magnitudeConfig = magnitudeConfig
        self.executedActionProbability = executedActionProbability
        self.explorationMode = explorationMode
        self.shadowPolicyId = shadowPolicyId
        self.shadowActionProbability = shadowActionProbability
        self.shadowDirectionConfig = shadowDirectionConfig
        self.shadowMagnitudeConfig = shadowMagnitudeConfig
    }
    
    // MARK: - Factory Methods
    
    /// Creates a baseline control policy selection (no exploration, no shadow).
    public static func baselineControl() -> PolicySelection {
        PolicySelection(
            executedPolicyId: "baseline",
            directionConfig: nil,
            magnitudeConfig: nil,
            executedActionProbability: 1.0,
            explorationMode: .control
        )
    }
    
    /// Creates a baseline policy selection with shadow logging.
    ///
    /// - Parameters:
    ///   - shadowPolicyId: The policy ID that would have been chosen if exploring.
    ///   - shadowActionProbability: The probability of that shadow selection.
    ///   - shadowDirectionConfig: The direction config for the shadow policy.
    ///   - shadowMagnitudeConfig: The magnitude config for the shadow policy.
    public static func baselineShadow(
        shadowPolicyId: String,
        shadowActionProbability: Double,
        shadowDirectionConfig: DirectionPolicyConfig? = nil,
        shadowMagnitudeConfig: MagnitudePolicyConfig? = nil
    ) -> PolicySelection {
        PolicySelection(
            executedPolicyId: "baseline",
            directionConfig: nil,
            magnitudeConfig: nil,
            executedActionProbability: 1.0,
            explorationMode: .shadow,
            shadowPolicyId: shadowPolicyId,
            shadowActionProbability: shadowActionProbability,
            shadowDirectionConfig: shadowDirectionConfig,
            shadowMagnitudeConfig: shadowMagnitudeConfig
        )
    }
    
    /// Creates an exploration policy selection (alternative policy is actually executed).
    ///
    /// - Parameters:
    ///   - policyId: The policy ID being executed.
    ///   - actionProbability: The probability of selecting this policy.
    ///   - directionConfig: The direction config for this policy.
    ///   - magnitudeConfig: The magnitude config for this policy.
    public static func explore(
        policyId: String,
        actionProbability: Double,
        directionConfig: DirectionPolicyConfig? = nil,
        magnitudeConfig: MagnitudePolicyConfig? = nil
    ) -> PolicySelection {
        PolicySelection(
            executedPolicyId: policyId,
            directionConfig: directionConfig,
            magnitudeConfig: magnitudeConfig,
            executedActionProbability: actionProbability,
            explorationMode: .explore
        )
    }
}

/// Type alias for the policy selection provider closure.
///
/// This closure is called for each exercise during session planning to determine
/// which policy to use for that exercise's direction/magnitude computation.
///
/// - Parameters:
///   - signals: Snapshot of lift signals (features) for the current exercise.
///   - variationContext: Context about the exercise variation (substitution, family, etc.).
/// - Returns: A `PolicySelection` indicating which policy to use and exploration metadata.
public typealias PolicySelectionProvider = @Sendable (LiftSignalsSnapshot, VariationContext) -> PolicySelection
