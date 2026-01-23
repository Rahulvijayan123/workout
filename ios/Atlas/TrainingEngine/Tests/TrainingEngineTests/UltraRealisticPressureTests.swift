import XCTest
@testable import TrainingEngine

final class UltraRealisticPressureTests: XCTestCase {
    
    // MARK: - Deterministic RNG (splitmix64)
    
    private struct SeededRNG {
        private var state: UInt64
        
        init(seed: UInt64) {
            self.state = seed != 0 ? seed : 0x9E3779B97F4A7C15
        }
        
        mutating func nextUInt64() -> UInt64 {
            state &+= 0x9E3779B97F4A7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
            z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
            return z ^ (z >> 31)
        }
        
        mutating func nextDouble01() -> Double {
            let v = nextUInt64() >> 11
            return Double(v) / Double(1 << 53)
        }
        
        mutating func int(in range: ClosedRange<Int>) -> Int {
            let lower = range.lowerBound
            let upper = range.upperBound
            if lower == upper { return lower }
            let span = UInt64(upper - lower + 1)
            return lower + Int(nextUInt64() % span)
        }
    }
    
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
    
    // MARK: - Targeted Edge Cases
    
    func testScheduleDrift_RotationDoesNotAdvanceWhenWorkoutsAreMissed() {
        // Rotation schedules should advance only when a workout is completed (i.e., shows up in history).
        // If the user misses days, the next workout should remain the same.
        
        let aId = UUID(uuidString: "00000000-0000-0000-0000-0000000000A1")!
        let bId = UUID(uuidString: "00000000-0000-0000-0000-0000000000B2")!
        let cId = UUID(uuidString: "00000000-0000-0000-0000-0000000000C3")!
        
        let bench = Exercise(
            id: "bench",
            name: "Bench Press",
            equipment: .barbell,
            primaryMuscles: [.chest],
            secondaryMuscles: [.triceps],
            movementPattern: .horizontalPush
        )
        
        let p = SetPrescription(setCount: 3, targetRepsRange: 5...5, targetRIR: 2, increment: .pounds(5))
        let templateA = WorkoutTemplate(id: aId, name: "A", exercises: [TemplateExercise(exercise: bench, prescription: p, order: 0)])
        let templateB = WorkoutTemplate(id: bId, name: "B", exercises: [TemplateExercise(exercise: bench, prescription: p, order: 0)])
        let templateC = WorkoutTemplate(id: cId, name: "C", exercises: [TemplateExercise(exercise: bench, prescription: p, order: 0)])
        
        let plan = TrainingPlan(
            id: UUID(uuidString: "00000000-0000-0000-0000-00000000F00D")!,
            name: "Rotation",
            templates: [aId: templateA, bId: templateB, cId: templateC],
            schedule: .rotation(order: [aId, bId, cId]),
            progressionPolicies: [bench.id: .none],
            inSessionPolicies: [bench.id: .none],
            substitutionPool: [],
            deloadConfig: nil,
            loadRoundingPolicy: .standardPounds,
            createdAt: day(makeDate(year: 2026, month: 1, day: 1))
        )
        
        let user = UserProfile(
            id: "u",
            sex: .male,
            experience: .intermediate,
            goals: [.strength],
            weeklyFrequency: 4,
            availableEquipment: .commercialGym,
            preferredUnit: .pounds
        )
        
        let start = day(makeDate(year: 2026, month: 1, day: 3))
        
        // User last completed template A on start day.
        let sessionA = CompletedSession(
            date: start,
            templateId: aId,
            name: "A",
            exerciseResults: [],
            startedAt: start
        )
        
        var history = WorkoutHistory(sessions: [sessionA], liftStates: [:], readinessHistory: [], recentVolumeByDate: [:])
        
        // Next workout should be B.
        let next1 = Engine.recommendSession(date: day(calendar.date(byAdding: .day, value: 1, to: start)!), userProfile: user, plan: plan, history: history, readiness: 80)
        XCTAssertEqual(next1.templateId, bId)
        
        // User misses several days (no session recorded) — next workout should STILL be B.
        let next2 = Engine.recommendSession(date: day(calendar.date(byAdding: .day, value: 5, to: start)!), userProfile: user, plan: plan, history: history, readiness: 80)
        XCTAssertEqual(next2.templateId, bId)
        
        // Once user actually completes B, next becomes C.
        let sessionB = CompletedSession(
            date: day(calendar.date(byAdding: .day, value: 5, to: start)!),
            templateId: bId,
            name: "B",
            exerciseResults: [],
            startedAt: day(calendar.date(byAdding: .day, value: 5, to: start)!)
        )
        history = WorkoutHistory(sessions: [sessionB, sessionA], liftStates: [:], readinessHistory: [], recentVolumeByDate: [:])
        
        let next3 = Engine.recommendSession(date: day(calendar.date(byAdding: .day, value: 6, to: start)!), userProfile: user, plan: plan, history: history, readiness: 80)
        XCTAssertEqual(next3.templateId, cId)
    }
    
