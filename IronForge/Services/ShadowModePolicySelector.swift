// ShadowModePolicySelector.swift
// Shadow mode policy selector - executes baseline but logs counterfactual shadow policy.
//
// This allows offline evaluation of alternative policies without actually applying them.

import Foundation
import TrainingEngine

/// Shadow mode policy selector.
///
/// Always executes baseline policy but:
/// 1. Samples what an alternative policy (e.g., bandit) would have chosen
/// 2. Logs that as the "shadow policy" for offline evaluation
///
/// This is useful for:
/// - Gathering counterfactual data before deploying a bandit
/// - Evaluating new policies without risk
/// - Building confidence in policy performance before exploration
public final class ShadowModePolicySelector: ProgressionPolicySelector, @unchecked Sendable {
    
    /// The bandit selector to use for shadow policy selection.
    private let shadowBandit: ThompsonSamplingBanditPolicySelector
    
    /// Creates a shadow mode selector with an underlying bandit for shadow selection.
    ///
    /// - Parameter shadowBandit: The bandit to use for computing shadow policy selections.
    public init(shadowBandit: ThompsonSamplingBanditPolicySelector) {
        self.shadowBandit = shadowBandit
    }
    
    /// Creates a shadow mode selector with a default bandit configuration.
    public convenience init(stateStore: BanditStateStore) {
        let bandit = ThompsonSamplingBanditPolicySelector(
            stateStore: stateStore,
            isEnabled: false // Not used for actual selection, just shadow
        )
        self.init(shadowBandit: bandit)
    }
    
    public func selectPolicy(
        for signals: LiftSignalsSnapshot,
        variationContext: VariationContext,
        userId: String
    ) -> PolicySelection {
        // Get what the bandit would have chosen (for shadow logging)
        let shadowSelection = shadowBandit.selectPolicy(
            for: signals,
            variationContext: variationContext,
            userId: userId
        )
        
        // Return baseline execution with shadow policy logged
        return PolicySelection.baselineShadow(
            shadowPolicyId: shadowSelection.executedPolicyId,
            shadowActionProbability: shadowSelection.executedActionProbability,
            shadowDirectionConfig: shadowSelection.directionConfig,
            shadowMagnitudeConfig: shadowSelection.magnitudeConfig
        )
    }
    
    public func recordOutcome(_ entry: DecisionLogEntry, userId: String) {
        // In shadow mode, we still update bandit priors based on baseline outcomes
        // This allows the bandit to learn even though we're not applying its selections
        shadowBandit.recordOutcome(entry, userId: userId)
    }
}
