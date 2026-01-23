import XCTest
@testable import TrainingEngine

final class EdgeCaseBreakerTests: XCTestCase {
    
    private let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(secondsFromGMT: 0)!
        return c
    }()
    
    private func day(_ date: Date) -> Date {
        calendar.startOfDay(for: date)
    }
    
    private func makeDate(year: Int, month: Int, day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }
    
    // MARK: - Substitution safety
    
    func testBodyweightSubstitution_DoesNotCarryOverBarbellLoad() {
        // Real-world: barbell bench unavailable, user is travelling, only bodyweight is available.
        // The engine must not carry over a heavy barbell load into a bodyweight substitute.
        
        let tId = UUID(uuidString: "00000000-0000-0000-0000-00000000F101")!
        
        let barbellBench = Exercise(
            id: "bb_bench",
            name: "Barbell Bench Press",
            equipment: .barbell,
            primaryMuscles: [.chest],
            secondaryMuscles: [.triceps],
            movementPattern: .horizontalPush
        )
        
        let pushup = Exercise(
            id: "pushup",
            name: "Push-Up",
            equipment: .bodyweight,
            primaryMuscles: [.chest],
            secondaryMuscles: [.triceps],
            movementPattern: .horizontalPush
        )
        
        let rx = SetPrescription(setCount: 3, targetRepsRange: 8...12, targetRIR: 2, restSeconds: 90, increment: .pounds(5))
        let template = WorkoutTemplate(id: tId, name: "Push", exercises: [TemplateExercise(exercise: barbellBench, prescription: rx, order: 0)])
        
        let plan = TrainingPlan(
            name: "Bodyweight substitution safety",
            templates: [tId: template],
            schedule: .rotation(order: [tId]),
            progressionPolicies: [barbellBench.id: .doubleProgression(config: .default)],
            inSessionPolicies: [:],
            substitutionPool: [pushup],
            deloadConfig: nil,
            loadRoundingPolicy: .standardPounds
        )
        
        let user = UserProfile(
            sex: .male,
            experience: .intermediate,
            goals: [.hypertrophy],
            weeklyFrequency: 3,
            availableEquipment: .bodyweightOnly,
            preferredUnit: .pounds
        )
        
        let benchState = LiftState(
            exerciseId: barbellBench.id,
            lastWorkingWeight: .pounds(225),
            rollingE1RM: 275,
            lastSessionDate: makeDate(year: 2026, month: 2, day: 1)
        )
        
        let history = WorkoutHistory(
            sessions: [],
            liftStates: [barbellBench.id: benchState],
            readinessHistory: [],
            recentVolumeByDate: [:]
        )
        
        let date = makeDate(year: 2026, month: 2, day: 10)
        let sessionPlan = Engine.recommendSession(
            date: date,
            userProfile: user,
            plan: plan,
            history: history,
            readiness: 80,
            calendar: calendar
        )
        
        XCTAssertEqual(sessionPlan.exercises.count, 1)
        XCTAssertEqual(sessionPlan.exercises[0].exercise.id, pushup.id)
        
        // Critical: bodyweight substitute should use 0 external load.
        XCTAssertEqual(sessionPlan.exercises[0].sets[0].targetLoad.value, 0, accuracy: 1e-9)
    }
    
    // MARK: - Top set/backoff: incomplete top set should not re-shape backoffs
    
    func testTopSetBackoffDailyMax_DoesNotAdjustIfTopSetNotCompletedOrZeroReps() {
        // Real-world: top set attempt aborted (spotter/rack issue) -> backoffs should remain planned.
        
        let cfg = TopSetBackoffConfig(backoffSetCount: 3, backoffPercentage: 0.75, loadIncrement: .pounds(5), useDailyMax: true, minimumTopSetReps: 1)
        
        let plannedNext = SetPlan(
            setIndex: 1,
            targetLoad: .pounds(190), // deliberately different from what daily-max computation would yield
            targetReps: 5,
            targetRIR: 1,
            restSeconds: 180,
            isWarmup: false,
            backoffPercentage: 0.75,
            inSessionPolicy: .topSetBackoff(config: cfg),
            roundingPolicy: .standardPounds
        )
        
        let notCompleted = SetResult(reps: 0, load: .pounds(300), rirObserved: nil, completed: false)
        
        let adjusted = Engine.adjustDuringSession(
            currentSetResult: notCompleted,
            plannedNextSet: plannedNext
        )
        
        XCTAssertEqual(adjusted.targetLoad, plannedNext.targetLoad)
    }
    
    // MARK: - High-fatigue deload: sparse baseline must not trigger
    
    func testHighFatigue_DoesNotTriggerWithInsufficientBaselineCoverage() {
        // If volume history is sparse (missing most days), we shouldn't treat baseline as "near zero"
        // and trigger high-fatigue deload erroneously.
        
        let tId = UUID(uuidString: "00000000-0000-0000-0000-00000000F102")!
        let squat = Exercise.barbellSquat
        let rx = SetPrescription(setCount: 3, targetRepsRange: 5...5, targetRIR: 2, increment: .pounds(5))
        let template = WorkoutTemplate(id: tId, name: "Squat", exercises: [TemplateExercise(exercise: squat, prescription: rx, order: 0)])
        
        let deload = DeloadConfig(
            intensityReduction: 0.15,
            volumeReduction: 1,
            scheduledDeloadWeeks: nil,
            readinessThreshold: 50,
            lowReadinessDaysRequired: 3
        )
        
        let plan = TrainingPlan(
            name: "HighFatigue sparse baseline",
            templates: [tId: template],
            schedule: .rotation(order: [tId]),
            progressionPolicies: [squat.id: .none],
            inSessionPolicies: [:],
            substitutionPool: [],
            deloadConfig: deload,
            loadRoundingPolicy: .standardPounds
        )
        
        let user = UserProfile(sex: .male, experience: .intermediate, goals: [.strength], weeklyFrequency: 3, availableEquipment: .commercialGym, preferredUnit: .pounds)
        let date = makeDate(year: 2026, month: 2, day: 20)
        
        // Only 2 baseline days recorded (sparse), but 7 recent days recorded.
        var volume: [Date: Double] = [:]
        
        let baselineDay1 = calendar.date(byAdding: .day, value: -20, to: date)!
        let baselineDay2 = calendar.date(byAdding: .day, value: -21, to: date)!
        volume[baselineDay1] = 10_000
        volume[baselineDay2] = 10_000
        
        for i in 0..<7 {
            let d = calendar.date(byAdding: .day, value: -i, to: date)!
            volume[d] = 15_000
        }
        
        let history = WorkoutHistory(sessions: [], liftStates: [:], readinessHistory: [], recentVolumeByDate: volume)
        
        // Low readiness today, but not enough consecutive low days to trigger lowReadiness.
        let sessionPlan = Engine.recommendSession(date: date, userProfile: user, plan: plan, history: history, readiness: 40, calendar: calendar)
        
        // Should NOT deload due to high-fatigue given sparse baseline.
        XCTAssertFalse(sessionPlan.isDeload)
    }
    
    // MARK: - Volume boundaries (guard against off-by-one)
    
    func testWorkoutHistory_TotalVolume_SevenDayWindowIsInclusiveAndDayBucketed() {
        let today = day(makeDate(year: 2026, month: 2, day: 28))
        
        var volume: [Date: Double] = [:]
        
        // 8 days ago should be excluded from lastDays: 7
        let eightDaysAgo = calendar.date(byAdding: .day, value: -7, to: today)! // because inclusive window is 0..6 days ago
        volume[calendar.date(byAdding: .hour, value: 9, to: eightDaysAgo)!] = 1_000
        
        // 7-day window (today through 6 days ago): total should be 7_000
        for i in 0..<7 {
            let d = calendar.date(byAdding: .day, value: -i, to: today)!
            volume[calendar.date(byAdding: .hour, value: i, to: d)!] = 1_000
        }
        
        let history = WorkoutHistory(sessions: [], liftStates: [:], readinessHistory: [], recentVolumeByDate: volume)
        let total = history.totalVolume(lastDays: 7, from: today, calendar: calendar)
        XCTAssertEqual(total, 7_000, accuracy: 1e-9)
    }
}

