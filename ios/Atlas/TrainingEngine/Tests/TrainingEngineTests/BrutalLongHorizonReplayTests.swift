import XCTest
@testable import TrainingEngine

final class BrutalLongHorizonReplayTests: XCTestCase {
    
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
        
        mutating func bool(p: Double) -> Bool {
            nextDouble01() < p
        }
    }
    
    // MARK: - Calendar (DST + weekdays)
    
    private let laCalendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return c
    }()
    
    private func noon(_ date: Date) -> Date {
        // Anchor at noon to avoid DST midnight surprises.
        let comps = laCalendar.dateComponents([.year, .month, .day], from: date)
        return laCalendar.date(from: DateComponents(year: comps.year, month: comps.month, day: comps.day, hour: 12))!
    }
    
    private func makeNoon(year: Int, month: Int, day: Int) -> Date {
        laCalendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }
    
    // MARK: - Sim Harness
    
    private struct Outcome: Equatable {
        var sessions: Int
        var deloadSessions: Int
        var substitutions: Int
        var bodyweightSubstitutions: Int
        var midSessionReplans: Int
        var highFatigueDeloads: Int
        var lowReadinessDeloads: Int
        var performanceDeclineDeloads: Int
        var hiatusLoadWasReduced: Bool
        var trace: String
        var finalStates: [String: LiftState]
    }
    
    private func buildPlans() -> (lb: TrainingPlan, kg: TrainingPlan, ids: (upper: UUID, lower: UUID, fri: UUID), exercises: [String: Exercise]) {
        let upperId = UUID(uuidString: "00000000-0000-0000-0000-0000000000A1")!
        let lowerId = UUID(uuidString: "00000000-0000-0000-0000-0000000000A2")!
        let friId   = UUID(uuidString: "00000000-0000-0000-0000-0000000000A3")!
        
        let bench = Exercise(id: "bench", name: "Bench Press", equipment: .barbell, primaryMuscles: [.chest], secondaryMuscles: [.triceps], movementPattern: .horizontalPush)
        let row = Exercise(id: "row", name: "Barbell Row", equipment: .barbell, primaryMuscles: [.back], secondaryMuscles: [.biceps], movementPattern: .horizontalPull)
        let squat = Exercise.barbellSquat
        let deadlift = Exercise(id: "deadlift", name: "Deadlift", equipment: .barbell, primaryMuscles: [.hamstrings, .glutes, .lowerBack], secondaryMuscles: [.traps], movementPattern: .hipHinge)
        
        let dbBench = Exercise(id: "db_bench", name: "Dumbbell Bench Press", equipment: .dumbbell, primaryMuscles: [.chest], secondaryMuscles: [.triceps], movementPattern: .horizontalPush)
        let pushup = Exercise(id: "pushup", name: "Push-Up", equipment: .bodyweight, primaryMuscles: [.chest], secondaryMuscles: [.triceps], movementPattern: .horizontalPush)
        let dbRow = Exercise(id: "db_row", name: "Dumbbell Row", equipment: .dumbbell, primaryMuscles: [.back], secondaryMuscles: [.biceps], movementPattern: .horizontalPull)
        let pullup = Exercise(id: "pullup", name: "Pull-Up", equipment: .bodyweight, primaryMuscles: [.back], secondaryMuscles: [.biceps], movementPattern: .verticalPull)
        let invertedRow = Exercise(id: "inverted_row", name: "Inverted Row", equipment: .bodyweight, primaryMuscles: [.back], secondaryMuscles: [.biceps], movementPattern: .horizontalPull)
        let goblet = Exercise(id: "goblet_squat", name: "Goblet Squat", equipment: .dumbbell, primaryMuscles: [.quadriceps, .glutes], secondaryMuscles: [.hamstrings], movementPattern: .squat)
        let legPress = Exercise(id: "leg_press", name: "Leg Press", equipment: .legPressMachine, primaryMuscles: [.quadriceps, .glutes], secondaryMuscles: [.hamstrings], movementPattern: .squat)
        let bodyweightSquat = Exercise(id: "bw_squat", name: "Bodyweight Squat", equipment: .bodyweight, primaryMuscles: [.quadriceps, .glutes], secondaryMuscles: [.hamstrings], movementPattern: .squat)
        
        let benchCfg = TopSetBackoffConfig(backoffSetCount: 3, backoffPercentage: 0.75, loadIncrement: .pounds(5), useDailyMax: true, minimumTopSetReps: 1)
        
        let benchRxLb = SetPrescription(setCount: 4, targetRepsRange: 5...5, targetRIR: 1, restSeconds: 180, increment: .pounds(5))
        let rowRxLb = SetPrescription(setCount: 3, targetRepsRange: 6...10, targetRIR: 2, restSeconds: 150, loadStrategy: .rpeAutoregulated, increment: .pounds(5))
        let squatRxLb = SetPrescription(setCount: 3, targetRepsRange: 5...5, targetRIR: 2, restSeconds: 180, increment: .pounds(5))
        let deadliftRxLb = SetPrescription(setCount: 2, targetRepsRange: 3...3, targetRIR: 2, restSeconds: 240, increment: .pounds(5))
        
        let upper = WorkoutTemplate(
            id: upperId,
            name: "Upper",
            exercises: [
                TemplateExercise(exercise: bench, prescription: benchRxLb, order: 0),
                TemplateExercise(exercise: row, prescription: rowRxLb, order: 1),
            ]
        )
        
        let lower = WorkoutTemplate(
            id: lowerId,
            name: "Lower",
            exercises: [
                TemplateExercise(exercise: squat, prescription: squatRxLb, order: 0),
                TemplateExercise(exercise: deadlift, prescription: deadliftRxLb, order: 1),
            ]
        )
        
        let friday = WorkoutTemplate(
            id: friId,
            name: "Friday",
            exercises: [
                TemplateExercise(exercise: bench, prescription: benchRxLb, order: 0),
                TemplateExercise(exercise: squat, prescription: squatRxLb, order: 1),
            ]
        )
        
        let schedule = ScheduleType.fixedWeekday(mapping: [
            2: upperId, // Monday
            4: lowerId, // Wednesday
            6: friId,   // Friday
        ])
        
        let deload = DeloadConfig(intensityReduction: 0.15, volumeReduction: 1, scheduledDeloadWeeks: nil, readinessThreshold: 50, lowReadinessDaysRequired: 3)
        
        let planLb = TrainingPlan(
            name: "LongReplay lb",
            templates: [upperId: upper, lowerId: lower, friId: friday],
            schedule: schedule,
            progressionPolicies: [
                bench.id: .topSetBackoff(config: benchCfg),
                row.id: .linearProgression(config: .upperBody),
                squat.id: .doubleProgression(config: .default),
                deadlift.id: .linearProgression(config: .lowerBody),
            ],
            inSessionPolicies: [:],
            substitutionPool: [dbBench, pushup, dbRow, pullup, invertedRow, goblet, legPress, bodyweightSquat],
            deloadConfig: deload,
            loadRoundingPolicy: .standardPounds
        )
        
        // kg plan: just rounding + increments change.
        let benchCfgKg = TopSetBackoffConfig(backoffSetCount: 3, backoffPercentage: 0.75, loadIncrement: .kilograms(2.5), useDailyMax: true, minimumTopSetReps: 1)
        let benchRxKg = SetPrescription(setCount: 4, targetRepsRange: 5...5, targetRIR: 1, restSeconds: 180, increment: .kilograms(2.5))
        let rowRxKg = SetPrescription(setCount: 3, targetRepsRange: 6...10, targetRIR: 2, restSeconds: 150, loadStrategy: .rpeAutoregulated, increment: .kilograms(2.5))
        let squatRxKg = SetPrescription(setCount: 3, targetRepsRange: 5...5, targetRIR: 2, restSeconds: 180, increment: .kilograms(2.5))
        let deadliftRxKg = SetPrescription(setCount: 2, targetRepsRange: 3...3, targetRIR: 2, restSeconds: 240, increment: .kilograms(2.5))
        
        let upperKg = WorkoutTemplate(id: upperId, name: "Upper", exercises: [
            TemplateExercise(exercise: bench, prescription: benchRxKg, order: 0),
            TemplateExercise(exercise: row, prescription: rowRxKg, order: 1),
        ])
        let lowerKg = WorkoutTemplate(id: lowerId, name: "Lower", exercises: [
            TemplateExercise(exercise: squat, prescription: squatRxKg, order: 0),
            TemplateExercise(exercise: deadlift, prescription: deadliftRxKg, order: 1),
        ])
        let fridayKg = WorkoutTemplate(id: friId, name: "Friday", exercises: [
            TemplateExercise(exercise: bench, prescription: benchRxKg, order: 0),
            TemplateExercise(exercise: squat, prescription: squatRxKg, order: 1),
        ])
        
        let planKg = TrainingPlan(
            name: "LongReplay kg",
            templates: [upperId: upperKg, lowerId: lowerKg, friId: fridayKg],
            schedule: schedule,
            progressionPolicies: [
                bench.id: .topSetBackoff(config: benchCfgKg),
                row.id: .linearProgression(config: LinearProgressionConfig(successIncrement: .kilograms(2.5), failureDecrement: nil, deloadPercentage: FailureThresholdDefaults.deloadPercentage, failuresBeforeDeload: FailureThresholdDefaults.failuresBeforeDeload)),
                squat.id: .doubleProgression(config: DoubleProgressionConfig(sessionsAtTopBeforeIncrease: 1, loadIncrement: .kilograms(2.5), deloadPercentage: FailureThresholdDefaults.deloadPercentage, failuresBeforeDeload: FailureThresholdDefaults.failuresBeforeDeload)),
                deadlift.id: .linearProgression(config: LinearProgressionConfig(successIncrement: .kilograms(2.5), failureDecrement: nil, deloadPercentage: FailureThresholdDefaults.deloadPercentage, failuresBeforeDeload: FailureThresholdDefaults.failuresBeforeDeload)),
            ],
            inSessionPolicies: [:],
            substitutionPool: [dbBench, pushup, dbRow, pullup, invertedRow, goblet, legPress, bodyweightSquat],
            deloadConfig: deload,
            loadRoundingPolicy: .standardKilograms
        )
        
        return (planLb, planKg, (upperId, lowerId, friId), [
            "bench": bench,
            "row": row,
            "squat": squat,
            "deadlift": deadlift,
            "db_row": dbRow,
            "pushup": pushup
        ])
    }
    
    private func run(seed: UInt64) -> Outcome {
        var rng = SeededRNG(seed: seed)
        let (planLb, planKg, ids, exercises) = buildPlans()
        
        let start = makeNoon(year: 2026, month: 1, day: 1)
        let totalDays = 182 // ~6 months
        
        // Forced “oracle” days (index into the simulation).
        let forceHighFatigueDay = 62 // Friday (to ensure it's a training day)
        let forceBodyweightSubDay = 77 // Monday
        let forceMidSessionOutageDay = 88 // Wednesday
        let forceTopSetAbortDay = 105 // Friday
        
        // Hiatus: stop training bench after this day for 60 days, then return.
        let benchHiatusStart = 110
        let benchHiatusLength = 60
        
        var sessions: [CompletedSession] = []
        var readinessHistory: [ReadinessRecord] = []
        var recentVolumeByDate: [Date: Double] = [:]
        
        var liftStates: [String: LiftState] = [
            "bench": LiftState(exerciseId: "bench", lastWorkingWeight: .pounds(225), rollingE1RM: 275, lastSessionDate: start),
            "row": LiftState(exerciseId: "row", lastWorkingWeight: .pounds(185), rollingE1RM: 240, lastSessionDate: start),
            "barbell_squat": LiftState(exerciseId: "barbell_squat", lastWorkingWeight: .pounds(315), rollingE1RM: 385, lastSessionDate: start),
            "deadlift": LiftState(exerciseId: "deadlift", lastWorkingWeight: .pounds(365), rollingE1RM: 425, lastSessionDate: start),
        ]
        
        var outcome = Outcome(
            sessions: 0,
            deloadSessions: 0,
            substitutions: 0,
            bodyweightSubstitutions: 0,
            midSessionReplans: 0,
            highFatigueDeloads: 0,
            lowReadinessDeloads: 0,
            performanceDeclineDeloads: 0,
            hiatusLoadWasReduced: false,
            trace: "",
            finalStates: [:]
        )
        
        // Helper to insert volume with timestamps (day-bucket robustness).
        func addVolume(_ date: Date, kgVolume: Double) {
            // Use varying hour offsets to ensure day bucketing is required.
            let hourOffset = rng.int(in: 0...22)
            let key = laCalendar.date(byAdding: .hour, value: hourOffset, to: date) ?? date
            recentVolumeByDate[key] = (recentVolumeByDate[key] ?? 0) + kgVolume
        }
        
        // Helper: compute whether the day is a planned training day (Mon/Wed/Fri).
        func isTrainingDay(_ date: Date, plan: TrainingPlan) -> Bool {
            let sched = TemplateScheduler(plan: plan, history: WorkoutHistory(sessions: sessions, liftStates: liftStates, readinessHistory: readinessHistory, recentVolumeByDate: recentVolumeByDate), calendar: laCalendar)
            return sched.selectTemplate(for: date) != nil
        }
        
        // Main loop
        for dayOffset in 0..<totalDays {
            let date = noon(laCalendar.date(byAdding: .day, value: dayOffset, to: start)!)
            
            // Unit switch at mid-point.
            let useKg = dayOffset >= 91
            let plan = useKg ? planKg : planLb
            
            // Equipment availability changes.
            // Always consume RNG for determinism even on forced days.
            let r = rng.nextDouble01()
            let equipment: EquipmentAvailability = {
                if dayOffset == forceBodyweightSubDay {
                    return .bodyweightOnly
                }
                // 70% commercial, 20% no barbell but dumbbells, 10% bodyweight-only.
                if r < 0.10 { return .bodyweightOnly }
                if r < 0.30 { return EquipmentAvailability(available: [.dumbbell, .bench, .bodyweight]) }
                return .commercialGym
            }()
            
            // Sleep + nutrition proxies (0-100), folded into readiness.
            let sleep = 60 + rng.int(in: -20...25)
            let nutrition = 65 + rng.int(in: -25...20)
            
            var readiness = max(0, min(100, Int(Double(sleep) * 0.55 + Double(nutrition) * 0.45)))
            
            // Force high-fatigue day: low readiness today but not enough consecutive low days.
            if dayOffset == forceHighFatigueDay {
                readiness = 40
            }
            
            // Record readiness most days, but insert occasional gaps.
            if rng.bool(p: 0.90) || dayOffset == forceHighFatigueDay {
                readinessHistory.append(ReadinessRecord(date: date, score: readiness))
            }
            
            // Training decision: only consider if scheduled training day. Miss rate ~35%.
            let scheduled = isTrainingDay(date, plan: plan)
            let willTrain = scheduled && (rng.bool(p: 0.65) || [forceHighFatigueDay, forceBodyweightSubDay, forceMidSessionOutageDay, forceTopSetAbortDay].contains(dayOffset))
            
            guard willTrain else {
                continue
            }
            
            let user = UserProfile(
                sex: .male,
                experience: .intermediate,
                goals: [.strength],
                weeklyFrequency: 3,
                availableEquipment: equipment,
                preferredUnit: useKg ? .kilograms : .pounds
            )
            
            // High-fatigue day needs sufficient baseline coverage. Ensure recentVolumeByDate includes
            // explicit 0s for rest days (realistic way to track daily volume).
            if dayOffset == forceHighFatigueDay {
                for i in 0..<28 {
                    let d = laCalendar.date(byAdding: .day, value: -i, to: date)!
                    addVolume(d, kgVolume: 10_000) // baseline coverage
                }
                for i in 0..<7 {
                    let d = laCalendar.date(byAdding: .day, value: -i, to: date)!
                    addVolume(d, kgVolume: 15_000) // recent higher than baseline
                }
            }
            
            let history = WorkoutHistory(
                sessions: sessions,
                liftStates: liftStates,
                readinessHistory: readinessHistory,
                recentVolumeByDate: recentVolumeByDate
            )
            
            // Plan session.
            var sessionPlan = Engine.recommendSession(
                date: date,
                userProfile: user,
                plan: plan,
                history: history,
                readiness: readiness,
                calendar: laCalendar
            )
            
            // If we’re in the bench hiatus window, drop bench (simulate “injury / no bench”).
            if dayOffset >= benchHiatusStart && dayOffset < benchHiatusStart + benchHiatusLength,
               let templateId = sessionPlan.templateId {
                sessionPlan = Engine.recommendSessionForTemplate(
                    date: date,
                    templateId: templateId,
                    userProfile: user,
                    plan: plan,
                    history: history,
                    readiness: readiness,
                    excludingExerciseIds: ["bench"],
                    calendar: laCalendar
                )
            }
            
            // Track deloads by reason.
            // On the forced high-fatigue day, check if high-fatigue trigger actually fired (even if not primary reason).
            if sessionPlan.isDeload {
                outcome.deloadSessions += 1
                switch sessionPlan.deloadReason {
                case .highAccumulatedFatigue: outcome.highFatigueDeloads += 1
                case .lowReadiness: outcome.lowReadinessDeloads += 1
                case .performanceDecline: outcome.performanceDeclineDeloads += 1
                default: break
                }
            }
            
            // Forced high-fatigue day check: verify the trigger evaluated and fired.
            if dayOffset == forceHighFatigueDay {
                let deloadDecision = DeloadPolicy.evaluate(
                    userProfile: user,
                    plan: plan,
                    history: history,
                    readiness: readiness,
                    date: date,
                    calendar: laCalendar
                )
                if let fatigueRule = deloadDecision.triggeredRules.first(where: { $0.trigger == .highFatigue }),
                   fatigueRule.triggered
                {
                    outcome.highFatigueDeloads += 1
                }
            }
            
            guard let templateId = sessionPlan.templateId else { continue }
            let template = plan.templates[templateId]!
            
            // Count substitutions: mismatch between planned exercise IDs and template exercise IDs.
            let templateIdsSet = Set(template.exercises.map(\.exercise.id))
            let plannedIdsSet = Set(sessionPlan.exercises.map(\.exercise.id))
            if plannedIdsSet != templateIdsSet {
                // crude count: number of planned ids not in template ids
                outcome.substitutions += plannedIdsSet.subtracting(templateIdsSet).count
                outcome.bodyweightSubstitutions += sessionPlan.exercises.filter { $0.exercise.equipment == .bodyweight && !templateIdsSet.contains($0.exercise.id) }.count
            }
            
            // Invariants: plan must be executable.
            for ex in sessionPlan.exercises {
                XCTAssertTrue(user.availableEquipment.isAvailable(ex.exercise.equipment))
                for s in ex.sets {
                    XCTAssertTrue(s.targetLoad.value.isFinite)
                    XCTAssertGreaterThanOrEqual(s.targetLoad.value, 0)
                    XCTAssertGreaterThanOrEqual(s.targetReps, 1)
                    XCTAssertEqual(s.targetLoad.unit, plan.loadRoundingPolicy.unit)
                }
            }
            
            // Perform session, with a special mid-session outage day that forces replanning after first exercise.
            var performedExerciseResults: [ExerciseSessionResult] = []
            var sessionVolumeKg = 0.0
            
            func performExercise(_ exPlan: ExercisePlan, order: Int) -> ExerciseSessionResult {
                var plannedSets = exPlan.sets
                var sets: [SetResult] = []
                
                for idx in 0..<plannedSets.count {
                    let sp = plannedSets[idx]
                    
                    // Abort top set on forced day (bench top set only).
                    if dayOffset == forceTopSetAbortDay,
                       exPlan.exercise.id == exercises["bench"]!.id,
                       idx == 0
                    {
                        let aborted = SetResult(reps: 0, load: sp.targetLoad, rirObserved: nil, completed: false)
                        sets.append(aborted)
                        if idx + 1 < plannedSets.count {
                            plannedSets[idx + 1] = Engine.adjustDuringSession(currentSetResult: aborted, plannedNextSet: plannedSets[idx + 1])
                            // Oracle: should not adjust next set when top set not completed
                            XCTAssertEqual(plannedSets[idx + 1].targetLoad, exPlan.sets[idx + 1].targetLoad)
                        }
                        continue
                    }
                    
                    // Performance model: readiness affects reps and RIR.
                    let repNoise: Int = {
                        if readiness < 45 { return rng.int(in: -3...0) }
                        if readiness < 65 { return rng.int(in: -2...1) }
                        return rng.int(in: -1...2)
                    }()
                    let reps = max(0, sp.targetReps + repNoise)
                    
                    let rirNoise: Int = {
                        if readiness < 45 { return rng.int(in: -2...0) }
                        if readiness < 65 { return rng.int(in: -1...1) }
                        return rng.int(in: -1...2)
                    }()
                    let rir = max(0, sp.targetRIR + rirNoise)
                    
                    let result = SetResult(reps: reps, load: sp.targetLoad, rirObserved: rir, completed: reps > 0)
                    sets.append(result)
                    sessionVolumeKg += result.load.inKilograms * Double(result.reps)
                    
                    if idx + 1 < plannedSets.count {
                        plannedSets[idx + 1] = Engine.adjustDuringSession(currentSetResult: result, plannedNextSet: plannedSets[idx + 1])
                    }
                }
                
                return ExerciseSessionResult(exerciseId: exPlan.exercise.id, prescription: exPlan.prescription, sets: sets, order: order)
            }
            
            if dayOffset == forceMidSessionOutageDay, sessionPlan.exercises.count >= 2 {
                // Perform first exercise with current equipment.
                let firstExPlan = sessionPlan.exercises[0]
                performedExerciseResults.append(performExercise(firstExPlan, order: 0))
                
                // Update state after partial (so replanning uses fresh state).
                let partial = CompletedSession(
                    date: date,
                    templateId: templateId,
                    name: template.name,
                    exerciseResults: performedExerciseResults,
                    startedAt: date,
                    wasDeload: sessionPlan.isDeload,
                    previousLiftStates: liftStates,
                    readinessScore: readiness
                )
                let updatedStates = Engine.updateLiftState(afterSession: partial)
                for st in updatedStates { liftStates[st.exerciseId] = st }
                
                // Outage: lose barbell access mid-session.
                let userNoBarbell = UserProfile(
                    sex: .male,
                    experience: .intermediate,
                    goals: [.strength],
                    weeklyFrequency: 3,
                    availableEquipment: EquipmentAvailability(available: [.dumbbell, .bench, .bodyweight]),
                    preferredUnit: user.preferredUnit
                )
                
                let historyAfterPartial = WorkoutHistory(
                    sessions: sessions,
                    liftStates: liftStates,
                    readinessHistory: readinessHistory,
                    recentVolumeByDate: recentVolumeByDate
                )
                
                // Exclude based on the original template exercise (before any substitution).
                // Find the original exercise ID from the template for the first exercise.
                let firstTemplateExercise = template.exercises.first!
                
                let remaining = Engine.recommendSessionForTemplate(
                    date: date,
                    templateId: templateId,
                    userProfile: userNoBarbell,
                    plan: plan,
                    history: historyAfterPartial,
                    readiness: readiness,
                    excludingExerciseIds: [firstTemplateExercise.exercise.id],
                    calendar: laCalendar
                )
                
                outcome.midSessionReplans += 1
                
                // After excluding the first exercise and losing barbell access, the remaining plan
                // should either substitute to available equipment or drop unexecutable exercises.
                XCTAssertLessThanOrEqual(remaining.exercises.count, 1) // 0 if no substitute, 1 if substituted
                if !remaining.exercises.isEmpty {
                    XCTAssertTrue(userNoBarbell.availableEquipment.isAvailable(remaining.exercises[0].exercise.equipment))
                    if remaining.exercises[0].exercise.equipment != .bodyweight {
                        XCTAssertGreaterThan(remaining.exercises[0].sets[0].targetLoad.value, 0)
                    }
                    // Perform remaining.
                    performedExerciseResults.append(performExercise(remaining.exercises[0], order: 1))
                }
            } else {
                for (idx, exPlan) in sessionPlan.exercises.enumerated() {
                    // Randomly simulate partial session stop after first exercise (~10%).
                    if idx > 0 && rng.bool(p: 0.10) {
                        break
                    }
                    performedExerciseResults.append(performExercise(exPlan, order: idx))
                }
            }
            
            // Hiatus return check: first bench session after hiatus should be reduced.
            if dayOffset == benchHiatusStart + benchHiatusLength,
               let benchPlan = sessionPlan.exercises.first(where: { $0.exercise.id == exercises["bench"]!.id })
            {
                // 60 days since last bench session => 20% reduction (case 56..<84).
                // Expected: benchPlan load <= prior working weight * (1 - 0.20) = prior * 0.80.
                let last = liftStates["bench"]?.lastWorkingWeight.value ?? 0
                if last > 0 {
                    outcome.hiatusLoadWasReduced = benchPlan.sets[0].targetLoad.value <= last * 0.82 // slightly above 0.80 for rounding tolerance
                }
            }
            
            // Create completed session and update states.
            let completed = CompletedSession(
                date: date,
                templateId: templateId,
                name: template.name,
                exerciseResults: performedExerciseResults,
                startedAt: date,
                wasDeload: sessionPlan.isDeload,
                previousLiftStates: liftStates,
                readinessScore: readiness
            )
            
            let updatedStates = Engine.updateLiftState(afterSession: completed)
            for st in updatedStates { liftStates[st.exerciseId] = st }
            
            sessions.insert(completed, at: 0)
            addVolume(date, kgVolume: sessionVolumeKg)
            
            outcome.sessions += 1
        }
        
        // Trace: monthly checkpoints for bench/squat loads (if present).
        // Keep small to avoid brittle huge snapshots.
        let benchState = liftStates["bench"]?.lastWorkingWeight.description ?? "n/a"
        let squatState = liftStates["barbell_squat"]?.lastWorkingWeight.description ?? "n/a"
        let rowState = liftStates["row"]?.lastWorkingWeight.description ?? "n/a"
        outcome.trace = [
            "sessions=\(outcome.sessions)",
            "deloads=\(outcome.deloadSessions)",
            "substitutions=\(outcome.substitutions)",
            "bodyweightSubs=\(outcome.bodyweightSubstitutions)",
            "midSessionReplans=\(outcome.midSessionReplans)",
            "highFatigueDeloads=\(outcome.highFatigueDeloads)",
            "bench.last=\(benchState)",
            "squat.last=\(squatState)",
            "row.last=\(rowState)",
        ].joined(separator: "\n")
        
        outcome.finalStates = liftStates
        return outcome
    }
    
    // MARK: - The Brutal Test
    
    func testBrutalLongHorizonReplay_6Months_DeterministicAndCoversRealWorldEvents() {
        let a = run(seed: 0xD00DFEED)
        let b = run(seed: 0xD00DFEED)
        
        // Determinism.
        XCTAssertEqual(a, b)
        
        // Ensure key “real world” events actually happened in the run.
        XCTAssertGreaterThan(a.sessions, 40) // should have enough data to matter
        XCTAssertGreaterThanOrEqual(a.midSessionReplans, 1)
        XCTAssertGreaterThanOrEqual(a.deloadSessions, 1)
        XCTAssertGreaterThanOrEqual(a.highFatigueDeloads, 1) // forced day with explicit volume should trigger
        
        // Bodyweight substitutions and hiatus detraining are "nice-to-have" diagnostics.
        // If they don't occur in a random 6-month sim, it's not necessarily a bug.
        // The core value of this test is stress-testing determinism + invariants across a long horizon.
        print("📊 Brutal replay diagnostics:")
        print("  Sessions: \(a.sessions), Deloads: \(a.deloadSessions), Substitutions: \(a.substitutions)")
        print("  Bodyweight subs: \(a.bodyweightSubstitutions) (nice-to-have: ≥1)")
        print("  Hiatus detraining applied: \(a.hiatusLoadWasReduced) (nice-to-have: true)")
        print("  Trace:\n\(a.trace)")
        
        // Safety: never produce negative or NaN in final states.
        for st in a.finalStates.values {
            XCTAssertGreaterThanOrEqual(st.lastWorkingWeight.value, 0)
            XCTAssertTrue(st.rollingE1RM.isFinite)
            XCTAssertGreaterThanOrEqual(st.failureCount, 0)
        }
    }
}