    func testEquipmentOutage_RequiresPlanRewriteToAvailableSubstitute() {
        // If an exercise's equipment is not available (e.g., barbell bench in a dumbbell-only gym),
        // the engine should be able to produce an executable plan via substitution.
        
        let tId = UUID(uuidString: "00000000-0000-0000-0000-00000000E001")!
        
        let barbellBench = Exercise(
            id: "bb_bench",
            name: "Barbell Bench Press",
            equipment: .barbell,
            primaryMuscles: [.chest],
            secondaryMuscles: [.triceps, .frontDelts],
            movementPattern: .horizontalPush
        )
        
        let dumbbellBench = Exercise(
            id: "db_bench",
            name: "Dumbbell Bench Press",
            equipment: .dumbbell,
            primaryMuscles: [.chest],
            secondaryMuscles: [.triceps, .frontDelts],
            movementPattern: .horizontalPush
        )
        
        let prescription = SetPrescription(setCount: 3, targetRepsRange: 8...12, targetRIR: 2, increment: .pounds(5))
        let template = WorkoutTemplate(id: tId, name: "Push", exercises: [TemplateExercise(exercise: barbellBench, prescription: prescription, order: 0)])
        
        let plan = TrainingPlan(
            id: UUID(uuidString: "00000000-0000-0000-0000-00000000E002")!,
            name: "Equipment outage plan",
            templates: [tId: template],
            schedule: .rotation(order: [tId]),
            progressionPolicies: [barbellBench.id: .doubleProgression(config: .default)],
            inSessionPolicies: [barbellBench.id: .rirAutoregulation(config: .default)],
            substitutionPool: [dumbbellBench],
            deloadConfig: nil,
            loadRoundingPolicy: .standardPounds
        )
        
        let commercialUser = UserProfile(
            id: "u",
            sex: .male,
            experience: .intermediate,
            goals: [.hypertrophy],
            weeklyFrequency: 4,
            availableEquipment: .commercialGym,
            preferredUnit: .pounds
        )
        
        let noBarbell = EquipmentAvailability(available: [.dumbbell, .bench, .bodyweight])
        let outageUser = UserProfile(
            id: "u",
            sex: .male,
            experience: .intermediate,
            goals: [.hypertrophy],
            weeklyFrequency: 4,
            availableEquipment: noBarbell,
            preferredUnit: .pounds
        )
        
        let date = day(makeDate(year: 2026, month: 2, day: 12))
        let history = WorkoutHistory(sessions: [], liftStates: [:], readinessHistory: [], recentVolumeByDate: [:])
        
        let normalPlan = Engine.recommendSession(date: date, userProfile: commercialUser, plan: plan, history: history, readiness: 80)
        XCTAssertEqual(normalPlan.exercises.first?.exercise.id, barbellBench.id)
        
        let outagePlan = Engine.recommendSession(date: date, userProfile: outageUser, plan: plan, history: history, readiness: 80)
        
        // Under outage, the session must still be executable with available equipment.
        XCTAssertEqual(outagePlan.exercises.count, 1)
        XCTAssertTrue(outageUser.availableEquipment.isAvailable(outagePlan.exercises[0].exercise.equipment))
        
        // Strong expectation: we should actually swap to the dumbbell bench (plan rewrite).
        XCTAssertEqual(outagePlan.exercises[0].exercise.id, dumbbellBench.id)
    }
    
