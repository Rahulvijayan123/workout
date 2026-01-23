import Foundation

// Run with:
// swift -DDEBUG \
//   "IronForge/Models/Exercise.swift" \
//   "IronForge/Repositories/ExerciseRepository.swift" \
//   "IronForge/Models/WorkoutModels.swift" \
//   "IronForge/Models/ProgressionEngine.swift" \
//   "IronForge/Repositories/WorkoutStore.swift" \
//   "IronForgeTests/IronForgeTortureHarness.swift"

@main
struct IronForgeTortureHarness {
    static func main() async {
        let started = Date()
        var failures: [String] = []
        func fail(_ message: String) {
            failures.append(message)
            fputs("FAIL: \(message)\n", stderr)
        }
        func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
            if !condition() { fail(message) }
        }
        
        // MARK: - Reset persisted state (fake data sandbox)
        
        // Reset both v1 (legacy) and v2 (TrainingEngine-powered) keys
        let keysToReset = [
            "ironforge.workoutTemplates.v1",
            "ironforge.workoutSessions.v1",
            "ironforge.exerciseStates.v1",
            "ironforge.workoutTemplates.v2",
            "ironforge.workoutSessions.v2",
            "ironforge.liftStates.v2"
        ]
        for key in keysToReset {
            UserDefaults.standard.removeObject(forKey: key)
        }
        
        // MARK: - Deterministic fixtures
        
        func exercise(_ id: String) -> Exercise {
            if let ex = ExerciseSeeds.defaultExercises.first(where: { $0.id == id }) {
                return ex
            }
            // Fallback: create a minimally valid Exercise.
            return Exercise(
                id: id,
                name: id.replacingOccurrences(of: "_", with: " "),
                bodyPart: "back",
                equipment: "barbell",
                gifUrl: nil,
                target: "lats",
                secondaryMuscles: [],
                instructions: []
            )
        }
        
        let bench = exercise("barbell_bench_press")
        let squat = exercise("barbell_back_squat")
        
        let testTemplate = WorkoutTemplate(
            name: "Torture Template",
            exercises: [
                WorkoutTemplateExercise(
                    exercise: ExerciseRef(from: bench),
                    setsTarget: 3,
                    repRangeMin: 6,
                    repRangeMax: 10,
                    increment: 5,
                    deloadFactor: 0.9,
                    failureThreshold: 2
                ),
                WorkoutTemplateExercise(
                    exercise: ExerciseRef(from: squat),
                    setsTarget: 2,
                    repRangeMin: 5,
                    repRangeMax: 8,
                    increment: 10,
                    deloadFactor: 0.9,
                    failureThreshold: 2
                )
            ]
        )
        
        // MARK: - Store end-to-end scenarios
        
        let store = await MainActor.run { WorkoutStore(exerciseRepository: LocalExerciseRepository()) }
        
        await MainActor.run {
            store.createTemplate(name: testTemplate.name, exercises: testTemplate.exercises)
        }
        
        let createdTemplate: WorkoutTemplate? = await MainActor.run {
            store.templates.first(where: { $0.name == testTemplate.name })
        }
        expect(createdTemplate != nil, "Template should be created and retrievable from store")
        guard let createdTemplate else {
            exit(1)
        }
        
        await MainActor.run { store.startSession(from: createdTemplate) }
        
        var session: WorkoutSession? = await MainActor.run { store.activeSession }
        expect(session != nil, "Starting a session should populate activeSession")
        guard var session else { exit(1) }
        
        expect(session.exercises.count == 2, "Session should have 2 exercises from template")
        
        // Prefill checks: no ExerciseState yet => weight 0; reps seeded at repRangeMin; set count setsTarget.
        for ex in session.exercises {
            expect(ex.sets.count == ex.setsTarget, "Seeded set count should match setsTarget for \(ex.exercise.id)")
            expect(ex.sets.allSatisfy { $0.reps == ex.repRangeMin }, "Seeded reps should start at repRangeMin for \(ex.exercise.id)")
            expect(ex.sets.allSatisfy { $0.weight == 0 }, "Seeded weight should be 0 with no ExerciseState for \(ex.exercise.id)")
        }
        
