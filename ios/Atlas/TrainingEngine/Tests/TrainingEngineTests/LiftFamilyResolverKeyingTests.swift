// LiftFamilyResolverKeyingTests.swift
// Unit tests for LiftFamilyResolver state keying behavior.
// Validates that:
// - Direct family members (squat, bench, deadlift, ohp) write to family baseline
// - Variations (pause_bench, front_squat, sumo_deadlift) write to their own ID
// - Substitutions (leg_press, hack_squat) write to their own ID

import XCTest
@testable import TrainingEngine

final class LiftFamilyResolverKeyingTests: XCTestCase {
    
    // MARK: - Bench Press Family
    
    func testBenchDirectMemberWritesToFamilyBaseline() {
        // "bench" is a direct member - should write to "bench_press"
        let resolution = LiftFamilyResolver.resolveStateKeys(fromId: "bench")
        
        XCTAssertEqual(resolution.referenceStateKey, "bench_press", "Reference key should be family baseline")
        XCTAssertEqual(resolution.updateStateKey, "bench_press", "Direct member should write to family baseline")
        XCTAssertTrue(resolution.isDirectMember, "bench should be a direct member")
        XCTAssertEqual(resolution.coefficient, 1.0, accuracy: 0.01, "Base bench should have coefficient 1.0")
    }
    
    func testBenchPressDirectMemberWritesToFamilyBaseline() {
        let resolution = LiftFamilyResolver.resolveStateKeys(fromId: "bench_press")
        
        XCTAssertEqual(resolution.referenceStateKey, "bench_press")
        XCTAssertEqual(resolution.updateStateKey, "bench_press")
        XCTAssertTrue(resolution.isDirectMember)
    }
    
    func testPauseBenchVariationWritesToOwnId() {
        let resolution = LiftFamilyResolver.resolveStateKeys(fromId: "pause_bench")
        
        XCTAssertEqual(resolution.referenceStateKey, "bench_press", "Should read from family baseline")
        XCTAssertEqual(resolution.updateStateKey, "pause_bench", "Variation should write to its own ID")
        XCTAssertFalse(resolution.isDirectMember, "pause_bench is NOT a direct member")
    }
    
    func testCloseGripBenchVariationWritesToOwnId() {
        let resolution = LiftFamilyResolver.resolveStateKeys(fromId: "close_grip_bench")
        
        XCTAssertEqual(resolution.referenceStateKey, "bench_press")
        XCTAssertEqual(resolution.updateStateKey, "close_grip_bench")
        XCTAssertFalse(resolution.isDirectMember)
    }
    
    func testInclineBenchVariationWritesToOwnId() {
        let resolution = LiftFamilyResolver.resolveStateKeys(fromId: "incline_bench")
        
        XCTAssertEqual(resolution.referenceStateKey, "bench_press")
        XCTAssertEqual(resolution.updateStateKey, "incline_bench")
        XCTAssertFalse(resolution.isDirectMember)
    }
    
    // MARK: - Squat Family
    
    func testSquatDirectMemberWritesToFamilyBaseline() {
        let resolution = LiftFamilyResolver.resolveStateKeys(fromId: "squat")
        
        XCTAssertEqual(resolution.referenceStateKey, "squat")
        XCTAssertEqual(resolution.updateStateKey, "squat", "squat should write to squat (family baseline)")
        XCTAssertTrue(resolution.isDirectMember)
    }
    
    func testBackSquatDirectMemberWritesToFamilyBaseline() {
        let resolution = LiftFamilyResolver.resolveStateKeys(fromId: "back_squat")
        
        XCTAssertEqual(resolution.referenceStateKey, "squat")
        XCTAssertEqual(resolution.updateStateKey, "squat")
        XCTAssertTrue(resolution.isDirectMember)
    }
    
    func testFrontSquatVariationWritesToOwnId() {
        let resolution = LiftFamilyResolver.resolveStateKeys(fromId: "front_squat")
        
        XCTAssertEqual(resolution.referenceStateKey, "squat", "Should read from squat family baseline")
        XCTAssertEqual(resolution.updateStateKey, "front_squat", "Variation should write to its own ID")
        XCTAssertFalse(resolution.isDirectMember)
        XCTAssertEqual(resolution.coefficient, 0.80, accuracy: 0.01, "Front squat typically 80% of back squat")
    }
    
    func testLegPressSubstitutionWritesToOwnId() {
        let resolution = LiftFamilyResolver.resolveStateKeys(fromId: "leg_press")
        
        XCTAssertEqual(resolution.referenceStateKey, "squat", "Should read from squat family")
        XCTAssertEqual(resolution.updateStateKey, "leg_press", "Substitution should write to its own ID")
        XCTAssertFalse(resolution.isDirectMember, "leg_press is a substitution, not direct member")
        XCTAssertEqual(resolution.coefficient, 1.5, accuracy: 0.01, "Leg press typically handles more weight")
    }
    