    func testPlateau_RepeatedFailuresCauseLoadReductionUnderDoubleProgression() {
        // "Plateau" here is modeled as repeated failures (below rep minimum) at the same load.
        // Double progression should deload after N consecutive failures.
        
        let tId = UUID(uuidString: "00000000-0000-0000-0000-00000000A1A7")!
        let curl = Exercise(
            id: "curl",
            name: "Dumbbell Curl",
            equipment: .dumbbell,
            primaryMuscles: [.biceps],
            secondaryMuscles: [.forearms],
            movementPattern: .elbowFlexion
        )
        
        let prescription = SetPrescription(setCount: 3, targetRepsRange: 8...12, targetRIR: 2, increment: .pounds(5))
        let template = WorkoutTemplate(id: tId, name: "Arms", exercises: [TemplateExercise(exercise: curl, prescription: prescription, order: 0)])
        
        let dpConfig = DoubleProgressionConfig(
            sessionsAtTopBeforeIncrease: 1,
            loadIncrement: .pounds(5),
            deloadPercentage: 0.10,
            failuresBeforeDeload: 2
        )
        
        let plan = TrainingPlan(
            id: UUID(uuidString: "00000000-0000-0000-0000-00000000A1A8")!,
            name: "Plateau test plan",
            templates: [tId: template],
            schedule: .rotation(order: [tId]),
            progressionPolicies: [curl.id: .doubleProgression(config: dpConfig)],
            inSessionPolicies: [curl.id: .none],
            substitutionPool: [],
            deloadConfig: nil,
            loadRoundingPolicy: .standardPounds
        )
        
        let user = UserProfile(
            id: "u",
            sex: .male,
            experience: .intermediate,
            goals: [.hypertrophy],
            weeklyFrequency: 3,
            availableEquipment: .commercialGym,
            preferredUnit: .pounds
        )
        
        let day1 = day(makeDate(year: 2026, month: 2, day: 1))
        let day2 = day(makeDate(year: 2026, month: 2, day: 4))
        let day3 = day(makeDate(year: 2026, month: 2, day: 7))
        
        var liftStates: [String: LiftState] = [
            curl.id: LiftState(exerciseId: curl.id, lastWorkingWeight: .pounds(100))
        ]
        
        func failedSession(on date: Date, previous: [String: LiftState]) -> CompletedSession {
            let sets: [SetResult] = [
                SetResult(reps: 6, load: .pounds(100), rirObserved: 0, completed: true),
                SetResult(reps: 6, load: .pounds(100), rirObserved: 0, completed: true),
                SetResult(reps: 6, load: .pounds(100), rirObserved: 0, completed: true),
            ]
            let ex = ExerciseSessionResult(exerciseId: curl.id, prescription: prescription, sets: sets, order: 0)
            return CompletedSession(
                date: date,
                templateId: tId,
                name: "Arms",
                exerciseResults: [ex],
                startedAt: date,
                wasDeload: false,
                previousLiftStates: previous
            )
        }
        
        // After first failure session.
        let s1 = failedSession(on: day1, previous: liftStates)
        let updated1 = Engine.updateLiftState(afterSession: s1)
        for st in updated1 { liftStates[st.exerciseId] = st }
        
        // After second consecutive failure.
        let s2 = failedSession(on: day2, previous: liftStates)
        let updated2 = Engine.updateLiftState(afterSession: s2)
        for st in updated2 { liftStates[st.exerciseId] = st }
        
        let history = WorkoutHistory(
            sessions: [s2, s1],
            liftStates: liftStates,
            readinessHistory: [],
            recentVolumeByDate: [:]
        )
        
        let plan3 = Engine.recommendSession(date: day3, userProfile: user, plan: plan, history: history, readiness: 80)
        XCTAssertEqual(plan3.exercises.count, 1)
        
        // Should deload the load (100 * 0.90 = 90) due to failuresBeforeDeload = 2.
        XCTAssertEqual(plan3.exercises[0].sets[0].targetLoad.value, 90, accuracy: 0.001)
        XCTAssertEqual(plan3.exercises[0].sets[0].targetLoad.unit, LoadUnit.pounds)
        
        // Target reps should reset to lower bound on failure.
        XCTAssertEqual(plan3.exercises[0].sets[0].targetReps, prescription.targetRepsRange.lowerBound)
    }
    