        // --- Exercise 1 (bench): within-range -> increase reps
        let benchIdx = session.exercises.firstIndex(where: { $0.exercise.id == bench.id })
        expect(benchIdx != nil, "Bench should exist in session")
        if let benchIdx {
            for i in session.exercises[benchIdx].sets.indices {
                session.exercises[benchIdx].sets[i].weight = 100
                session.exercises[benchIdx].sets[i].reps = 8
                session.exercises[benchIdx].sets[i].isCompleted = true
            }
            
            await MainActor.run { store.updateActiveSession(session) }
            
            // Safeguard C: initialize state from first working set weight
            await MainActor.run { store.initializeExerciseState(exerciseId: bench.id, initialWeight: 100) }
            
            let snapshot = await MainActor.run { store.completeExercise(performanceId: session.exercises[benchIdx].id) }
            expect(snapshot != nil, "Completing bench should return a NextPrescriptionSnapshot")
            if let snapshot {
                expect(snapshot.exerciseId == bench.id, "Snapshot exerciseId should match bench")
                expect(snapshot.reason == .increaseReps, "Bench within-range should suggest increaseReps")
                expect(snapshot.nextWorkingWeight == 100, "Bench within-range should hold weight at 100")
                expect(snapshot.targetReps == 9, "Bench within-range should target +1 rep (8 -> 9)")
            }
            
            // Pull updated session back from store
            session = await MainActor.run { store.activeSession } ?? session
            let updatedBench = session.exercises[benchIdx]
            expect(updatedBench.isCompleted, "Bench performance should be marked completed after completion")
            expect(updatedBench.nextPrescription != nil, "Bench performance should store nextPrescription")
        }
        
        // Finish session -> should persist session + states
        await MainActor.run { store.updateActiveSession(session) }
        await MainActor.run { store.finishActiveSession() }
        let sessionsCount = await MainActor.run { store.sessions.count }
        expect(sessionsCount == 1, "Finishing should save 1 session (got \(sessionsCount))")
        
        // Start a new session: bench should prefill weight from ExerciseState (100)
        await MainActor.run { store.startSession(from: createdTemplate) }
        let session2 = await MainActor.run { store.activeSession }
        expect(session2 != nil, "Second session should start")
        if let session2 {
            if let bench2 = session2.exercises.first(where: { $0.exercise.id == bench.id }) {
                expect(bench2.sets.allSatisfy { $0.weight == 100 }, "Bench should prefill weight from ExerciseState (100)")
                expect(bench2.sets.count == bench2.setsTarget, "Bench set count should match setsTarget")
                expect(bench2.repRangeMin == 6 && bench2.repRangeMax == 10, "Bench rep range should match template snapshot")
            } else {
                fail("Bench missing in second session")
            }
        }
        
        // MARK: - Progression edge cases (direct engine tests)
        
        // Failure threshold behavior: 2 misses -> deload (0.9 multiplier)
        do {
            var state: ExerciseState? = ExerciseState(exerciseId: squat.id, currentWorkingWeight: 200, failuresCount: 0)
            let basePerformance = ExercisePerformance(
                exercise: ExerciseRef(from: squat),
                setsTarget: 2,
                repRangeMin: 5,
                repRangeMax: 8,
                increment: 10,
                deloadFactor: 0.9,
                failureThreshold: 2,
                sets: [
                    WorkoutSet(reps: 4, weight: 200, isCompleted: true),
                    WorkoutSet(reps: 4, weight: 200, isCompleted: true)
                ],
                nextPrescription: nil,
                isCompleted: false
            )
            
            let r1 = ProgressionEngine.nextPrescription(performance: basePerformance, priorState: state)
            expect(r1.snapshot.reason == .hold, "First miss should hold (not deload)")
            expect(r1.updatedState.failuresCount == 1, "First miss should increment failuresCount to 1")
            expect(r1.snapshot.nextWorkingWeight == 200, "First miss should hold weight")
            state = r1.updatedState
            
            let r2 = ProgressionEngine.nextPrescription(performance: basePerformance, priorState: state)
            expect(r2.snapshot.reason == .deload, "Second miss should deload at threshold")
            expect(r2.updatedState.failuresCount == 0, "Deload should reset failuresCount to 0")
            expect(r2.snapshot.nextWorkingWeight == 180, "Deload should apply 0.9 multiplier (200 -> 180)")
        }

