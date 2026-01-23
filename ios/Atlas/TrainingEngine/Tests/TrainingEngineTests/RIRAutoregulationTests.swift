import XCTest
@testable import TrainingEngine

final class RIRAutoregulationTests: XCTestCase {
    
    let config = RIRAutoregulationConfig.default
    let roundingPolicy = LoadRoundingPolicy.standardPounds
    
    // MARK: - In-Session Adjustment Tests
    
    func testOnTarget_NoAdjustment() {
        // Given: RIR matches target (2)
        let currentResult = SetResult(
            reps: 8,
            load: .pounds(100),
            rirObserved: 2  // Target is 2
        )
        
        let plannedNext = SetPlan(
            setIndex: 1,
            targetLoad: .pounds(100),
            targetReps: 8,
            targetRIR: 2,
            restSeconds: 120
        )
        
        // When
        let adjusted = RIRAutoregulationPolicy.adjustInSession(
            config: config,
            currentResult: currentResult,
            plannedNext: plannedNext,
            roundingPolicy: roundingPolicy
        )
        
        // Then: No change
        XCTAssertEqual(adjusted.targetLoad.value, 100, accuracy: 0.01)
    }
    
    func testHarderThanExpected_DecreasesLoad() {
        // Given: RIR 0 when target was 2 (harder)
        let currentResult = SetResult(
            reps: 8,
            load: .pounds(100),
            rirObserved: 0  // Much harder than target 2
        )
        
        let plannedNext = SetPlan(
            setIndex: 1,
            targetLoad: .pounds(100),
            targetReps: 8,
            targetRIR: 2,
            restSeconds: 120
        )
        
        // When
        let adjusted = RIRAutoregulationPolicy.adjustInSession(
            config: config,
            currentResult: currentResult,
            plannedNext: plannedNext,
            roundingPolicy: roundingPolicy
        )
        
        // Then: Load should decrease
        // RIR diff = 0 - 2 = -2
        // Adjustment = -2 * 0.025 = -0.05 (5% decrease)
        // 100 * 0.95 = 95
        XCTAssertLessThan(adjusted.targetLoad.value, 100)
    }
    
    func testEasierThanExpected_IncreasesLoad() {
        // Given: RIR 4 when target was 2 (easier)
        let currentResult = SetResult(
            reps: 8,
            load: .pounds(100),
            rirObserved: 4  // Easier than target 2
        )
        
        let plannedNext = SetPlan(
            setIndex: 1,
            targetLoad: .pounds(100),
            targetReps: 8,
            targetRIR: 2,
            restSeconds: 120
        )
        
        // When
        let adjusted = RIRAutoregulationPolicy.adjustInSession(
            config: config,
            currentResult: currentResult,
            plannedNext: plannedNext,
            roundingPolicy: roundingPolicy
        )
        
        // Then: Load should increase
        // RIR diff = 4 - 2 = +2
        // Adjustment = +2 * 0.025 = +0.05 (5% increase)
        // 100 * 1.05 = 105
        XCTAssertGreaterThan(adjusted.targetLoad.value, 100)
    }
    
    func testNoUpwardAdjustment_WhenConfiguredOff() {
        // Given: Conservative config that doesn't allow upward adjustment
        let conservativeConfig = RIRAutoregulationConfig.conservative
        
        let currentResult = SetResult(
            reps: 8,
            load: .pounds(100),
            rirObserved: 5  // Much easier than target
        )
        
        let plannedNext = SetPlan(
            setIndex: 1,
            targetLoad: .pounds(100),
            targetReps: 8,
            targetRIR: 2,
            restSeconds: 120
        )
        
        // When
        let adjusted = RIRAutoregulationPolicy.adjustInSession(
            config: conservativeConfig,
            currentResult: currentResult,
            plannedNext: plannedNext,
            roundingPolicy: roundingPolicy
        )
        
        // Then: No increase (conservative config)
        XCTAssertEqual(adjusted.targetLoad.value, 100, accuracy: 0.01)
    }
    
    func testMissingRIRData_NoAdjustment() {
        // Given: No RIR observed
        let currentResult = SetResult(
            reps: 8,
            load: .pounds(100),
            rirObserved: nil
        )
        
        let plannedNext = SetPlan(
            setIndex: 1,
            targetLoad: .pounds(100),
            targetReps: 8,
            targetRIR: 2,
            restSeconds: 120
        )
        
        // When
        let adjusted = RIRAutoregulationPolicy.adjustInSession(
            config: config,
            currentResult: currentResult,
            plannedNext: plannedNext,
            roundingPolicy: roundingPolicy
        )
        
        // Then: No change
        XCTAssertEqual(adjusted.targetLoad.value, plannedNext.targetLoad.value, accuracy: 0.01)
    }
    