    func testMultiUnit_UpdateLiftState_ConvertsPriorE1RMValuesWhenUnitChanges() throws {
        // Realistic: user switches from lb logging to kg logging mid-program.
        // Engine must not mix units when smoothing rollingE1RM or checking trends.
        
        let squat = Exercise.barbellSquat
        let prescription = SetPrescription(setCount: 1, targetRepsRange: 1...1, targetRIR: 0, increment: .kilograms(2.5))
        
        let prevDate = day(makeDate(year: 2026, month: 3, day: 1))
        let date = day(makeDate(year: 2026, month: 3, day: 8))
        
        // Previous state is in pounds.
        let prevState = LiftState(
            exerciseId: squat.id,
            lastWorkingWeight: .pounds(220),
            rollingE1RM: 220,
            failureCount: 0,
            lastDeloadDate: nil,
            trend: .stable,
            e1rmHistory: [E1RMSample(date: prevDate, value: 220)]
        )
        
        // New session is logged in kilograms (1 rep, so e1RM == weight).
        let set = SetResult(reps: 1, load: .kilograms(100), rirObserved: 0, completed: true)
        let ex = ExerciseSessionResult(exerciseId: squat.id, prescription: prescription, sets: [set], order: 0)
        let session = CompletedSession(
            date: date,
            templateId: nil,
            name: "Unit switch",
            exerciseResults: [ex],
            startedAt: date,
            wasDeload: false,
            previousLiftStates: [squat.id: prevState]
        )
        
        let updated = Engine.updateLiftState(afterSession: session)
        let st = try XCTUnwrap(updated.first(where: { $0.exerciseId == squat.id }))
        
        // Must adopt the session unit for last working weight.
        XCTAssertEqual(st.lastWorkingWeight.unit, LoadUnit.kilograms)
        
        // rollingE1RM must be smoothed in consistent units (convert 220 lb -> kg before smoothing).
        // 220 lb = 99.790224 kg.
        let prevKg = Load.pounds(220).converted(to: .kilograms).value
        let expected = 0.3 * 100.0 + 0.7 * prevKg
        XCTAssertEqual(st.rollingE1RM, expected, accuracy: 1e-6)
        
        // History should also be converted to the new unit (no mixed-unit artifacts).
        XCTAssertEqual(st.e1rmHistory.count, 2)
        XCTAssertEqual(st.e1rmHistory[0].value, prevKg, accuracy: 1e-6)
        XCTAssertEqual(st.e1rmHistory[1].value, 100.0, accuracy: 1e-6)
    }
    
    func testMultiUnit_RecommendSession_OutputsLoadsInRoundingPolicyUnit() throws {
        // If a plan is configured to round in kg, session output should use kg loads
        // even if lastWorkingWeight was stored in lb.
        
        let tId = UUID(uuidString: "00000000-0000-0000-0000-00000000B001")!
        let squat = Exercise.barbellSquat
        
        let prescription = SetPrescription(setCount: 3, targetRepsRange: 5...5, targetRIR: 2, increment: .kilograms(2.5))
        let template = WorkoutTemplate(id: tId, name: "Squat", exercises: [TemplateExercise(exercise: squat, prescription: prescription, order: 0)])
        
        let plan = TrainingPlan(
            id: UUID(uuidString: "00000000-0000-0000-0000-00000000B002")!,
            name: "kg plan",
            templates: [tId: template],
            schedule: .rotation(order: [tId]),
            progressionPolicies: [squat.id: .none],
            inSessionPolicies: [squat.id: .none],
            substitutionPool: [],
            deloadConfig: nil,
            loadRoundingPolicy: .standardKilograms
        )
        
        let user = UserProfile(
            id: "u",
            sex: .male,
            experience: .intermediate,
            goals: [.strength],
            weeklyFrequency: 3,
            availableEquipment: .commercialGym,
            preferredUnit: .kilograms
        )
        
        let history = WorkoutHistory(
            sessions: [],
            liftStates: [squat.id: LiftState(exerciseId: squat.id, lastWorkingWeight: .pounds(220), rollingE1RM: 220)],
            readinessHistory: [],
            recentVolumeByDate: [:]
        )
        
        let date = day(makeDate(year: 2026, month: 3, day: 10))
        let sessionPlan = Engine.recommendSession(date: date, userProfile: user, plan: plan, history: history, readiness: 80)
        
        let set0 = try XCTUnwrap(sessionPlan.exercises.first?.sets.first)
        XCTAssertEqual(set0.targetLoad.unit, LoadUnit.kilograms)
        
        // 220 lb ~ 99.79 kg, rounded to nearest 1.25 kg -> 100.0 kg.
        XCTAssertEqual(set0.targetLoad.value, 100.0, accuracy: 1e-6)
    }
    
