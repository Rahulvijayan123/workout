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
/// Key design decisions:
/// - Shadow selection **bypasses the exploration gate** so we always log a real counterfactual
///   (not "baseline" again when the gate would have blocked exploration)
/// - Shadow arms **exclude baseline** so `shadowPolicyId` is always a meaningful alternative
/// - We **never update bandit priors** in shadow mode (learning only from executed actions)
///
/// This is useful for:
/// - Gathering counterfactual data before deploying a bandit
/// - Evaluating new policies without risk
/// - Building confidence in policy performance before exploration
public final class ShadowModePolicySelector: ProgressionPolicySelector, @unchecked Sendable {
    
    /// The bandit selector to use for shadow policy selection.
    /// Configured to always pass the exploration gate and exclude baseline from arms.
    private let shadowBandit: ThompsonSamplingBanditPolicySelector
    
    /// Creates a shadow mode selector with an underlying bandit for shadow selection.
    ///
    /// - Parameter shadowBandit: The bandit to use for computing shadow policy selections.
    ///   The bandit should be configured to bypass gating and exclude baseline from arms.
    public init(shadowBandit: ThompsonSamplingBanditPolicySelector) {
        self.shadowBandit = shadowBandit
    }
    
    /// Creates a shadow mode selector with a default bandit configuration.
    ///
    /// The internal bandit is configured to:
    /// - **Bypass gating**: Always compute a shadow choice regardless of fail streaks, readiness, etc.
    /// - **Exclude baseline**: Shadow policy is always a non-baseline alternative (conservative, aggressive, etc.)
    /// - **Never update priors**: Learning happens only from actually-executed policies
    public convenience init(stateStore: BanditStateStore) {
        // Gate config that always passes - we want shadow logging unconditionally
        let bypassGateConfig = BanditGateConfig(
            minBaselineExposures: 0,
            minDaysSinceDeload: 0,
            maxFailStreak: Int.max,
            minReadiness: 0,
            allowDuringDeload: true
        )
        
        // Get default arms and filter out baseline so shadow is always a real alternative
        let nonBaselineArms = ThompsonSamplingBanditPolicySelector.defaultArms().filter { $0.id != "baseline" }
        
        // If somehow all arms are baseline (shouldn't happen), fall back to default arms
        // to avoid crashing. The shadow will be baseline in this edge case.
        let arms = nonBaselineArms.isEmpty ? nil : nonBaselineArms
        
        let bandit = ThompsonSamplingBanditPolicySelector(
            stateStore: stateStore,
            gateConfig: bypassGateConfig,
            arms: arms,
            isEnabled: true  // Always enabled for shadow selection
        )
        self.init(shadowBandit: bandit)
    }
    
    public func selectPolicy(
        for signals: LiftSignalsSnapshot,
        variationContext: VariationContext,
        userId: String
    ) -> PolicySelection {
        // Get what the bandit would have chosen (for shadow logging)
        // Note: shadowBandit is configured to bypass gating and exclude baseline,
        // so this will always return a non-baseline alternative policy.
        let shadowSelection = shadowBandit.selectPolicyIgnoringGate(
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
        // Shadow mode MUST NOT update bandit priors.
        // We only log counterfactuals; learning updates should only happen for executed actions.
        // The bandit learns only when explorationMode == "explore" (in ThompsonSamplingBanditPolicySelector).
    }
}
