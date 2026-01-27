// V10BaselineAndProgressionTests.swift
// Regression tests for V10 fixes:
// 1. Advanced microloading baseline anchor (uses lastWorkingWeight, not derived %e1RM)
// 2. Two easy sessions gate for advanced upper-body presses
// 3. Isolation rep-first progression
// 4. Conservative hold behavior during cuts/maintenance

import XCTest
@testable import TrainingEngine

final class V10BaselineAndProgressionTests: XCTestCase {
    
    // MARK: - Test Helpers
    
    private func makeUserProfile(
        experience: ExperienceLevel = .advanced,
        sex: BiologicalSex = .male,
        bodyWeight: Double = 180.0,
        goal: TrainingGoal = .hypertrophy
    ) -> UserProfile {
        UserProfile(
            sex: sex,
            experience: experience,
            goals: [goal],
            bodyWeight: Load(value: bodyWeight, unit: .pounds),
            age: 30
        )
    }
    
    private func makeLiftSignals(
        exerciseId: String = "bench_press",
        movementPattern: MovementPattern = .horizontalPush,
        equipment: Equipment = .barbell,
        experienceLevel: ExperienceLevel = .advanced,
        lastWorkingWeight: Double = 235.0,
        rollingE1RM: Double = 266.0,
        targetReps: Int = 4,
        targetRIR: Int = 2,
        lastSessionAvgRIR: Double? = 2.5,
        lastSessionReps: [Int] = [4, 4, 4],
        recentEasySessionCount: Int = 0,
        todayReadiness: Int = 75,
        primaryGoal: TrainingGoal? = .hypertrophy
    ) -> LiftSignals {
        return LiftSignals(
            exerciseId: exerciseId,
            movementPattern: movementPattern,
            equipment: equipment,
            lastWorkingWeight: Load(value: lastWorkingWeight, unit: .pounds),
            rollingE1RM: rollingE1RM,
            failStreak: 0,
            highRpeStreak: 0,
            daysSinceLastExposure: 3,
            daysSinceDeload: 14,
            trend: .stable,
            successfulSessionsCount: 10,
            successStreak: 3,
            lastSessionWasFailure: false,
            lastSessionWasGrinder: false,
            lastSessionAvgRIR: lastSessionAvgRIR,
            lastSessionReps: lastSessionReps,
            recentSessionRIRs: [lastSessionAvgRIR].compactMap { $0 },
            recentEasySessionCount: recentEasySessionCount,
            todayReadiness: todayReadiness,
            recentReadinessScores: [todayReadiness, 72, 78],
            prescription: SetPrescription(
                setCount: 3,
                targetRepsRange: targetReps...targetReps,
                targetRIR: targetRIR,
                restSeconds: 180,
                loadStrategy: .percentageE1RM,  // This is the key - %e1RM with nil percentage
                targetPercentage: nil,           // nil triggers the derived calculation
                increment: Load(value: 5.0, unit: .pounds)
            ),
            experienceLevel: experienceLevel,
            bodyWeight: Load(value: 180.0, unit: .pounds),
            sessionDeloadTriggered: false,
            sessionDeloadReason: nil,
            sessionIntent: .heavy,
            primaryGoal: primaryGoal
        )
    }
    
    // MARK: - Test 1: Advanced Bench Microloading Baseline Anchor
    //
    // This was the core V9 bug: baseline was computed from derived %e1RM instead of
    // lastWorkingWeight, causing ~229 instead of ~235 for holds.
    
    func testAdvancedBenchHoldUsesLastWorkingWeight() {
        // Setup: Advanced bench with:
        // - lastWorkingWeight = 235 lb
        // - rollingE1RM ≈ 266 lb
        // - targetReps = 4, targetRIR = 2
        //
        // Old bug: derivedPct = (37 - 6) / 36 ≈ 0.861
        //          baseline = 266 * 0.861 ≈ 229 (rounded to 228.75)
        // Fixed: baseline should anchor to lastWorkingWeight = 235
        
        let signals = makeLiftSignals(
            lastWorkingWeight: 235.0,
            rollingE1RM: 266.0,
            targetReps: 4,
            targetRIR: 2,
            lastSessionAvgRIR: 2.0,  // At target effort - should hold
            lastSessionReps: [4, 4, 4]
        )
        
        // Direction should be hold (met targets at target effort)
        let direction = DirectionPolicy.decide(signals: signals)
        XCTAssertEqual(direction.direction, .hold, "Should hold when effort is at target")
        
        // The magnitude should NOT produce a large drop from 235
        let basePolicy = LoadRoundingPolicy(increment: 1.25, unit: .pounds, mode: .nearest)
        let magnitude = MagnitudePolicy.compute(
            direction: direction,
            signals: signals,
            baseRoundingPolicy: basePolicy,
            config: .default
        )
        
        // For hold, multiplier should be 1.0 and increment should be 0
        XCTAssertEqual(magnitude.loadMultiplier, 1.0, "Hold should have multiplier of 1.0")
        XCTAssertEqual(magnitude.absoluteIncrement.value, 0.0, accuracy: 0.01, "Hold should have 0 increment")
        
        // Verify rounding policy uses microloading increment
        XCTAssertEqual(magnitude.roundingPolicy.increment, 1.25, "Should use 1.25 lb microloading increment")
    }
    
