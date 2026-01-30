// BanditPolicySelectorTests.swift
// Tests for Thompson sampling bandit policy selector and state store.

import XCTest
import TrainingEngine
@testable import IronForge

final class BanditPolicySelectorTests: XCTestCase {
    
    // MARK: - Bandit State Store Tests
    
    func testInMemoryStoreDefaultsToUniformPrior() {
        let store = InMemoryBanditStateStore()
        let prior = store.getPrior(userId: "user1", familyKey: "bench", armId: "baseline")
        
        XCTAssertEqual(prior.alpha, 1.0, "Default alpha should be 1.0 (uniform prior)")
        XCTAssertEqual(prior.beta, 1.0, "Default beta should be 1.0 (uniform prior)")
    }
    
    func testStoreUpdatesPriorOnReward() {
        let store = InMemoryBanditStateStore()
        let userId = "user1"
        let familyKey = "squat"
        let armId = "aggressive"
        
        // Record a success (reward = 1)
        store.updatePrior(userId: userId, familyKey: familyKey, armId: armId, reward: 1.0)
        let priorAfterSuccess = store.getPrior(userId: userId, familyKey: familyKey, armId: armId)
        
        XCTAssertEqual(priorAfterSuccess.alpha, 2.0, "Alpha should increment on success")
        XCTAssertEqual(priorAfterSuccess.beta, 1.0, "Beta should not change on success")
        
        // Record a failure (reward = 0)
        store.updatePrior(userId: userId, familyKey: familyKey, armId: armId, reward: 0.0)
        let priorAfterFailure = store.getPrior(userId: userId, familyKey: familyKey, armId: armId)
        
        XCTAssertEqual(priorAfterFailure.alpha, 2.0, "Alpha should not change on failure")
        XCTAssertEqual(priorAfterFailure.beta, 2.0, "Beta should increment on failure")
    }
    
    func testStoreResetClearsPriors() {
        let store = InMemoryBanditStateStore()
        let userId = "user1"
        let familyKey = "bench"
        
        // Add some data
        store.updatePrior(userId: userId, familyKey: familyKey, armId: "baseline", reward: 1.0)
        store.updatePrior(userId: userId, familyKey: familyKey, armId: "aggressive", reward: 0.0)
        
        // Reset for this family
        store.reset(userId: userId, familyKey: familyKey)
        
        // Verify reset
        let baselinePrior = store.getPrior(userId: userId, familyKey: familyKey, armId: "baseline")
        let aggressivePrior = store.getPrior(userId: userId, familyKey: familyKey, armId: "aggressive")
        
        XCTAssertEqual(baselinePrior.alpha, 1.0, "Prior should be reset to default")
        XCTAssertEqual(aggressivePrior.alpha, 1.0, "Prior should be reset to default")
    }
    
    func testStoreResetAllForUserClearsAllFamilies() {
        let store = InMemoryBanditStateStore()
        let userId = "user1"
        
        // Add data for multiple families
        store.updatePrior(userId: userId, familyKey: "bench", armId: "baseline", reward: 1.0)
        store.updatePrior(userId: userId, familyKey: "squat", armId: "baseline", reward: 1.0)
        store.updatePrior(userId: "user2", familyKey: "bench", armId: "baseline", reward: 1.0)
        
        // Reset all for user1
        store.resetAll(userId: userId)
        
        // User1's data should be reset
        let user1Bench = store.getPrior(userId: userId, familyKey: "bench", armId: "baseline")
        let user1Squat = store.getPrior(userId: userId, familyKey: "squat", armId: "baseline")
        XCTAssertEqual(user1Bench.alpha, 1.0, "User1's priors should be reset")
        XCTAssertEqual(user1Squat.alpha, 1.0, "User1's priors should be reset")
        
        // User2's data should be preserved
        let user2Bench = store.getPrior(userId: "user2", familyKey: "bench", armId: "baseline")
        XCTAssertEqual(user2Bench.alpha, 2.0, "User2's priors should be preserved")
    }
    
    // MARK: - Beta Prior Tests
    