        // Degenerate inputs: failureThreshold <= 0 should be clamped to 1 (immediate deload on first miss).
        do {
            let perf = ExercisePerformance(
                exercise: ExerciseRef(from: bench),
                setsTarget: 3,
                repRangeMin: 6,
                repRangeMax: 10,
                increment: 5,
                deloadFactor: -0.5,
                failureThreshold: 0,
                sets: [
                    WorkoutSet(reps: 3, weight: 100, isCompleted: true),
                    WorkoutSet(reps: 3, weight: 100, isCompleted: true),
                    WorkoutSet(reps: 3, weight: 100, isCompleted: true)
                ],
                nextPrescription: nil,
                isCompleted: false
            )
            let out = ProgressionEngine.nextPrescription(performance: perf, priorState: ExerciseState(exerciseId: bench.id, currentWorkingWeight: 100, failuresCount: 0))
            expect(out.snapshot.failureThreshold == 1, "failureThreshold <= 0 should clamp to 1 in snapshot")
            expect(out.snapshot.reason == .deload, "With clamped threshold=1, first miss should deload")
            expect(out.snapshot.nextWorkingWeight >= 0, "Deload should never produce negative weight (clamped to >= 0)")
        }
        
        // Rep range sanity: if repRangeMin > repRangeMax, we should not crash
        do {
            let weird = ExercisePerformance(
                exercise: ExerciseRef(from: bench),
                setsTarget: 3,
                repRangeMin: 12,
                repRangeMax: 8,
                increment: 5,
                deloadFactor: 0.9,
                failureThreshold: 2,
                sets: [
                    WorkoutSet(reps: 10, weight: 100, isCompleted: true),
                    WorkoutSet(reps: 10, weight: 100, isCompleted: true),
                    WorkoutSet(reps: 10, weight: 100, isCompleted: true)
                ],
                nextPrescription: nil,
                isCompleted: false
            )
            _ = ProgressionEngine.nextPrescription(performance: weird, priorState: nil)
            expect(true, "Rep range inversion should not crash")
        }
        
        // MARK: - Backward-compat decode tests
        
        do {
            struct LegacyWorkoutTemplate: Codable {
                var id: UUID = UUID()
                var name: String
                var exercises: [LegacyTemplateExercise]
                var createdAt: Date = Date()
                var updatedAt: Date = Date()
            }
            
            let legacy = LegacyWorkoutTemplate(
                name: "LegacyTemplate",
                exercises: [
                    LegacyTemplateExercise(
                        id: UUID(),
                        exercise: ExerciseRef(from: bench),
                        sets: 4,
                        repRange: 8...12,
                        increment: 2.5
                    )
                ]
            )
            
            let data = try JSONEncoder().encode(legacy)
            let decoded = try JSONDecoder().decode(WorkoutTemplate.self, from: data)
            expect(decoded.name == "LegacyTemplate", "Legacy template name should decode")
            expect(decoded.exercises.first?.setsTarget == 4, "Legacy sets should map to setsTarget")
            expect(decoded.exercises.first?.repRangeMin == 8 && decoded.exercises.first?.repRangeMax == 12, "Legacy repRange should map to repRangeMin/Max")
            expect(decoded.exercises.first?.increment == 2.5, "Legacy increment should decode")
        } catch {
            fail("Legacy template decode threw: \(error)")
        }
        