    func testAdjustmentCapped_AtMaxPerSet() {
        // Given: Very large RIR deviation
        let currentResult = SetResult(
            reps: 8,
            load: .pounds(100),
            rirObserved: 0  // Target is 2, diff = -2
        )
        
        // Use a config with small max adjustment
        let cappedConfig = RIRAutoregulationConfig(
            targetRIR: 2,
            adjustmentPerRIR: 0.10,  // 10% per RIR
            maxAdjustmentPerSet: 0.05,  // But capped at 5%
            minimumLoad: .pounds(20),
            allowUpwardAdjustment: true
        )
        
        let plannedNext = SetPlan(
            setIndex: 1,
            targetLoad: .pounds(100),
            targetReps: 8,
            targetRIR: 2,
            restSeconds: 120
        )
        
        // When
        let adjusted = RIRAutoregulationPolicy.adjustInSession(
            config: cappedConfig,
            currentResult: currentResult,
            plannedNext: plannedNext,
            roundingPolicy: roundingPolicy
        )
        
        // Then: Adjustment capped at 5% (not 20%)
        // 100 * 0.95 = 95
        XCTAssertGreaterThanOrEqual(adjusted.targetLoad.value, 95)
    }
    
    func testMinimumLoadEnforced() {
        // Given: Adjustment would go below minimum
        let currentResult = SetResult(
            reps: 8,
            load: .pounds(25),
            rirObserved: 0
        )
        
        let plannedNext = SetPlan(
            setIndex: 1,
            targetLoad: .pounds(25),
            targetReps: 8,
            targetRIR: 2,
            restSeconds: 120
        )
        
        // When
        let adjusted = RIRAutoregulationPolicy.adjustInSession(
            config: config,
            currentResult: currentResult,
            plannedNext: plannedNext,
            roundingPolicy: roundingPolicy
        )
        
        // Then: Should not go below minimum (20 lbs)
        XCTAssertGreaterThanOrEqual(adjusted.targetLoad.value, config.minimumLoad.value)
    }
    
    // MARK: - RIR Deviation Evaluation
    
    func testEvaluateRIRDeviation_OnTarget() {
        let evaluation = RIRAutoregulationPolicy.evaluateRIRDeviation(
            config: config,
            observedRIR: 2,
            targetRIR: 2
        )
        
        if case .onTarget = evaluation {
            // Success
        } else {
            XCTFail("Expected onTarget")
        }
    }
    
    func testEvaluateRIRDeviation_Easier() {
        let evaluation = RIRAutoregulationPolicy.evaluateRIRDeviation(
            config: config,
            observedRIR: 4,
            targetRIR: 2
        )
        
        if case .easierThanExpected(let rirOver, _) = evaluation {
            XCTAssertEqual(rirOver, 2)
        } else {
            XCTFail("Expected easierThanExpected")
        }
    }
    
    func testEvaluateRIRDeviation_Harder() {
        let evaluation = RIRAutoregulationPolicy.evaluateRIRDeviation(
            config: config,
            observedRIR: 0,
            targetRIR: 2
        )
        
        if case .harderThanExpected(let rirUnder, _) = evaluation {
            XCTAssertEqual(rirUnder, 2)
        } else {
            XCTFail("Expected harderThanExpected")
        }
    }
    
    // MARK: - Determinism Tests
    
    func testAdjustment_IsDeterministic() {
        let currentResult = SetResult(
            reps: 8,
            load: .pounds(100),
            rirObserved: 0
        )
        
        let plannedNext = SetPlan(
            setIndex: 1,
            targetLoad: .pounds(100),
            targetReps: 8,
            targetRIR: 2,
            restSeconds: 120
        )
        
        // Run multiple times
        let results = (0..<10).map { _ in
            RIRAutoregulationPolicy.adjustInSession(
                config: config,
                currentResult: currentResult,
                plannedNext: plannedNext,
                roundingPolicy: roundingPolicy
            )
        }
        
        // All results should be identical
        let firstResult = results[0].targetLoad.value
        for result in results {
            XCTAssertEqual(result.targetLoad.value, firstResult, accuracy: 0.001)
        }
    }
}