    func testBetaPriorUpdateMath() {
        var prior = BetaPrior()
        XCTAssertEqual(prior.alpha, 1.0)
        XCTAssertEqual(prior.beta, 1.0)
        XCTAssertEqual(prior.mean, 0.5, accuracy: 0.001)
        
        // Success
        prior.update(reward: 1.0)
        XCTAssertEqual(prior.alpha, 2.0)
        XCTAssertEqual(prior.beta, 1.0)
        XCTAssertEqual(prior.mean, 2.0/3.0, accuracy: 0.001)
        
        // Failure
        prior.update(reward: 0.0)
        XCTAssertEqual(prior.alpha, 2.0)
        XCTAssertEqual(prior.beta, 2.0)
        XCTAssertEqual(prior.mean, 0.5, accuracy: 0.001)
        
        // Multiple successes
        prior.update(reward: 1.0)
        prior.update(reward: 1.0)
        prior.update(reward: 1.0)
        XCTAssertEqual(prior.alpha, 5.0)
        XCTAssertEqual(prior.beta, 2.0)
        XCTAssertEqual(prior.mean, 5.0/7.0, accuracy: 0.001)
    }
    
    // MARK: - Bandit Gate Tests
    
    func testBanditGateFailsOnLowExposures() {
        let store = InMemoryBanditStateStore()
        let bandit = ThompsonSamplingBanditPolicySelector(
            stateStore: store,
            gateConfig: BanditGateConfig(minBaselineExposures: 5),
            isEnabled: true
        )
        
        // Low exposure count
        let signals = createSignals(successfulSessionsCount: 2)
        let variationContext = createVariationContext()
        
        let selection = bandit.selectPolicy(for: signals, variationContext: variationContext, userId: "user1")
        
        // Should fall back to baseline control when gate fails
        XCTAssertEqual(selection.executedPolicyId, "baseline")
        XCTAssertEqual(selection.executedActionProbability, 1.0)
        XCTAssertEqual(selection.explorationMode, .control)
    }
    
    func testBanditGateFailsOnHighFailStreak() {
        let store = InMemoryBanditStateStore()
        let bandit = ThompsonSamplingBanditPolicySelector(
            stateStore: store,
            gateConfig: BanditGateConfig(maxFailStreak: 1),
            isEnabled: true
        )
        
        // High fail streak
        let signals = createSignals(failStreak: 2, successfulSessionsCount: 10)
        let variationContext = createVariationContext()
        
        let selection = bandit.selectPolicy(for: signals, variationContext: variationContext, userId: "user1")
        
        XCTAssertEqual(selection.executedPolicyId, "baseline")
        XCTAssertEqual(selection.explorationMode, .control)
    }
    
    func testBanditGateFailsOnLowReadiness() {
        let store = InMemoryBanditStateStore()
        let bandit = ThompsonSamplingBanditPolicySelector(
            stateStore: store,
            gateConfig: BanditGateConfig(minReadiness: 60),
            isEnabled: true
        )
        
        // Low readiness
        let signals = createSignals(todayReadiness: 45, successfulSessionsCount: 10)
        let variationContext = createVariationContext()
        
        let selection = bandit.selectPolicy(for: signals, variationContext: variationContext, userId: "user1")
        
        XCTAssertEqual(selection.executedPolicyId, "baseline")
        XCTAssertEqual(selection.explorationMode, .control)
    }
    
    func testBanditGateFailsDuringDeload() {
        let store = InMemoryBanditStateStore()
        let bandit = ThompsonSamplingBanditPolicySelector(
            stateStore: store,
            gateConfig: BanditGateConfig(allowDuringDeload: false),
            isEnabled: true
        )
        
        // Deload session
        let signals = createSignals(sessionDeloadTriggered: true, successfulSessionsCount: 10)
        let variationContext = createVariationContext()
        
        let selection = bandit.selectPolicy(for: signals, variationContext: variationContext, userId: "user1")
        
        XCTAssertEqual(selection.executedPolicyId, "baseline")
        XCTAssertEqual(selection.explorationMode, .control)
    }
    
