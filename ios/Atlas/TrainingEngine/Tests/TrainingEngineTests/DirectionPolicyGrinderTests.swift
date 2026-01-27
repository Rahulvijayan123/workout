// DirectionPolicyGrinderTests.swift
// Tests for grinder handling in DirectionPolicy (V6 alignment).

import XCTest
@testable import TrainingEngine

final class DirectionPolicyGrinderTests: XCTestCase {
    
    // MARK: - Test Helpers
    
    /// Creates lift signals with grinder state for testing.
    private func makeGrinderSignals(
        experience: ExperienceLevel,
        sessionIntent: SessionIntent = .general,
        highRpeStreak: Int = 1,
        lastSessionWasGrinder: Bool = true,
        todayReadiness: Int = 75
    ) -> LiftSignals {
        LiftSignals(
            exerciseId: "bench",
            movementPattern: .horizontalPush,
            equipment: .barbell,
            lastWorkingWeight: Load(value: 200, unit: .pounds),
            rollingE1RM: 250,
            failStreak: 0,
            highRpeStreak: highRpeStreak,
            daysSinceLastExposure: 3,
            daysSinceDeload: 30,
            trend: .stable,
            successfulSessionsCount: 10,
            successStreak: 0, // Broken by grinder
            lastSessionWasFailure: false,
            lastSessionWasGrinder: lastSessionWasGrinder,
            lastSessionAvgRIR: 0.5, // Close to failure
            lastSessionReps: [5, 5, 5],
            todayReadiness: todayReadiness,
            recentReadinessScores: [75, 80, 70],
            prescription: SetPrescription(
                setCount: 3,
                targetRepsRange: 5...5,
                targetRIR: 2,
                restSeconds: 180,
                loadStrategy: .absolute,
                increment: Load(value: 5, unit: .pounds)
            ),
            experienceLevel: experience,
            bodyWeight: Load(value: 180, unit: .pounds),
            sessionDeloadTriggered: false,
            sessionDeloadReason: nil,
            sessionIntent: sessionIntent
        )
    }
    
    // MARK: - V6 Rulebook Alignment Tests
    
    /// V6 rulebook: "Single grinder/miss for intermediate+: slight reduction (~2.5%)"
    func testIntermediateGrinder_ShouldDecreaseSlightly() {
        let signals = makeGrinderSignals(experience: .intermediate)
        let decision = DirectionPolicy.decide(signals: signals)
        
        XCTAssertEqual(decision.direction, .decreaseSlightly,
            "Intermediate lifter with single grinder should get decreaseSlightly per V6 rulebook")
        XCTAssertEqual(decision.primaryReason, .minorFatigueSignal)
    }
    
    func testAdvancedGrinder_ShouldDecreaseSlightly() {
        let signals = makeGrinderSignals(experience: .advanced)
        let decision = DirectionPolicy.decide(signals: signals)
        
        XCTAssertEqual(decision.direction, .decreaseSlightly,
            "Advanced lifter with single grinder should get decreaseSlightly per V6 rulebook")
    }
    
    func testEliteGrinder_ShouldDecreaseSlightly() {
        let signals = makeGrinderSignals(experience: .elite)
        let decision = DirectionPolicy.decide(signals: signals)
        
        XCTAssertEqual(decision.direction, .decreaseSlightly,
            "Elite lifter with single grinder should get decreaseSlightly per V6 rulebook")
    }
    
    // MARK: - Beginner Exception Tests
    
    /// Beginners should hold on grinder (simpler mental model, let them consolidate)
    func testBeginnerGrinder_ShouldHold() {
        let signals = makeGrinderSignals(experience: .beginner)
        let decision = DirectionPolicy.decide(signals: signals)
        
        XCTAssertEqual(decision.direction, .hold,
            "Beginner with grinder should hold to consolidate")
        XCTAssertEqual(decision.primaryReason, .grinderSuccess)
    }
    
    // MARK: - Session Intent Tests
    
    /// Volume days for intermediate+ should still get decreaseSlightly on grinder
    func testIntermediateVolumeDay_Grinder_ShouldDecreaseSlightly() {
        let signals = makeGrinderSignals(experience: .intermediate, sessionIntent: .volume)
        let decision = DirectionPolicy.decide(signals: signals)
        
        XCTAssertEqual(decision.direction, .decreaseSlightly,
            "Intermediate on volume day with grinder should get decreaseSlightly per V6 rulebook")
    }
    
    /// Heavy days for intermediate+ should get decreaseSlightly on grinder
    func testIntermediateHeavyDay_Grinder_ShouldDecreaseSlightly() {
        let signals = makeGrinderSignals(experience: .intermediate, sessionIntent: .heavy)
        let decision = DirectionPolicy.decide(signals: signals)
        
        XCTAssertEqual(decision.direction, .decreaseSlightly,
            "Intermediate on heavy day with grinder should get decreaseSlightly")
    }
    
