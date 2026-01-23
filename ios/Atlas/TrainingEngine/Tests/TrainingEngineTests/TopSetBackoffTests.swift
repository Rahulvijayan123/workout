import XCTest
@testable import TrainingEngine

final class TopSetBackoffTests: XCTestCase {
    
    let config = TopSetBackoffConfig.default
    let roundingPolicy = LoadRoundingPolicy.standardPounds
    
    // MARK: - Backoff Set Load Calculation
    
    func testTopSetIsFirstSet_ReceivesFullLoad() {
        let topSetLoad = Load.pounds(225)
        
        let setLoad = TopSetBackoffPolicy.computeSetLoad(
            config: config,
            setIndex: 0,
            totalSets: 4,
            topSetLoad: topSetLoad,
            roundingPolicy: roundingPolicy
        )
        
        // First set (index 0) should get full top set load
        XCTAssertEqual(setLoad.value, 225, accuracy: 0.01)
    }
    
    func testBackoffSets_ReceiveReducedLoad() {
        let topSetLoad = Load.pounds(225)
        
        // Second set (index 1) should be a backoff set
        let backoffLoad = TopSetBackoffPolicy.computeSetLoad(
            config: config,
            setIndex: 1,
            totalSets: 4,
            topSetLoad: topSetLoad,
            roundingPolicy: roundingPolicy
        )
        
        // Default backoff is 85% of 225 = 191.25, rounded to 190 (2.5 lb increments)
        let expectedBackoff = 225 * 0.85  // 191.25
        let rounded = (expectedBackoff / 2.5).rounded() * 2.5  // 190
        XCTAssertEqual(backoffLoad.value, rounded, accuracy: 0.01)
    }
    
    func testAllBackoffSets_ReceiveSameLoad() {
        let topSetLoad = Load.pounds(315)
        
        let backoff1 = TopSetBackoffPolicy.computeSetLoad(
            config: config,
            setIndex: 1,
            totalSets: 4,
            topSetLoad: topSetLoad,
            roundingPolicy: roundingPolicy
        )
        
        let backoff2 = TopSetBackoffPolicy.computeSetLoad(
            config: config,
            setIndex: 2,
            totalSets: 4,
            topSetLoad: topSetLoad,
            roundingPolicy: roundingPolicy
        )
        
        let backoff3 = TopSetBackoffPolicy.computeSetLoad(
            config: config,
            setIndex: 3,
            totalSets: 4,
            topSetLoad: topSetLoad,
            roundingPolicy: roundingPolicy
        )
        
        // All backoff sets should have same load
        XCTAssertEqual(backoff1.value, backoff2.value, accuracy: 0.01)
        XCTAssertEqual(backoff2.value, backoff3.value, accuracy: 0.01)
    }
    
    // MARK: - Daily Max Calculation
    
    func testDailyMaxCalculation_FromTopSet() {
        let topSetResult = SetResult(
            reps: 5,
            load: .pounds(225)
        )
        
        let dailyMax = TopSetBackoffPolicy.computeDailyMax(
            topSetResult: topSetResult,
            targetReps: 5
        )
        
        // Brzycki: 225 * (36 / (37 - 5)) = 225 * (36 / 32) = 253.125
        let expected = E1RMCalculator.brzycki(weight: 225, reps: 5)
        XCTAssertEqual(dailyMax, expected, accuracy: 0.01)
    }
    
    // MARK: - Top Set Evaluation
    
    func testTopSetEvaluation_ExceededTarget() {
        let result = SetResult(reps: 5, load: .pounds(225))
        
        let evaluation = TopSetBackoffPolicy.evaluateTopSet(
            config: config,
            result: result,
            targetReps: 3
        )
        
        if case .exceededTarget(let repsOver, let suggestedIncrease) = evaluation {
            XCTAssertEqual(repsOver, 2)
            XCTAssertEqual(suggestedIncrease.value, config.loadIncrement.value)
        } else {
            XCTFail("Expected exceededTarget")
        }
    }
    
    func testTopSetEvaluation_MetTarget() {
        let result = SetResult(reps: 3, load: .pounds(225))
        
        let evaluation = TopSetBackoffPolicy.evaluateTopSet(
            config: config,
            result: result,
            targetReps: 3
        )
        
        if case .metTarget = evaluation {
            // Success
        } else {
            XCTFail("Expected metTarget")
        }
    }
    
    func testTopSetEvaluation_MissedTarget() {
        let minTopSetRepsConfig = TopSetBackoffConfig(
            minimumTopSetReps: 3
        )
        
        let result = SetResult(reps: 1, load: .pounds(225))
        
        let evaluation = TopSetBackoffPolicy.evaluateTopSet(
            config: minTopSetRepsConfig,
            result: result,
            targetReps: 5
        )
        
        if case .missedTarget(let repsMissed) = evaluation {
            // requiredReps = max(targetReps=5, minimumTopSetReps=3) = 5 → 5 - 1 = 4
            XCTAssertEqual(repsMissed, 4)
        } else {
            XCTFail("Expected missedTarget")
        }
    }
    
