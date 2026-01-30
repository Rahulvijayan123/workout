// ProgressionPolicySelector.swift
// Protocol for selecting progression policies for the TrainingEngine.
//
// This abstraction allows the app to implement different policy selection strategies
// (shadow mode, bandit, etc.) without coupling the TrainingEngine to app-layer concerns.

import Foundation
import TrainingEngine

/// Protocol for selecting progression policies.
///
/// Implementations can provide different strategies:
/// - Shadow mode: Always execute baseline, but log counterfactual shadow policy
/// - Bandit mode: Actually explore alternative policies based on Thompson sampling
/// - Control mode: Pure baseline execution with no exploration
public protocol ProgressionPolicySelector: AnyObject, Sendable {
    /// Selects a policy for a given lift.
    ///
    /// - Parameters:
    ///   - signals: Snapshot of lift signals (features) for the current exercise.
    ///   - variationContext: Context about the exercise variation (substitution, family, etc.).
    ///   - userId: The user ID for per-user policy state.
    /// - Returns: A `PolicySelection` indicating which policy to use and exploration metadata.
    func selectPolicy(
        for signals: LiftSignalsSnapshot,
        variationContext: VariationContext,
        userId: String
    ) -> PolicySelection
    
    /// Called when an outcome is recorded to update policy state (e.g., bandit priors).
    ///
    /// - Parameters:
    ///   - entry: The decision log entry with outcome filled in.
    ///   - userId: The user ID.
    func recordOutcome(_ entry: DecisionLogEntry, userId: String)
}

// MARK: - Default Implementation

extension ProgressionPolicySelector {
    /// Default implementation that does nothing for outcome recording.
    /// Override in implementations that need to update state (e.g., bandit).
    public func recordOutcome(_ entry: DecisionLogEntry, userId: String) {
        // Default: no-op
    }
}

// MARK: - Control Mode Selector (Baseline Only)

/// A simple selector that always returns baseline control policy.
/// Use this when no exploration is desired.
public final class ControlModePolicySelector: ProgressionPolicySelector, @unchecked Sendable {
    
    public static let shared = ControlModePolicySelector()
    
    private init() {}
    
    public func selectPolicy(
        for signals: LiftSignalsSnapshot,
        variationContext: VariationContext,
        userId: String
    ) -> PolicySelection {
        return .baselineControl()
    }
}