    func testBanditGatePassesWhenAllConditionsMet() {
        let store = InMemoryBanditStateStore()
        let bandit = ThompsonSamplingBanditPolicySelector(
            stateStore: store,
            gateConfig: BanditGateConfig(
                minBaselineExposures: 5,
                minDaysSinceDeload: 7,
                maxFailStreak: 1,
                minReadiness: 50,
                allowDuringDeload: false
            ),
            isEnabled: true
        )
        
        // All conditions met
        let signals = createSignals(
            successfulSessionsCount: 10,
            failStreak: 0,
            todayReadiness: 75,
            daysSinceDeload: 14,
            sessionDeloadTriggered: false
        )
        let variationContext = createVariationContext()
        
        let selection = bandit.selectPolicy(for: signals, variationContext: variationContext, userId: "user1")
        
        // Should explore (not control)
        XCTAssertEqual(selection.explorationMode, .explore)
    }
    
    func testBanditDisabledReturnsBaseline() {
        let store = InMemoryBanditStateStore()
        let bandit = ThompsonSamplingBanditPolicySelector(
            stateStore: store,
            isEnabled: false // Disabled
        )
        
        let signals = createSignals(successfulSessionsCount: 100)
        let variationContext = createVariationContext()
        
        let selection = bandit.selectPolicy(for: signals, variationContext: variationContext, userId: "user1")
        
        XCTAssertEqual(selection.executedPolicyId, "baseline")
        XCTAssertEqual(selection.explorationMode, .control)
    }
    
    // MARK: - Bandit Arm Selection Tests
    
    func testBanditSelectsFromAvailableArms() {
        let store = InMemoryBanditStateStore()
        let customArms = [
            BanditArm.baseline,
            BanditArm(id: "conservative"),
            BanditArm(id: "aggressive")
        ]
        let bandit = ThompsonSamplingBanditPolicySelector(
            stateStore: store,
            arms: customArms,
            isEnabled: true
        )
        
        let signals = createSignals(successfulSessionsCount: 20)
        let variationContext = createVariationContext()
        
        // Run multiple selections to verify we get different arms
        var selectedArmIds = Set<String>()
        for _ in 0..<100 {
            let selection = bandit.selectPolicy(for: signals, variationContext: variationContext, userId: "user1")
            selectedArmIds.insert(selection.executedPolicyId)
        }
        
        // With uniform priors, we should see multiple different arms selected
        XCTAssertTrue(selectedArmIds.count > 1, "Bandit should explore multiple arms with uniform priors")
    }
    
    // MARK: - Reward Computation Tests
    
    func testRewardIsZeroForInjury() {
        let store = InMemoryBanditStateStore()
        let bandit = ThompsonSamplingBanditPolicySelector(
            stateStore: store,
            isEnabled: true
        )
        
        // Create a decision entry with injury context
        let entry = createDecisionEntry(
            policyId: "aggressive",
            explorationMode: "explore",
            outcome: createOutcome(wasSuccess: true, wasGrinder: false, executionContext: .injuryDiscomfort)
        )
        
        let priorBefore = store.getPrior(userId: "user1", familyKey: "bench", armId: "aggressive")
        XCTAssertEqual(priorBefore.alpha, 1.0)
        XCTAssertEqual(priorBefore.beta, 1.0)
        
        bandit.recordOutcome(entry, userId: "user1")
        
        // Reward should be 0 (injury), so beta should increment
        let priorAfter = store.getPrior(userId: "user1", familyKey: "bench", armId: "aggressive")
        XCTAssertEqual(priorAfter.alpha, 1.0, "Alpha should not change on injury")
        XCTAssertEqual(priorAfter.beta, 2.0, "Beta should increment on injury (reward=0)")
    }
    
    func testRewardIsZeroForGrinder() {
        let store = InMemoryBanditStateStore()
        let bandit = ThompsonSamplingBanditPolicySelector(
            stateStore: store,
            isEnabled: true
        )
        
        let entry = createDecisionEntry(
            policyId: "aggressive",
            explorationMode: "explore",
            outcome: createOutcome(wasSuccess: true, wasGrinder: true, executionContext: .normal)
        )
        
        bandit.recordOutcome(entry, userId: "user1")
        
        let priorAfter = store.getPrior(userId: "user1", familyKey: "bench", armId: "aggressive")
        XCTAssertEqual(priorAfter.alpha, 1.0, "Alpha should not change on grinder")
        XCTAssertEqual(priorAfter.beta, 2.0, "Beta should increment on grinder (reward=0)")
    }
    