    func testAdvancedBenchEasySessionWithTwoEasyGate() {
        // Advanced bench with easy session (RIR > target + margin)
        // BUT only 1 recent easy session → should still hold (needs 2)
        
        let signals = makeLiftSignals(
            experienceLevel: .advanced,
            lastWorkingWeight: 235.0,
            lastSessionAvgRIR: 3.5,  // Easy: RIR > targetRIR(2) + 1.0 margin
            lastSessionReps: [4, 4, 4],
            recentEasySessionCount: 1  // Only 1 easy session, need 2
        )
        
        let direction = DirectionPolicy.decide(signals: signals)
        
        // Should hold because two easy sessions gate is not met
        XCTAssertEqual(
            direction.direction, 
            .hold, 
            "Advanced upper-body press should require two easy sessions before increasing"
        )
    }
    
    func testAdvancedBenchIncreaseWithTwoEasySessions() {
        // Advanced bench with easy session AND two recent easy sessions
        // → should allow increase
        
        let signals = makeLiftSignals(
            experienceLevel: .advanced,
            lastWorkingWeight: 235.0,
            lastSessionAvgRIR: 3.5,  // Easy: RIR > targetRIR(2) + 1.0 margin
            lastSessionReps: [4, 4, 4],
            recentEasySessionCount: 2  // Has 2 easy sessions
        )
        
        let direction = DirectionPolicy.decide(signals: signals)
        
        // Should increase because two easy sessions gate is met
        XCTAssertEqual(
            direction.direction,
            .increase,
            "Advanced upper-body press with two easy sessions should increase"
        )
    }
    
    // MARK: - Test 2: Intermediate Lifter Does Not Need Two Easy Sessions
    
    func testIntermediateBenchDoesNotRequireTwoEasySessions() {
        // Intermediate bench with easy session
        // → should increase (two easy sessions gate is for advanced/elite only)
        
        let signals = makeLiftSignals(
            experienceLevel: .intermediate,
            lastWorkingWeight: 185.0,
            rollingE1RM: 220.0,
            lastSessionAvgRIR: 3.5,  // Easy
            lastSessionReps: [5, 5, 5],
            recentEasySessionCount: 1  // Only 1 easy session
        )
        
        let direction = DirectionPolicy.decide(signals: signals)
        
        // Intermediate should increase without needing two easy sessions
        XCTAssertEqual(
            direction.direction,
            .increase,
            "Intermediate lifter should increase without two easy sessions gate"
        )
    }
    
    // MARK: - Test 3: Isolation Rep-First Progression
    
    func testIsolationHoldsOnEasyRIR() {
        // Isolation exercise (lateral raise) with easy RIR but not at rep ceiling
        // → should hold (isolations use rep progression, not RIR-based load increases)
        
        let signals = LiftSignals(
            exerciseId: "lateral_raise",
            movementPattern: .shoulderAbduction,  // Isolation
            equipment: .dumbbell,
            lastWorkingWeight: Load(value: 15.0, unit: .pounds),
            rollingE1RM: 25.0,
            failStreak: 0,
            highRpeStreak: 0,
            daysSinceLastExposure: 3,
            daysSinceDeload: 14,
            trend: .stable,
            successfulSessionsCount: 5,
            successStreak: 2,
            lastSessionWasFailure: false,
            lastSessionWasGrinder: false,
            lastSessionAvgRIR: 3.5,  // Easy by RIR
            lastSessionReps: [10, 10, 10],  // In range but not at top (12)
            recentSessionRIRs: [3.5],
            recentEasySessionCount: 1,
            todayReadiness: 75,
            recentReadinessScores: [75, 70, 78],
            prescription: SetPrescription(
                setCount: 3,
                targetRepsRange: 8...12,  // Rep range with ceiling at 12
                targetRIR: 2,
                restSeconds: 60,
                loadStrategy: .absolute,
                increment: Load(value: 2.5, unit: .pounds)
            ),
            experienceLevel: .intermediate,
            bodyWeight: Load(value: 180.0, unit: .pounds),
            sessionDeloadTriggered: false,
            sessionDeloadReason: nil,
            sessionIntent: .volume
        )
        
        let direction = DirectionPolicy.decide(signals: signals)
        
        // Isolation should hold until reps reach ceiling (12)
        XCTAssertEqual(
            direction.direction,
            .hold,
            "Isolation should hold on easy RIR when reps aren't at ceiling"
        )
    }
    
