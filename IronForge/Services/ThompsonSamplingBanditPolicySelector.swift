// ThompsonSamplingBanditPolicySelector.swift
// Thompson sampling multi-armed bandit for policy selection.
//
// Arms: baseline + counterfactual policies (conservative, aggressive, linear_only)
// State: per-(userId, familyReferenceKey) Beta priors for each arm
// Selection: Thompson sample each arm's Beta, choose argmax, return propensity
// Update: Compute reward from outcome, update alpha/beta for executed arm

import Foundation
import TrainingEngine

/// Exploration gate configuration.
public struct BanditGateConfig: Codable, Sendable {
    /// Minimum number of baseline exposures before exploration.
    public let minBaselineExposures: Int
    
    /// Minimum days since last deload before exploration.
    public let minDaysSinceDeload: Int
    
    /// Maximum fail streak before falling back to baseline.
    public let maxFailStreak: Int
    
    /// Minimum readiness score for exploration.
    public let minReadiness: Int
    
    /// Whether to allow exploration during deload sessions.
    public let allowDuringDeload: Bool
    
    public init(
        minBaselineExposures: Int = 5,
        minDaysSinceDeload: Int = 7,
        maxFailStreak: Int = 1,
        minReadiness: Int = 50,
        allowDuringDeload: Bool = false
    ) {
        self.minBaselineExposures = minBaselineExposures
        self.minDaysSinceDeload = minDaysSinceDeload
        self.maxFailStreak = maxFailStreak
        self.minReadiness = minReadiness
        self.allowDuringDeload = allowDuringDeload
    }
    
    public static let `default` = BanditGateConfig()
    
    /// Conservative gate for initial deployment.
    public static let conservative = BanditGateConfig(
        minBaselineExposures: 10,
        minDaysSinceDeload: 14,
        maxFailStreak: 0,
        minReadiness: 60,
        allowDuringDeload: false
    )
}

/// Bandit arm definition.
public struct BanditArm: Sendable, Hashable {
    /// Unique identifier for the arm.
    public let id: String
    
    /// Direction policy config (nil = use default).
    public let directionConfig: DirectionPolicyConfig?
    
    /// Magnitude policy config (nil = use default).
    public let magnitudeConfig: MagnitudePolicyConfig?
    
    public init(
        id: String,
        directionConfig: DirectionPolicyConfig? = nil,
        magnitudeConfig: MagnitudePolicyConfig? = nil
    ) {
        self.id = id
        self.directionConfig = directionConfig
        self.magnitudeConfig = magnitudeConfig
    }
    
    // Hash/equality are defined on `id` only.
    // Configs are not hashable/codable and should not affect arm identity.
    public static func == (lhs: BanditArm, rhs: BanditArm) -> Bool {
        lhs.id == rhs.id
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    /// The baseline arm (default configs).
    public static let baseline = BanditArm(id: "baseline")
}

/// Thompson sampling bandit policy selector.
///
/// Implements a multi-armed bandit for selecting between baseline and alternative
/// progression policies. Uses Thompson sampling with Beta priors for exploration.
public final class ThompsonSamplingBanditPolicySelector: ProgressionPolicySelector, @unchecked Sendable {
    
    /// State store for persisting bandit priors.
    private let stateStore: BanditStateStore
    
    /// Exploration gate configuration.
    public let gateConfig: BanditGateConfig
    
    /// Available bandit arms.
    public let arms: [BanditArm]
    
    /// Whether bandit is enabled (if false, always returns baseline).
    public var isEnabled: Bool
    
    /// Number of samples for propensity estimation.
    private let propensitySamples: Int
    
    /// Pain severity threshold for injury detection.
    public let painSeverityThreshold: Int
    
    /// Random number generator for deterministic testing (optional).
    private var rng: RandomNumberGenerator
    
    /// Lock for thread safety.
    private let lock = NSLock()
    
    /// IDs of decisions we've already updated priors for (to prevent double-counting).
    private var updatedDecisionIds = Set<UUID>()
    