    // MARK: - Backoff Set Adjustment
    
    func testAdjustBackoffSets_BasedOnActualTopSet() {
        let topSetResult = SetResult(reps: 5, load: .pounds(225))
        
        let plannedBackoffs = [
            SetPlan(setIndex: 1, targetLoad: .pounds(190), targetReps: 8, targetRIR: 2, restSeconds: 180),
            SetPlan(setIndex: 2, targetLoad: .pounds(190), targetReps: 8, targetRIR: 2, restSeconds: 180),
            SetPlan(setIndex: 3, targetLoad: .pounds(190), targetReps: 8, targetRIR: 2, restSeconds: 180)
        ]
        
        let adjusted = TopSetBackoffPolicy.adjustBackoffSets(
            config: config,
            topSetResult: topSetResult,
            plannedBackoffSets: plannedBackoffs,
            roundingPolicy: roundingPolicy
        )
        
        // Daily max from 225x5: ~253 lbs
        // Backoff at 85%: ~215, rounded
        XCTAssertEqual(adjusted.count, 3)
        
        // All adjusted sets should have same load
        let firstLoad = adjusted[0].targetLoad.value
        for set in adjusted {
            XCTAssertEqual(set.targetLoad.value, firstLoad, accuracy: 0.01)
        }
    }
    
    // MARK: - Different Configurations
    
    func testStrengthConfig_LowerBackoffPercentage() {
        let strengthConfig = TopSetBackoffConfig.strength
        let topSetLoad = Load.pounds(315)
        
        let backoffLoad = TopSetBackoffPolicy.computeSetLoad(
            config: strengthConfig,
            setIndex: 1,
            totalSets: 5,
            topSetLoad: topSetLoad,
            roundingPolicy: roundingPolicy
        )
        
        // Strength config uses 80% backoff
        let expectedBackoff = 315 * 0.80  // 252
        let rounded = (expectedBackoff / 2.5).rounded() * 2.5
        XCTAssertEqual(backoffLoad.value, rounded, accuracy: 0.01)
    }

    // MARK: - Progressive Overload Criteria

    func testComputeTopSetLoad_DoesNotIncreaseIfTopSetMissesPrescriptionTarget() {
        let prescription = SetPrescription(setCount: 4, targetRepsRange: 5...5, targetRIR: 1, increment: .pounds(5))
        let config = TopSetBackoffConfig.strength // minimumTopSetReps is 1, but prescription target is 5

        let topSet = SetResult(reps: 3, load: .pounds(315))
        let exerciseResult = ExerciseSessionResult(
            exerciseId: "squat",
            prescription: prescription,
            sets: [topSet]
        )

        let history = WorkoutHistory(
            sessions: [
                CompletedSession(date: Date(), name: "Legs", exerciseResults: [exerciseResult], startedAt: Date())
            ],
            liftStates: ["squat": LiftState(exerciseId: "squat", lastWorkingWeight: .pounds(315))]
        )

        let nextTopSetLoad = TopSetBackoffPolicy.computeTopSetLoad(
            config: config,
            prescription: prescription,
            liftState: history.liftStates["squat"]!,
            history: history,
            exerciseId: "squat"
        )

        XCTAssertEqual(nextTopSetLoad.value, 315, accuracy: 0.01)
    }

    func testComputeTopSetLoad_IncreasesIfTopSetMeetsPrescriptionTarget() {
        let prescription = SetPrescription(setCount: 4, targetRepsRange: 5...5, targetRIR: 1, increment: .pounds(5))
        let config = TopSetBackoffConfig.strength

        let topSet = SetResult(reps: 5, load: .pounds(315))
        let exerciseResult = ExerciseSessionResult(
            exerciseId: "squat",
            prescription: prescription,
            sets: [topSet]
        )

        let history = WorkoutHistory(
            sessions: [
                CompletedSession(date: Date(), name: "Legs", exerciseResults: [exerciseResult], startedAt: Date())
            ],
            liftStates: ["squat": LiftState(exerciseId: "squat", lastWorkingWeight: .pounds(315))]
        )

        let nextTopSetLoad = TopSetBackoffPolicy.computeTopSetLoad(
            config: config,
            prescription: prescription,
            liftState: history.liftStates["squat"]!,
            history: history,
            exerciseId: "squat"
        )

        XCTAssertEqual(nextTopSetLoad.value, 320, accuracy: 0.01)
    }
}
