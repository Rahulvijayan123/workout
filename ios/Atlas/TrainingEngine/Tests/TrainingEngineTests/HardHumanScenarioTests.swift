import XCTest
@testable import TrainingEngine

final class HardHumanScenarioTests: XCTestCase {
    
    private let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(secondsFromGMT: 0)!
        return c
    }()
    
    private func day(_ date: Date) -> Date {
        calendar.startOfDay(for: date)
    }
    
    private func makeDate(year: Int, month: Int, day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }
    
    // MARK: - Readiness history: real-world data gaps
    
    func testConsecutiveLowReadinessDays_DoesNotCountAcrossMissingDays() {
        // Realistic: readiness data can be missing for some days (watch not worn, etc.).
        // "Consecutive days" should not count across gaps.
        
        let today = day(makeDate(year: 2026, month: 2, day: 10))
        let twoDaysAgo = day(calendar.date(byAdding: .day, value: -2, to: today)!)
        let fiveDaysAgo = day(calendar.date(byAdding: .day, value: -5, to: today)!)
        
        // Low readiness records exist, but with gaps (no record for yesterday, no record for 3-4 days ago).
        let readinessHistory = [
            ReadinessRecord(date: today, score: 40),
            ReadinessRecord(date: twoDaysAgo, score: 45),
            ReadinessRecord(date: fiveDaysAgo, score: 42),
        ]
        
        let history = WorkoutHistory(
            sessions: [],
            liftStates: [:],
            readinessHistory: readinessHistory,
            recentVolumeByDate: [:]
        )
        
        let consecutive = history.consecutiveLowReadinessDays(threshold: 50, from: today, calendar: calendar)
        
        // Expected: only 1 consecutive day (today). The -2 day record is not consecutive.
        XCTAssertEqual(consecutive, 1)
    }
    
    // MARK: - Load strategy: percentage of e1RM (spec-level feature)
    
    func testRecommendSession_PercentageE1RM_UsesRollingE1RM_WhenAvailable() {
        let exercise = Exercise(
            id: "squat",
            name: "Back Squat",
            equipment: .barbell,
            primaryMuscles: [.quadriceps, .glutes],
            secondaryMuscles: [.hamstrings, .lowerBack],
            movementPattern: .squat
        )
        
        let prescription = SetPrescription(
            setCount: 3,
            targetRepsRange: 3...3,
            targetRIR: 2,
            loadStrategy: .percentageE1RM,
            targetPercentage: 0.80,
            increment: .pounds(5)
        )
        
        let template = WorkoutTemplate(
            name: "Squat Day",
            exercises: [
                TemplateExercise(exercise: exercise, prescription: prescription, order: 0)
            ]
        )
        
        let plan = TrainingPlan(
            name: "Percent Plan",
            templates: [template.id: template],
            schedule: .rotation(order: [template.id]),
            progressionPolicies: [exercise.id: .none],
            inSessionPolicies: [:], // no in-session adjustment needed for this test
            substitutionPool: [],
            deloadConfig: nil,
            loadRoundingPolicy: .standardPounds
        )
        
        let user = UserProfile(
            sex: .male,
            experience: .intermediate,
            goals: [.strength],
            weeklyFrequency: 3,
            availableEquipment: .commercialGym,
            preferredUnit: .pounds
        )
        
        let state = LiftState(
            exerciseId: exercise.id,
            lastWorkingWeight: .pounds(225),
            rollingE1RM: 300 // lb
        )
        
        let history = WorkoutHistory(
            sessions: [],
            liftStates: [exercise.id: state],
            readinessHistory: [ReadinessRecord(date: Date(), score: 80)],
            recentVolumeByDate: [:]
        )
        
        let sessionPlan = Engine.recommendSession(
            date: Date(),
            userProfile: user,
            plan: plan,
            history: history,
            readiness: 80
        )
        
        XCTAssertFalse(sessionPlan.exercises.isEmpty)
        let plannedLoad = sessionPlan.exercises[0].sets[0].targetLoad.value
        
        // 80% of 300 = 240 (already roundable)
        XCTAssertEqual(plannedLoad, 240, accuracy: 0.001)
    }
    
    // MARK: - Combined: between-session progression + in-session RIR
    
    func testDoubleProgressionPlusRIR_InSessionAdjustsWithoutBreakingProgression() {
        let bench = Exercise(
            id: "bench",
            name: "Bench Press",
            equipment: .barbell,
            primaryMuscles: [.chest],
            secondaryMuscles: [.triceps],
            movementPattern: .horizontalPush
        )
        
        let prescription = SetPrescription(
            setCount: 3,
            targetRepsRange: 6...10,
            targetRIR: 2,
            loadStrategy: .absolute,
            increment: .pounds(5)
        )
        
        let template = WorkoutTemplate(
            name: "Bench",
            exercises: [TemplateExercise(exercise: bench, prescription: prescription, order: 0)]
        )
        
        let plan = TrainingPlan(
            name: "DP+RIR",
            templates: [template.id: template],
            schedule: .rotation(order: [template.id]),
            progressionPolicies: [bench.id: .doubleProgression(config: .default)],
            inSessionPolicies: [bench.id: .rirAutoregulation(config: .default)],
            substitutionPool: [],
            deloadConfig: nil,
            loadRoundingPolicy: .standardPounds
        )
        
        let user = UserProfile(
            sex: .male,
            experience: .intermediate,
            goals: [.hypertrophy],
            weeklyFrequency: 3,
            availableEquipment: .commercialGym,
            preferredUnit: .pounds
        )
        
        let state = LiftState(exerciseId: bench.id, lastWorkingWeight: .pounds(185))
        let history = WorkoutHistory(sessions: [], liftStates: [bench.id: state], readinessHistory: [], recentVolumeByDate: [:])
        
        let sessionPlan = Engine.recommendSession(
            date: Date(),
            userProfile: user,
            plan: plan,
            history: history,
            readiness: 80
        )
        
        let sets = sessionPlan.exercises[0].sets
        XCTAssertEqual(sets.count, 3)
        
        // Simulate set 1 being easier than expected (higher RIR)
        let result1 = SetResult(
            reps: sets[0].targetReps,
            load: sets[0].targetLoad,
            rirObserved: sets[0].targetRIR + 2,
            completed: true
        )
        
        let adjustedSet2 = Engine.adjustDuringSession(
            currentSetResult: result1,
            plannedNextSet: sets[1]
        )
        
        // RIR policy should adjust load upward (deterministically).
        XCTAssertGreaterThan(adjustedSet2.targetLoad.value, sets[1].targetLoad.value)
        
        // Between-session progression policy should remain DP (not replaced by RIR)
        XCTAssertEqual(sessionPlan.exercises[0].progressionPolicy, .doubleProgression(config: .default))
    }
}