    /// Creates a Thompson sampling bandit policy selector.
    ///
    /// - Parameters:
    ///   - stateStore: Store for persisting bandit state.
    ///   - gateConfig: Configuration for the exploration gate.
    ///   - arms: Available bandit arms (defaults to baseline + counterfactual policies).
    ///   - isEnabled: Whether bandit is enabled (default: false for safety).
    ///   - propensitySamples: Number of samples for propensity estimation.
    ///   - painSeverityThreshold: Pain severity threshold for injury (default: 5).
    ///   - rng: Random number generator (defaults to system random).
    public init(
        stateStore: BanditStateStore,
        gateConfig: BanditGateConfig = .default,
        arms: [BanditArm]? = nil,
        isEnabled: Bool = false,
        propensitySamples: Int = 128,
        painSeverityThreshold: Int = 5,
        rng: RandomNumberGenerator = SystemRandomNumberGenerator()
    ) {
        self.stateStore = stateStore
        self.gateConfig = gateConfig
        self.isEnabled = isEnabled
        self.propensitySamples = propensitySamples
        self.painSeverityThreshold = painSeverityThreshold
        self.rng = rng
        
        // Default arms: baseline + counterfactual policies from TrainingDataLogger
        self.arms = arms ?? Self.defaultArms()
    }
    
    /// Returns the default set of bandit arms.
    public static func defaultArms() -> [BanditArm] {
        let counterfactualPolicies = TrainingDataLogger.shared.counterfactualPolicies
        
        var arms = [BanditArm.baseline]
        
        for policy in counterfactualPolicies {
            arms.append(BanditArm(
                id: policy.id,
                directionConfig: policy.directionConfig,
                magnitudeConfig: policy.magnitudeConfig
            ))
        }
        
        return arms
    }
    
    // MARK: - ProgressionPolicySelector
    
    public func selectPolicy(
        for signals: LiftSignalsSnapshot,
        variationContext: VariationContext,
        userId: String
    ) -> PolicySelection {
        // If disabled, always return baseline
        guard isEnabled else {
            return .baselineControl()
        }
        
        // Check exploration gate
        guard passesExplorationGate(signals: signals) else {
            return .baselineControl()
        }
        
        // Get family key for state lookup (familyReferenceKey is always non-nil)
        let familyKey = variationContext.familyReferenceKey
        
        // Get current priors
        let priors = stateStore.getPriors(userId: userId, familyKey: familyKey, armIds: arms.map(\.id))
        
        // Thompson sample and select best arm
        let (selectedArm, propensity) = thompsonSample(priors: priors)
        
        // Return policy selection
        if selectedArm.id == "baseline" {
            return PolicySelection(
                executedPolicyId: selectedArm.id,
                directionConfig: nil,
                magnitudeConfig: nil,
                executedActionProbability: propensity,
                explorationMode: .explore
            )
        } else {
            return PolicySelection(
                executedPolicyId: selectedArm.id,
                directionConfig: selectedArm.directionConfig,
                magnitudeConfig: selectedArm.magnitudeConfig,
                executedActionProbability: propensity,
                explorationMode: .explore
            )
        }
    }
    
    public func recordOutcome(_ entry: DecisionLogEntry, userId: String) {
        // Only update if we have an outcome
        guard let outcome = entry.outcome else { return }
        
        // Prevent double-counting
        lock.lock()
        if updatedDecisionIds.contains(entry.id) {
            lock.unlock()
            return
        }
        updatedDecisionIds.insert(entry.id)
        // Trim old IDs to prevent unbounded growth (keep last 1000)
        if updatedDecisionIds.count > 1000 {
            _ = updatedDecisionIds.popFirst()
        }
        lock.unlock()
        
        // Only update for explore mode (not shadow/control)
        guard entry.explorationMode == "explore" else { return }
        
        // Get family key (familyReferenceKey is always non-nil)
        let familyKey = entry.variationContext.familyReferenceKey
        
        // Compute reward
        let reward = computeReward(outcome: outcome)
        
        // Update priors for the executed arm
        stateStore.updatePrior(
            userId: userId,
            familyKey: familyKey,
            armId: entry.executedPolicyId,
            reward: reward
        )
    }
    
    // MARK: - Private Helpers
    
    /// Checks if the exploration gate passes for the given signals.
    private func passesExplorationGate(signals: LiftSignalsSnapshot) -> Bool {
        // Check minimum baseline exposures
        if signals.successfulSessionsCount < gateConfig.minBaselineExposures {
            return false
        }
        
        // Check days since deload
        if let daysSinceDeload = signals.daysSinceDeload,
           daysSinceDeload < gateConfig.minDaysSinceDeload {
            return false
        }
        
        // Check fail streak
        if signals.failStreak > gateConfig.maxFailStreak {
            return false
        }
        
        // Check readiness
        if signals.todayReadiness < gateConfig.minReadiness {
            return false
        }
        
        // Check deload session
        if signals.sessionDeloadTriggered && !gateConfig.allowDuringDeload {
            return false
        }
        
        return true
    }
    