    func testIsolationIncreasesAtRepCeiling() {
        // Isolation exercise at rep ceiling with easy effort
        // → should increase (reached ceiling, ready to bump load)
        
        let signals = LiftSignals(
            exerciseId: "lateral_raise",
            movementPattern: .shoulderAbduction,  // Isolation
            equipment: .dumbbell,
            lastWorkingWeight: Load(value: 15.0, unit: .pounds),
            rollingE1RM: 25.0,
            failStreak: 0,
            highRpeStreak: 0,
            daysSinceLastExposure: 3,
            daysSinceDeload: 14,
            trend: .stable,
            successfulSessionsCount: 5,
            successStreak: 2,
            lastSessionWasFailure: false,
            lastSessionWasGrinder: false,
            lastSessionAvgRIR: 3.0,  // Easy enough
            lastSessionReps: [12, 12, 12],  // At ceiling!
            recentSessionRIRs: [3.0],
            recentEasySessionCount: 1,
            todayReadiness: 75,
            recentReadinessScores: [75, 70, 78],
            prescription: SetPrescription(
                setCount: 3,
                targetRepsRange: 8...12,  // Rep ceiling is 12
                targetRIR: 2,
                restSeconds: 60,
                loadStrategy: .absolute,
                increment: Load(value: 2.5, unit: .pounds)
            ),
            experienceLevel: .intermediate,
            bodyWeight: Load(value: 180.0, unit: .pounds),
            sessionDeloadTriggered: false,
            sessionDeloadReason: nil,
            sessionIntent: .volume
        )
        
        let direction = DirectionPolicy.decide(signals: signals)
        
        // Isolation at rep ceiling should increase
        XCTAssertEqual(
            direction.direction,
            .increase,
            "Isolation at rep ceiling should increase load"
        )
    }
    
    func testIsolationHoldsOnGrinder() {
        // Isolation exercise with grinder (RIR below target)
        // → should hold (not decrease, unlike compounds)
        
        let signals = LiftSignals(
            exerciseId: "lateral_raise",
            movementPattern: .shoulderAbduction,
            equipment: .dumbbell,
            lastWorkingWeight: Load(value: 15.0, unit: .pounds),
            rollingE1RM: 25.0,
            failStreak: 0,
            highRpeStreak: 0,
            daysSinceLastExposure: 3,
            daysSinceDeload: 14,
            trend: .stable,
            successfulSessionsCount: 5,
            successStreak: 0,
            lastSessionWasFailure: false,
            lastSessionWasGrinder: true,  // Grinder!
            lastSessionAvgRIR: 0.5,  // Hard session
            lastSessionReps: [10, 10, 10],
            recentSessionRIRs: [0.5],
            recentEasySessionCount: 0,
            todayReadiness: 75,
            recentReadinessScores: [75, 70, 78],
            prescription: SetPrescription(
                setCount: 3,
                targetRepsRange: 8...12,
                targetRIR: 2,
                restSeconds: 60,
                loadStrategy: .absolute,
                increment: Load(value: 2.5, unit: .pounds)
            ),
            experienceLevel: .intermediate,
            bodyWeight: Load(value: 180.0, unit: .pounds),
            sessionDeloadTriggered: false,
            sessionDeloadReason: nil,
            sessionIntent: .volume
        )
        
        let direction = DirectionPolicy.decide(signals: signals)
        
        // Isolation grinder should hold (not decrease)
        XCTAssertEqual(
            direction.direction,
            .hold,
            "Isolation grinder should hold, not decrease"
        )
    }
    
    // MARK: - Test 4: Cut/Maintenance Phase
    
