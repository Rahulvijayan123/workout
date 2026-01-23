import XCTest
@testable import TrainingEngine

final class DoubleProgressionTests: XCTestCase {
    
    let config = DoubleProgressionConfig.default
    let prescription = SetPrescription(
        setCount: 3,
        targetRepsRange: 6...10,
        targetRIR: 2,
        increment: .pounds(5)
    )
    
    // MARK: - Hit Top of Range → Load Increase
    
    func testAllSetsAtTopOfRange_IncreasesLoad() {
        // Given: All sets at 10 reps (top of 6-10 range)
        let workingSets = [
            SetResult(reps: 10, load: .pounds(100)),
            SetResult(reps: 10, load: .pounds(100)),
            SetResult(reps: 10, load: .pounds(100))
        ]
        
        let exerciseResult = ExerciseSessionResult(
            exerciseId: "bench_press",
            prescription: prescription,
            sets: workingSets
        )
        
        let liftState = LiftState(
            exerciseId: "bench_press",
            lastWorkingWeight: .pounds(100)
        )
        
        let history = WorkoutHistory(
            sessions: [
                CompletedSession(
                    date: Date(),
                    name: "Push",
                    exerciseResults: [exerciseResult],
                    startedAt: Date()
                )
            ],
            liftStates: ["bench_press": liftState]
        )
        
        // When
        let nextLoad = DoubleProgressionPolicy.computeNextLoad(
            config: config,
            prescription: prescription,
            liftState: liftState,
            history: history,
            exerciseId: "bench_press"
        )
        
        // Then: Load should increase by 5 lbs
        XCTAssertEqual(nextLoad.value, 105, accuracy: 0.01)
        XCTAssertEqual(nextLoad.unit, .pounds)
    }
    
    func testAllSetsExceedingTopOfRange_StillIncreasesLoad() {
        // Given: All sets exceed top of range
        let workingSets = [
            SetResult(reps: 12, load: .pounds(100)),
            SetResult(reps: 11, load: .pounds(100)),
            SetResult(reps: 10, load: .pounds(100))
        ]
        
        let exerciseResult = ExerciseSessionResult(
            exerciseId: "bench_press",
            prescription: prescription,
            sets: workingSets
        )
        
        let history = createHistory(exerciseResult: exerciseResult, load: .pounds(100))
        let liftState = history.liftStates["bench_press"]!
        
        // When
        let nextLoad = DoubleProgressionPolicy.computeNextLoad(
            config: config,
            prescription: prescription,
            liftState: liftState,
            history: history,
            exerciseId: "bench_press"
        )
        
        // Then
        XCTAssertEqual(nextLoad.value, 105, accuracy: 0.01)
    }
    
    // MARK: - Within Range → Maintain Load (Rep Progression)
    
    func testAllSetsWithinRange_MaintainsLoad() {
        // Given: All sets within range (7, 7, 6)
        let workingSets = [
            SetResult(reps: 7, load: .pounds(100)),
            SetResult(reps: 7, load: .pounds(100)),
            SetResult(reps: 6, load: .pounds(100))
        ]
        
        let exerciseResult = ExerciseSessionResult(
            exerciseId: "bench_press",
            prescription: prescription,
            sets: workingSets
        )
        
        let history = createHistory(exerciseResult: exerciseResult, load: .pounds(100))
        let liftState = history.liftStates["bench_press"]!
        
        // When
        let nextLoad = DoubleProgressionPolicy.computeNextLoad(
            config: config,
            prescription: prescription,
            liftState: liftState,
            history: history,
            exerciseId: "bench_press"
        )
        
        // Then: Load should stay the same
        XCTAssertEqual(nextLoad.value, 100, accuracy: 0.01)
    }
    
    func testTargetRepsIncreaseWhenWithinRange() {
        // Given: All sets at 7 reps
        let workingSets = [
            SetResult(reps: 7, load: .pounds(100)),
            SetResult(reps: 7, load: .pounds(100)),
            SetResult(reps: 7, load: .pounds(100))
        ]
        
        let exerciseResult = ExerciseSessionResult(
            exerciseId: "bench_press",
            prescription: prescription,
            sets: workingSets
        )
        
        let history = createHistory(exerciseResult: exerciseResult, load: .pounds(100))
        
        // When
        let targetReps = DoubleProgressionPolicy.computeTargetReps(
            config: config,
            prescription: prescription,
            history: history,
            exerciseId: "bench_press"
        )
        
        // Then: Target reps should be 8 (min + 1)
        XCTAssertEqual(targetReps, 8)
    }
    
