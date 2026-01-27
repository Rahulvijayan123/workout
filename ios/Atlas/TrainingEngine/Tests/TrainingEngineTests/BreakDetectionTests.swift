// BreakDetectionTests.swift
// Unit tests for training break detection and reset behavior.
// Validates that:
// - 8-13 day gaps trigger resetAfterBreak with 5% reduction
// - 14-27 day gaps trigger resetAfterBreak with 10% reduction (V6 rulebook)
// - 28+ day gaps trigger progressively larger reductions
// - Days < 8 do NOT trigger resetAfterBreak

import XCTest
@testable import TrainingEngine

final class BreakDetectionTests: XCTestCase {
    
    // MARK: - Test Helpers
    
    private func makeSignals(
        daysSinceLastExposure: Int?,
        experienceLevel: ExperienceLevel = .intermediate,
        lastSessionReps: [Int] = [5, 5, 5],
        todayReadiness: Int = 75
    ) -> LiftSignals {
        return LiftSignals(
            exerciseId: "squat",
            movementPattern: .squat,
            equipment: .barbell,
            lastWorkingWeight: Load(value: 315.0, unit: .pounds),
            rollingE1RM: 378.0,
            failStreak: 0,
            highRpeStreak: 0,
            daysSinceLastExposure: daysSinceLastExposure,
            daysSinceDeload: 30,
            trend: .stable,
            successfulSessionsCount: 10,
            successStreak: 3,
            lastSessionWasFailure: false,
            lastSessionWasGrinder: false,
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
            bodyWeight: Load(value: 180.0, unit: .pounds),
            sessionDeloadTriggered: false,
            sessionDeloadReason: nil,
            sessionIntent: .heavy
        )
    }
    
    // MARK: - No Break (< 8 days)
    
    func testNormalSessionNoBreakTriggered_3Days() {
        let signals = makeSignals(daysSinceLastExposure: 3)
        let decision = DirectionPolicy.decide(signals: signals)
        
        XCTAssertNotEqual(decision.direction, .resetAfterBreak, "3 days should NOT trigger break reset")
    }
    
    func testNormalSessionNoBreakTriggered_5Days() {
        let signals = makeSignals(daysSinceLastExposure: 5)
        let decision = DirectionPolicy.decide(signals: signals)
        
        XCTAssertNotEqual(decision.direction, .resetAfterBreak, "5 days should NOT trigger break reset")
    }
    
    func testNormalSessionNoBreakTriggered_7Days() {
        let signals = makeSignals(daysSinceLastExposure: 7)
        let decision = DirectionPolicy.decide(signals: signals)
        
        XCTAssertNotEqual(decision.direction, .resetAfterBreak, "7 days should NOT trigger break reset")
    }
    
    // MARK: - Training Gap (8-13 days)
    
    func testTrainingGap_8Days() {
        let signals = makeSignals(daysSinceLastExposure: 8)
        let decision = DirectionPolicy.decide(signals: signals)
        
        XCTAssertEqual(decision.direction, .resetAfterBreak, "8 days should trigger training gap reset")
        XCTAssertEqual(decision.primaryReason, .extendedBreak)
    }
    
    func testTrainingGap_10Days() {
        let signals = makeSignals(daysSinceLastExposure: 10)
        let decision = DirectionPolicy.decide(signals: signals)
        
        XCTAssertEqual(decision.direction, .resetAfterBreak, "10 days should trigger training gap reset")
    }
    
    func testTrainingGap_13Days() {
        let signals = makeSignals(daysSinceLastExposure: 13)
        let decision = DirectionPolicy.decide(signals: signals)
        
        XCTAssertEqual(decision.direction, .resetAfterBreak, "13 days should trigger training gap reset")
    }
    
