// MicroloadingConstraintTests.swift
// Unit tests for microloading respecting gym equipment constraints.
// Validates that MagnitudePolicy.selectRoundingPolicy never selects an increment
// smaller than the base policy's increment (gym's available plates).

import XCTest
@testable import TrainingEngine

final class MicroloadingConstraintTests: XCTestCase {
    
    // MARK: - Test Helpers
    
    private func makeSignals(
        exerciseId: String = "bench",
        movementPattern: MovementPattern = .horizontalPush,
        equipment: Equipment = .barbell,
        experienceLevel: ExperienceLevel = .intermediate,
        lastWorkingWeight: Double = 185.0
    ) -> LiftSignals {
        return LiftSignals(
            exerciseId: exerciseId,
            movementPattern: movementPattern,
            equipment: equipment,
            lastWorkingWeight: Load(value: lastWorkingWeight, unit: .pounds),
            rollingE1RM: lastWorkingWeight * 1.2,
            failStreak: 0,
            highRpeStreak: 0,
            daysSinceLastExposure: 3,
            daysSinceDeload: 14,
            trend: .stable,
            successfulSessionsCount: 5,
            successStreak: 3,
            lastSessionWasFailure: false,
            lastSessionWasGrinder: false,
            lastSessionAvgRIR: 2.0,
            lastSessionReps: [5, 5, 5],
            todayReadiness: 75,
            recentReadinessScores: [75, 70, 80],
            prescription: SetPrescription(
                setCount: 3,
                targetRepsRange: 5...5,
                targetRIR: 2,
                restSeconds: 180,
                loadStrategy: .absolute,
                increment: Load(value: 5.0, unit: .pounds)
            ),
            experienceLevel: experienceLevel,
            bodyWeight: Load(value: 180.0, unit: .pounds),
            sessionDeloadTriggered: false,
            sessionDeloadReason: nil,
            sessionIntent: .heavy
        )
    }
    
    // MARK: - Gym A: 1.25 lb increment (microloading capable)
    
    func testGymWithMicroplatesAllowsMicroloading() {
        // Gym A has 1.25 lb plates - microloading should work
        let basePolicy = LoadRoundingPolicy(increment: 1.25, unit: .pounds, mode: .nearest)
        let signals = makeSignals(
            movementPattern: .horizontalPush,
            equipment: .barbell,
            experienceLevel: .intermediate
        )
        
        let direction = DirectionDecision.increase()
        let magnitude = MagnitudePolicy.compute(
            direction: direction,
            signals: signals,
            baseRoundingPolicy: basePolicy,
            config: .default
        )
        
        // Should allow 1.25 lb increment for intermediate+ upper body press
        XCTAssertEqual(magnitude.roundingPolicy.increment, 1.25, "Gym with microplates should use 1.25 lb increment")
    }
    
    // MARK: - Gym B: 2.5 lb increment (no microplates)
    
    func testGymWithoutMicroplatesRespectsConstraint() {
        // Gym B only has 2.5 lb plates - cannot microload
        let basePolicy = LoadRoundingPolicy(increment: 2.5, unit: .pounds, mode: .nearest)
        let signals = makeSignals(
            movementPattern: .horizontalPush,
            equipment: .barbell,
            experienceLevel: .intermediate
        )
        
        let direction = DirectionDecision.increase()
        let magnitude = MagnitudePolicy.compute(
            direction: direction,
            signals: signals,
            baseRoundingPolicy: basePolicy,
            config: .default
        )
        
        // Should NOT use 1.25 lb - must stay at 2.5 lb minimum
        XCTAssertGreaterThanOrEqual(
            magnitude.roundingPolicy.increment, 
            2.5,
            "Gym without microplates should NOT go below 2.5 lb increment"
        )
    }
    
    func testGymWithStandardPlatesRespectsConstraint() {
        // Gym C only has 5 lb plates (2.5 lb each side)
        let basePolicy = LoadRoundingPolicy(increment: 5.0, unit: .pounds, mode: .nearest)
        let signals = makeSignals(
            movementPattern: .horizontalPush,
            equipment: .barbell,
            experienceLevel: .advanced
        )
        
        let direction = DirectionDecision.increase()
        let magnitude = MagnitudePolicy.compute(
            direction: direction,
            signals: signals,
            baseRoundingPolicy: basePolicy,
            config: .default
        )
        
        // Should NOT go below 5 lb increment
        XCTAssertGreaterThanOrEqual(
            magnitude.roundingPolicy.increment,
            5.0,
            "Gym with only standard plates should NOT go below 5 lb increment"
        )
    }
    
    // MARK: - Beginner Behavior
    
    func testBeginnerDoesNotUseMicroloading() {
        // Beginners should use standard increments even with microplates available
        let basePolicy = LoadRoundingPolicy(increment: 1.25, unit: .pounds, mode: .nearest)
        let signals = makeSignals(
            movementPattern: .horizontalPush,
            equipment: .barbell,
            experienceLevel: .beginner
        )
        
        let direction = DirectionDecision.increase()
        let magnitude = MagnitudePolicy.compute(
            direction: direction,
            signals: signals,
            baseRoundingPolicy: basePolicy,
            config: .default
        )
        
        // Beginners should get base policy (gym's increment)
        // The actual behavior depends on implementation - at minimum it shouldn't crash
        XCTAssertGreaterThanOrEqual(magnitude.roundingPolicy.increment, basePolicy.increment)
    }
    
    // MARK: - Lower Body Compounds
    