    // MARK: - Below Range → Failure Count / Deload
    
    func testBelowLowerBound_MaintainsLoadIfNotEnoughFailures() {
        // Given: Sets below lower bound, but failure count is 0
        let workingSets = [
            SetResult(reps: 5, load: .pounds(100)),
            SetResult(reps: 5, load: .pounds(100)),
            SetResult(reps: 4, load: .pounds(100))
        ]
        
        let exerciseResult = ExerciseSessionResult(
            exerciseId: "bench_press",
            prescription: prescription,
            sets: workingSets
        )
        
        let liftState = LiftState(
            exerciseId: "bench_press",
            lastWorkingWeight: .pounds(100),
            failureCount: 0  // Not enough failures yet
        )
        
        let history = WorkoutHistory(
            sessions: [
                CompletedSession(
                    date: Date(),
                    name: "Push",
                    exerciseResults: [exerciseResult],
                    startedAt: Date()
                )
            ],
            liftStates: ["bench_press": liftState]
        )
        
        // When
        let nextLoad = DoubleProgressionPolicy.computeNextLoad(
            config: config,
            prescription: prescription,
            liftState: liftState,
            history: history,
            exerciseId: "bench_press"
        )
        
        // Then: Load should stay same (not enough failures for deload)
        XCTAssertEqual(nextLoad.value, 100, accuracy: 0.01)
    }
    
    func testBelowLowerBound_DeloadsAfterEnoughFailures() {
        // Given: Sets below lower bound, failure count at threshold
        let workingSets = [
            SetResult(reps: 5, load: .pounds(100)),
            SetResult(reps: 5, load: .pounds(100)),
            SetResult(reps: 4, load: .pounds(100))
        ]
        
        let exerciseResult = ExerciseSessionResult(
            exerciseId: "bench_press",
            prescription: prescription,
            sets: workingSets
        )
        
        let liftState = LiftState(
            exerciseId: "bench_press",
            lastWorkingWeight: .pounds(100),
            failureCount: 2  // At threshold (default failuresBeforeDeload = 2)
        )
        
        let history = WorkoutHistory(
            sessions: [
                CompletedSession(
                    date: Date(),
                    name: "Push",
                    exerciseResults: [exerciseResult],
                    startedAt: Date()
                )
            ],
            liftStates: ["bench_press": liftState]
        )
        
        // When
        let nextLoad = DoubleProgressionPolicy.computeNextLoad(
            config: config,
            prescription: prescription,
            liftState: liftState,
            history: history,
            exerciseId: "bench_press"
        )
        
        // Then: Load should deload by 10% (100 * 0.90 = 90)
        XCTAssertEqual(nextLoad.value, 90, accuracy: 0.01)
    }
    
    // MARK: - Edge Cases
    
    func testNoHistory_UsesLastWorkingWeight() {
        // Given: No session history
        let liftState = LiftState(
            exerciseId: "bench_press",
            lastWorkingWeight: .pounds(100)
        )
        
        let history = WorkoutHistory(
            sessions: [],
            liftStates: ["bench_press": liftState]
        )
        
        // When
        let nextLoad = DoubleProgressionPolicy.computeNextLoad(
            config: config,
            prescription: prescription,
            liftState: liftState,
            history: history,
            exerciseId: "bench_press"
        )
        
        // Then
        XCTAssertEqual(nextLoad.value, 100, accuracy: 0.01)
    }
    
    func testProgressionEvaluationCorrectlyIdentifiesLoadIncrease() {
        let workingSets = [
            SetResult(reps: 10, load: .pounds(100)),
            SetResult(reps: 10, load: .pounds(100)),
            SetResult(reps: 10, load: .pounds(100))
        ]
        
        let exerciseResult = ExerciseSessionResult(
            exerciseId: "bench_press",
            prescription: prescription,
            sets: workingSets
        )
        
        let decision = DoubleProgressionPolicy.evaluateProgression(
            config: config,
            prescription: prescription,
            lastResult: exerciseResult
        )
        
        if case .increaseLoad(let amount, _) = decision {
            XCTAssertEqual(amount.value, 5)
        } else {
            XCTFail("Expected increaseLoad decision")
        }
    }

    // MARK: - sessionsAtTopBeforeIncrease