    func testTrainingGapMagnitude_8to13Days() {
        // 8-13 days should yield ~5% reduction
        let signals = makeSignals(daysSinceLastExposure: 10)
        let direction = DirectionPolicy.decide(signals: signals)
        let basePolicy = LoadRoundingPolicy.standardPounds
        
        let magnitude = MagnitudePolicy.compute(
            direction: direction,
            signals: signals,
            baseRoundingPolicy: basePolicy
        )
        
        // Should be around 5% reduction (loadMultiplier ~0.95)
        XCTAssertEqual(magnitude.loadMultiplier, 0.95, accuracy: 0.01, "8-13 day gap should yield ~5% reduction")
    }
    
    // MARK: - Extended Break (14-27 days) - V6 Rulebook
    
    func testExtendedBreak_14Days() {
        let signals = makeSignals(daysSinceLastExposure: 14)
        let decision = DirectionPolicy.decide(signals: signals)
        
        XCTAssertEqual(decision.direction, .resetAfterBreak, "14 days should trigger extended break reset")
    }
    
    func testExtendedBreak_21Days() {
        let signals = makeSignals(daysSinceLastExposure: 21)
        let decision = DirectionPolicy.decide(signals: signals)
        
        XCTAssertEqual(decision.direction, .resetAfterBreak, "21 days should trigger extended break reset")
    }
    
    func testExtendedBreak_27Days() {
        let signals = makeSignals(daysSinceLastExposure: 27)
        let decision = DirectionPolicy.decide(signals: signals)
        
        XCTAssertEqual(decision.direction, .resetAfterBreak, "27 days should trigger extended break reset")
    }
    
    func testExtendedBreakMagnitude_14to27Days() {
        // V6 rulebook: >14 days since lift exposure: apply ~10% reduction (break_reset)
        let signals = makeSignals(daysSinceLastExposure: 21)
        let direction = DirectionPolicy.decide(signals: signals)
        let basePolicy = LoadRoundingPolicy.standardPounds
        
        let magnitude = MagnitudePolicy.compute(
            direction: direction,
            signals: signals,
            baseRoundingPolicy: basePolicy
        )
        
        // Should be around 10% reduction (loadMultiplier ~0.90)
        XCTAssertEqual(magnitude.loadMultiplier, 0.90, accuracy: 0.01, "14-27 day gap should yield ~10% reduction per V6 rulebook")
    }
    
    // MARK: - Moderate Detraining (28-55 days)
    
    func testModerateDetraining_28Days() {
        let signals = makeSignals(daysSinceLastExposure: 28)
        let decision = DirectionPolicy.decide(signals: signals)
        
        XCTAssertEqual(decision.direction, .resetAfterBreak, "28 days should trigger extended break reset")
    }
    
    func testModerateDetrainingMagnitude_28to55Days() {
        // 28-55 days should yield ~15% reduction
        let signals = makeSignals(daysSinceLastExposure: 40)
        let direction = DirectionPolicy.decide(signals: signals)
        let basePolicy = LoadRoundingPolicy.standardPounds
        
        let magnitude = MagnitudePolicy.compute(
            direction: direction,
            signals: signals,
            baseRoundingPolicy: basePolicy
        )
        
        // Should be around 15% reduction (loadMultiplier ~0.85)
        XCTAssertEqual(magnitude.loadMultiplier, 0.85, accuracy: 0.01, "28-55 day gap should yield ~15% reduction")
    }
    
    // MARK: - Significant Detraining (56-83 days)
    
    func testSignificantDetraining_60Days() {
        let signals = makeSignals(daysSinceLastExposure: 60)
        let decision = DirectionPolicy.decide(signals: signals)
        
        XCTAssertEqual(decision.direction, .resetAfterBreak, "60 days should trigger extended break reset")
    }
    
    func testSignificantDetrainingMagnitude_56to83Days() {
        // 56-83 days should yield ~20% reduction
        let signals = makeSignals(daysSinceLastExposure: 70)
        let direction = DirectionPolicy.decide(signals: signals)
        let basePolicy = LoadRoundingPolicy.standardPounds
        
        let magnitude = MagnitudePolicy.compute(
            direction: direction,
            signals: signals,
            baseRoundingPolicy: basePolicy
        )
        
        // Should be around 20% reduction (loadMultiplier ~0.80)
        XCTAssertEqual(magnitude.loadMultiplier, 0.80, accuracy: 0.01, "56-83 day gap should yield ~20% reduction")
    }
    
