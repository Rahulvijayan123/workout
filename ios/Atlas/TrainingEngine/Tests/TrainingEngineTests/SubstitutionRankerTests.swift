import XCTest
@testable import TrainingEngine

final class SubstitutionRankerTests: XCTestCase {
    
    // MARK: - Test Exercises
    
    let benchPress = Exercise(
        id: "bench_press",
        name: "Barbell Bench Press",
        equipment: .barbell,
        primaryMuscles: [.chest],
        secondaryMuscles: [.triceps, .frontDelts],
        movementPattern: .horizontalPush
    )
    
    let dumbbellBenchPress = Exercise(
        id: "db_bench_press",
        name: "Dumbbell Bench Press",
        equipment: .dumbbell,
        primaryMuscles: [.chest],
        secondaryMuscles: [.triceps, .frontDelts],
        movementPattern: .horizontalPush
    )
    
    let inclineBenchPress = Exercise(
        id: "incline_bench",
        name: "Incline Barbell Bench Press",
        equipment: .barbell,
        primaryMuscles: [.chest, .frontDelts],
        secondaryMuscles: [.triceps],
        movementPattern: .horizontalPush
    )
    
    let cableFly = Exercise(
        id: "cable_fly",
        name: "Cable Fly",
        equipment: .cable,
        primaryMuscles: [.chest],
        secondaryMuscles: [],
        movementPattern: .horizontalPush
    )
    
    let tricepPushdown = Exercise(
        id: "tricep_pushdown",
        name: "Tricep Pushdown",
        equipment: .cable,
        primaryMuscles: [.triceps],
        secondaryMuscles: [],
        movementPattern: .elbowExtension
    )
    
    let pullUp = Exercise.pullUp
    
    let availableEquipment = EquipmentAvailability.commercialGym
    
    // MARK: - Basic Ranking Tests
    
    func testRanking_ReturnsSortedByScore() {
        let candidates = [dumbbellBenchPress, inclineBenchPress, cableFly, tricepPushdown, pullUp]
        
        let substitutions = SubstitutionRanker.rank(
            for: benchPress,
            candidates: candidates,
            availableEquipment: availableEquipment,
            maxResults: 5
        )
        
        // Verify sorted by score
        for i in 0..<(substitutions.count - 1) {
            XCTAssertGreaterThanOrEqual(
                substitutions[i].score,
                substitutions[i + 1].score,
                "Substitutions should be sorted by score descending"
            )
        }
    }
    
    func testRanking_ExcludesOriginalExercise() {
        var candidates = [dumbbellBenchPress, inclineBenchPress]
        candidates.append(benchPress)  // Include the original
        
        let substitutions = SubstitutionRanker.rank(
            for: benchPress,
            candidates: candidates,
            availableEquipment: availableEquipment,
            maxResults: 5
        )
        
        // Original should not be in results
        XCTAssertFalse(substitutions.contains { $0.exercise.id == benchPress.id })
    }
    
    func testRanking_ExcludesUnavailableEquipment() {
        let homeGymEquipment = EquipmentAvailability.homeGym
        let candidates = [dumbbellBenchPress, cableFly]  // Cable not in home gym
        
        let substitutions = SubstitutionRanker.rank(
            for: benchPress,
            candidates: candidates,
            availableEquipment: homeGymEquipment,
            maxResults: 5
        )
        
        // Cable fly should be excluded
        XCTAssertFalse(substitutions.contains { $0.exercise.id == cableFly.id })
        
        // Dumbbell should be included
        XCTAssertTrue(substitutions.contains { $0.exercise.id == dumbbellBenchPress.id })
    }
    
    func testRanking_RespectsMaxResults() {
        let candidates = [dumbbellBenchPress, inclineBenchPress, cableFly, tricepPushdown, pullUp]
        
        let substitutions = SubstitutionRanker.rank(
            for: benchPress,
            candidates: candidates,
            availableEquipment: availableEquipment,
            maxResults: 2
        )
        
        XCTAssertEqual(substitutions.count, 2)
    }
    
    // MARK: - Scoring Tests
    
    func testScoring_HigherForSamePrimaryMuscles() {
        let candidates = [dumbbellBenchPress, tricepPushdown]
        
        let substitutions = SubstitutionRanker.rank(
            for: benchPress,
            candidates: candidates,
            availableEquipment: availableEquipment,
            maxResults: 5
        )
        
        // DB bench (same primary: chest) should score higher than tricep pushdown
        let dbBenchSub = substitutions.first { $0.exercise.id == dumbbellBenchPress.id }
        let tricepSub = substitutions.first { $0.exercise.id == tricepPushdown.id }
        
        XCTAssertNotNil(dbBenchSub)
        XCTAssertNotNil(tricepSub)
        XCTAssertGreaterThan(dbBenchSub!.score, tricepSub!.score)
    }
    
    func testScoring_HigherForSameMovementPattern() {
        // DB bench and incline both have horizontal push pattern
        let candidates = [dumbbellBenchPress, pullUp]
        
        let substitutions = SubstitutionRanker.rank(
            for: benchPress,
            candidates: candidates,
            availableEquipment: availableEquipment,
            maxResults: 5
        )
        
        let dbBenchSub = substitutions.first { $0.exercise.id == dumbbellBenchPress.id }
        let pullUpSub = substitutions.first { $0.exercise.id == pullUp.id }
        
        XCTAssertNotNil(dbBenchSub)
        XCTAssertNotNil(pullUpSub)
        XCTAssertGreaterThan(dbBenchSub!.score, pullUpSub!.score)
    }
    