    func testSessionsAtTopBeforeIncrease_DoesNotIncreaseLoadUntilStreakMet() {
        // Given: Require 2 consecutive \"top\" sessions before increasing load.
        let cfg = DoubleProgressionConfig(
            sessionsAtTopBeforeIncrease: 2,
            loadIncrement: .pounds(5),
            deloadPercentage: 0.10,
            failuresBeforeDeload: 2
        )

        let pres = SetPrescription(
            setCount: 3,
            targetRepsRange: 6...10,
            targetRIR: 2,
            increment: .pounds(5)
        )

        let workingSets = [
            SetResult(reps: 10, load: .pounds(100)),
            SetResult(reps: 10, load: .pounds(100)),
            SetResult(reps: 10, load: .pounds(100))
        ]

        let exerciseResult = ExerciseSessionResult(
            exerciseId: "bench_press",
            prescription: pres,
            sets: workingSets
        )

        let liftState = LiftState(exerciseId: "bench_press", lastWorkingWeight: .pounds(100))

        // Only one top session in history
        let history = WorkoutHistory(
            sessions: [
                CompletedSession(
                    date: Date(),
                    name: "Push",
                    exerciseResults: [exerciseResult],
                    startedAt: Date()
                )
            ],
            liftStates: ["bench_press": liftState]
        )

        // When
        let nextLoad = DoubleProgressionPolicy.computeNextLoad(
            config: cfg,
            prescription: pres,
            liftState: liftState,
            history: history,
            exerciseId: "bench_press"
        )
        let nextReps = DoubleProgressionPolicy.computeTargetReps(
            config: cfg,
            prescription: pres,
            history: history,
            exerciseId: "bench_press"
        )

        // Then: hold load; keep reps at upper bound
        XCTAssertEqual(nextLoad.value, 100, accuracy: 0.01)
        XCTAssertEqual(nextReps, 10)
    }

    func testSessionsAtTopBeforeIncrease_IncreasesLoadWhenStreakMet() {
        let cfg = DoubleProgressionConfig(
            sessionsAtTopBeforeIncrease: 2,
            loadIncrement: .pounds(5),
            deloadPercentage: 0.10,
            failuresBeforeDeload: 2
        )

        let pres = SetPrescription(
            setCount: 3,
            targetRepsRange: 6...10,
            targetRIR: 2,
            increment: .pounds(5)
        )

        let workingSets = [
            SetResult(reps: 10, load: .pounds(100)),
            SetResult(reps: 10, load: .pounds(100)),
            SetResult(reps: 10, load: .pounds(100))
        ]

        let r1 = ExerciseSessionResult(exerciseId: "bench_press", prescription: pres, sets: workingSets)
        let r2 = ExerciseSessionResult(exerciseId: "bench_press", prescription: pres, sets: workingSets)

        let liftState = LiftState(exerciseId: "bench_press", lastWorkingWeight: .pounds(100))

        // Two top sessions in history (most recent first)
        let history = WorkoutHistory(
            sessions: [
                CompletedSession(date: Date(), name: "Push", exerciseResults: [r2], startedAt: Date()),
                CompletedSession(date: Date().addingTimeInterval(-86400), name: "Push", exerciseResults: [r1], startedAt: Date().addingTimeInterval(-86400)),
            ],
            liftStates: ["bench_press": liftState]
        )

        let nextLoad = DoubleProgressionPolicy.computeNextLoad(
            config: cfg,
            prescription: pres,
            liftState: liftState,
            history: history,
            exerciseId: "bench_press"
        )
        let nextReps = DoubleProgressionPolicy.computeTargetReps(
            config: cfg,
            prescription: pres,
            history: history,
            exerciseId: "bench_press"
        )

        XCTAssertEqual(nextLoad.value, 105, accuracy: 0.01)
        XCTAssertEqual(nextReps, 6)
    }
    
    // MARK: - Helpers
    
    private func createHistory(exerciseResult: ExerciseSessionResult, load: Load) -> WorkoutHistory {
        let liftState = LiftState(
            exerciseId: exerciseResult.exerciseId,
            lastWorkingWeight: load
        )
        
        return WorkoutHistory(
            sessions: [
                CompletedSession(
                    date: Date(),
                    name: "Test Session",
                    exerciseResults: [exerciseResult],
                    startedAt: Date()
                )
            ],
            liftStates: [exerciseResult.exerciseId: liftState]
        )
    }
}
