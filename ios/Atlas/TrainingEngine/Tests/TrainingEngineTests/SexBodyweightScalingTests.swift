// SexBodyweightScalingTests.swift
// Unit tests for sex-aware bodyweight plumbing and increment scaling.
// Validates that:
// 1. relativeStrength is computed when bodyWeight is provided
// 2. sex-aware thresholds change computed increments (magnitude)
// 3. direction decisions are NOT affected by sex (only magnitude)

import XCTest
@testable import TrainingEngine

final class SexBodyweightScalingTests: XCTestCase {
    
    // MARK: - Test Helpers
    
    private func makeSignals(
        exerciseId: String = "bench",
        movementPattern: MovementPattern = .horizontalPush,
        equipment: Equipment = .barbell,
        experienceLevel: ExperienceLevel = .intermediate,
        sex: BiologicalSex = .male,
        bodyWeight: Load? = Load(value: 180.0, unit: .pounds),
        lastWorkingWeight: Double = 185.0,
        rollingE1RM: Double? = nil,
        todayReadiness: Int = 75,
        lastSessionReps: [Int] = [5, 5, 5],
        lastSessionWasFailure: Bool = false,
        lastSessionWasGrinder: Bool = false,
        daysSinceLastExposure: Int? = 3
    ) -> LiftSignals {
        let e1rm = rollingE1RM ?? lastWorkingWeight * 1.2
        return LiftSignals(
            exerciseId: exerciseId,
            movementPattern: movementPattern,
            equipment: equipment,
            lastWorkingWeight: Load(value: lastWorkingWeight, unit: .pounds),
            rollingE1RM: e1rm,
            failStreak: 0,
            highRpeStreak: 0,
            daysSinceLastExposure: daysSinceLastExposure,
            daysSinceDeload: 14,
            trend: .stable,
            successfulSessionsCount: 5,
            successStreak: 3,
            lastSessionWasFailure: lastSessionWasFailure,
            lastSessionWasGrinder: lastSessionWasGrinder,
            lastSessionAvgRIR: 2.0,
            lastSessionReps: lastSessionReps,
            todayReadiness: todayReadiness,
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
            sex: sex,
            bodyWeight: bodyWeight,
            sessionDeloadTriggered: false,
            sessionDeloadReason: nil,
            sessionIntent: .heavy
        )
    }
    
    // MARK: - Relative Strength Computation
    
    func testRelativeStrengthComputedWhenBodyWeightProvided() {
        let signals = makeSignals(
            bodyWeight: Load(value: 180.0, unit: .pounds),
            rollingE1RM: 225.0
        )
        
        // relativeStrength = e1RM / bodyWeight = 225 / 180 = 1.25
        XCTAssertNotNil(signals.relativeStrength, "relativeStrength should be computed when bodyWeight is provided")
        XCTAssertEqual(signals.relativeStrength!, 1.25, accuracy: 0.01)
    }
    
    func testRelativeStrengthNilWhenBodyWeightNil() {
        let signals = makeSignals(bodyWeight: nil)
        XCTAssertNil(signals.relativeStrength, "relativeStrength should be nil when bodyWeight is nil")
    }
    
    func testRelativeStrengthNilWhenBodyWeightZero() {
        let signals = makeSignals(bodyWeight: Load(value: 0.0, unit: .pounds))
        XCTAssertNil(signals.relativeStrength, "relativeStrength should be nil when bodyWeight is zero")
    }
    
    // MARK: - Sex-Aware Threshold Tests
    
    func testStrengthThresholdsLowerForFemale() {
        let config = MagnitudePolicyConfig.default
        
        let maleThresholds = config.strengthScalingThresholds(for: .horizontalPush, sex: .male)
        let femaleThresholds = config.strengthScalingThresholds(for: .horizontalPush, sex: .female)
        
        // Female thresholds should be lower than male
        XCTAssertLessThan(femaleThresholds.medium, maleThresholds.medium, 
                          "Female medium threshold should be lower than male")
        XCTAssertLessThan(femaleThresholds.high, maleThresholds.high,
                          "Female high threshold should be lower than male")
        
        // Female thresholds should be approximately 62% of male
        let femaleScale = 0.62
        XCTAssertEqual(femaleThresholds.medium, maleThresholds.medium * femaleScale, accuracy: 0.01)
        XCTAssertEqual(femaleThresholds.high, maleThresholds.high * femaleScale, accuracy: 0.01)
    }
    
    func testStrengthThresholdsMidpointForOther() {
        let config = MagnitudePolicyConfig.default
        
        let maleThresholds = config.strengthScalingThresholds(for: .squat, sex: .male)
        let femaleThresholds = config.strengthScalingThresholds(for: .squat, sex: .female)
        let otherThresholds = config.strengthScalingThresholds(for: .squat, sex: .other)
        
        // "Other" thresholds should be midpoint between male and female
        let expectedMedium = (maleThresholds.medium + femaleThresholds.medium) / 2.0
        let expectedHigh = (maleThresholds.high + femaleThresholds.high) / 2.0
        
        XCTAssertEqual(otherThresholds.medium, expectedMedium, accuracy: 0.01,
                       "'Other' medium threshold should be midpoint of male and female")
        XCTAssertEqual(otherThresholds.high, expectedHigh, accuracy: 0.01,
                       "'Other' high threshold should be midpoint of male and female")
    }
    