    func testHackSquatSubstitutionWritesToOwnId() {
        let resolution = LiftFamilyResolver.resolveStateKeys(fromId: "hack_squat")
        
        XCTAssertEqual(resolution.referenceStateKey, "squat")
        XCTAssertEqual(resolution.updateStateKey, "hack_squat")
        XCTAssertFalse(resolution.isDirectMember)
    }
    
    // MARK: - Deadlift Family
    
    func testDeadliftDirectMemberWritesToFamilyBaseline() {
        let resolution = LiftFamilyResolver.resolveStateKeys(fromId: "deadlift")
        
        XCTAssertEqual(resolution.referenceStateKey, "deadlift")
        XCTAssertEqual(resolution.updateStateKey, "deadlift")
        XCTAssertTrue(resolution.isDirectMember)
    }
    
    func testSumoDeadliftVariationWritesToOwnId() {
        // Sumo is a valid primary stance but we track it separately
        let resolution = LiftFamilyResolver.resolveStateKeys(fromId: "sumo_deadlift")
        
        XCTAssertEqual(resolution.referenceStateKey, "deadlift")
        XCTAssertEqual(resolution.updateStateKey, "sumo_deadlift")
        XCTAssertFalse(resolution.isDirectMember, "sumo is tracked separately from conventional")
    }
    
    func testTrapBarDeadliftVariationWritesToOwnId() {
        let resolution = LiftFamilyResolver.resolveStateKeys(fromId: "trap_bar_deadlift")
        
        XCTAssertEqual(resolution.referenceStateKey, "deadlift")
        XCTAssertEqual(resolution.updateStateKey, "trap_bar_deadlift")
        XCTAssertFalse(resolution.isDirectMember)
    }
    
    func testRdlVariationWritesToOwnId() {
        // RDL is a hip hinge movement but tracked separately
        let resolution = LiftFamilyResolver.resolveStateKeys(fromId: "rdl")
        
        // RDL may or may not be in the deadlift family - check it's at least consistent
        XCTAssertEqual(resolution.updateStateKey, "rdl", "RDL should write to its own ID")
    }
    
    // MARK: - Overhead Press Family
    
    func testOhpDirectMemberWritesToFamilyBaseline() {
        let resolution = LiftFamilyResolver.resolveStateKeys(fromId: "ohp")
        
        XCTAssertEqual(resolution.referenceStateKey, "overhead_press")
        XCTAssertEqual(resolution.updateStateKey, "overhead_press")
        XCTAssertTrue(resolution.isDirectMember)
    }
    
    func testSeatedOhpVariationWritesToOwnId() {
        let resolution = LiftFamilyResolver.resolveStateKeys(fromId: "seated_ohp")
        
        XCTAssertEqual(resolution.referenceStateKey, "overhead_press")
        XCTAssertEqual(resolution.updateStateKey, "seated_ohp")
        XCTAssertFalse(resolution.isDirectMember)
    }
    
    // MARK: - Row Family
    
    func testRowDirectMemberWritesToFamilyBaseline() {
        let resolution = LiftFamilyResolver.resolveStateKeys(fromId: "row")
        
        XCTAssertEqual(resolution.referenceStateKey, "row")
        XCTAssertEqual(resolution.updateStateKey, "row")
        XCTAssertTrue(resolution.isDirectMember)
    }
    
    func testCableRowVariationWritesToOwnId() {
        let resolution = LiftFamilyResolver.resolveStateKeys(fromId: "cable_row")
        
        XCTAssertEqual(resolution.referenceStateKey, "row")
        XCTAssertEqual(resolution.updateStateKey, "cable_row")
        XCTAssertFalse(resolution.isDirectMember)
    }
    
    // MARK: - Exercise Object Resolution (resolve(_ exercise:))
    
    func testExerciseResolutionBenchDirect() {
        let exercise = Exercise(
            id: "bench",
            name: "Bench Press",
            equipment: .barbell,
            primaryMuscles: [.chest],
            movementPattern: .horizontalPush
        )
        
        let resolution = LiftFamilyResolver.resolve(exercise)
        
        XCTAssertEqual(resolution.family.id, "bench_press")
        XCTAssertEqual(resolution.referenceStateKey, "bench_press")
        XCTAssertEqual(resolution.updateStateKey, "bench_press", "Direct member writes to family baseline")
        XCTAssertTrue(resolution.isDirectMember)
    }
    