    /// Light days can be more lenient - hold on first grinder
    func testIntermediateLightDay_FirstGrinder_ShouldHold() {
        let signals = makeGrinderSignals(
            experience: .intermediate,
            sessionIntent: .light,
            highRpeStreak: 1
        )
        let decision = DirectionPolicy.decide(signals: signals)
        
        XCTAssertEqual(decision.direction, .hold,
            "Light day with first grinder can hold")
    }
    
    /// Light days with repeated grinders should still decrease
    func testIntermediateLightDay_RepeatedGrinder_ShouldDecreaseSlightly() {
        let signals = makeGrinderSignals(
            experience: .intermediate,
            sessionIntent: .light,
            highRpeStreak: 2 // Not first grinder anymore
        )
        let decision = DirectionPolicy.decide(signals: signals)
        
        XCTAssertEqual(decision.direction, .decreaseSlightly,
            "Light day with repeated grinders should get decreaseSlightly")
    }
    
    // MARK: - Non-Grinder Tests
    
    /// No grinder, no failure - should check for normal progression
    func testIntermediateNoGrinder_ShouldNotTriggerGrinderBranch() {
        let signals = LiftSignals(
            exerciseId: "bench",
            movementPattern: .horizontalPush,
            equipment: .barbell,
            lastWorkingWeight: Load(value: 200, unit: .pounds),
            rollingE1RM: 250,
            failStreak: 0,
            highRpeStreak: 0,
            daysSinceLastExposure: 3,
            daysSinceDeload: 30,
            trend: .stable,
            successfulSessionsCount: 10,
            successStreak: 2,
            lastSessionWasFailure: false,
            lastSessionWasGrinder: false,
            lastSessionAvgRIR: 2.5, // Clean session
            lastSessionReps: [5, 5, 5],
            todayReadiness: 75,
            recentReadinessScores: [75, 80, 70],
            prescription: SetPrescription(
                setCount: 3,
                targetRepsRange: 5...5,
                targetRIR: 2,
                restSeconds: 180,
                loadStrategy: .absolute,
                increment: Load(value: 5, unit: .pounds)
            ),
            experienceLevel: .intermediate,
            bodyWeight: Load(value: 180, unit: .pounds),
            sessionDeloadTriggered: false,
            sessionDeloadReason: nil,
            sessionIntent: .general
        )
        
        let decision = DirectionPolicy.decide(signals: signals)
        
        // Should not be grinder-related reasons
        XCTAssertNotEqual(decision.primaryReason, .grinderSuccess)
        XCTAssertNotEqual(decision.primaryReason, .minorFatigueSignal)
    }
    
    // MARK: - Magnitude Tests
    
    /// Verify that grinder decreaseSlightly uses ~2.5% reduction for intermediate
    func testGrinderMagnitude_Intermediate_ShouldBe_2_5_to_3_Percent() {
        let signals = makeGrinderSignals(experience: .intermediate)
        let decision = DirectionPolicy.decide(signals: signals)
        
        XCTAssertEqual(decision.direction, .decreaseSlightly)
        
        let magnitude = MagnitudePolicy.compute(
            direction: DirectionDecision(
                direction: .decreaseSlightly,
                primaryReason: .minorFatigueSignal,
                explanation: "Test"
            ),
            signals: signals,
            baseRoundingPolicy: .standardPounds
        )
        
        // MagnitudePolicyConfig.default.acuteReadinessReduction for intermediate is 0.03 (3%)
        // This is close to the V6 rulebook's ~2.5%
        let expectedMultiplier = 1.0 - 0.03
        XCTAssertEqual(magnitude.loadMultiplier, expectedMultiplier, accuracy: 0.01,
            "Intermediate grinder reduction should be ~3%")
    }
    
    func testGrinderMagnitude_Advanced_ShouldBe_4_Percent() {
        let signals = makeGrinderSignals(experience: .advanced)
        
        let magnitude = MagnitudePolicy.compute(
            direction: DirectionDecision(
                direction: .decreaseSlightly,
                primaryReason: .minorFatigueSignal,
                explanation: "Test"
            ),
            signals: signals,
            baseRoundingPolicy: .standardPounds
        )
        
        // MagnitudePolicyConfig.default.acuteReadinessReduction for advanced is 0.04 (4%)
        let expectedMultiplier = 1.0 - 0.04
        XCTAssertEqual(magnitude.loadMultiplier, expectedMultiplier, accuracy: 0.01,
            "Advanced grinder reduction should be ~4%")
    }
}