        do {
            struct LegacyWorkoutSession: Codable {
                var id: UUID = UUID()
                var templateId: UUID?
                var name: String
                var startedAt: Date = Date()
                var endedAt: Date? = Date()
                var exercises: [LegacySessionExercise]
            }
            
            let legacy = LegacyWorkoutSession(
                templateId: nil,
                name: "LegacySession",
                exercises: [
                    LegacySessionExercise(
                        id: UUID(),
                        exercise: ExerciseRef(from: bench),
                        plannedSets: 3,
                        repRange: 6...10,
                        increment: 5,
                        sets: [
                            WorkoutSet(reps: 8, weight: 100, isCompleted: true),
                            WorkoutSet(reps: 8, weight: 100, isCompleted: true),
                            WorkoutSet(reps: 7, weight: 100, isCompleted: true)
                        ]
                    )
                ]
            )
            
            let data = try JSONEncoder().encode(legacy)
            let decoded = try JSONDecoder().decode(WorkoutSession.self, from: data)
            expect(decoded.name == "LegacySession", "Legacy session name should decode")
            expect(decoded.exercises.first?.setsTarget == 3, "Legacy plannedSets should map to setsTarget")
            expect(decoded.exercises.first?.repRangeMin == 6 && decoded.exercises.first?.repRangeMax == 10, "Legacy repRange should map to repRangeMin/Max")
        } catch {
            fail("Legacy session decode threw: \(error)")
        }
        
        // MARK: - Randomized stress test (no UI, but exercises the core algorithm hard)
        
        do {
            var rng = SeededRNG(seed: 0xC0FFEE)
            var state: ExerciseState? = ExerciseState(exerciseId: bench.id, currentWorkingWeight: 100, failuresCount: 0)
            
            for iter in 0..<20000 {
                let lb = 6
                let ub = 10
                let reps = (0..<3).map { _ in rng.int(in: 0...12) }
                let weights = (0..<3).map { _ in Double(rng.int(in: 60...140)) }
                
                let sets = zip(reps, weights).map { (r, w) in
                    WorkoutSet(reps: r, weight: w, isCompleted: true)
                }
                
                let perf = ExercisePerformance(
                    exercise: ExerciseRef(from: bench),
                    setsTarget: 3,
                    repRangeMin: lb,
                    repRangeMax: ub,
                    increment: 5,
                    deloadFactor: 0.9,
                    failureThreshold: 2,
                    sets: sets,
                    nextPrescription: nil,
                    isCompleted: false
                )
                
                let out = ProgressionEngine.nextPrescription(performance: perf, priorState: state)
                
                // Invariants
                expect(out.snapshot.nextWorkingWeight.isFinite, "Iter \(iter): nextWorkingWeight should be finite")
                expect(out.snapshot.nextWorkingWeight >= 0, "Iter \(iter): nextWorkingWeight should be non-negative")
                expect(out.snapshot.targetReps >= lb || lb > ub, "Iter \(iter): targetReps should be >= lb (unless invalid range)")
                expect(out.updatedState.failuresCount >= 0, "Iter \(iter): failuresCount should be non-negative")
                
                state = out.updatedState
            }
        }
        
        let duration = Date().timeIntervalSince(started)
        if failures.isEmpty {
            print("PASS: IronForge torture harness completed in \(String(format: "%.2fs", duration))")
        } else {
            print("FAILED: \(failures.count) issue(s) found in \(String(format: "%.2fs", duration))")
            for (idx, msg) in failures.enumerated() {
                print("\(idx + 1). \(msg)")
            }
            exit(1)
        }
    }
}

// MARK: - Tiny deterministic RNG (for reproducible stress tests)

struct SeededRNG {
    private var state: UInt64
    init(seed: UInt64) { self.state = seed }
    
    mutating func next() -> UInt64 {
        // xorshift64*
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
    
    mutating func int(in range: ClosedRange<Int>) -> Int {
        let span = UInt64(range.upperBound - range.lowerBound + 1)
        let v = next() % span
        return range.lowerBound + Int(v)
    }
}