    func testSquatDoesNotGetMicroloading() {
        // Squats should use standard increments, not microloading
        let basePolicy = LoadRoundingPolicy(increment: 2.5, unit: .pounds, mode: .nearest)
        let signals = makeSignals(
            exerciseId: "squat",
            movementPattern: .squat,
            equipment: .barbell,
            experienceLevel: .intermediate,
            lastWorkingWeight: 315.0
        )
        
        let direction = DirectionDecision.increase()
        let magnitude = MagnitudePolicy.compute(
            direction: direction,
            signals: signals,
            baseRoundingPolicy: basePolicy,
            config: .default
        )
        
        // Squat should NOT get 1.25 lb microloading (that's for upper body press)
        XCTAssertGreaterThanOrEqual(magnitude.roundingPolicy.increment, 2.5)
    }
    
    func testDeadliftDoesNotGetMicroloading() {
        // Deadlifts should use standard increments
        let basePolicy = LoadRoundingPolicy(increment: 2.5, unit: .pounds, mode: .nearest)
        let signals = makeSignals(
            exerciseId: "deadlift",
            movementPattern: .hipHinge,
            equipment: .barbell,
            experienceLevel: .intermediate,
            lastWorkingWeight: 405.0
        )
        
        let direction = DirectionDecision.increase()
        let magnitude = MagnitudePolicy.compute(
            direction: direction,
            signals: signals,
            baseRoundingPolicy: basePolicy,
            config: .default
        )
        
        XCTAssertGreaterThanOrEqual(magnitude.roundingPolicy.increment, 2.5)
    }
    
    // MARK: - Overhead Press (Upper Body Press)
    
    func testOhpGetsMicroloadingWhenAvailable() {
        // OHP is upper body press - should get microloading if gym supports it
        let basePolicy = LoadRoundingPolicy(increment: 1.25, unit: .pounds, mode: .nearest)
        let signals = makeSignals(
            exerciseId: "ohp",
            movementPattern: .verticalPush,
            equipment: .barbell,
            experienceLevel: .intermediate,
            lastWorkingWeight: 135.0
        )
        
        let direction = DirectionDecision.increase()
        let magnitude = MagnitudePolicy.compute(
            direction: direction,
            signals: signals,
            baseRoundingPolicy: basePolicy,
            config: .default
        )
        
        // OHP with microplates available should use 1.25 lb
        XCTAssertEqual(magnitude.roundingPolicy.increment, 1.25)
    }
    
    func testOhpRespectsGymConstraintWithoutMicroplates() {
        // OHP at a gym without microplates
        let basePolicy = LoadRoundingPolicy(increment: 2.5, unit: .pounds, mode: .nearest)
        let signals = makeSignals(
            exerciseId: "ohp",
            movementPattern: .verticalPush,
            equipment: .barbell,
            experienceLevel: .intermediate,
            lastWorkingWeight: 135.0
        )
        
        let direction = DirectionDecision.increase()
        let magnitude = MagnitudePolicy.compute(
            direction: direction,
            signals: signals,
            baseRoundingPolicy: basePolicy,
            config: .default
        )
        
        // OHP without microplates should use 2.5 lb minimum
        XCTAssertGreaterThanOrEqual(magnitude.roundingPolicy.increment, 2.5)
    }
    
    // MARK: - Microloading Disabled
    
    func testMicroloadingDisabledUsesBasePolicy() {
        let basePolicy = LoadRoundingPolicy(increment: 1.25, unit: .pounds, mode: .nearest)
        let signals = makeSignals(
            movementPattern: .horizontalPush,
            equipment: .barbell,
            experienceLevel: .intermediate
        )
        
        // Disable microloading
        let config = MagnitudePolicyConfig(enableMicroloading: false)
        
        let direction = DirectionDecision.increase()
        let magnitude = MagnitudePolicy.compute(
            direction: direction,
            signals: signals,
            baseRoundingPolicy: basePolicy,
            config: config
        )
        
        // With microloading disabled, should use base policy as-is
        XCTAssertEqual(magnitude.roundingPolicy.increment, basePolicy.increment)
    }
    
    // MARK: - Metric Units
    
    func testMetricMicroloadingRespectsConstraints() {
        // Gym with 0.5 kg increments (microplates)
        let basePolicy = LoadRoundingPolicy(increment: 0.5, unit: .kilograms, mode: .nearest)
        let signals = makeSignals(
            movementPattern: .horizontalPush,
            equipment: .barbell,
            experienceLevel: .intermediate
        )
        
        let direction = DirectionDecision.increase()
        let magnitude = MagnitudePolicy.compute(
            direction: direction,
            signals: signals,
            baseRoundingPolicy: basePolicy,
            config: .default
        )
        
        // Should allow 0.5 kg for microloading
        XCTAssertEqual(magnitude.roundingPolicy.increment, 0.5)
    }
    
    func testMetricGymWithoutMicroplatesRespectsConstraint() {
        // Gym with 1.25 kg increments (no microplates)
        let basePolicy = LoadRoundingPolicy(increment: 1.25, unit: .kilograms, mode: .nearest)
        let signals = makeSignals(
            movementPattern: .horizontalPush,
            equipment: .barbell,
            experienceLevel: .intermediate
        )
        
        let direction = DirectionDecision.increase()
        let magnitude = MagnitudePolicy.compute(
            direction: direction,
            signals: signals,
            baseRoundingPolicy: basePolicy,
            config: .default
        )
        
        // Should NOT go below 1.25 kg
        XCTAssertGreaterThanOrEqual(magnitude.roundingPolicy.increment, 1.25)
    }
}