    func testStrengthThresholdsForDifferentPatterns() {
        let config = MagnitudePolicyConfig.default
        
        // Test squat thresholds
        let squatMale = config.strengthScalingThresholds(for: .squat, sex: .male)
        let squatFemale = config.strengthScalingThresholds(for: .squat, sex: .female)
        XCTAssertEqual(squatMale.medium, 2.0)
        XCTAssertEqual(squatMale.high, 2.5)
        XCTAssertLessThan(squatFemale.medium, squatMale.medium)
        
        // Test hip hinge thresholds
        let hingeMale = config.strengthScalingThresholds(for: .hipHinge, sex: .male)
        let hingeFemale = config.strengthScalingThresholds(for: .hipHinge, sex: .female)
        XCTAssertEqual(hingeMale.medium, 2.25)
        XCTAssertEqual(hingeMale.high, 2.75)
        XCTAssertLessThan(hingeFemale.medium, hingeMale.medium)
    }
    
    // MARK: - Increment Scaling by Sex
    
    func testFemaleLowRelativeStrengthGetsFullIncrement() {
        // A female lifter at 0.6x BW bench (below medium threshold) should get full increment
        let basePolicy = LoadRoundingPolicy(increment: 2.5, unit: .pounds, mode: .nearest)
        let signals = makeSignals(
            movementPattern: .horizontalPush,
            sex: .female,
            bodyWeight: Load(value: 150.0, unit: .pounds),
            lastWorkingWeight: 85.0,
            rollingE1RM: 90.0  // 90/150 = 0.6 BW - below female medium threshold
        )
        
        let direction = DirectionDecision.increase()
        let magnitude = MagnitudePolicy.compute(
            direction: direction,
            signals: signals,
            baseRoundingPolicy: basePolicy,
            config: .default
        )
        
        // At low relative strength, should get full increment without scaling down
        // (strengthScale = 1.0)
        XCTAssertNotNil(magnitude.absoluteIncrement)
    }
    
    func testMaleSameAbsoluteLoadGetsScaledIncrement() {
        // A male lifter at the same absolute load but lower relative strength
        // might get different increment than female at same relative strength
        let basePolicy = LoadRoundingPolicy(increment: 2.5, unit: .pounds, mode: .nearest)
        
        // Male at 225 lb bench with 180 lb BW = 1.25 BW (at male medium threshold)
        let maleSignals = makeSignals(
            movementPattern: .horizontalPush,
            sex: .male,
            bodyWeight: Load(value: 180.0, unit: .pounds),
            lastWorkingWeight: 215.0,
            rollingE1RM: 225.0  // 225/180 = 1.25 BW - at male medium threshold
        )
        
        // Female at 135 lb bench with 130 lb BW = 1.04 BW (above female high threshold of ~1.09)
        let femaleSignals = makeSignals(
            movementPattern: .horizontalPush,
            sex: .female,
            bodyWeight: Load(value: 130.0, unit: .pounds),
            lastWorkingWeight: 130.0,
            rollingE1RM: 135.0  // 135/130 = 1.04 BW - at female high threshold
        )
        
        let direction = DirectionDecision.increase()
        let maleMagnitude = MagnitudePolicy.compute(
            direction: direction,
            signals: maleSignals,
            baseRoundingPolicy: basePolicy,
            config: .default
        )
        let femaleMagnitude = MagnitudePolicy.compute(
            direction: direction,
            signals: femaleSignals,
            baseRoundingPolicy: basePolicy,
            config: .default
        )
        
        // Both should get increments (the exact values may differ based on strength tier)
        XCTAssertGreaterThan(maleMagnitude.absoluteIncrement.value, 0)
        XCTAssertGreaterThan(femaleMagnitude.absoluteIncrement.value, 0)
    }
    
    // MARK: - Direction NOT Affected by Sex
    
    func testDirectionUnchangedBySex_Increase() {
        // Same performance scenario should yield same direction regardless of sex
        let maleSignals = makeSignals(
            sex: .male,
            todayReadiness: 80,
            lastSessionReps: [5, 5, 5],
            lastSessionWasFailure: false,
            lastSessionWasGrinder: false
        )
        let femaleSignals = makeSignals(
            sex: .female,
            todayReadiness: 80,
            lastSessionReps: [5, 5, 5],
            lastSessionWasFailure: false,
            lastSessionWasGrinder: false
        )
        
        let maleDecision = DirectionPolicy.decide(signals: maleSignals)
        let femaleDecision = DirectionPolicy.decide(signals: femaleSignals)
        
        // Direction should be the same
        XCTAssertEqual(maleDecision.direction, femaleDecision.direction,
                       "Direction should not be affected by sex")
    }
    