    // MARK: - Integrated “Real Life” Simulation
    
    func testIntegratedSimulation_16Weeks_MissedWorkouts_EquipmentOutages_UnitSwitch_DeterministicAndSafe() {
        // This is intentionally a "realistic abuse test":
        // - Day-level simulation across weeks
        // - Missed workouts (schedule drift)
        // - Equipment outages (should remain executable via substitutions)
        // - Mid-run unit switch (lb -> kg)
        // - Noisy performance + in-session adjustments
        // And we require determinism + invariants.
        
        func makePlan(loadRounding: LoadRoundingPolicy, increment: Load) -> TrainingPlan {
            let pushId = UUID(uuidString: "00000000-0000-0000-0000-00000000C001")!
            let pullId = UUID(uuidString: "00000000-0000-0000-0000-00000000C002")!
            let legsId = UUID(uuidString: "00000000-0000-0000-0000-00000000C003")!
            
            // Main lifts (some require barbell).
            let bench = Exercise(id: "bench", name: "Bench Press", equipment: .barbell, primaryMuscles: [.chest], secondaryMuscles: [.triceps], movementPattern: .horizontalPush)
            let row = Exercise(id: "row", name: "Barbell Row", equipment: .barbell, primaryMuscles: [.back], secondaryMuscles: [.biceps], movementPattern: .horizontalPull)
            let squat = Exercise.barbellSquat
            
            // Substitutions (dumbbell/bodyweight/machine).
            let dbBench = Exercise(id: "db_bench", name: "Dumbbell Bench Press", equipment: .dumbbell, primaryMuscles: [.chest], secondaryMuscles: [.triceps], movementPattern: .horizontalPush)
            let pushup = Exercise(id: "pushup", name: "Push-Up", equipment: .bodyweight, primaryMuscles: [.chest], secondaryMuscles: [.triceps], movementPattern: .horizontalPush)
            let dbRow = Exercise(id: "db_row", name: "Dumbbell Row", equipment: .dumbbell, primaryMuscles: [.back], secondaryMuscles: [.biceps], movementPattern: .horizontalPull)
            let legPress = Exercise(id: "leg_press", name: "Leg Press", equipment: .legPressMachine, primaryMuscles: [.quadriceps, .glutes], secondaryMuscles: [.hamstrings], movementPattern: .squat)
            let goblet = Exercise(id: "goblet_squat", name: "Goblet Squat", equipment: .dumbbell, primaryMuscles: [.quadriceps, .glutes], secondaryMuscles: [.hamstrings], movementPattern: .squat)
            
            let benchRx = SetPrescription(setCount: 3, targetRepsRange: 6...10, targetRIR: 2, increment: increment)
            let rowRx = SetPrescription(setCount: 3, targetRepsRange: 6...10, targetRIR: 2, increment: increment)
            let squatRx = SetPrescription(setCount: 3, targetRepsRange: 5...5, targetRIR: 2, increment: increment)
            
            let push = WorkoutTemplate(
                id: pushId,
                name: "Push",
                exercises: [TemplateExercise(exercise: bench, prescription: benchRx, order: 0)]
            )
            let pull = WorkoutTemplate(
                id: pullId,
                name: "Pull",
                exercises: [TemplateExercise(exercise: row, prescription: rowRx, order: 0)]
            )
            let legs = WorkoutTemplate(
                id: legsId,
                name: "Legs",
                exercises: [TemplateExercise(exercise: squat, prescription: squatRx, order: 0)]
            )
            
            let deload = DeloadConfig(
                intensityReduction: 0.15,
                volumeReduction: 1,
                scheduledDeloadWeeks: 6,
                readinessThreshold: 50,
                lowReadinessDaysRequired: 3
            )
            
            return TrainingPlan(
                id: UUID(uuidString: "00000000-0000-0000-0000-00000000C0F0")!,
                name: "Realistic simulation plan",
                templates: [pushId: push, pullId: pull, legsId: legs],
                schedule: .rotation(order: [pushId, pullId, legsId]),
                progressionPolicies: [
                    bench.id: .doubleProgression(config: .default),
                    row.id: .linearProgression(config: .default),
                    squat.id: .topSetBackoff(config: .default),
                ],
                inSessionPolicies: [
                    bench.id: .rirAutoregulation(config: .default),
                    row.id: .none,
                    squat.id: .rirAutoregulation(config: .default),
                ],
                substitutionPool: [dbBench, pushup, dbRow, legPress, goblet],
                deloadConfig: deload,
                loadRoundingPolicy: loadRounding
            )
        }
        
        func run(seed: UInt64) -> (sessions: Int, deloads: Int, finalStates: [String: LiftState]) {
            var rng = SeededRNG(seed: seed)
            
            let start = day(makeDate(year: 2026, month: 1, day: 1))
            let totalDays = 7 * 16
            
            let planLb = makePlan(loadRounding: .standardPounds, increment: .pounds(5))
            let planKg = makePlan(loadRounding: .standardKilograms, increment: .kilograms(2.5))
            
            var history = WorkoutHistory(sessions: [], liftStates: [:], readinessHistory: [], recentVolumeByDate: [:])
            var sessionsCount = 0
            var deloadCount = 0
            
            for dayOffset in 0..<totalDays {
                let date = day(calendar.date(byAdding: .day, value: dayOffset, to: start)!)
                
                // Unit switch after 8 weeks.
                let useKg = dayOffset >= (7 * 8)
                let plan = useKg ? planKg : planLb
                
                // Equipment swings: commercial (0), home gym (1), bodyweight-only (2), "no barbell but dumbbells" (3)
                let equipMode = rng.int(in: 0...3)
                let equipment: EquipmentAvailability = {
                    switch equipMode {
                    case 0: return .commercialGym
                    case 1: return .homeGym
                    case 2: return .bodyweightOnly
                    default:
                        return EquipmentAvailability(available: [.dumbbell, .bench, .bodyweight])
                    }
                }()
                
                // Readiness: noisy but with occasional low streaks.
                let baseReadiness = 60 + rng.int(in: -25...25)
                let readiness = max(0, min(100, baseReadiness))
                
                // Record readiness every day (realistic).
                var readinessHistory = history.readinessHistory
                readinessHistory.append(ReadinessRecord(date: date, score: readiness))
                
                // Missed workouts: ~45% chance to train on any given day.
                let trainsToday = rng.nextDouble01() < 0.45
                
                // Persist daily readiness even on non-training days.
                history = WorkoutHistory(
                    sessions: history.sessions,
                    liftStates: history.liftStates,
                    readinessHistory: readinessHistory,
                    recentVolumeByDate: history.recentVolumeByDate
                )
                
                guard trainsToday else { continue }
                
                let user = UserProfile(
                    id: "u",
                    sex: .male,
                    experience: .intermediate,
                    goals: [.strength],
                    weeklyFrequency: 4,
                    availableEquipment: equipment,
                    preferredUnit: useKg ? .kilograms : .pounds
                )
                
                let sessionPlan = Engine.recommendSession(
                    date: date,
                    userProfile: user,
                    plan: plan,
                    history: history,
                    readiness: readiness
                )
                
                // Invariants: if we got a session, it must be executable with current equipment.
                XCTAssertNotNil(sessionPlan.templateId)
                XCTAssertFalse(sessionPlan.exercises.isEmpty)
                for exPlan in sessionPlan.exercises {
                    XCTAssertTrue(user.availableEquipment.isAvailable(exPlan.exercise.equipment))
                    for set in exPlan.sets {
                        XCTAssertGreaterThanOrEqual(set.targetLoad.value, 0)
                        XCTAssertTrue(set.targetLoad.value.isFinite)
                        XCTAssertGreaterThanOrEqual(set.targetReps, 1)
                        // Output loads should match plan rounding unit after the unit switch.
                        XCTAssertEqual(set.targetLoad.unit, plan.loadRoundingPolicy.unit)
                    }
                }
                
                // Simulate completion with noisy performance and in-session adjustments.
                var exerciseResults: [ExerciseSessionResult] = []
                var sessionVolumeKg: Double = 0
                
                for (order, exPlan) in sessionPlan.exercises.enumerated() {
                    var plannedSets = exPlan.sets
                    var performedSets: [SetResult] = []
                    
                    for setIndex in 0..<plannedSets.count {
                        let setPlan = plannedSets[setIndex]
                        
                        // Performance model: more misses on low readiness; occasional overshoots on high readiness.
                        let repNoise: Int = {
                            if readiness < 45 { return rng.int(in: -3...0) }
                            if readiness < 65 { return rng.int(in: -2...1) }
                            return rng.int(in: -1...2)
                        }()
                        let reps = max(0, setPlan.targetReps + repNoise)
                        
                        let rirNoise: Int = {
                            if readiness < 45 { return rng.int(in: -2...0) }
                            if readiness < 65 { return rng.int(in: -1...1) }
                            return rng.int(in: -1...2)
                        }()
                        let observedRIR = max(0, setPlan.targetRIR + rirNoise)
                        
                        let result = SetResult(
                            reps: reps,
                            load: setPlan.targetLoad,
                            rirObserved: observedRIR,
                            completed: reps > 0
                        )
                        performedSets.append(result)
                        
                        // Update volume in kg (unit-neutral).
                        sessionVolumeKg += result.load.inKilograms * Double(result.reps)
                        
                        // In-session adjustment for next set.
                        if setIndex + 1 < plannedSets.count {
                            plannedSets[setIndex + 1] = Engine.adjustDuringSession(
                                currentSetResult: result,
                                plannedNextSet: plannedSets[setIndex + 1]
                            )
                        }
                    }
                    
                    exerciseResults.append(ExerciseSessionResult(
                        exerciseId: exPlan.exercise.id,
                        prescription: exPlan.prescription,
                        sets: performedSets,
                        order: order
                    ))
                }
                
                let completed = CompletedSession(
                    date: date,
                    templateId: sessionPlan.templateId,
                    name: sessionPlan.templateId.map { plan.templates[$0]?.name ?? "Workout" } ?? "Workout",
                    exerciseResults: exerciseResults,
                    startedAt: date,
                    wasDeload: sessionPlan.isDeload,
                    previousLiftStates: history.liftStates,
                    readinessScore: readiness
                )
                
                let updatedStates = Engine.updateLiftState(afterSession: completed)
                var newLiftStates = history.liftStates
                for st in updatedStates {
                    newLiftStates[st.exerciseId] = st
                }
                
                // Persist volume + session to history.
                var volumeByDate = history.recentVolumeByDate
                volumeByDate[date] = (volumeByDate[date] ?? 0) + sessionVolumeKg
                
                var sessions = history.sessions
                sessions.insert(completed, at: 0)
                
                history = WorkoutHistory(
                    sessions: sessions,
                    liftStates: newLiftStates,
                    readinessHistory: history.readinessHistory,
                    recentVolumeByDate: volumeByDate
                )
                
                sessionsCount += 1
                if completed.wasDeload { deloadCount += 1 }
            }
            
            return (sessionsCount, deloadCount, history.liftStates)
        }
        
        let r1 = run(seed: 0xC0FFEE)
        let r2 = run(seed: 0xC0FFEE)
        
        XCTAssertEqual(r1.sessions, r2.sessions)
        XCTAssertEqual(r1.deloads, r2.deloads)
        XCTAssertEqual(r1.finalStates, r2.finalStates)
    }
}