    func testRewardIsZeroForFailure() {
        let store = InMemoryBanditStateStore()
        let bandit = ThompsonSamplingBanditPolicySelector(
            stateStore: store,
            isEnabled: true
        )
        
        let entry = createDecisionEntry(
            policyId: "conservative",
            explorationMode: "explore",
            outcome: createOutcome(wasSuccess: false, wasGrinder: false, executionContext: .normal)
        )
        
        bandit.recordOutcome(entry, userId: "user1")
        
        let priorAfter = store.getPrior(userId: "user1", familyKey: "bench", armId: "conservative")
        XCTAssertEqual(priorAfter.alpha, 1.0, "Alpha should not change on failure")
        XCTAssertEqual(priorAfter.beta, 2.0, "Beta should increment on failure (reward=0)")
    }
    
    func testRewardIsOneForSuccessNoGrinderNoInjury() {
        let store = InMemoryBanditStateStore()
        let bandit = ThompsonSamplingBanditPolicySelector(
            stateStore: store,
            isEnabled: true
        )
        
        let entry = createDecisionEntry(
            policyId: "baseline",
            explorationMode: "explore",
            outcome: createOutcome(wasSuccess: true, wasGrinder: false, executionContext: .normal)
        )
        
        bandit.recordOutcome(entry, userId: "user1")
        
        let priorAfter = store.getPrior(userId: "user1", familyKey: "bench", armId: "baseline")
        XCTAssertEqual(priorAfter.alpha, 2.0, "Alpha should increment on success")
        XCTAssertEqual(priorAfter.beta, 1.0, "Beta should not change on success")
    }
    
    func testNoUpdateForShadowMode() {
        let store = InMemoryBanditStateStore()
        let bandit = ThompsonSamplingBanditPolicySelector(
            stateStore: store,
            isEnabled: true
        )
        
        // Shadow mode entry - should not update priors
        let entry = createDecisionEntry(
            policyId: "baseline",
            explorationMode: "shadow",
            outcome: createOutcome(wasSuccess: true, wasGrinder: false, executionContext: .normal)
        )
        
        bandit.recordOutcome(entry, userId: "user1")
        
        let priorAfter = store.getPrior(userId: "user1", familyKey: "bench", armId: "baseline")
        XCTAssertEqual(priorAfter.alpha, 1.0, "Alpha should not change in shadow mode")
        XCTAssertEqual(priorAfter.beta, 1.0, "Beta should not change in shadow mode")
    }
    
    func testNoUpdateForControlMode() {
        let store = InMemoryBanditStateStore()
        let bandit = ThompsonSamplingBanditPolicySelector(
            stateStore: store,
            isEnabled: true
        )
        
        // Control mode entry - should not update priors
        let entry = createDecisionEntry(
            policyId: "baseline",
            explorationMode: "control",
            outcome: createOutcome(wasSuccess: true, wasGrinder: false, executionContext: .normal)
        )
        
        bandit.recordOutcome(entry, userId: "user1")
        
        let priorAfter = store.getPrior(userId: "user1", familyKey: "bench", armId: "baseline")
        XCTAssertEqual(priorAfter.alpha, 1.0, "Alpha should not change in control mode")
        XCTAssertEqual(priorAfter.beta, 1.0, "Beta should not change in control mode")
    }
    
    // MARK: - Helpers
    
    private func createSignals(
        successfulSessionsCount: Int = 0,
        failStreak: Int = 0,
        todayReadiness: Int = 75,
        daysSinceDeload: Int? = 14,
        sessionDeloadTriggered: Bool = false
    ) -> LiftSignalsSnapshot {
        LiftSignalsSnapshot(
            exerciseId: "test-bench",
            movementPattern: .horizontalPush,
            equipment: .barbell,
            lastWorkingWeightValue: 100,
            lastWorkingWeightUnit: .pounds,
            rollingE1RM: 150,
            failStreak: failStreak,
            highRpeStreak: 0,
            successStreak: 3,
            daysSinceLastExposure: 3,
            daysSinceDeload: daysSinceDeload,
            trend: .stable,
            successfulSessionsCount: successfulSessionsCount,
            exposuresInRecentWindow: 4,
            sessionDeloadTriggered: sessionDeloadTriggered,
            sessionDeloadReason: nil,
            todayReadiness: todayReadiness,
            recentReadinessScores: [75, 70, 72],
            bodyweightKg: 80,
            experienceLevel: .intermediate,
            sessionIntent: SessionIntent(
                primaryGoal: .strength,
                readinessLevel: .normal,
                availableTime: nil,
                isForcedDeload: false,
                isPlannedDeloadWeek: false
            )
        )
    }
    