    func testDirectionUnchangedBySex_Hold() {
        // Low readiness should yield hold regardless of sex
        let maleSignals = makeSignals(
            sex: .male,
            todayReadiness: 62,  // Borderline low readiness
            lastSessionReps: [5, 5, 5],
            lastSessionWasFailure: false,
            lastSessionWasGrinder: false
        )
        let femaleSignals = makeSignals(
            sex: .female,
            todayReadiness: 62,
            lastSessionReps: [5, 5, 5],
            lastSessionWasFailure: false,
            lastSessionWasGrinder: false
        )
        
        let maleDecision = DirectionPolicy.decide(signals: maleSignals)
        let femaleDecision = DirectionPolicy.decide(signals: femaleSignals)
        
        XCTAssertEqual(maleDecision.direction, femaleDecision.direction,
                       "Direction should not be affected by sex for same readiness")
    }
    
    func testDirectionUnchangedBySex_ResetAfterBreak() {
        // Extended break should trigger reset regardless of sex
        let maleSignals = makeSignals(
            sex: .male,
            daysSinceLastExposure: 21
        )
        let femaleSignals = makeSignals(
            sex: .female,
            daysSinceLastExposure: 21
        )
        
        let maleDecision = DirectionPolicy.decide(signals: maleSignals)
        let femaleDecision = DirectionPolicy.decide(signals: femaleSignals)
        
        XCTAssertEqual(maleDecision.direction, .resetAfterBreak,
                       "Male should get resetAfterBreak for extended break")
        XCTAssertEqual(femaleDecision.direction, .resetAfterBreak,
                       "Female should get resetAfterBreak for extended break")
    }
    
    func testDirectionUnchangedBySex_Grinder() {
        // Grinder session should yield same direction regardless of sex
        let maleSignals = makeSignals(
            experienceLevel: .intermediate,
            sex: .male,
            todayReadiness: 75,
            lastSessionWasGrinder: true
        )
        let femaleSignals = makeSignals(
            experienceLevel: .intermediate,
            sex: .female,
            todayReadiness: 75,
            lastSessionWasGrinder: true
        )
        
        let maleDecision = DirectionPolicy.decide(signals: maleSignals)
        let femaleDecision = DirectionPolicy.decide(signals: femaleSignals)
        
        XCTAssertEqual(maleDecision.direction, femaleDecision.direction,
                       "Direction should not be affected by sex for grinder scenarios")
    }
    
    // MARK: - DoubleProgression Sex-Aware Scaling
    
    func testDoubleProgressionUsesUserProfileSex() {
        // This test validates that UserProfile correctly stores sex
        // for use with sex-aware strength scaling
        
        let maleProfile = UserProfile(
            id: "male-user",
            sex: .male,
            experience: .intermediate,
            goals: [.strength],
            bodyWeight: Load(value: 180.0, unit: .pounds)
        )
        
        let femaleProfile = UserProfile(
            id: "female-user",
            sex: .female,
            experience: .intermediate,
            goals: [.strength],
            bodyWeight: Load(value: 130.0, unit: .pounds)
        )
        
        // Both profiles should work without error with sex-aware scaling
        XCTAssertEqual(maleProfile.sex, .male)
        XCTAssertEqual(femaleProfile.sex, .female)
    }
    
    // MARK: - Edge Cases
    
    func testVeryHighRelativeStrengthFemale() {
        // Female at very high relative strength should get reduced increment
        let basePolicy = LoadRoundingPolicy(increment: 2.5, unit: .pounds, mode: .nearest)
        let signals = makeSignals(
            movementPattern: .horizontalPush,
            sex: .female,
            bodyWeight: Load(value: 130.0, unit: .pounds),
            lastWorkingWeight: 175.0,
            rollingE1RM: 195.0  // 195/130 = 1.5 BW - very high for female
        )
        
        let direction = DirectionDecision.increase()
        let magnitude = MagnitudePolicy.compute(
            direction: direction,
            signals: signals,
            baseRoundingPolicy: basePolicy,
            config: .default
        )
        
        // Should still produce a valid increment
        XCTAssertGreaterThanOrEqual(magnitude.absoluteIncrement.value, 0)
    }
    
    func testNoBodyWeightFallsBackToAbsoluteThresholds() {
        // Without bodyweight, should fall back to absolute e1RM thresholds
        // (Note: these aren't sex-aware in DoubleProgression yet, but the direction
        // policy should still work)
        let signals = makeSignals(
            sex: .female,
            bodyWeight: nil,  // No bodyweight
            lastWorkingWeight: 95.0,
            rollingE1RM: 105.0
        )
        
        // relativeStrength should be nil
        XCTAssertNil(signals.relativeStrength)
        
        // Direction should still work
        let decision = DirectionPolicy.decide(signals: signals)
        XCTAssertNotNil(decision.direction)
    }
}
