// MovementIncrementScalingTests.swift
// Unit tests for movement-pattern-based increment scaling.
// Validates that:
// 1. Isolation exercises get smaller increments than compounds
// 2. Small upper-body isolations (lateral raises, curls) get the smallest increments
// 3. Movement-specific caps are respected

import XCTest
@testable import TrainingEngine

final class MovementIncrementScalingTests: XCTestCase {
    
    // MARK: - Test Helpers
    
    private func makeSignals(
        movementPattern: MovementPattern,
        equipment: Equipment = .dumbbell,
        experienceLevel: ExperienceLevel = .intermediate,
        sex: BiologicalSex = .male,
        bodyWeight: Load? = Load(value: 180.0, unit: .pounds),
        lastWorkingWeight: Double = 50.0,
        rollingE1RM: Double? = nil,
        prescriptionIncrement: Double = 5.0
    ) -> LiftSignals {
        let e1rm = rollingE1RM ?? lastWorkingWeight * 1.2
        return LiftSignals(
            exerciseId: "test_exercise",
            movementPattern: movementPattern,
            equipment: equipment,
            lastWorkingWeight: Load(value: lastWorkingWeight, unit: .pounds),
            rollingE1RM: e1rm,
            failStreak: 0,
            highRpeStreak: 0,
            daysSinceLastExposure: 3,
            daysSinceDeload: 14,
            trend: .stable,
            successfulSessionsCount: 5,
            successStreak: 3,
            lastSessionWasFailure: false,
            lastSessionWasGrinder: false,
            lastSessionAvgRIR: 3.0, // Easy session to trigger increase
            lastSessionReps: [10, 10, 10],
            todayReadiness: 75,
            recentReadinessScores: [75, 70, 80],
            prescription: SetPrescription(
                setCount: 3,
                targetRepsRange: 8...12,
                targetRIR: 2,
                restSeconds: 90,
                loadStrategy: .absolute,
                increment: Load(value: prescriptionIncrement, unit: .pounds)
            ),
            experienceLevel: experienceLevel,
            sex: sex,
            bodyWeight: bodyWeight,
            sessionDeloadTriggered: false,
            sessionDeloadReason: nil,
            sessionIntent: .general
        )
    }
    
    private func computeIncrement(for signals: LiftSignals) -> Load {
        // Get direction decision first
        let (direction, _) = DirectionPolicy.decideWithTrace(signals: signals)
        
        // Compute magnitude
        let magnitude = MagnitudePolicy.compute(
            direction: direction,
            signals: signals,
            baseRoundingPolicy: .standardPounds
        )
        
        return magnitude.absoluteIncrement
    }
    
    // MARK: - Isolation vs Compound Tests
    
    func testLateralRaiseIncrementSmallerThanSquat() {
        // Same prescription (5 lb increment), same experience level
        let lateralRaiseSignals = makeSignals(movementPattern: .shoulderAbduction)
        let squatSignals = makeSignals(movementPattern: .squat, equipment: .barbell)
        
        let lateralRaiseIncrement = computeIncrement(for: lateralRaiseSignals)
        let squatIncrement = computeIncrement(for: squatSignals)
        
        XCTAssertLessThan(
            lateralRaiseIncrement.value,
            squatIncrement.value,
            "Lateral raise increment (\(lateralRaiseIncrement.value) lb) should be smaller than squat increment (\(squatIncrement.value) lb)"
        )
    }
    
    func testBicepCurlIncrementSmallerThanDeadlift() {
        let curlSignals = makeSignals(movementPattern: .elbowFlexion)
        let deadliftSignals = makeSignals(movementPattern: .hipHinge, equipment: .barbell)
        
        let curlIncrement = computeIncrement(for: curlSignals)
        let deadliftIncrement = computeIncrement(for: deadliftSignals)
        
        XCTAssertLessThan(
            curlIncrement.value,
            deadliftIncrement.value,
            "Bicep curl increment (\(curlIncrement.value) lb) should be smaller than deadlift increment (\(deadliftIncrement.value) lb)"
        )
    }
    