    private func createVariationContext() -> VariationContext {
        VariationContext(
            isPrimaryExercise: true,
            isSubstitution: false,
            originalExerciseId: nil,
            familyReferenceKey: "bench",
            familyUpdateKey: "bench",
            familyCoefficient: 1.0,
            movementPattern: .horizontalPush,
            equipment: .barbell,
            stateIsExerciseSpecific: true
        )
    }
    
    private func createDecisionEntry(
        policyId: String,
        explorationMode: String,
        outcome: OutcomeRecord?
    ) -> DecisionLogEntry {
        DecisionLogEntry(
            id: UUID(),
            sessionId: UUID(),
            exerciseId: "test-bench",
            userId: "user1",
            timestamp: Date(),
            sessionDate: Date(),
            historySummary: HistorySummary(
                sessionCount: 10,
                sessionsLast7Days: 3,
                sessionsLast14Days: 6,
                sessionsLast28Days: 12,
                volumeLast7Days: 10000,
                volumeLast14Days: 20000,
                avgSessionDurationMinutes: 60,
                deloadSessionsLast28Days: 1,
                daysSinceLastWorkout: 2,
                trainingStreakWeeks: 8
            ),
            lastExposures: [],
            trendStatistics: TrendStatistics(
                trend: .stable,
                slopePerSession: 0.01,
                slopePercentage: 1.0,
                rSquared: 0.8,
                dataPoints: 10,
                volatility: 0.05,
                recentE1RM: 150,
                baselineE1RM: 145
            ),
            readinessDistribution: ReadinessDistribution(
                currentScore: 75,
                recentScores: [75, 70, 72],
                avgLast7Days: 72,
                avgLast14Days: 71,
                percentile: 0.6,
                trend: .stable,
                volatility: 5.0
            ),
            constraintInfo: ConstraintInfo(
                equipmentAvailable: true,
                roundingIncrement: 5.0,
                roundingUnit: .pounds,
                microloadingEnabled: false,
                minLoadFloor: nil,
                maxLoadCeiling: nil,
                sessionTimeLimit: nil,
                isPlannedDeloadWeek: false
            ),
            variationContext: createVariationContext(),
            sessionIntent: SessionIntent(
                primaryGoal: .strength,
                readinessLevel: .normal,
                availableTime: nil,
                isForcedDeload: false,
                isPlannedDeloadWeek: false
            ),
            experienceLevel: .intermediate,
            liftSignals: createSignals(successfulSessionsCount: 10),
            action: ActionRecord(
                direction: .increase,
                primaryReason: .successAndRecovery,
                contributingReasons: [],
                deltaLoadValue: 5,
                deltaLoadUnit: .pounds,
                loadMultiplier: 1.0,
                absoluteLoadValue: 105,
                absoluteLoadUnit: .pounds,
                baselineLoadValue: 100,
                targetReps: 8,
                targetRIR: 2,
                setCount: 3,
                volumeAdjustment: 0,
                isSessionDeload: false,
                isExerciseDeload: false,
                adjustmentKind: .none,
                explanation: "Test",
                confidence: 0.9
            ),
            policyChecks: [],
            counterfactuals: [],
            executedPolicyId: policyId,
            executedActionProbability: 0.5,
            explorationMode: explorationMode,
            outcome: outcome,
            engineVersion: "1.0.0"
        )
    }
    
    private func createOutcome(
        wasSuccess: Bool,
        wasGrinder: Bool,
        executionContext: ExecutionContext
    ) -> OutcomeRecord {
        OutcomeRecord(
            repsPerSet: [10, 10, 9],
            avgReps: 9.67,
            totalReps: 29,
            rirPerSet: [2, 2, 1],
            avgRIR: 1.67,
            actualLoadValue: 100,
            actualLoadUnit: .pounds,
            sessionE1RM: 133,
            wasSuccess: wasSuccess,
            wasFailure: !wasSuccess,
            wasGrinder: wasGrinder,
            totalVolume: 2900,
            inSessionAdjustments: [],
            readinessScore: 75,
            executionContext: executionContext
        )
    }
}