    // MARK: - Major Detraining (84+ days)
    
    func testMajorDetraining_90Days() {
        let signals = makeSignals(daysSinceLastExposure: 90)
        let decision = DirectionPolicy.decide(signals: signals)
        
        XCTAssertEqual(decision.direction, .resetAfterBreak, "90 days should trigger extended break reset")
    }
    
    func testMajorDetrainingMagnitude_84PlusDays() {
        // 84+ days should yield ~25% reduction
        let signals = makeSignals(daysSinceLastExposure: 100)
        let direction = DirectionPolicy.decide(signals: signals)
        let basePolicy = LoadRoundingPolicy.standardPounds
        
        let magnitude = MagnitudePolicy.compute(
            direction: direction,
            signals: signals,
            baseRoundingPolicy: basePolicy
        )
        
        // Should be around 25% reduction (loadMultiplier ~0.75)
        XCTAssertEqual(magnitude.loadMultiplier, 0.75, accuracy: 0.01, "84+ day gap should yield ~25% reduction")
    }
    
    // MARK: - Cold Start (nil exposure)
    
    func testColdStartNilExposure() {
        // Nil daysSinceLastExposure should NOT trigger break reset
        let signals = makeSignals(daysSinceLastExposure: nil)
        let decision = DirectionPolicy.decide(signals: signals)
        
        // Cold start with no history should hold (insufficient data), not reset
        XCTAssertNotEqual(decision.direction, .resetAfterBreak, "nil exposure should NOT trigger break reset")
    }
    
    // MARK: - Experience Level Independence
    
    func testBreakResetAppliesToAllExperienceLevels() {
        let experienceLevels: [ExperienceLevel] = [.beginner, .intermediate, .advanced, .elite]
        
        for experience in experienceLevels {
            let signals = makeSignals(daysSinceLastExposure: 21, experienceLevel: experience)
            let decision = DirectionPolicy.decide(signals: signals)
            
            XCTAssertEqual(
                decision.direction,
                .resetAfterBreak,
                "\(experience) should trigger break reset at 21 days"
            )
        }
    }
    
    // MARK: - LiftState Date Computation
    
    func testLiftStateDaysSinceLastSession() {
        var state = LiftState(exerciseId: "squat")
        
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        
        // Set last session date to 14 days ago
        let now = Date()
        let twoWeeksAgo = calendar.date(byAdding: .day, value: -14, to: now)!
        state.lastSessionDate = twoWeeksAgo
        
        let daysSince = state.daysSinceLastSession(from: now, calendar: calendar)
        
        XCTAssertEqual(daysSince, 14, "Should compute 14 days since last session")
    }
    
    func testLiftStateDaysSinceNilWhenNoHistory() {
        let state = LiftState(exerciseId: "squat")
        
        let daysSince = state.daysSinceLastSession()
        
        XCTAssertNil(daysSince, "Should be nil when no lastSessionDate")
    }
    
    // MARK: - Config Threshold Customization
    
    func testCustomExtendedBreakThreshold() {
        // Custom config with 21 day threshold instead of 14
        let config = DirectionPolicyConfig(extendedBreakDays: 21, trainingGapDays: 14)
        
        // 14 days should NOT trigger extended break with custom config
        let signals14 = makeSignals(daysSinceLastExposure: 14)
        let decision14 = DirectionPolicy.decide(signals: signals14, config: config)
        
        // With custom config, 14 days is now a training gap (14-20), not extended break (21+)
        XCTAssertEqual(decision14.direction, .resetAfterBreak) // Still resets, but as training gap
        
        // 21 days should trigger extended break
        let signals21 = makeSignals(daysSinceLastExposure: 21)
        let decision21 = DirectionPolicy.decide(signals: signals21, config: config)
        
        XCTAssertEqual(decision21.direction, .resetAfterBreak)
    }
}