    /// Performs Thompson sampling and returns the selected arm with its propensity.
    private func thompsonSample(priors: [String: BetaPrior]) -> (BanditArm, Double) {
        lock.lock()
        defer { lock.unlock() }
        
        // Sample from each arm's Beta distribution
        var samples: [(arm: BanditArm, sample: Double)] = []
        
        for arm in arms {
            let prior = priors[arm.id] ?? BetaPrior()
            let sample = sampleBeta(alpha: prior.alpha, beta: prior.beta)
            samples.append((arm, sample))
        }
        
        // Find argmax
        guard let best = samples.max(by: { $0.sample < $1.sample }) else {
            return (BanditArm.baseline, 1.0)
        }
        
        // Estimate propensity via repeated sampling
        var winCounts: [String: Int] = [:]
        for arm in arms {
            winCounts[arm.id] = 0
        }
        
        for _ in 0..<propensitySamples {
            var roundSamples: [(String, Double)] = []
            for arm in arms {
                let prior = priors[arm.id] ?? BetaPrior()
                let sample = sampleBeta(alpha: prior.alpha, beta: prior.beta)
                roundSamples.append((arm.id, sample))
            }
            
            if let winner = roundSamples.max(by: { $0.1 < $1.1 }) {
                winCounts[winner.0, default: 0] += 1
            }
        }
        
        let propensity = Double(winCounts[best.arm.id, default: 0]) / Double(propensitySamples)
        // IMPORTANT: This should represent P(executed_action | executed_policy, state_at_decision_time).
        // We only clamp to a tiny epsilon to avoid exactly-zero probabilities from Monte Carlo variance.
        let clamped = max(1e-6, min(1.0, propensity))
        return (best.arm, clamped)
    }
    
    /// Samples from a Beta distribution using the Gamma method.
    private func sampleBeta(alpha: Double, beta: Double) -> Double {
        let x = sampleGamma(shape: alpha)
        let y = sampleGamma(shape: beta)
        return x / (x + y)
    }
    
    /// Samples from a Gamma distribution using Marsaglia and Tsang's method.
    private func sampleGamma(shape: Double) -> Double {
        if shape < 1 {
            // For shape < 1, use the transformation method
            let u = Double.random(in: 0..<1, using: &rng)
            return sampleGamma(shape: shape + 1) * pow(u, 1.0 / shape)
        }
        
        // Marsaglia and Tsang's method for shape >= 1
        let d = shape - 1.0 / 3.0
        let c = 1.0 / sqrt(9.0 * d)
        
        while true {
            var x: Double
            var v: Double
            
            repeat {
                x = sampleStandardNormal()
                v = 1.0 + c * x
            } while v <= 0
            
            v = v * v * v
            let u = Double.random(in: 0..<1, using: &rng)
            
            if u < 1.0 - 0.0331 * (x * x) * (x * x) {
                return d * v
            }
            
            if log(u) < 0.5 * x * x + d * (1.0 - v + log(v)) {
                return d * v
            }
        }
    }
    
    /// Samples from a standard normal distribution using Box-Muller transform.
    private func sampleStandardNormal() -> Double {
        let u1 = Double.random(in: 0..<1, using: &rng)
        let u2 = Double.random(in: 0..<1, using: &rng)
        return sqrt(-2.0 * log(u1)) * cos(2.0 * .pi * u2)
    }
    
    /// Computes reward from outcome.
    ///
    /// Reward = 1 if success AND not grinder AND no injury
    /// Reward = 0 otherwise
    ///
    /// Injury is defined as: executionContext == .injuryDiscomfort
    private func computeReward(outcome: OutcomeRecord) -> Double {
        // Check for injury
        if outcome.executionContext == .injuryDiscomfort {
            return 0.0
        }
        
        // Check for success and not grinder
        if outcome.wasSuccess && !outcome.wasGrinder {
            return 1.0
        }
        
        return 0.0
    }
}

// MARK: - Beta Prior

/// Beta distribution prior for a bandit arm.
public struct BetaPrior: Codable, Sendable {
    /// Alpha parameter (successes + 1).
    public var alpha: Double
    
    /// Beta parameter (failures + 1).
    public var beta: Double
    
    /// Creates a uniform prior (Beta(1,1)).
    public init(alpha: Double = 1.0, beta: Double = 1.0) {
        self.alpha = alpha
        self.beta = beta
    }
    
    /// Updates the prior with a reward observation.
    public mutating func update(reward: Double) {
        alpha += reward
        beta += (1.0 - reward)
    }
    
    /// Returns the posterior mean.
    public var mean: Double {
        alpha / (alpha + beta)
    }
    
    /// Returns the posterior variance.
    public var variance: Double {
        (alpha * beta) / ((alpha + beta) * (alpha + beta) * (alpha + beta + 1))
    }
}