    func testTricepExtensionIncrementSmallerThanBenchPress() {
        let extensionSignals = makeSignals(movementPattern: .elbowExtension)
        let benchSignals = makeSignals(movementPattern: .horizontalPush, equipment: .barbell)
        
        let extensionIncrement = computeIncrement(for: extensionSignals)
        let benchIncrement = computeIncrement(for: benchSignals)
        
        XCTAssertLessThan(
            extensionIncrement.value,
            benchIncrement.value,
            "Tricep extension increment (\(extensionIncrement.value) lb) should be smaller than bench press increment (\(benchIncrement.value) lb)"
        )
    }
    
    func testLegExtensionIncrementSmallerThanSquat() {
        let legExtSignals = makeSignals(movementPattern: .kneeExtension, equipment: .machine)
        let squatSignals = makeSignals(movementPattern: .squat, equipment: .barbell)
        
        let legExtIncrement = computeIncrement(for: legExtSignals)
        let squatIncrement = computeIncrement(for: squatSignals)
        
        XCTAssertLessThan(
            legExtIncrement.value,
            squatIncrement.value,
            "Leg extension increment (\(legExtIncrement.value) lb) should be smaller than squat increment (\(squatIncrement.value) lb)"
        )
    }
    
    // MARK: - Small Upper-Body Isolation Cap Tests
    
    func testLateralRaiseIncrementCappedAt2_5Pounds() {
        // Even with large prescription increment, lateral raises should be capped
        let signals = makeSignals(
            movementPattern: .shoulderAbduction,
            prescriptionIncrement: 10.0 // Large prescription
        )
        
        let increment = computeIncrement(for: signals)
        
        XCTAssertLessThanOrEqual(
            increment.value,
            2.5,
            "Lateral raise increment should be capped at 2.5 lb, got \(increment.value) lb"
        )
    }
    
    func testBicepCurlIncrementCappedAt2_5Pounds() {
        let signals = makeSignals(
            movementPattern: .elbowFlexion,
            prescriptionIncrement: 10.0
        )
        
        let increment = computeIncrement(for: signals)
        
        XCTAssertLessThanOrEqual(
            increment.value,
            2.5,
            "Bicep curl increment should be capped at 2.5 lb, got \(increment.value) lb"
        )
    }
    
    func testFrontRaiseIncrementCappedAt2_5Pounds() {
        let signals = makeSignals(
            movementPattern: .shoulderFlexion,
            prescriptionIncrement: 10.0
        )
        
        let increment = computeIncrement(for: signals)
        
        XCTAssertLessThanOrEqual(
            increment.value,
            2.5,
            "Front raise increment should be capped at 2.5 lb, got \(increment.value) lb"
        )
    }
    
    func testTricepExtensionIncrementCappedAt2_5Pounds() {
        let signals = makeSignals(
            movementPattern: .elbowExtension,
            prescriptionIncrement: 10.0
        )
        
        let increment = computeIncrement(for: signals)
        
        XCTAssertLessThanOrEqual(
            increment.value,
            2.5,
            "Tricep extension increment should be capped at 2.5 lb, got \(increment.value) lb"
        )
    }
    
    // MARK: - Other Isolation Cap Tests
    
    func testLegExtensionIncrementCappedAt5Pounds() {
        let signals = makeSignals(
            movementPattern: .kneeExtension,
            equipment: .machine,
            prescriptionIncrement: 15.0
        )
        
        let increment = computeIncrement(for: signals)
        
        XCTAssertLessThanOrEqual(
            increment.value,
            5.0,
            "Leg extension increment should be capped at 5.0 lb, got \(increment.value) lb"
        )
    }
    