    func testScoring_BonusForSameEquipment() {
        // Incline uses barbell (same as bench), cable fly doesn't
        let candidates = [inclineBenchPress, cableFly]
        
        let substitutions = SubstitutionRanker.rank(
            for: benchPress,
            candidates: candidates,
            availableEquipment: availableEquipment,
            maxResults: 5
        )
        
        let inclineSub = substitutions.first { $0.exercise.id == inclineBenchPress.id }
        let cableFlySub = substitutions.first { $0.exercise.id == cableFly.id }
        
        XCTAssertNotNil(inclineSub)
        XCTAssertNotNil(cableFlySub)
        
        // Incline should score higher due to equipment match bonus
        XCTAssertGreaterThan(inclineSub!.score, cableFlySub!.score)
    }
    
    // MARK: - Determinism Tests
    
    func testRanking_IsDeterministic() {
        let candidates = [dumbbellBenchPress, inclineBenchPress, cableFly, tricepPushdown]
        
        let results = (0..<10).map { _ in
            SubstitutionRanker.rank(
                for: benchPress,
                candidates: candidates,
                availableEquipment: availableEquipment,
                maxResults: 5
            )
        }
        
        // All runs should produce identical order
        let firstResult = results[0]
        for result in results {
            XCTAssertEqual(result.count, firstResult.count)
            for i in 0..<result.count {
                XCTAssertEqual(result[i].exercise.id, firstResult[i].exercise.id)
                XCTAssertEqual(result[i].score, firstResult[i].score, accuracy: 0.0001)
            }
        }
    }
    
    func testRanking_StableTieBreaking() {
        // Create exercises with potentially similar scores
        let exercise1 = Exercise(
            id: "ex_a",
            name: "Exercise A",
            equipment: .dumbbell,
            primaryMuscles: [.chest],
            secondaryMuscles: [],
            movementPattern: .horizontalPush
        )
        
        let exercise2 = Exercise(
            id: "ex_b",
            name: "Exercise B",
            equipment: .dumbbell,
            primaryMuscles: [.chest],
            secondaryMuscles: [],
            movementPattern: .horizontalPush
        )
        
        let candidates = [exercise2, exercise1]  // Reverse alphabetical order
        
        let substitutions = SubstitutionRanker.rank(
            for: benchPress,
            candidates: candidates,
            availableEquipment: availableEquipment,
            maxResults: 5
        )
        
        // Should be sorted by name for tie-breaking (A before B)
        if substitutions.count >= 2 &&
           abs(substitutions[0].score - substitutions[1].score) < 0.001 {
            XCTAssertLessThan(
                substitutions[0].exercise.name,
                substitutions[1].exercise.name,
                "Ties should be broken alphabetically by name"
            )
        }
    }
    
    // MARK: - Helper Tests
    
    func testFindBestSubstitute_ReturnsTopResult() {
        let candidates = [dumbbellBenchPress, inclineBenchPress, cableFly]
        
        let best = SubstitutionRanker.findBestSubstitute(
            for: benchPress,
            candidates: candidates,
            availableEquipment: availableEquipment
        )
        
        XCTAssertNotNil(best)
        
        // Should be same as first result from rank()
        let ranked = SubstitutionRanker.rank(
            for: benchPress,
            candidates: candidates,
            availableEquipment: availableEquipment,
            maxResults: 1
        )
        
        XCTAssertEqual(best?.exercise.id, ranked.first?.exercise.id)
    }
    
    func testFindBestSubstitute_ReturnsNilIfBelowMinScore() {
        let candidates = [pullUp]  // Very different from bench press
        
        let best = SubstitutionRanker.findBestSubstitute(
            for: benchPress,
            candidates: candidates,
            availableEquipment: availableEquipment,
            minimumScore: 0.9  // Very high threshold
        )
        
        XCTAssertNil(best)
    }
    
    func testHasValidSubstitutes_ReturnsTrueWhenAvailable() {
        let candidates = [dumbbellBenchPress]
        
        let hasValid = SubstitutionRanker.hasValidSubstitutes(
            for: benchPress,
            candidates: candidates,
            availableEquipment: availableEquipment
        )
        
        XCTAssertTrue(hasValid)
    }
    
    func testHasValidSubstitutes_ReturnsFalseWhenNoneAvailable() {
        let candidates = [pullUp]  // Very different
        
        let hasValid = SubstitutionRanker.hasValidSubstitutes(
            for: benchPress,
            candidates: candidates,
            availableEquipment: availableEquipment,
            minimumScore: 0.9
        )
        
        XCTAssertFalse(hasValid)
    }
    
    // MARK: - Reasons Tests
    
    func testSubstitution_IncludesReasons() {
        let candidates = [dumbbellBenchPress]
        
        let substitutions = SubstitutionRanker.rank(
            for: benchPress,
            candidates: candidates,
            availableEquipment: availableEquipment,
            maxResults: 1
        )
        
        XCTAssertFalse(substitutions.isEmpty)
        XCTAssertFalse(substitutions[0].reasons.isEmpty)
        
        // Should have muscle overlap and equipment available reasons
        let hasEquipmentReason = substitutions[0].reasons.contains { $0.category == .equipmentAvailable }
        XCTAssertTrue(hasEquipmentReason)
    }
}
