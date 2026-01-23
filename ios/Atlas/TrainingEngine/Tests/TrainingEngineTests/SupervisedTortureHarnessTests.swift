import XCTest
@testable import TrainingEngine

/// A "supervised" torture harness: we script known scenarios and compute expected outputs explicitly.
/// The goal is to catch real-world integration gaps (not just unit-level math).
final class SupervisedTortureHarnessTests: XCTestCase {
    
    // MARK: - Deterministic Calendar Helpers (DST-safe)
    
    private let laCalendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return c
    }()
    
    private func makeLocalNoon(_ year: Int, _ month: Int, _ day: Int) -> Date {
        laCalendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12, minute: 0))!
    }
    
    // MARK: - Core harness test
    
    func testSupervisedTortureHarness_AllMajorGaps() throws {
        // ===== Templates + schedule (fixed weekday) =====
        
        let upperId = UUID(uuidString: "00000000-0000-0000-0000-00000000D201")!
        let lowerId = UUID(uuidString: "00000000-0000-0000-0000-00000000D202")!
        let auxId   = UUID(uuidString: "00000000-0000-0000-0000-00000000D203")!
        
        let bench = Exercise(
            id: "bench",
            name: "Bench Press",
            equipment: .barbell,
            primaryMuscles: [.chest],
            secondaryMuscles: [.triceps, .frontDelts],
            movementPattern: .horizontalPush
        )
        
        let row = Exercise(
            id: "row",
            name: "Barbell Row",
            equipment: .barbell,
            primaryMuscles: [.back],
            secondaryMuscles: [.biceps],
            movementPattern: .horizontalPull
        )
        
        let squat = Exercise.barbellSquat
        
        let dbBench = Exercise(
            id: "db_bench",
            name: "Dumbbell Bench Press",
            equipment: .dumbbell,
            primaryMuscles: [.chest],
            secondaryMuscles: [.triceps, .frontDelts],
            movementPattern: .horizontalPush
        )
        
        let dbRow = Exercise(
            id: "db_row",
            name: "Dumbbell Row",
            equipment: .dumbbell,
            primaryMuscles: [.back],
            secondaryMuscles: [.biceps],
            movementPattern: .horizontalPull
        )
        
        // Top set + 3 backoffs, daily max enabled.
        let benchTopSetCfg = TopSetBackoffConfig(
            backoffSetCount: 3,
            backoffPercentage: 0.75,
            loadIncrement: .pounds(5),
            useDailyMax: true,
            minimumTopSetReps: 1
        )
        
        let benchRx = SetPrescription(
            setCount: 4,
            targetRepsRange: 5...5,
            targetRIR: 1,
            restSeconds: 180,
            loadStrategy: .absolute,
            increment: .pounds(5)
        )
        
        let rowRx = SetPrescription(
            setCount: 3,
            targetRepsRange: 6...10,
            targetRIR: 2,
            restSeconds: 150,
            loadStrategy: .rpeAutoregulated,
            increment: .pounds(5)
        )
        
        let squatRx = SetPrescription(
            setCount: 3,
            targetRepsRange: 5...5,
            targetRIR: 2,
            restSeconds: 180,
            loadStrategy: .absolute,
            increment: .pounds(5)
        )
        
        let upper = WorkoutTemplate(
            id: upperId,
            name: "Upper",
            exercises: [
                TemplateExercise(exercise: bench, prescription: benchRx, order: 0),
                TemplateExercise(exercise: row, prescription: rowRx, order: 1),
            ]
        )
        
        let lower = WorkoutTemplate(
            id: lowerId,
            name: "Lower",
            exercises: [
                TemplateExercise(exercise: squat, prescription: squatRx, order: 0),
            ]
        )
        
        // Auxiliary day intentionally uses an exercise that will collide with a substitute.
        let machineChestPress = Exercise(
            id: "machine_press",
            name: "Chest Press Machine",
            equipment: .chestPressMachine,
            primaryMuscles: [.chest],
            secondaryMuscles: [.triceps],
            movementPattern: .horizontalPush
        )
        
        let aux = WorkoutTemplate(
            id: auxId,
            name: "Aux",
            exercises: [
                TemplateExercise(exercise: machineChestPress, prescription: .hypertrophy, order: 0),
            ]
        )
        
        let schedule = ScheduleType.fixedWeekday(mapping: [
            2: upperId, // Monday
            4: lowerId, // Wednesday
            6: auxId    // Friday
        ])
        
        let deloadCfg = DeloadConfig(
            intensityReduction: 0.15,
            volumeReduction: 1,
            scheduledDeloadWeeks: nil,
            readinessThreshold: 50,
            lowReadinessDaysRequired: 3
        )
        
        let plan = TrainingPlan(
            id: UUID(uuidString: "00000000-0000-0000-0000-00000000D2F0")!,
            name: "Supervised harness plan",
            templates: [upperId: upper, lowerId: lower, auxId: aux],
            schedule: schedule,
            progressionPolicies: [
                bench.id: .topSetBackoff(config: benchTopSetCfg),
                row.id: .linearProgression(config: .upperBody),
                squat.id: .topSetBackoff(config: .powerlifting),
            ],
            inSessionPolicies: [:],
            substitutionPool: [dbBench, dbRow],
            deloadConfig: deloadCfg,
            loadRoundingPolicy: .standardPounds
        )
        
        let userCommercial = UserProfile(
            id: "u",
            sex: .male,
            experience: .intermediate,
            goals: [.strength],
            weeklyFrequency: 3,
            availableEquipment: .commercialGym,
            preferredUnit: .pounds
        )
        
        // ===== Baseline history =====
        
        let start = makeLocalNoon(2026, 3, 2) // Monday, pre-DST week
        let mondayAfterDST = makeLocalNoon(2026, 3, 9) // Monday after DST switch (DST starts Sun 3/8/2026)
        let wednesdayAfterDST = makeLocalNoon(2026, 3, 11)
        
        // Lift states (explicitly non-zero so supervised expectations are meaningful)
        let liftStates: [String: LiftState] = [
            bench.id: LiftState(exerciseId: bench.id, lastWorkingWeight: .pounds(225), rollingE1RM: 275, lastSessionDate: start),
            row.id: LiftState(exerciseId: row.id, lastWorkingWeight: .pounds(185), rollingE1RM: 240, lastSessionDate: start),
            squat.id: LiftState(exerciseId: squat.id, lastWorkingWeight: .pounds(315), rollingE1RM: 385, lastSessionDate: start),
        ]
        
        // Volume keys use timestamps (not start-of-day) to ensure day-bucket normalization is correct.
        var volumeByDate: [Date: Double] = [:]
        for i in 0..<28 {
            let d = laCalendar.date(byAdding: .day, value: -i, to: mondayAfterDST)!
            volumeByDate[d] = 10_000 // baseline ~10k/day
        }
        for i in 0..<7 {
            let d = laCalendar.date(byAdding: .day, value: -i, to: mondayAfterDST)!
            volumeByDate[d] = 15_000 // recent ~15k/day (150% of baseline)
        }
        
        // Readiness history: mostly fine, but we will set today's readiness low for high-fatigue-only trigger.
        let readinessHistory = [
            ReadinessRecord(date: laCalendar.date(byAdding: .day, value: -1, to: mondayAfterDST)!, score: 80),
            ReadinessRecord(date: laCalendar.date(byAdding: .day, value: -2, to: mondayAfterDST)!, score: 75),
        ]
        
        let history = WorkoutHistory(
            sessions: [],
            liftStates: liftStates,
            readinessHistory: readinessHistory,
            recentVolumeByDate: volumeByDate
        )
        
        // ===== 1) Fixed weekday schedule across DST + missed workout =====
        
        let plannedMon = Engine.recommendSession(
            date: mondayAfterDST,
            userProfile: userCommercial,
            plan: plan,
            history: history,
            readiness: 80,
            calendar: laCalendar
        )
        XCTAssertEqual(plannedMon.templateId, upperId)
        
        // User misses Monday (no session recorded). Wednesday should still be Wednesday template.
        let plannedWed = Engine.recommendSession(
            date: wednesdayAfterDST,
            userProfile: userCommercial,
            plan: plan,
            history: history,
            readiness: 80,
            calendar: laCalendar
        )
        XCTAssertEqual(plannedWed.templateId, lowerId)
        
        // ===== 2) Top set drives backoffs (daily max) end-to-end =====
        // We "know the answer": backoff load should become dailyMax * 0.75, rounded to 2.5 lb.
        
        XCTAssertEqual(plannedMon.exercises.count, 2)
        let benchPlan = plannedMon.exercises[0]
        XCTAssertEqual(benchPlan.exercise.id, bench.id)
        XCTAssertEqual(benchPlan.progressionPolicy, .topSetBackoff(config: benchTopSetCfg))
        XCTAssertEqual(benchPlan.sets.count, 4)
        
        let topSet = benchPlan.sets[0]
        XCTAssertEqual(topSet.setIndex, 0)
        
        // Force a "strong" top set day: 225 x 8
        let topResult = SetResult(reps: 8, load: topSet.targetLoad, rirObserved: 2, completed: true)
        
        let dailyMax = E1RMCalculator.brzycki(weight: topResult.load.value, reps: topResult.reps)
        let expectedBackoff = Load(value: dailyMax * 0.75, unit: topResult.load.unit)
            .rounded(using: .standardPounds)
        
        // Next set (set 1) should get adjusted to expectedBackoff
        let adjusted1 = Engine.adjustDuringSession(currentSetResult: topResult, plannedNextSet: benchPlan.sets[1])
        XCTAssertEqual(adjusted1.targetLoad, expectedBackoff)
        
        // Subsequent backoff sets should propagate the same load.
        let backoff1Result = SetResult(reps: 5, load: adjusted1.targetLoad, rirObserved: 2, completed: true)
        let adjusted2 = Engine.adjustDuringSession(currentSetResult: backoff1Result, plannedNextSet: benchPlan.sets[2])
        XCTAssertEqual(adjusted2.targetLoad, expectedBackoff)
        
        let backoff2Result = SetResult(reps: 5, load: adjusted2.targetLoad, rirObserved: 2, completed: true)
        let adjusted3 = Engine.adjustDuringSession(currentSetResult: backoff2Result, plannedNextSet: benchPlan.sets[3])
        XCTAssertEqual(adjusted3.targetLoad, expectedBackoff)
        
        // ===== 3) High-fatigue deload trigger (low readiness today + high volume, but NOT enough consecutive low days) =====
        // We "know" the trigger rules: lowReadiness requires 3 consecutive days; we only have today low.
        // Therefore the reason must be highAccumulatedFatigue, and deload should reduce load & set count.
        
        let lowReadinessToday = 40
        let fatigueDeloadMon = Engine.recommendSession(
            date: mondayAfterDST,
            userProfile: userCommercial,
            plan: plan,
            history: history,
            readiness: lowReadinessToday,
            calendar: laCalendar
        )
        
        XCTAssertTrue(fatigueDeloadMon.isDeload)
        XCTAssertEqual(fatigueDeloadMon.deloadReason, .highAccumulatedFatigue)
        
        // Bench deload should reduce sets from 4 -> 3 and reduce intensity by 15%.
        let benchDeload = fatigueDeloadMon.exercises.first { $0.exercise.id == bench.id }!
        XCTAssertEqual(benchDeload.sets.count, 3)
        let expectedTopLoadDeload = (topSet.targetLoad * (1.0 - 0.15)).rounded(using: .standardPounds)
        XCTAssertEqual(benchDeload.sets[0].targetLoad, expectedTopLoadDeload)
        
        // ===== 4) Dirty / out-of-order history input should not change results =====
        
        let older = CompletedSession(
            date: laCalendar.date(byAdding: .day, value: -10, to: mondayAfterDST)!,
            templateId: upperId,
            name: "Upper",
            exerciseResults: [],
            startedAt: laCalendar.date(byAdding: .day, value: -10, to: mondayAfterDST)!,
            previousLiftStates: liftStates
        )
        
        let newer = CompletedSession(
            date: laCalendar.date(byAdding: .day, value: -3, to: mondayAfterDST)!,
            templateId: upperId,
            name: "Upper",
            exerciseResults: [],
            startedAt: laCalendar.date(byAdding: .day, value: -3, to: mondayAfterDST)!,
            previousLiftStates: liftStates
        )
        
        let historySorted = WorkoutHistory(sessions: [newer, older], liftStates: liftStates, readinessHistory: readinessHistory, recentVolumeByDate: volumeByDate)
        let historyUnsorted = WorkoutHistory(sessions: [older, newer], liftStates: liftStates, readinessHistory: readinessHistory, recentVolumeByDate: volumeByDate)
        
        let planSorted = Engine.recommendSession(date: mondayAfterDST, userProfile: userCommercial, plan: plan, history: historySorted, readiness: 80, calendar: laCalendar)
        let planUnsorted = Engine.recommendSession(date: mondayAfterDST, userProfile: userCommercial, plan: plan, history: historyUnsorted, readiness: 80, calendar: laCalendar)
        XCTAssertEqual(planSorted, planUnsorted)
        
        // ===== 5) Warmups + partial sessions should not corrupt state =====
        
        let partialSets: [SetResult] = [
            SetResult(reps: 8, load: .pounds(135), rirObserved: 5, completed: true, isWarmup: true),
            SetResult(reps: 0, load: .pounds(225), rirObserved: 0, completed: true, isWarmup: false), // invalid: "completed" but 0 reps
            SetResult(reps: 8, load: .pounds(225), rirObserved: 0, completed: false, isWarmup: false), // invalid: not completed
        ]
        let partialExercise = ExerciseSessionResult(exerciseId: bench.id, prescription: benchRx, sets: partialSets, order: 0)
        let partialSession = CompletedSession(
            date: mondayAfterDST,
            templateId: upperId,
            name: "Upper Partial",
            exerciseResults: [partialExercise],
            startedAt: mondayAfterDST,
            previousLiftStates: liftStates
        )
        
        let updated = Engine.updateLiftState(afterSession: partialSession)
        let updatedBench = updated.first { $0.exerciseId == bench.id }!
        
        // No valid working sets -> state should remain unchanged.
        XCTAssertEqual(updatedBench.lastWorkingWeight, liftStates[bench.id]!.lastWorkingWeight)
        XCTAssertEqual(updatedBench.rollingE1RM, liftStates[bench.id]!.rollingE1RM, accuracy: 1e-9)
        
        // ===== 6) Substitution collisions: don't substitute to an exercise already in the template =====
        
        let collisionId = UUID(uuidString: "00000000-0000-0000-0000-00000000C011")!
        let a = Exercise(id: "a", name: "A (barbell only)", equipment: .barbell, primaryMuscles: [.chest], movementPattern: .horizontalPush)
        let b = Exercise(id: "b", name: "B (dumbbell)", equipment: .dumbbell, primaryMuscles: [.chest], movementPattern: .horizontalPush)
        let c = Exercise(id: "c", name: "C (machine)", equipment: .chestPressMachine, primaryMuscles: [.chest], movementPattern: .horizontalPush)
        
        let collisionTemplate = WorkoutTemplate(
            id: collisionId,
            name: "Collision",
            exercises: [
                TemplateExercise(exercise: a, prescription: .hypertrophy, order: 0),
                TemplateExercise(exercise: b, prescription: .hypertrophy, order: 1),
            ]
        )
        
        let collisionPlan = TrainingPlan(
            name: "Collision Plan",
            templates: [collisionId: collisionTemplate],
            schedule: .rotation(order: [collisionId]),
            progressionPolicies: [a.id: .none, b.id: .none],
            inSessionPolicies: [:],
            substitutionPool: [b, c], // "b" is best substitute but is already in template; should pick "c"
            deloadConfig: nil,
            loadRoundingPolicy: .standardPounds
        )
        
        let dumbbellOnly = UserProfile(
            sex: .male,
            experience: .intermediate,
            goals: [.hypertrophy],
            weeklyFrequency: 3,
            availableEquipment: EquipmentAvailability(available: [.dumbbell, .bench, .bodyweight, .chestPressMachine]),
            preferredUnit: .pounds
        )
        
        let collisionSession = Engine.recommendSession(
            date: mondayAfterDST,
            userProfile: dumbbellOnly,
            plan: collisionPlan,
            history: WorkoutHistory(),
            readiness: 80,
            calendar: laCalendar
        )
        
        // We expect: A gets substituted to C (not B), so B remains.
        XCTAssertEqual(collisionSession.exercises.count, 2)
        XCTAssertEqual(collisionSession.exercises[0].exercise.id, c.id)
        XCTAssertEqual(collisionSession.exercises[1].exercise.id, b.id)
        
        // ===== 7) No substitute available: omit unexecutable exercise (don’t return junk plan) =====
        
        let noneId = UUID(uuidString: "00000000-0000-0000-0000-00000000B001")!
        let barbellOnly = WorkoutTemplate(id: noneId, name: "Barbell", exercises: [TemplateExercise(exercise: bench, prescription: benchRx, order: 0)])
        let nonePlan = TrainingPlan(
            name: "No substitutes plan",
            templates: [noneId: barbellOnly],
            schedule: .rotation(order: [noneId]),
            progressionPolicies: [bench.id: .none],
            inSessionPolicies: [:],
            substitutionPool: [],
            deloadConfig: nil,
            loadRoundingPolicy: .standardPounds
        )
        
        let bodyweightOnly = UserProfile(
            sex: .male,
            experience: .intermediate,
            goals: [.generalFitness],
            weeklyFrequency: 3,
            availableEquipment: .bodyweightOnly,
            preferredUnit: .pounds
        )
        
        let noneSession = Engine.recommendSession(date: mondayAfterDST, userProfile: bodyweightOnly, plan: nonePlan, history: WorkoutHistory(), readiness: 80, calendar: laCalendar)
        XCTAssertTrue(noneSession.exercises.isEmpty)
        
        // ===== 8) Mid-session equipment change: replan remaining exercises (template bypass) =====
        
        // Start session with commercial equipment.
        let fullUpper = Engine.recommendSession(date: mondayAfterDST, userProfile: userCommercial, plan: plan, history: history, readiness: 80, calendar: laCalendar)
        XCTAssertEqual(fullUpper.templateId, upperId)
        XCTAssertEqual(fullUpper.exercises.map(\.exercise.id), [bench.id, row.id])
        
        // Complete the bench portion (simplified: just log the top set).
        let benchOnlyResult = ExerciseSessionResult(
            exerciseId: bench.id,
            prescription: benchRx,
            sets: [SetResult(reps: 5, load: fullUpper.exercises[0].sets[0].targetLoad, rirObserved: 1, completed: true)],
            order: 0
        )
        let benchOnlySession = CompletedSession(
            date: mondayAfterDST,
            templateId: upperId,
            name: "Upper (partial)",
            exerciseResults: [benchOnlyResult],
            startedAt: mondayAfterDST,
            wasDeload: false,
            previousLiftStates: history.liftStates,
            readinessScore: 80
        )
        
        // Update lift states and use them for replanning remaining work.
        let updatedStates = Engine.updateLiftState(afterSession: benchOnlySession)
        var updatedStateMap = history.liftStates
        for st in updatedStates { updatedStateMap[st.exerciseId] = st }
        let postBenchHistory = WorkoutHistory(
            sessions: history.sessions,
            liftStates: updatedStateMap,
            readinessHistory: history.readinessHistory,
            recentVolumeByDate: history.recentVolumeByDate
        )
        
        // Equipment outage: barbell unavailable.
        let userNoBarbell = UserProfile(
            id: "u",
            sex: .male,
            experience: .intermediate,
            goals: [.strength],
            weeklyFrequency: 3,
            availableEquipment: EquipmentAvailability(available: [.dumbbell, .bench, .bodyweight]),
            preferredUnit: .pounds
        )
        
        // Replan remaining exercises for the same template, excluding bench.
        let remaining = Engine.recommendSessionForTemplate(
            date: mondayAfterDST,
            templateId: upperId,
            userProfile: userNoBarbell,
            plan: plan,
            history: postBenchHistory,
            readiness: 80,
            excludingExerciseIds: [bench.id],
            calendar: laCalendar
        )
        
        XCTAssertEqual(remaining.templateId, upperId)
        XCTAssertEqual(remaining.exercises.count, 1)
        XCTAssertTrue(userNoBarbell.availableEquipment.isAvailable(remaining.exercises[0].exercise.equipment))
        XCTAssertEqual(remaining.exercises[0].exercise.id, dbRow.id) // should swap row -> db_row
        XCTAssertGreaterThan(remaining.exercises[0].sets[0].targetLoad.value, 0) // must not propose 0
        
        // ===== 9) Serialization/back-compat: encode/decode must preserve behavior =====
        
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let decoder = JSONDecoder()
        
        let planData = try encoder.encode(plan)
        let historyData = try encoder.encode(postBenchHistory)
        
        let decodedPlan = try decoder.decode(TrainingPlan.self, from: planData)
        let decodedHistory = try decoder.decode(WorkoutHistory.self, from: historyData)
        
        let p1 = Engine.recommendSession(date: mondayAfterDST, userProfile: userCommercial, plan: plan, history: postBenchHistory, readiness: 80, calendar: laCalendar)
        let p2 = Engine.recommendSession(date: mondayAfterDST, userProfile: userCommercial, plan: decodedPlan, history: decodedHistory, readiness: 80, calendar: laCalendar)
        XCTAssertEqual(p1, p2)
        
        // Back-compat: inSessionPolicies missing should decode to empty.
        let legacyJSON = """
        {
          "id": "00000000-0000-0000-0000-00000000AAAA",
          "name": "Legacy",
          "templates": {},
          "schedule": { "type": "manual" },
          "progressionPolicies": {},
          "substitutionPool": [],
          "deloadConfig": null,
          "loadRoundingPolicy": { "increment": 2.5, "unit": "lb", "mode": "nearest" },
          "createdAt": "2026-01-01T00:00:00Z"
        }
        """
        let legacyPlan = try decoder.decode(TrainingPlan.self, from: Data(legacyJSON.utf8))
        XCTAssertTrue(legacyPlan.inSessionPolicies.isEmpty)
        
        // ===== 10) Long hiatus / detraining: ramp load down deterministically =====
        
        let hiatusId = UUID(uuidString: "00000000-0000-0000-0000-00000000D301")!
        let hiatusTemplate = WorkoutTemplate(
            id: hiatusId,
            name: "Hiatus",
            exercises: [TemplateExercise(exercise: bench, prescription: benchRx, order: 0)]
        )
        
        let hiatusPlan = TrainingPlan(
            name: "Hiatus Plan",
            templates: [hiatusId: hiatusTemplate],
            schedule: .rotation(order: [hiatusId]),
            progressionPolicies: [bench.id: .none],
            inSessionPolicies: [:],
            substitutionPool: [],
            deloadConfig: nil,
            loadRoundingPolicy: .standardPounds
        )
        
        let sixtyDaysAgo = laCalendar.date(byAdding: .day, value: -60, to: mondayAfterDST)!
        let hiatusHistory = WorkoutHistory(
            sessions: [],
            liftStates: [
                bench.id: LiftState(exerciseId: bench.id, lastWorkingWeight: .pounds(200), rollingE1RM: 200, lastSessionDate: sixtyDaysAgo)
            ],
            readinessHistory: [],
            recentVolumeByDate: [:]
        )
        
        let hiatusSession = Engine.recommendSession(
            date: mondayAfterDST,
            userProfile: userCommercial,
            plan: hiatusPlan,
            history: hiatusHistory,
            readiness: 80,
            calendar: laCalendar
        )
        
        // 60 days -> 20% detraining reduction
        XCTAssertEqual(hiatusSession.exercises.count, 1)
        XCTAssertEqual(hiatusSession.exercises[0].sets[0].targetLoad, .pounds(160))
        
        // ===== Golden master mini-snapshot (detect unintended drift) =====
        // Keep this intentionally short and high-signal.
        let snapshot = [
            "mon.template=\(plannedMon.templateId!.uuidString)",
            "bench.top=\(topSet.targetLoad.description)",
            "bench.backoff=\(expectedBackoff.description)",
            "fatigue.deloadReason=\(fatigueDeloadMon.deloadReason!.rawValue)",
            "midSession.remainingExercise=\(remaining.exercises.first!.exercise.id)",
            "hiatus.bench=\(hiatusSession.exercises[0].sets[0].targetLoad.description)"
        ].joined(separator: "\n")
        
        XCTAssertEqual(snapshot, [
            "mon.template=00000000-0000-0000-0000-00000000D201",
            "bench.top=225 lb",
            "bench.backoff=210 lb",
            "fatigue.deloadReason=high_accumulated_fatigue",
            "midSession.remainingExercise=db_row",
            "hiatus.bench=160 lb"
        ].joined(separator: "\n"))
    }
}