    func testLegCurlIncrementCappedAt5Pounds() {
        let signals = makeSignals(
            movementPattern: .kneeFlexion,
            equipment: .machine,
            prescriptionIncrement: 15.0
        )
        
        let increment = computeIncrement(for: signals)
        
        XCTAssertLessThanOrEqual(
            increment.value,
            5.0,
            "Leg curl increment should be capped at 5.0 lb, got \(increment.value) lb"
        )
    }
    
    // MARK: - Compound Cap Tests (Unchanged)
    
    func testSquatIncrementCappedAt10Pounds() {
        let signals = makeSignals(
            movementPattern: .squat,
            equipment: .barbell,
            experienceLevel: .beginner, // Beginner gets full increment
            prescriptionIncrement: 15.0
        )
        
        let increment = computeIncrement(for: signals)
        
        XCTAssertLessThanOrEqual(
            increment.value,
            10.0,
            "Squat increment should be capped at 10.0 lb, got \(increment.value) lb"
        )
    }
    
    func testDeadliftIncrementCappedAt10Pounds() {
        let signals = makeSignals(
            movementPattern: .hipHinge,
            equipment: .barbell,
            experienceLevel: .beginner,
            prescriptionIncrement: 15.0
        )
        
        let increment = computeIncrement(for: signals)
        
        XCTAssertLessThanOrEqual(
            increment.value,
            10.0,
            "Deadlift increment should be capped at 10.0 lb, got \(increment.value) lb"
        )
    }
    
    func testBenchPressIncrementCappedAt5Pounds() {
        let signals = makeSignals(
            movementPattern: .horizontalPush,
            equipment: .barbell,
            experienceLevel: .beginner,
            prescriptionIncrement: 10.0
        )
        
        let increment = computeIncrement(for: signals)
        
        XCTAssertLessThanOrEqual(
            increment.value,
            5.0,
            "Bench press increment should be capped at 5.0 lb, got \(increment.value) lb"
        )
    }
    
    // MARK: - Experience Level Still Applies
    
    func testExperienceLevelScalingStillAppliesForIsolations() {
        // Advanced lifter should get smaller increments than beginner
        let advancedSignals = makeSignals(
            movementPattern: .shoulderAbduction,
            experienceLevel: .advanced
        )
        let beginnerSignals = makeSignals(
            movementPattern: .shoulderAbduction,
            experienceLevel: .beginner
        )
        
        let advancedIncrement = computeIncrement(for: advancedSignals)
        let beginnerIncrement = computeIncrement(for: beginnerSignals)
        
        // Both should be capped at 2.5 lb, but beginner may hit the cap while advanced is smaller
        XCTAssertLessThanOrEqual(
            advancedIncrement.value,
            beginnerIncrement.value,
            "Advanced lifter increment should be <= beginner increment for same movement"
        )
    }
    
    // MARK: - Default Policy Tests
    
    func testDefaultPolicyForIsolationUsesSmallIncrement() {
        // Isolation movements should default to smallIncrement config
        let policy = ProgressionPolicyType.defaultPolicy(
            for: .shoulderAbduction,
            goals: [.hypertrophy]
        )
        
        if case .doubleProgression(let config) = policy {
            XCTAssertEqual(
                config.loadIncrement.value,
                2.5,
                "Isolation default policy should use 2.5 lb increment, got \(config.loadIncrement.value)"
            )
        } else {
            XCTFail("Isolation default policy should be doubleProgression")
        }
    }
    
    func testDefaultPolicyForCompoundUsesLargerIncrement() {
        // Compound movements should use larger increments
        let policy = ProgressionPolicyType.defaultPolicy(
            for: .squat,
            goals: [.hypertrophy]
        )
        
        if case .doubleProgression(let config) = policy {
            XCTAssertGreaterThan(
                config.loadIncrement.value,
                2.5,
                "Compound default policy should use increment > 2.5 lb"
            )
        } else if case .topSetBackoff = policy {
            // Also acceptable for strength goals
        } else {
            XCTFail("Compound default policy should be doubleProgression or topSetBackoff")
        }
    }
}