    func testCutPhaseRequiresHighReadinessForIncrease() {
        // During fat loss (cut), should NOT increase even with easy session
        // if readiness is not high enough
        
        let signals = makeLiftSignals(
            lastSessionAvgRIR: 3.5,  // Easy
            lastSessionReps: [4, 4, 4],
            recentEasySessionCount: 3,  // Has easy sessions
            todayReadiness: 65,  // Below high threshold (75)
            primaryGoal: .fatLoss
        )
        
        let direction = DirectionPolicy.decide(signals: signals)
        
        // Should hold during cut with below-threshold readiness
        XCTAssertEqual(
            direction.direction,
            .hold,
            "Cut phase should require high readiness (75+) for increase"
        )
    }
    
    func testCutPhaseAllowsIncreaseWithHighReadiness() {
        // During fat loss (cut), SHOULD increase with easy session AND high readiness
        
        let signals = makeLiftSignals(
            lastSessionAvgRIR: 3.5,  // Easy
            lastSessionReps: [4, 4, 4],
            recentEasySessionCount: 3,  // Has easy sessions (includes two easy sessions gate)
            todayReadiness: 80,  // High readiness
            primaryGoal: .fatLoss
        )
        
        let direction = DirectionPolicy.decide(signals: signals)
        
        // Should increase during cut with high readiness + easy session
        XCTAssertEqual(
            direction.direction,
            .increase,
            "Cut phase with high readiness and easy session should increase"
        )
    }
    
    // MARK: - Test 5: Conservative Readiness Cuts
    
    func testLowReadinessHoldsWithoutCorroboration() {
        // Low readiness (60) but no corroborating signal (no grinder, no miss, stable trend)
        // → should hold (not decrease)
        
        let signals = makeLiftSignals(
            lastSessionAvgRIR: 2.0,  // Normal effort
            lastSessionReps: [4, 4, 4],
            todayReadiness: 60  // Low but not severe
        )
        
        let direction = DirectionPolicy.decide(signals: signals)
        
        // V10: Should hold without corroborating signal
        XCTAssertEqual(
            direction.direction,
            .hold,
            "Low readiness without corroboration should hold"
        )
    }
    
    func testSevereLowReadinessHoldsWithoutCorroboration() {
        // V10: Even severe low readiness (< 40) should HOLD load if there's no corroborating
        // fatigue/performance signal. The response is a readiness cut (volume reduction), not a load cut.
        
        let signals = makeLiftSignals(
            lastSessionAvgRIR: 2.0,
            lastSessionReps: [4, 4, 4],
            todayReadiness: 35  // Severe low
        )
        
        let direction = DirectionPolicy.decide(signals: signals)
        
        // Severe low without corroboration: hold (with readinessCut volume reduction in magnitude layer)
        XCTAssertEqual(
            direction.direction,
            .hold,
            "Severe low readiness without corroboration should hold load (volume cut only)"
        )
        
        // Magnitude policy should apply a volume reduction for low-readiness holds
        let basePolicy = LoadRoundingPolicy(increment: 2.5, unit: .pounds, mode: .nearest)
        let magnitude = MagnitudePolicy.compute(
            direction: direction,
            signals: signals,
            baseRoundingPolicy: basePolicy,
            config: .default
        )
        XCTAssertEqual(magnitude.volumeAdjustment, -1, "Low readiness hold should reduce volume by 1 set")
    }
    
    // MARK: - Test 6: Microloading Increment Clamp
    
    func testAdvancedBenchMicroloadingIncrementClamp() {
        // Advanced bench with microloading enabled (1.25 lb increment)
        // Should clamp to 1.25 lb, not scale up to 2.5 lb
        
        let signals = makeLiftSignals(
            experienceLevel: .advanced,
            lastWorkingWeight: 235.0,
            lastSessionAvgRIR: 3.5,  // Easy
            recentEasySessionCount: 2  // Passes two easy sessions gate
        )
        
        let direction = DirectionPolicy.decide(signals: signals)
        XCTAssertEqual(direction.direction, .increase)
        
        // With 1.25 lb microloading rounding, increment should be clamped to 1.25
        let basePolicy = LoadRoundingPolicy(increment: 1.25, unit: .pounds, mode: .nearest)
        let magnitude = MagnitudePolicy.compute(
            direction: direction,
            signals: signals,
            baseRoundingPolicy: basePolicy,
            config: .default
        )
        
        // The absolute increment for advanced upper body press should be clamped to microloading
        XCTAssertLessThanOrEqual(
            magnitude.absoluteIncrement.value,
            1.25,
            "Advanced bench microloading should clamp increment to 1.25 lb"
        )
        XCTAssertGreaterThan(
            magnitude.absoluteIncrement.value,
            0.0,
            "Increase should have a positive increment"
        )
    }
}
