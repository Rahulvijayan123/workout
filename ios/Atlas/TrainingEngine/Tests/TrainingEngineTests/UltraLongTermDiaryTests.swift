import XCTest
@testable import TrainingEngine

final class UltraLongTermDiaryTests: XCTestCase {
    
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
    
    // MARK: - Calendar (DST-safe)
    
    private let laCalendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return c
    }()
    
    private func noon(_ date: Date) -> Date {
        let comps = laCalendar.dateComponents([.year, .month, .day], from: date)
        return laCalendar.date(from: DateComponents(year: comps.year, month: comps.month, day: comps.day, hour: 12))!
    }
    
    private func makeNoon(year: Int, month: Int, day: Int) -> Date {
        laCalendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }
    
    // MARK: - Supervised long-term overload (oracle math)
    
    func testLongTerm_SupervisedProgressiveOverload_LinearAndDoubleProgression() {
        let tId = UUID(uuidString: "00000000-0000-0000-0000-00000000AB10")!
        
        let lp = Exercise(
            id: "lp",
            name: "Linear Progression Lift",
            equipment: .barbell,
            primaryMuscles: [.back],
            secondaryMuscles: [.biceps],
            movementPattern: .horizontalPull
        )
        
        let dp = Exercise(
            id: "dp",
            name: "Double Progression Lift",
            equipment: .barbell,
            primaryMuscles: [.chest],
            secondaryMuscles: [.triceps],
            movementPattern: .horizontalPush
        )
        
        let lpRx = SetPrescription(setCount: 3, targetRepsRange: 5...5, targetRIR: 2, restSeconds: 120, increment: .pounds(5))
        let dpRx = SetPrescription(setCount: 3, targetRepsRange: 6...10, targetRIR: 2, restSeconds: 120, increment: .pounds(5))
        
        let template = WorkoutTemplate(
            id: tId,
            name: "Supervised",
            exercises: [
                TemplateExercise(exercise: lp, prescription: lpRx, order: 0),
                TemplateExercise(exercise: dp, prescription: dpRx, order: 1),
            ]
        )
        
        let plan = TrainingPlan(
            id: UUID(uuidString: "00000000-0000-0000-0000-00000000AB11")!,
            name: "Supervised Long Term",
            templates: [tId: template],
            schedule: .rotation(order: [tId]),
            progressionPolicies: [
                lp.id: .linearProgression(config: LinearProgressionConfig(
                    successIncrement: .pounds(5),
                    failureDecrement: nil,
                    deloadPercentage: 0.10,
                    failuresBeforeDeload: 3
                )),
                dp.id: .doubleProgression(config: DoubleProgressionConfig(
                    sessionsAtTopBeforeIncrease: 1,
                    loadIncrement: .pounds(5),
                    deloadPercentage: 0.10,
                    failuresBeforeDeload: 3
                )),
            ],
            inSessionPolicies: [:],
            substitutionPool: [],
            deloadConfig: nil, // isolate progression math (no readiness-based deloads)
            loadRoundingPolicy: .standardPounds,
            createdAt: makeNoon(year: 2025, month: 1, day: 1)
        )
        
        let user = UserProfile(
            id: "u",
            sex: .male,
            experience: .intermediate,
            goals: [.strength],
            weeklyFrequency: 3,
            availableEquipment: .commercialGym,
            preferredUnit: .pounds
        )
        
        // Initial states so the very first recommendation is non-zero and oracle-able.
        var liftStates: [String: LiftState] = [
            lp.id: LiftState(exerciseId: lp.id, lastWorkingWeight: .pounds(100), rollingE1RM: 0, lastSessionDate: nil),
            dp.id: LiftState(exerciseId: dp.id, lastWorkingWeight: .pounds(100), rollingE1RM: 0, lastSessionDate: nil),
        ]
        var sessions: [CompletedSession] = []
        
        let start = makeNoon(year: 2025, month: 1, day: 2)
        let totalSessions = 110 // >2 years at ~1 session / 2-3 days (no detraining gaps)
        
        var lastDPLoad: Load?
        
        for i in 0..<totalSessions {
            let date = noon(laCalendar.date(byAdding: .day, value: i * 2, to: start)!)
            let history = WorkoutHistory(sessions: sessions, liftStates: liftStates, readinessHistory: [], recentVolumeByDate: [:])
            let sessionPlan = Engine.recommendSession(date: date, userProfile: user, plan: plan, history: history, readiness: 80, calendar: laCalendar)
            XCTAssertEqual(sessionPlan.exercises.count, 2)
            XCTAssertFalse(sessionPlan.isDeload)
            
            // ===== Linear progression oracle =====
            // Expected load: 100 + 5 * i
            let expectedLP = Load.pounds(100 + Double(i) * 5)
            let plannedLP = sessionPlan.exercises[0]
            XCTAssertEqual(plannedLP.exercise.id, lp.id)
            XCTAssertEqual(plannedLP.sets.first?.targetLoad, expectedLP)
            XCTAssertEqual(plannedLP.sets.first?.targetReps, 5)
            
            // ===== Double progression oracle =====
            // 5-session cycles: reps 6→10 while load holds; then load increases and reps reset.
            // Note: load increments are now adaptive (training-age aware), so we assert invariants rather than a hard-coded +5.
            let cycle = i % 5
            let expectedDPReps = 6 + cycle
            let plannedDP = sessionPlan.exercises[1]
            XCTAssertEqual(plannedDP.exercise.id, dp.id)
            XCTAssertEqual(plannedDP.sets.first?.targetReps, expectedDPReps)
            
            if let current = plannedDP.sets.first?.targetLoad {
                if let last = lastDPLoad {
                    // Should never decrease when we are always successful.
                    XCTAssertGreaterThanOrEqual(current.inKilograms, last.inKilograms)
                    
                    // Load should only change when reps reset (cycle boundary).
                    if cycle != 0 {
                        XCTAssertEqual(current, last)
                    } else if i > 0 {
                        // Adaptive increments should be small and plate-friendly.
                        let diffLb = current.converted(to: .pounds).value - last.converted(to: .pounds).value
                        XCTAssertTrue([2.5, 5.0].contains(diffLb), "Unexpected DP increment: \(diffLb) lb")
                    }
                }
                lastDPLoad = current
            }
            
            // Perform the session exactly as prescribed (so we "know" what next should be).
            func perform(_ ex: ExercisePlan, order: Int) -> ExerciseSessionResult {
                let sets = ex.sets.map { sp in
                    SetResult(reps: sp.targetReps, load: sp.targetLoad, rirObserved: sp.targetRIR, completed: true)
                }
                return ExerciseSessionResult(exerciseId: ex.exercise.id, prescription: ex.prescription, sets: sets, order: order)
            }
            
            let completed = CompletedSession(
                date: date,
                templateId: sessionPlan.templateId,
                name: "Supervised",
                exerciseResults: [
                    perform(plannedLP, order: 0),
                    perform(plannedDP, order: 1),
                ],
                startedAt: date,
                wasDeload: sessionPlan.isDeload,
                previousLiftStates: liftStates,
                readinessScore: 80
            )
            
            let updated = Engine.updateLiftState(afterSession: completed)
            for st in updated { liftStates[st.exerciseId] = st }
            sessions.insert(completed, at: 0)
        }
    }
    
    // MARK: - Two-year chaotic diary replay (long-term user data)
    
    private struct DiaryOutcome: Equatable {
        var sessions: Int
        var deloadSessions: Int
        var scheduledDeloads: Int
        var lowReadinessDeloads: Int
        var highFatigueDeloads: Int
        var performanceDeclineDeloads: Int
        
        // "Progression policy deloads" (load drops while sessionPlan.isDeload == false)
        var progressionLoadDrops: Int
        
        // Monotonicity violations (success → next planned load decreases for linear/double)
        var monotonicityViolations: Int
        
        var trace: String
        var finalStates: [String: LiftState]
    }
    
    private func buildTwoYearPlans() -> (lb: TrainingPlan, kg: TrainingPlan, ids: (upper: UUID, lower: UUID, fri: UUID), tracked: Set<String>) {
        let upperId = UUID(uuidString: "00000000-0000-0000-0000-00000000AC01")!
        let lowerId = UUID(uuidString: "00000000-0000-0000-0000-00000000AC02")!
        let friId   = UUID(uuidString: "00000000-0000-0000-0000-00000000AC03")!
        
        let bench = Exercise(id: "bench", name: "Bench Press", equipment: .barbell, primaryMuscles: [.chest], secondaryMuscles: [.triceps], movementPattern: .horizontalPush)
        let row = Exercise(id: "row", name: "Barbell Row", equipment: .barbell, primaryMuscles: [.back], secondaryMuscles: [.biceps], movementPattern: .horizontalPull)
        let squat = Exercise.barbellSquat
        let deadlift = Exercise(id: "deadlift", name: "Deadlift", equipment: .barbell, primaryMuscles: [.hamstrings, .glutes, .lowerBack], secondaryMuscles: [.traps], movementPattern: .hipHinge)
        let press = Exercise(id: "press", name: "Overhead Press", equipment: .barbell, primaryMuscles: [.shoulders], secondaryMuscles: [.triceps], movementPattern: .verticalPush)
        
        let benchCfgLb = TopSetBackoffConfig(backoffSetCount: 3, backoffPercentage: 0.78, loadIncrement: .pounds(5), useDailyMax: true, minimumTopSetReps: 1)
        
        let benchRxLb = SetPrescription(setCount: 4, targetRepsRange: 5...5, targetRIR: 1, restSeconds: 180, increment: .pounds(5))
        let rowRxLb = SetPrescription(setCount: 3, targetRepsRange: 6...10, targetRIR: 2, restSeconds: 150, loadStrategy: .rpeAutoregulated, increment: .pounds(5))
        let pressRxLb = SetPrescription(setCount: 3, targetRepsRange: 5...5, targetRIR: 2, restSeconds: 150, increment: .pounds(2.5))
        let squatRxLb = SetPrescription(setCount: 3, targetRepsRange: 5...8, targetRIR: 2, restSeconds: 180, increment: .pounds(5))
        let deadliftRxLb = SetPrescription(setCount: 2, targetRepsRange: 3...3, targetRIR: 2, restSeconds: 240, increment: .pounds(5))
        
        let upper = WorkoutTemplate(id: upperId, name: "Upper", exercises: [
            TemplateExercise(exercise: bench, prescription: benchRxLb, order: 0),
            TemplateExercise(exercise: row, prescription: rowRxLb, order: 1),
            TemplateExercise(exercise: press, prescription: pressRxLb, order: 2),
        ])
        
        let lower = WorkoutTemplate(id: lowerId, name: "Lower", exercises: [
            TemplateExercise(exercise: squat, prescription: squatRxLb, order: 0),
            TemplateExercise(exercise: deadlift, prescription: deadliftRxLb, order: 1),
        ])
        
        let friday = WorkoutTemplate(id: friId, name: "Friday", exercises: [
            TemplateExercise(exercise: bench, prescription: benchRxLb, order: 0),
            TemplateExercise(exercise: squat, prescription: squatRxLb, order: 1),
            TemplateExercise(exercise: row, prescription: rowRxLb, order: 2),
        ])
        
        let schedule = ScheduleType.fixedWeekday(mapping: [
            2: upperId, // Monday
            4: lowerId, // Wednesday
            6: friId,   // Friday
        ])
        
        let deload = DeloadConfig(
            intensityReduction: 0.15,
            volumeReduction: 1,
            scheduledDeloadWeeks: 8,
            readinessThreshold: 50,
            lowReadinessDaysRequired: 3
        )
        
        let planLb = TrainingPlan(
            name: "TwoYear lb",
            templates: [upperId: upper, lowerId: lower, friId: friday],
            schedule: schedule,
            progressionPolicies: [
                bench.id: .topSetBackoff(config: benchCfgLb),
                row.id: .doubleProgression(config: DoubleProgressionConfig(sessionsAtTopBeforeIncrease: 2, loadIncrement: .pounds(5), deloadPercentage: 0.10, failuresBeforeDeload: 3)),
                press.id: .linearProgression(config: LinearProgressionConfig(successIncrement: .pounds(2.5), failureDecrement: nil, deloadPercentage: 0.10, failuresBeforeDeload: 3)),
                squat.id: .doubleProgression(config: DoubleProgressionConfig(sessionsAtTopBeforeIncrease: 1, loadIncrement: .pounds(5), deloadPercentage: 0.10, failuresBeforeDeload: 3)),
                deadlift.id: .linearProgression(config: LinearProgressionConfig(successIncrement: .pounds(5), failureDecrement: nil, deloadPercentage: 0.10, failuresBeforeDeload: 3)),
            ],
            inSessionPolicies: [
                row.id: .rirAutoregulation(config: .default)
            ],
            substitutionPool: [],
            deloadConfig: deload,
            loadRoundingPolicy: .standardPounds,
            createdAt: makeNoon(year: 2025, month: 1, day: 1)
        )
        
        // kg plan mirrors lb but with kg increments + rounding.
        let benchCfgKg = TopSetBackoffConfig(backoffSetCount: 3, backoffPercentage: 0.78, loadIncrement: .kilograms(2.5), useDailyMax: true, minimumTopSetReps: 1)
        let benchRxKg = SetPrescription(setCount: 4, targetRepsRange: 5...5, targetRIR: 1, restSeconds: 180, increment: .kilograms(2.5))
        let rowRxKg = SetPrescription(setCount: 3, targetRepsRange: 6...10, targetRIR: 2, restSeconds: 150, loadStrategy: .rpeAutoregulated, increment: .kilograms(2.5))
        let pressRxKg = SetPrescription(setCount: 3, targetRepsRange: 5...5, targetRIR: 2, restSeconds: 150, increment: .kilograms(1.25))
        let squatRxKg = SetPrescription(setCount: 3, targetRepsRange: 5...8, targetRIR: 2, restSeconds: 180, increment: .kilograms(2.5))
        let deadliftRxKg = SetPrescription(setCount: 2, targetRepsRange: 3...3, targetRIR: 2, restSeconds: 240, increment: .kilograms(2.5))
        
        let upperKg = WorkoutTemplate(id: upperId, name: "Upper", exercises: [
            TemplateExercise(exercise: bench, prescription: benchRxKg, order: 0),
            TemplateExercise(exercise: row, prescription: rowRxKg, order: 1),
            TemplateExercise(exercise: press, prescription: pressRxKg, order: 2),
        ])
        let lowerKg = WorkoutTemplate(id: lowerId, name: "Lower", exercises: [
            TemplateExercise(exercise: squat, prescription: squatRxKg, order: 0),
            TemplateExercise(exercise: deadlift, prescription: deadliftRxKg, order: 1),
        ])
        let fridayKg = WorkoutTemplate(id: friId, name: "Friday", exercises: [
            TemplateExercise(exercise: bench, prescription: benchRxKg, order: 0),
            TemplateExercise(exercise: squat, prescription: squatRxKg, order: 1),
            TemplateExercise(exercise: row, prescription: rowRxKg, order: 2),
        ])
        
        let planKg = TrainingPlan(
            name: "TwoYear kg",
            templates: [upperId: upperKg, lowerId: lowerKg, friId: fridayKg],
            schedule: schedule,
            progressionPolicies: [
                bench.id: .topSetBackoff(config: benchCfgKg),
                row.id: .doubleProgression(config: DoubleProgressionConfig(sessionsAtTopBeforeIncrease: 2, loadIncrement: .kilograms(2.5), deloadPercentage: 0.10, failuresBeforeDeload: 3)),
                press.id: .linearProgression(config: LinearProgressionConfig(successIncrement: .kilograms(1.25), failureDecrement: nil, deloadPercentage: 0.10, failuresBeforeDeload: 3)),
                squat.id: .doubleProgression(config: DoubleProgressionConfig(sessionsAtTopBeforeIncrease: 1, loadIncrement: .kilograms(2.5), deloadPercentage: 0.10, failuresBeforeDeload: 3)),
                deadlift.id: .linearProgression(config: LinearProgressionConfig(successIncrement: .kilograms(2.5), failureDecrement: nil, deloadPercentage: 0.10, failuresBeforeDeload: 3)),
            ],
            inSessionPolicies: [
                row.id: .rirAutoregulation(config: RIRAutoregulationConfig(targetRIR: 2, adjustmentPerRIR: 0.025, maxAdjustmentPerSet: 0.10, minimumLoad: .kilograms(10), allowUpwardAdjustment: true))
            ],
            substitutionPool: [],
            deloadConfig: deload,
            loadRoundingPolicy: .standardKilograms,
            createdAt: makeNoon(year: 2025, month: 1, day: 1)
        )
        
        return (planLb, planKg, (upperId, lowerId, friId), [bench.id, row.id, press.id, squat.id, deadlift.id])
    }
    
    private func runTwoYearDiary(seed: UInt64) throws -> DiaryOutcome {
        var rng = SeededRNG(seed: seed)
        let (planLb, planKg, _, tracked) = buildTwoYearPlans()
        
        let start = makeNoon(year: 2025, month: 1, day: 1)
        let totalDays = 730
        
        // Segment-based unit changes to stress lb↔kg conversion more than once.
        func useKg(for dayOffset: Int) -> Bool {
            switch dayOffset {
            case 0..<200: return false
            case 200..<420: return true
            case 420..<600: return false
            default: return true
            }
        }
        
        // Forced deload-trigger scenarios.
        // These are computed to deterministically land on scheduled training days for the fixed-weekday plan.
        let trainingWeekdays: Set<Int> = {
            if case .fixedWeekday(let mapping) = planLb.schedule {
                return Set(mapping.keys)
            }
            // Fallback (shouldn't happen for this test): assume M/W/F.
            return [2, 4, 6]
        }()
        
        func nextTrainingDayOffset(atOrAfter desired: Int) -> Int {
            var o = max(0, desired)
            while o < totalDays {
                let d = noon(laCalendar.date(byAdding: .day, value: o, to: start)!)
                let weekday = laCalendar.component(.weekday, from: d)
                if trainingWeekdays.contains(weekday) { return o }
                o += 1
            }
            return max(0, min(desired, totalDays - 1))
        }
        
        func nextSquatDayOffset(atOrAfter desired: Int) -> Int {
            // Squat appears on Wednesday + Friday templates in buildTwoYearPlans().
            var o = max(0, desired)
            while o < totalDays {
                let d = noon(laCalendar.date(byAdding: .day, value: o, to: start)!)
                let weekday = laCalendar.component(.weekday, from: d)
                if weekday == 4 || weekday == 6 { return o } // Wed or Fri
                o += 1
            }
            return max(0, min(desired, totalDays - 1))
        }
        
        let forceHighFatigueDay = nextTrainingDayOffset(atOrAfter: 180)
        let lowReadinessTriggerDay = nextTrainingDayOffset(atOrAfter: 260)
        let forceLowReadinessStreakStart = max(0, lowReadinessTriggerDay - 2) // 3 consecutive calendar days ending on a training day
        let forcePlateauStart = nextSquatDayOffset(atOrAfter: 330) // force squat failures across multiple squat occurrences
        
        var sessions: [CompletedSession] = []
        var readinessHistory: [ReadinessRecord] = []
        var recentVolumeByDate: [Date: Double] = [:]
        
        // Seed states in pounds; updateLiftState handles unit conversion when kg sessions start.
        var liftStates: [String: LiftState] = [
            "bench": LiftState(exerciseId: "bench", lastWorkingWeight: .pounds(185), rollingE1RM: 225, lastSessionDate: start),
            "row": LiftState(exerciseId: "row", lastWorkingWeight: .pounds(155), rollingE1RM: 200, lastSessionDate: start),
            "press": LiftState(exerciseId: "press", lastWorkingWeight: .pounds(95), rollingE1RM: 120, lastSessionDate: start),
            "barbell_squat": LiftState(exerciseId: "barbell_squat", lastWorkingWeight: .pounds(275), rollingE1RM: 335, lastSessionDate: start),
            "deadlift": LiftState(exerciseId: "deadlift", lastWorkingWeight: .pounds(315), rollingE1RM: 385, lastSessionDate: start),
        ]
        
        var outcome = DiaryOutcome(
            sessions: 0,
            deloadSessions: 0,
            scheduledDeloads: 0,
            lowReadinessDeloads: 0,
            highFatigueDeloads: 0,
            performanceDeclineDeloads: 0,
            progressionLoadDrops: 0,
            monotonicityViolations: 0,
            trace: "",
            finalStates: [:]
        )
        
        // Track per-exercise last planned load (for monotonicity checks).
        var lastPlannedLoad: [String: Load] = [:]
        var lastWasSuccess: [String: Bool] = [:]
        var lastUnitByExercise: [String: LoadUnit] = [:]
        var consecutiveFailures: [String: Int] = [:]
        
        func addVolume(_ date: Date, kgVolume: Double) {
            // Use timestamps to force day-bucketing logic (and timezone correctness).
            let hourOffset = rng.int(in: 0...22)
            let key = laCalendar.date(byAdding: .hour, value: hourOffset, to: date) ?? date
            recentVolumeByDate[key] = (recentVolumeByDate[key] ?? 0) + kgVolume
        }
        
        func isTrainingDay(_ date: Date, plan: TrainingPlan) -> Bool {
            let sched = TemplateScheduler(plan: plan, history: WorkoutHistory(sessions: [], liftStates: [:], readinessHistory: [], recentVolumeByDate: [:]), calendar: laCalendar)
            return sched.selectTemplate(for: date) != nil
        }
        
        // Make sure baseline coverage exists periodically (simulate "app writes 0 volume on rest days").
        func maybeWriteZeroVolume(_ date: Date) {
            if rng.bool(p: 0.25) {
                addVolume(date, kgVolume: 0)
            }
        }
        
        // JSON round-trips to simulate long-term persistence + migrations.
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        
        // Main day-by-day diary replay.
        for dayOffset in 0..<totalDays {
            let date = noon(laCalendar.date(byAdding: .day, value: dayOffset, to: start)!)
            
            let plan = useKg(for: dayOffset) ? planKg : planLb
            let preferredUnit: LoadUnit = plan.loadRoundingPolicy.unit
            
            // Sleep + nutrition proxies, folded into readiness (0-100).
            let sleep = 60 + rng.int(in: -25...25)
            let nutrition = 65 + rng.int(in: -25...20)
            var readiness = max(0, min(100, Int(Double(sleep) * 0.55 + Double(nutrition) * 0.45)))
            
            // Force low readiness streak for 3 consecutive calendar days.
            if dayOffset >= forceLowReadinessStreakStart && dayOffset < forceLowReadinessStreakStart + 3 {
                readiness = 40
            }
            
            // Force high-fatigue day: low readiness today but not enough consecutive low days.
            if dayOffset == forceHighFatigueDay {
                readiness = 40
            }
            
            // Readiness records: sometimes multiple per day, sometimes delayed/out-of-order.
            if rng.bool(p: 0.88) || (dayOffset >= forceLowReadinessStreakStart && dayOffset < forceLowReadinessStreakStart + 3) || dayOffset == forceHighFatigueDay {
                readinessHistory.append(ReadinessRecord(date: date, score: readiness))
                if rng.bool(p: 0.20) {
                    // Extra same-day record with slightly different value.
                    readinessHistory.append(ReadinessRecord(date: laCalendar.date(byAdding: .hour, value: rng.int(in: 1...20), to: date)!, score: max(0, min(100, readiness + rng.int(in: -8...8)))))
                }
                if rng.bool(p: 0.10) {
                    // Delayed sync: record yesterday today.
                    let y = laCalendar.date(byAdding: .day, value: -1, to: date)!
                    readinessHistory.append(ReadinessRecord(date: y, score: max(0, min(100, readiness + rng.int(in: -10...10)))))
                }
            }
            
            let scheduled = isTrainingDay(date, plan: plan)
            let forceTrain = (dayOffset == forceHighFatigueDay)
                || (dayOffset >= forceLowReadinessStreakStart && dayOffset < forceLowReadinessStreakStart + 3)
                || (dayOffset == forcePlateauStart)
            
            let willTrain = scheduled && (rng.bool(p: 0.68) || forceTrain)
            
            guard willTrain else {
                maybeWriteZeroVolume(date)
                continue
            }
            
            let user = UserProfile(
                id: "u",
                sex: .male,
                experience: .intermediate,
                goals: [.strength],
                weeklyFrequency: 3,
                availableEquipment: .commercialGym,
                preferredUnit: preferredUnit
            )
            
            // Force baseline volume so high-fatigue can actually trigger.
            if dayOffset == forceHighFatigueDay {
                for i in 0..<28 {
                    let d = laCalendar.date(byAdding: .day, value: -i, to: date)!
                    addVolume(d, kgVolume: 10_000)
                }
                for i in 0..<7 {
                    let d = laCalendar.date(byAdding: .day, value: -i, to: date)!
                    addVolume(d, kgVolume: 15_000)
                }
            }
            
            let history = WorkoutHistory(
                sessions: sessions,
                liftStates: liftStates,
                readinessHistory: readinessHistory,
                recentVolumeByDate: recentVolumeByDate
            )
            
            // Persist/restore every ~60 days to simulate app restarts and decoding on large histories.
            if dayOffset > 0 && dayOffset % 60 == 0 {
                let planData = try encoder.encode(plan)
                let historyData = try encoder.encode(history)
                _ = try decoder.decode(TrainingPlan.self, from: planData)
                _ = try decoder.decode(WorkoutHistory.self, from: historyData)
            }
            
            let sessionPlan = Engine.recommendSession(
                date: date,
                userProfile: user,
                plan: plan,
                history: history,
                readiness: readiness,
                calendar: laCalendar
            )
            
            guard let templateId = sessionPlan.templateId else {
                XCTFail("Expected a template on scheduled training day")
                continue
            }
            
            // Track deloads.
            if sessionPlan.isDeload {
                outcome.deloadSessions += 1
                switch sessionPlan.deloadReason {
                case .scheduledDeload: outcome.scheduledDeloads += 1
                case .lowReadiness: outcome.lowReadinessDeloads += 1
                case .highAccumulatedFatigue: outcome.highFatigueDeloads += 1
                case .performanceDecline: outcome.performanceDeclineDeloads += 1
                default: break
                }
            }
            
            // Invariants: plan must be coherent and in the plan's unit.
            for ex in sessionPlan.exercises {
                XCTAssertTrue(tracked.contains(ex.exercise.id), "Unexpected exercise id \(ex.exercise.id)")
                for s in ex.sets {
                    XCTAssertTrue(s.targetLoad.value.isFinite)
                    XCTAssertGreaterThanOrEqual(s.targetLoad.value, 0)
                    XCTAssertGreaterThanOrEqual(s.targetReps, 1)
                    XCTAssertEqual(s.targetLoad.unit, plan.loadRoundingPolicy.unit)
                }
            }
            
            // Monotonicity check for linear/double progression lifts when last session was a success,
            // no session-level deload, and no long hiatus (avoid detraining adjustments).
            for ex in sessionPlan.exercises {
                let id = ex.exercise.id
                let planned = ex.sets.first!.targetLoad
                
                // Allow readiness-based cuts (decrease_slightly) as legitimate load reductions
                let isReadinessCut = ex.recommendedAdjustmentKind == .readinessCut
                let isBreakReset = ex.recommendedAdjustmentKind == .breakReset
                let isIntentionalReduction = isReadinessCut || isBreakReset
                
                if (ex.progressionPolicy.isLinearOrDoubleProgression),
                   ex.inSessionPolicy == .none, // autoregulated sets can legitimately reduce load
                   lastWasSuccess[id] == true,
                   sessionPlan.isDeload == false,
                   !isIntentionalReduction, // readiness-based reductions are allowed
                   lastUnitByExercise[id] == planned.unit
                {
                    // If the engine thinks it's a hiatus it may reduce; skip those cases.
                    if let lastDate = liftStates[id]?.lastSessionDate {
                        let lastDay = laCalendar.startOfDay(for: lastDate)
                        let today = laCalendar.startOfDay(for: date)
                        let days = laCalendar.dateComponents([.day], from: lastDay, to: today).day ?? 0
                        // Engine applies a small detraining reduction starting at ~2 weeks.
                        if days < 14 {
                            if let prev = lastPlannedLoad[id], planned.value + 1e-9 < prev.value {
                                outcome.monotonicityViolations += 1
                            }
                        }
                    }
                }
                
                // Count "progression-policy deloads": load drops while sessionPlan.isDeload is false.
                if sessionPlan.isDeload == false,
                   let prev = lastPlannedLoad[id],
                   planned.unit == prev.unit,
                   planned.value + 1e-9 < prev.value
                {
                    outcome.progressionLoadDrops += 1
                }
                
                lastPlannedLoad[id] = planned
                lastUnitByExercise[id] = planned.unit
            }
            
            // Perform session.
            var performedExerciseResults: [ExerciseSessionResult] = []
            var sessionVolumeKg = 0.0
            
            func performExercise(_ exPlan: ExercisePlan, order: Int) -> ExerciseSessionResult {
                var plannedSets = exPlan.sets
                var sets: [SetResult] = []
                
                // Plateau event: force squat failures across multiple squat occurrences.
                let forceSquatFail = (dayOffset >= forcePlateauStart && dayOffset < forcePlateauStart + 45) && (exPlan.exercise.id == "barbell_squat")
                
                for idx in 0..<plannedSets.count {
                    let sp = plannedSets[idx]
                    
                    // Performance model: readiness affects reps and RIR; plateau overrides.
                    let reps: Int = {
                        if forceSquatFail {
                            // Force below lower bound: guarantee failure.
                            return max(0, sp.targetReps - 3)
                        }
                        let repNoise: Int = {
                            if readiness < 45 { return rng.int(in: -3...0) }
                            if readiness < 65 { return rng.int(in: -2...1) }
                            return rng.int(in: -1...2)
                        }()
                        return max(0, sp.targetReps + repNoise)
                    }()
                    
                    let rir: Int? = {
                        if sp.inSessionPolicy == .none { return nil }
                        let rirNoise: Int = {
                            if readiness < 45 { return rng.int(in: -2...0) }
                            if readiness < 65 { return rng.int(in: -1...1) }
                            return rng.int(in: -1...2)
                        }()
                        return max(0, min(5, sp.targetRIR + rirNoise))
                    }()
                    
                    // Rarely simulate an aborted set (completed=false) but keep it bounded.
                    let completed: Bool = {
                        // Plateau days are meant to be strict consecutive failures; don't "accidentally" erase them.
                        if forceSquatFail { return reps > 0 }
                        return reps > 0 && !rng.bool(p: 0.03)
                    }()
                    let result = SetResult(reps: completed ? reps : 0, load: sp.targetLoad, rirObserved: rir, completed: completed)
                    sets.append(result)
                    sessionVolumeKg += result.load.inKilograms * Double(result.reps)
                    
                    if idx + 1 < plannedSets.count {
                        plannedSets[idx + 1] = Engine.adjustDuringSession(currentSetResult: result, plannedNextSet: plannedSets[idx + 1])
                    }
                    
                    // If this is a top-set/backoff bench day, verify backoff follows daily max adjustment.
                    if exPlan.exercise.id == "bench", idx == 0, exPlan.inSessionPolicy.isTopSetDailyMax {
                        if completed && result.reps > 0 {
                            let dailyMax = E1RMCalculator.brzycki(weight: result.load.value, reps: result.reps)
                            let expected = Load(value: dailyMax * 0.78, unit: result.load.unit).rounded(using: plan.loadRoundingPolicy)
                            if plannedSets.count > 1 {
                                XCTAssertEqual(plannedSets[1].targetLoad, expected)
                            }
                        }
                    }
                }
                
                // Record success/failure for monotonicity logic.
                let lower = exPlan.prescription.targetRepsRange.lowerBound
                let working = sets.filter { $0.completed && !$0.isWarmup && $0.reps > 0 }
                let success = !working.isEmpty && working.allSatisfy { $0.reps >= lower }
                lastWasSuccess[exPlan.exercise.id] = success
                if success {
                    consecutiveFailures[exPlan.exercise.id] = 0
                } else {
                    consecutiveFailures[exPlan.exercise.id] = (consecutiveFailures[exPlan.exercise.id] ?? 0) + 1
                }
                
                return ExerciseSessionResult(exerciseId: exPlan.exercise.id, prescription: exPlan.prescription, sets: sets, order: order)
            }
            
            // Partial-session dropout (~12%): stop after first exercise.
            for (idx, exPlan) in sessionPlan.exercises.enumerated() {
                if idx > 0 && rng.bool(p: 0.12) {
                    break
                }
                performedExerciseResults.append(performExercise(exPlan, order: idx))
            }
            
            let templateName = plan.templates[templateId]?.name ?? "Workout"
            let completed = CompletedSession(
                date: date,
                templateId: templateId,
                name: templateName,
                exerciseResults: performedExerciseResults,
                startedAt: date,
                wasDeload: sessionPlan.isDeload,
                previousLiftStates: liftStates,
                readinessScore: readiness
            )
            
            // Update states and store.
            let updatedStates = Engine.updateLiftState(afterSession: completed)
            for st in updatedStates { liftStates[st.exerciseId] = st }
            
            sessions.insert(completed, at: 0)
            addVolume(date, kgVolume: sessionVolumeKg)
            outcome.sessions += 1
            
            // Month-ish checkpoints: keep small and deterministic.
            if dayOffset % 90 == 0 {
                let bench = liftStates["bench"]?.lastWorkingWeight.description ?? "n/a"
                let squat = liftStates["barbell_squat"]?.lastWorkingWeight.description ?? "n/a"
                let dead = liftStates["deadlift"]?.lastWorkingWeight.description ?? "n/a"
                outcome.trace += [
                    "d=\(dayOffset)",
                    "bench=\(bench)",
                    "squat=\(squat)",
                    "deadlift=\(dead)",
                    "deloads=\(outcome.deloadSessions)"
                ].joined(separator: " ") + "\n"
            }
        }
        
        // Final invariants on states.
        for st in liftStates.values {
            XCTAssertGreaterThanOrEqual(st.lastWorkingWeight.value, 0)
            XCTAssertTrue(st.rollingE1RM.isFinite)
            XCTAssertGreaterThanOrEqual(st.failureCount, 0)
        }
        
        outcome.finalStates = liftStates
        return outcome
    }
    
    func testLongTerm_TwoYearDiaryReplay_DeterministicAndStable() throws {
        let a = try runTwoYearDiary(seed: 0xC0FFEE_2025)
        let b = try runTwoYearDiary(seed: 0xC0FFEE_2025)
        
        // Determinism across a long replay.
        XCTAssertEqual(a, b)
        
        // Sanity: we should have enough sessions to make long-term issues visible.
        XCTAssertGreaterThan(a.sessions, 120)
        
        // We should see deloads over 2 years (scheduled alone should create some).
        XCTAssertGreaterThanOrEqual(a.deloadSessions, 2)
        XCTAssertGreaterThanOrEqual(a.scheduledDeloads, 1)
        
        // Forced trigger days should make high-fatigue deloads non-zero unless something regressed.
        // NOTE: Low readiness alone does NOT trigger session-level deloads by design.
        // DeloadPolicy handles it at the lift level via "decrease_slightly" instead.
        XCTAssertGreaterThanOrEqual(a.highFatigueDeloads, 1)
        // lowReadinessDeloads will be 0 since they're handled at lift level, not session level
        
        // Monotonicity violations should be extremely rare; treat >0 as a real bug signal.
        XCTAssertEqual(a.monotonicityViolations, 0, "Monotonicity violations detected:\n\(a.trace)")
        
        // Print diagnostics (useful when iterating on real bugs).
        print("📈 Two-year diary diagnostics:")
        print("  Sessions: \(a.sessions)")
        print("  Deloads: \(a.deloadSessions) (scheduled=\(a.scheduledDeloads), lowReadiness=\(a.lowReadinessDeloads), highFatigue=\(a.highFatigueDeloads), perfDecline=\(a.performanceDeclineDeloads))")
        print("  Progression load drops (non-deload): \(a.progressionLoadDrops)")
        print("  Trace:\n\(a.trace)")
    }
}

// MARK: - Small helpers for policy checks (tests only)

private extension ProgressionPolicyType {
    var isLinearOrDoubleProgression: Bool {
        switch self {
        case .linearProgression, .doubleProgression:
            return true
        default:
            return false
        }
    }
}

private extension InSessionAdjustmentPolicyType {
    var isTopSetDailyMax: Bool {
        if case .topSetBackoff(let cfg) = self, cfg.useDailyMax {
            return true
        }
        return false
    }
}

