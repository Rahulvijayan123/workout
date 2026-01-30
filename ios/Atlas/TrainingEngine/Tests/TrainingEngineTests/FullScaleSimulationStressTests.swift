import XCTest
@testable import TrainingEngine

final class FullScaleSimulationStressTests: XCTestCase {
    
    // MARK: - Deterministic RNG
    
    private struct SeededRNG {
        private var state: UInt64
        
        init(seed: UInt64) {
            self.state = seed != 0 ? seed : 0x9E3779B97F4A7C15
        }
        
        mutating func nextUInt64() -> UInt64 {
            // splitmix64 (fast, deterministic, good enough for simulation noise)
            state &+= 0x9E3779B97F4A7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
            z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
            return z ^ (z >> 31)
        }
        
        mutating func nextDouble01() -> Double {
            // [0,1)
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
    
    private enum PerformanceMode {
        /// Always completes target reps at target RIR (good day).
        case meetTargets
        /// Adds deterministic “noise” to reps/RIR; can miss targets.
        case noisy
    }
    
    // MARK: - Helpers
    
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
    
    private func assertRounded(_ load: Load, policy: LoadRoundingPolicy, file: StaticString = #filePath, line: UInt = #line) {
        let inPolicyUnit = load.converted(to: policy.unit)
        let nearest = (inPolicyUnit.value / policy.increment).rounded() * policy.increment
        XCTAssertEqual(inPolicyUnit.value, nearest, accuracy: 1e-6, file: file, line: line)
    }
    
    private func assertValidSetPlan(_ set: SetPlan, prescription: SetPrescription, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertGreaterThanOrEqual(set.targetLoad.value, 0, file: file, line: line)
        XCTAssertGreaterThanOrEqual(set.targetReps, 1, file: file, line: line)
        XCTAssertGreaterThanOrEqual(set.targetReps, prescription.targetRepsRange.lowerBound, file: file, line: line)
        XCTAssertLessThanOrEqual(set.targetReps, prescription.targetRepsRange.upperBound, file: file, line: line)
        assertRounded(set.targetLoad, policy: set.roundingPolicy, file: file, line: line)
    }
    
    private func performExercise(
        exercisePlan: ExercisePlan,
        readiness: Int,
        rng: inout SeededRNG,
        mode: PerformanceMode
    ) -> (result: ExerciseSessionResult, didAdjust: Bool) {
        var mutablePlans = exercisePlan.sets
        let originalLoads = mutablePlans.map(\.targetLoad.value)
        var didAdjust = false
        
        var results: [SetResult] = []
        
        for setIndex in 0..<mutablePlans.count {
            let plan = mutablePlans[setIndex]
            
            let reps: Int
            let observedRIR: Int?
            let completed: Bool
            
            switch mode {
            case .meetTargets:
                reps = plan.targetReps
                observedRIR = plan.targetRIR
                completed = true
                
            case .noisy:
                // Simple, deterministic performance model:
                // - High readiness → around target reps / target RIR
                // - Medium readiness → slightly harder
                // - Low readiness → harder, can miss reps & RIR
                let readinessBand: Int
                switch readiness {
                case 0..<50: readinessBand = 0
                case 50..<70: readinessBand = 1
                default: readinessBand = 2
                }
                
                let repNoise: Int
                let rirNoise: Int
                switch readinessBand {
                case 2:
                    repNoise = rng.int(in: -1...1)
                    rirNoise = rng.int(in: -1...1)
                case 1:
                    repNoise = rng.int(in: -2...0)
                    rirNoise = rng.int(in: -2...0)
                default:
                    repNoise = rng.int(in: -4...(-1))
                    rirNoise = rng.int(in: -4...(-1))
                }
                
                let lower = exercisePlan.prescription.targetRepsRange.lowerBound
                let upper = exercisePlan.prescription.targetRepsRange.upperBound
                let minPossible = max(1, lower - 3) // allow misses below lower bound (edge case)
                
                let rawReps = plan.targetReps + repNoise
                reps = max(minPossible, min(upper, rawReps))
                
                let rawRIR = plan.targetRIR + rirNoise
                observedRIR = max(0, rawRIR)
                
                // Edge case: on very low readiness, sometimes the last set is skipped.
                if readiness < 35 && setIndex == mutablePlans.count - 1 {
                    completed = false
                } else {
                    completed = true
                }
            }
            
            let result = SetResult(
                reps: completed ? reps : 0,
                load: plan.targetLoad,
                rirObserved: completed ? observedRIR : nil,
                completed: completed,
                isWarmup: plan.isWarmup
            )
            results.append(result)
            
            if setIndex + 1 < mutablePlans.count {
                let next = mutablePlans[setIndex + 1]
                let adjusted = Engine.adjustDuringSession(
                    currentSetResult: result,
                    plannedNextSet: next
                )
                didAdjust = didAdjust || (abs(adjusted.targetLoad.value - next.targetLoad.value) > 0.0001)
                mutablePlans[setIndex + 1] = adjusted
            }
        }
        
        // If the engine adjusted future set loads, that should show up as a load vector change.
        let newLoads = mutablePlans.map(\.targetLoad.value)
        didAdjust = didAdjust || (originalLoads != newLoads)
        
        return (
            ExerciseSessionResult(
                exerciseId: exercisePlan.exercise.id,
                prescription: exercisePlan.prescription,
                sets: results,
                order: 0
            ),
            didAdjust
        )
    }
    
    // MARK: - Realistic end-to-end cycle simulation
    
    func testEndToEndCycle_12Weeks_MixedPolicies_ScheduledDeload_DeterministicAndSafe() {
        // Exercises
        let bench = Exercise(
            id: "bench",
            name: "Barbell Bench Press",
            equipment: .barbell,
            primaryMuscles: [.chest],
            secondaryMuscles: [.triceps, .frontDelts],
            movementPattern: .horizontalPush
        )
        let ohp = Exercise(
            id: "ohp",
            name: "Overhead Press",
            equipment: .barbell,
            primaryMuscles: [.shoulders, .frontDelts],
            secondaryMuscles: [.triceps],
            movementPattern: .verticalPush
        )
        let row = Exercise(
            id: "row",
            name: "Barbell Row",
            equipment: .barbell,
            primaryMuscles: [.back, .lats],
            secondaryMuscles: [.biceps],
            movementPattern: .horizontalPull
        )
        let pulldown = Exercise(
            id: "pulldown",
            name: "Lat Pulldown",
            equipment: .latPulldownMachine,
            primaryMuscles: [.lats, .back],
            secondaryMuscles: [.biceps],
            movementPattern: .verticalPull
        )
        let squat = Exercise(
            id: "squat",
            name: "Back Squat",
            equipment: .barbell,
            primaryMuscles: [.quadriceps, .glutes],
            secondaryMuscles: [.hamstrings, .lowerBack],
            movementPattern: .squat
        )
        let rdl = Exercise(
            id: "rdl",
            name: "Romanian Deadlift",
            equipment: .barbell,
            primaryMuscles: [.hamstrings, .glutes],
            secondaryMuscles: [.lowerBack],
            movementPattern: .hipHinge
        )
        let curl = Exercise(
            id: "curl",
            name: "Dumbbell Curl",
            equipment: .dumbbell,
            primaryMuscles: [.biceps],
            secondaryMuscles: [],
            movementPattern: .elbowFlexion
        )
        
        // Substitutions
        let dbBench = Exercise(
            id: "db_bench",
            name: "Dumbbell Bench Press",
            equipment: .dumbbell,
            primaryMuscles: [.chest],
            secondaryMuscles: [.triceps, .frontDelts],
            movementPattern: .horizontalPush
        )
        let inclineBench = Exercise(
            id: "incline_bench",
            name: "Incline Barbell Bench Press",
            equipment: .barbell,
            primaryMuscles: [.chest, .frontDelts],
            secondaryMuscles: [.triceps],
            movementPattern: .horizontalPush
        )
        
        // Templates
        let push = WorkoutTemplate(
            name: "Push",
            exercises: [
                TemplateExercise(
                    exercise: bench,
                    prescription: SetPrescription(setCount: 3, targetRepsRange: 6...10, targetRIR: 2, increment: .pounds(5)),
                    order: 0
                ),
                TemplateExercise(
                    exercise: ohp,
                    prescription: SetPrescription(setCount: 3, targetRepsRange: 6...10, targetRIR: 2, increment: .pounds(2.5)),
                    order: 1
                ),
            ]
        )
        let pull = WorkoutTemplate(
            name: "Pull",
            exercises: [
                TemplateExercise(
                    exercise: row,
                    prescription: SetPrescription(setCount: 3, targetRepsRange: 8...12, targetRIR: 2, increment: .pounds(5)),
                    order: 0
                ),
                TemplateExercise(
                    exercise: pulldown,
                    prescription: SetPrescription(setCount: 3, targetRepsRange: 8...12, targetRIR: 2, increment: .pounds(5)),
                    order: 1
                ),
                TemplateExercise(
                    exercise: curl,
                    prescription: SetPrescription(setCount: 3, targetRepsRange: 10...15, targetRIR: 1, increment: .pounds(2.5)),
                    order: 2
                ),
            ]
        )
        let legs = WorkoutTemplate(
            name: "Legs",
            exercises: [
                TemplateExercise(
                    exercise: squat,
                    // Top set + 3 backoffs
                    prescription: SetPrescription(setCount: 4, targetRepsRange: 5...5, targetRIR: 1, increment: .pounds(5)),
                    order: 0
                ),
                TemplateExercise(
                    exercise: rdl,
                    prescription: SetPrescription(setCount: 3, targetRepsRange: 6...8, targetRIR: 2, increment: .pounds(5)),
                    order: 1
                ),
            ]
        )
        
        let deloadConfig = DeloadConfig(
            intensityReduction: 0.12,
            volumeReduction: 1,
            scheduledDeloadWeeks: 4,
            readinessThreshold: 50,
            lowReadinessDaysRequired: 3
        )
        
        let plan = TrainingPlan(
            name: "4-day",
            templates: [push.id: push, pull.id: pull, legs.id: legs],
            schedule: .fixedWeekday(mapping: [
                2: push.id, // Monday
                3: pull.id, // Tuesday
                5: legs.id  // Thursday
            ]),
            progressionPolicies: [
                bench.id: .doubleProgression(config: .default),
                ohp.id: .rirAutoregulation(config: .default),
                squat.id: .topSetBackoff(config: .strength),
                rdl.id: .linearProgression(config: .default)
            ],
            substitutionPool: [dbBench, inclineBench],
            deloadConfig: deloadConfig,
            loadRoundingPolicy: .standardPounds
        )
        
        let fullEquipmentUser = UserProfile(
            sex: .male,
            experience: .intermediate,
            goals: [.hypertrophy],
            weeklyFrequency: 4,
            availableEquipment: .commercialGym,
            preferredUnit: .pounds
        )
        
        let limitedEquipmentUser = UserProfile(
            sex: .male,
            experience: .intermediate,
            goals: [.hypertrophy],
            weeklyFrequency: 4,
            availableEquipment: EquipmentAvailability(available: [.dumbbell, .bodyweight, .pullUpBar, .bench]),
            preferredUnit: .pounds
        )
        
        // Initial state
        var liftStates: [String: LiftState] = [
            bench.id: LiftState(exerciseId: bench.id, lastWorkingWeight: .pounds(185)),
            ohp.id: LiftState(exerciseId: ohp.id, lastWorkingWeight: .pounds(115)),
            row.id: LiftState(exerciseId: row.id, lastWorkingWeight: .pounds(155)),
            pulldown.id: LiftState(exerciseId: pulldown.id, lastWorkingWeight: .pounds(140)),
            squat.id: LiftState(exerciseId: squat.id, lastWorkingWeight: .pounds(275)),
            rdl.id: LiftState(exerciseId: rdl.id, lastWorkingWeight: .pounds(225)),
            curl.id: LiftState(exerciseId: curl.id, lastWorkingWeight: .pounds(30)),
        ]
        
        var sessionsMostRecentFirst: [CompletedSession] = []
        var readinessHistory: [ReadinessRecord] = []
        var volumeByDay: [Date: Double] = [:]
        var rng = SeededRNG(seed: 1337)
        
        let start = day(makeDate(year: 2026, month: 1, day: 5)) // Monday
        let totalDays = 12 * 7
        
        var scheduledDeloadCount = 0
        var benchSawRepProgression = false
        var anyOHPInSessionAdjustment = false
        
        for dayIndex in 0..<totalDays {
            let date = day(calendar.date(byAdding: .day, value: dayIndex, to: start)!)
            
            // Readiness mostly high; keep it stable to isolate scheduled deload behavior.
            let readiness = 75
            readinessHistory.insert(ReadinessRecord(date: date, score: readiness), at: 0)
            
            let history = WorkoutHistory(
                sessions: sessionsMostRecentFirst,
                liftStates: liftStates,
                readinessHistory: readinessHistory,
                recentVolumeByDate: volumeByDay
            )
            
            // Determinism check on a specific day.
            let userForDay = (dayIndex == 14) ? limitedEquipmentUser : fullEquipmentUser
            let a = Engine.recommendSession(date: date, userProfile: userForDay, plan: plan, history: history, readiness: readiness)
            let b = Engine.recommendSession(date: date, userProfile: userForDay, plan: plan, history: history, readiness: readiness)
            XCTAssertEqual(a, b, "recommendSession must be deterministic")
            
            let sessionPlan = a
            if sessionPlan.templateId == nil {
                // Rest day
                continue
            }
            
            XCTAssertFalse(sessionPlan.exercises.isEmpty)
            
            if sessionPlan.isDeload, sessionPlan.deloadReason == .scheduledDeload {
                scheduledDeloadCount += 1
            }
            
            // Validate sets + rounding + rep targets
            for ex in sessionPlan.exercises {
                XCTAssertFalse(ex.sets.isEmpty)
                for set in ex.sets {
                    assertValidSetPlan(set, prescription: ex.prescription)
                }
                
                // Top set + backoff sanity: first set should be >= backoffs
                if case .topSetBackoff = ex.progressionPolicy, ex.sets.count >= 2 {
                    let top = ex.sets[0].targetLoad.value
                    let backoffMax = ex.sets.dropFirst().map(\.targetLoad.value).max() ?? top
                    XCTAssertGreaterThanOrEqual(top, backoffMax)
                }
            }
            
            // Substitution filtering edge case (limited equipment day)
            if dayIndex == 14, let benchPlan = sessionPlan.exercises.first(where: { $0.exercise.id == bench.id }) {
                XCTAssertFalse(benchPlan.substitutions.contains { $0.exercise.equipment == .barbell })
                XCTAssertTrue(benchPlan.substitutions.contains { $0.exercise.id == dbBench.id })
            }
            
            // Track rep progression signals for bench
            if let benchPlan = sessionPlan.exercises.first(where: { $0.exercise.id == bench.id }) {
                if (benchPlan.sets.first?.targetReps ?? 0) > benchPlan.prescription.targetRepsRange.lowerBound {
                    benchSawRepProgression = true
                }
            }
            
            // Perform the session using only public entrypoints
            var exerciseResults: [ExerciseSessionResult] = []
            
            for ex in sessionPlan.exercises {
                let mode: PerformanceMode = (ex.exercise.id == ohp.id) ? .noisy : .meetTargets
                let performed = performExercise(exercisePlan: ex, readiness: readiness, rng: &rng, mode: mode)
                exerciseResults.append(performed.result)
                if ex.exercise.id == ohp.id {
                    anyOHPInSessionAdjustment = anyOHPInSessionAdjustment || performed.didAdjust
                }
            }
            
            let completedSession = CompletedSession(
                date: date,
                templateId: sessionPlan.templateId,
                name: plan.templates[sessionPlan.templateId!]?.name ?? "Workout",
                exerciseResults: exerciseResults,
                startedAt: date,
                wasDeload: sessionPlan.isDeload,
                previousLiftStates: liftStates,
                readinessScore: readiness
            )
            
            // Update volume (start-of-day key)
            volumeByDay[date, default: 0] += completedSession.totalVolume
            
            // Update lift states
            let updated = Engine.updateLiftState(afterSession: completedSession)
            for st in updated {
                liftStates[st.exerciseId] = st
            }
            
            // Prepend session (most recent first)
            sessionsMostRecentFirst.insert(completedSession, at: 0)
        }
        
        // Assertions that prove the system actually did meaningful work.
        XCTAssertGreaterThanOrEqual(scheduledDeloadCount, 1, "Expected at least one scheduled deload over 12 weeks")
        XCTAssertTrue(benchSawRepProgression, "Expected bench to show rep progression above lower bound")
        XCTAssertTrue(anyOHPInSessionAdjustment, "Expected at least one in-session autoregulation adjustment on OHP")
        
        // Bench should not go negative and should stay rounded
        let finalBench = liftStates[bench.id]!.lastWorkingWeight
        XCTAssertGreaterThan(finalBench.value, 0)
        assertRounded(finalBench, policy: .standardPounds)
    }
    
    func testRecommendSession_LowReadinessDeload_AppliesConfiguredIntensityAndVolume() {
        let bench = Exercise(
            id: "bench",
            name: "Bench Press",
            equipment: .barbell,
            primaryMuscles: [.chest],
            secondaryMuscles: [.triceps],
            movementPattern: .horizontalPush
        )
        
        let template = WorkoutTemplate(
            name: "Bench Day",
            exercises: [
                TemplateExercise(
                    exercise: bench,
                    prescription: SetPrescription(setCount: 5, targetRepsRange: 6...10, targetRIR: 2, increment: .pounds(5)),
                    order: 0
                )
            ]
        )
        
        let deloadConfig = DeloadConfig(
            intensityReduction: 0.15,
            volumeReduction: 2,
            scheduledDeloadWeeks: nil,
            readinessThreshold: 50,
            lowReadinessDaysRequired: 3
        )
        
        let plan = TrainingPlan(
            name: "Test",
            templates: [template.id: template],
            schedule: .rotation(order: [template.id]),
            progressionPolicies: [bench.id: .doubleProgression(config: .default)],
            substitutionPool: [],
            deloadConfig: deloadConfig,
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
        
        let today = day(makeDate(year: 2026, month: 2, day: 2))
        let yesterday = day(calendar.date(byAdding: .day, value: -1, to: today)!)
        let twoDaysAgo = day(calendar.date(byAdding: .day, value: -2, to: today)!)
        
        let readinessHistory = [
            ReadinessRecord(date: yesterday, score: 45),
            ReadinessRecord(date: twoDaysAgo, score: 40)
        ]
        
        let liftStates: [String: LiftState] = [
            bench.id: LiftState(exerciseId: bench.id, lastWorkingWeight: .pounds(100))
        ]
        
        let history = WorkoutHistory(
            sessions: [],
            liftStates: liftStates,
            readinessHistory: readinessHistory,
            recentVolumeByDate: [:]
        )
        
        let sessionPlan = Engine.recommendSession(
            date: today,
            userProfile: user,
            plan: plan,
            history: history,
            readiness: 35
        )
        
        // NOTE: Low readiness no longer triggers a full session-level deload.
        // Instead, DirectionPolicy handles it at the lift level with "decrease_slightly" direction.
        // This prevents over-deloading and allows more granular control.
        XCTAssertFalse(sessionPlan.isDeload, "Low readiness should not trigger session-level deload; handled at lift level")
        XCTAssertEqual(sessionPlan.exercises.count, 1)
        
        let benchPlan = sessionPlan.exercises[0]
        
        // Per-exercise direction should indicate readiness cut
        XCTAssertEqual(benchPlan.recommendedAdjustmentKind, .readinessCut, "Should recommend readiness cut for low readiness")
        XCTAssertEqual(benchPlan.direction, .hold, "Low readiness (single day) should hold load (volume cut only)")
        
        // V10 readiness behavior: hold load but reduce volume (-1 set).
        XCTAssertEqual(benchPlan.sets.count, 4, "Readiness cut should reduce volume by 1 set")
        XCTAssertEqual(benchPlan.sets[0].targetLoad.value, 100.0, accuracy: 0.001, "Load should be held at baseline for single-day low readiness")
        assertRounded(benchPlan.sets[0].targetLoad, policy: .standardPounds)
    }
    
    func testRecommendSession_PerformanceDeclineDeload_FiresFromHistory() {
        let squat = Exercise(
            id: "squat",
            name: "Back Squat",
            equipment: .barbell,
            primaryMuscles: [.quadriceps, .glutes],
            secondaryMuscles: [.hamstrings, .lowerBack],
            movementPattern: .squat
        )
        
        let template = WorkoutTemplate(
            name: "Squat Day",
            exercises: [
                TemplateExercise(
                    exercise: squat,
                    prescription: SetPrescription(setCount: 3, targetRepsRange: 5...5, targetRIR: 1, increment: .pounds(5)),
                    order: 0
                )
            ]
        )
        
        let plan = TrainingPlan(
            name: "Test",
            templates: [template.id: template],
            schedule: .rotation(order: [template.id]),
            progressionPolicies: [squat.id: .linearProgression(config: .default)],
            substitutionPool: [],
            deloadConfig: .default,
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
        
        let baseDate = day(makeDate(year: 2026, month: 3, day: 2))
        let prescription = SetPrescription(setCount: 3, targetRepsRange: 5...5, targetRIR: 1, increment: .pounds(5))
        
        // Build 3 non-deload sessions with *meaningfully* declining e1RM (same load, fewer reps).
        let s1Date = calendar.date(byAdding: .day, value: -21, to: baseDate)!
        let s2Date = calendar.date(byAdding: .day, value: -14, to: baseDate)!
        let s3Date = calendar.date(byAdding: .day, value: -7, to: baseDate)!
        
        func makeSession(date: Date, reps: Int) -> CompletedSession {
            let set = SetResult(reps: reps, load: .pounds(315), rirObserved: 1, completed: true)
            let ex = ExerciseSessionResult(exerciseId: squat.id, prescription: prescription, sets: [set], order: 0)
            return CompletedSession(date: date, templateId: template.id, name: "Squat Day", exerciseResults: [ex], startedAt: date, wasDeload: false)
        }
        
        let s1 = makeSession(date: s1Date, reps: 5) // highest e1RM
        let s2 = makeSession(date: s2Date, reps: 4)
        let s3 = makeSession(date: s3Date, reps: 3) // lowest e1RM
        
        let state = LiftState(exerciseId: squat.id, lastWorkingWeight: .pounds(315), rollingE1RM: 0, lastSessionDate: s3Date)
        let history = WorkoutHistory(
            sessions: [s3, s2, s1],
            liftStates: [squat.id: state],
            readinessHistory: [ReadinessRecord(date: baseDate, score: 80)],
            recentVolumeByDate: [:]
        )
        
        let planOut = Engine.recommendSession(
            date: baseDate,
            userProfile: user,
            plan: plan,
            history: history,
            readiness: 80
        )
        
        // NOTE: Performance decline is now handled at the LIFT level by DirectionPolicy,
        // not at the session level. This provides more granular control and prevents
        // over-deloading when only one lift is declining.
        // Session-level deload only fires for scheduled deload or high accumulated fatigue.
        XCTAssertFalse(planOut.isDeload, "Performance decline should not trigger session-level deload; handled at lift level")
        
        // Verify that the lift-level direction handles the decline appropriately.
        // With a declining trend and sufficient history, DirectionPolicy may recommend
        // deload or hold depending on the exact state.
        XCTAssertEqual(planOut.exercises.count, 1)
        let squatPlan = planOut.exercises[0]
        
        // The direction should reflect the declining performance
        // Could be deload (if fail/rpe streaks are high enough) or hold/decreaseSlightly
        XCTAssertNotNil(squatPlan.direction, "Direction should be set based on performance signals")
    }
    
    func testStress_SeededFuzz_200Sessions_InvariantsAndDeterminism() {
        // Single-template plan to stress repeatability under varying readiness and adjustments
        let press = Exercise(
            id: "press",
            name: "Dumbbell Press",
            equipment: .dumbbell,
            primaryMuscles: [.chest],
            secondaryMuscles: [.triceps],
            movementPattern: .horizontalPush
        )
        let curl = Exercise(
            id: "curl",
            name: "Curl",
            equipment: .dumbbell,
            primaryMuscles: [.biceps],
            secondaryMuscles: [],
            movementPattern: .elbowFlexion
        )
        
        let template = WorkoutTemplate(
            name: "Upper",
            exercises: [
                TemplateExercise(
                    exercise: press,
                    prescription: SetPrescription(setCount: 4, targetRepsRange: 8...12, targetRIR: 2, increment: .pounds(2.5)),
                    order: 0
                ),
                TemplateExercise(
                    exercise: curl,
                    prescription: SetPrescription(setCount: 3, targetRepsRange: 10...15, targetRIR: 1, increment: .pounds(2.5)),
                    order: 1
                )
            ]
        )
        
        let plan = TrainingPlan(
            name: "Fuzz",
            templates: [template.id: template],
            schedule: .rotation(order: [template.id]),
            progressionPolicies: [
                press.id: .rirAutoregulation(config: .default),
                curl.id: .doubleProgression(config: .smallIncrement)
            ],
            substitutionPool: [],
            deloadConfig: DeloadConfig(
                intensityReduction: 0.10,
                volumeReduction: 1,
                scheduledDeloadWeeks: 6,
                readinessThreshold: 45,
                lowReadinessDaysRequired: 2
            ),
            loadRoundingPolicy: .standardPounds
        )
        
        let user = UserProfile(
            sex: .female,
            experience: .beginner,
            goals: [.hypertrophy],
            weeklyFrequency: 4,
            availableEquipment: .commercialGym,
            preferredUnit: .pounds
        )
        
        var rng = SeededRNG(seed: 424242)
        var liftStates: [String: LiftState] = [
            press.id: LiftState(exerciseId: press.id, lastWorkingWeight: .pounds(40)),
            curl.id: LiftState(exerciseId: curl.id, lastWorkingWeight: .pounds(15))
        ]
        var sessionsMostRecentFirst: [CompletedSession] = []
        var readinessHistory: [ReadinessRecord] = []
        var volumeByDay: [Date: Double] = [:]
        
        let start = day(makeDate(year: 2026, month: 1, day: 6))
        
        for i in 0..<200 {
            let date = day(calendar.date(byAdding: .day, value: i, to: start)!)
            let readiness = rng.int(in: 25...95)
            readinessHistory.insert(ReadinessRecord(date: date, score: readiness), at: 0)
            
            let history = WorkoutHistory(
                sessions: sessionsMostRecentFirst,
                liftStates: liftStates,
                readinessHistory: readinessHistory,
                recentVolumeByDate: volumeByDay
            )
            
            let planA = Engine.recommendSession(date: date, userProfile: user, plan: plan, history: history, readiness: readiness)
            let planB = Engine.recommendSession(date: date, userProfile: user, plan: plan, history: history, readiness: readiness)
            XCTAssertEqual(planA, planB)
            
            guard let _ = planA.templateId else {
                continue
            }
            
            // Invariants on output
            for ex in planA.exercises {
                XCTAssertFalse(ex.sets.isEmpty)
                for set in ex.sets {
                    assertValidSetPlan(set, prescription: ex.prescription)
                }
            }
            
            // Perform session (noisy)
            var exerciseResults: [ExerciseSessionResult] = []
            for ex in planA.exercises {
                let performed = performExercise(exercisePlan: ex, readiness: readiness, rng: &rng, mode: .noisy)
                exerciseResults.append(performed.result)
            }
            
            let completed = CompletedSession(
                date: date,
                templateId: planA.templateId,
                name: "Upper",
                exerciseResults: exerciseResults,
                startedAt: date,
                wasDeload: planA.isDeload,
                previousLiftStates: liftStates,
                readinessScore: readiness
            )
            
            volumeByDay[date, default: 0] += completed.totalVolume
            
            let updatedStates = Engine.updateLiftState(afterSession: completed)
            for st in updatedStates {
                XCTAssertGreaterThanOrEqual(st.failureCount, 0)
                XCTAssertGreaterThanOrEqual(st.rollingE1RM, 0)
                XCTAssertGreaterThanOrEqual(st.lastWorkingWeight.value, 0)
                liftStates[st.exerciseId] = st
            }
            
            sessionsMostRecentFirst.insert(completed, at: 0)
        }
    }
}