    func testExerciseResolutionPauseBenchVariation() {
        let exercise = Exercise(
            id: "pause_bench",
            name: "Pause Bench Press",
            equipment: .barbell,
            primaryMuscles: [.chest],
            movementPattern: .horizontalPush
        )
        
        let resolution = LiftFamilyResolver.resolve(exercise)
        
        XCTAssertEqual(resolution.family.id, "bench_press")
        XCTAssertEqual(resolution.referenceStateKey, "bench_press")
        XCTAssertEqual(resolution.updateStateKey, "pause_bench", "Variation writes to own ID")
        XCTAssertFalse(resolution.isDirectMember)
    }
    
    func testExerciseResolutionFrontSquatVariation() {
        let exercise = Exercise(
            id: "front_squat",
            name: "Front Squat",
            equipment: .barbell,
            primaryMuscles: [.quadriceps],
            movementPattern: .squat
        )
        
        let resolution = LiftFamilyResolver.resolve(exercise)
        
        XCTAssertEqual(resolution.family.id, "squat")
        XCTAssertEqual(resolution.referenceStateKey, "squat")
        XCTAssertEqual(resolution.updateStateKey, "front_squat")
        XCTAssertFalse(resolution.isDirectMember)
    }
    
    func testExerciseResolutionLegPressSubstitution() {
        let exercise = Exercise(
            id: "leg_press",
            name: "Leg Press",
            equipment: .machine,
            primaryMuscles: [.quadriceps, .glutes],
            movementPattern: .squat
        )
        
        let resolution = LiftFamilyResolver.resolve(exercise)
        
        XCTAssertEqual(resolution.family.id, "squat")
        XCTAssertEqual(resolution.referenceStateKey, "squat")
        XCTAssertEqual(resolution.updateStateKey, "leg_press")
        XCTAssertFalse(resolution.isDirectMember)
    }
    
    // MARK: - State Key Consistency
    
    func testStateKeyConsistencyBetweenMethods() {
        // Ensure resolveStateKeys(fromId:) and resolve(_ exercise:) produce consistent results
        let exerciseIds = ["bench", "squat", "deadlift", "ohp", "front_squat", "pause_bench", "sumo_deadlift"]
        
        for id in exerciseIds {
            let idResolution = LiftFamilyResolver.resolveStateKeys(fromId: id)
            
            let exercise = Exercise(
                id: id,
                name: id.replacingOccurrences(of: "_", with: " ").capitalized,
                equipment: .barbell,
                primaryMuscles: [.quadriceps],
                movementPattern: id.contains("squat") ? .squat : 
                                 id.contains("bench") ? .horizontalPush :
                                 id.contains("deadlift") ? .hipHinge : .verticalPush
            )
            let exerciseResolution = LiftFamilyResolver.resolve(exercise)
            
            XCTAssertEqual(
                idResolution.isDirectMember,
                exerciseResolution.isDirectMember,
                "isDirectMember should match for '\(id)'"
            )
            XCTAssertEqual(
                idResolution.referenceStateKey,
                exerciseResolution.referenceStateKey,
                "referenceStateKey should match for '\(id)'"
            )
            XCTAssertEqual(
                idResolution.updateStateKey,
                exerciseResolution.updateStateKey,
                "updateStateKey should match for '\(id)'"
            )
        }
    }
    
    // MARK: - V7 Dataset Specific IDs
    
    func testV7DatasetLiftsResolveCorrectly() {
        // These are the exact IDs used in the V7 dataset
        let v7Lifts = [
            ("squat", true, "squat"),
            ("bench", true, "bench_press"),
            ("deadlift", true, "deadlift"),
            ("ohp", true, "overhead_press"),
            ("front_squat", false, "front_squat"),
            ("sumo_deadlift", false, "sumo_deadlift"),
            ("pause_bench", false, "pause_bench"),
            ("leg_press", false, "leg_press"),
            ("hack_squat", false, "hack_squat"),
            ("trap_bar_deadlift", false, "trap_bar_deadlift")
        ]
        
        for (liftId, expectedDirect, expectedUpdateKey) in v7Lifts {
            let resolution = LiftFamilyResolver.resolveStateKeys(fromId: liftId)
            
            XCTAssertEqual(
                resolution.isDirectMember,
                expectedDirect,
                "V7 lift '\(liftId)' should have isDirectMember=\(expectedDirect)"
            )
            XCTAssertEqual(
                resolution.updateStateKey,
                expectedUpdateKey,
                "V7 lift '\(liftId)' should have updateStateKey='\(expectedUpdateKey)'"
            )
        }
    }
}
