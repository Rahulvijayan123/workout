import XCTest
@testable import TrainingEngine

final class ProductionGradeConfidenceTests: XCTestCase {
    
    private let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(secondsFromGMT: 0)!
        return c
    }()
    
    private func makeDate(year: Int, month: Int, day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }
    
    // MARK: - Entrypoint consistency (production safety)
    
    func testEntrypoints_DoubleProgression_nextPrescriptionMatchesRecommendSession() {
        let tId = UUID(uuidString: "00000000-0000-0000-0000-00000000E101")!
        
        let squat = Exercise.barbellSquat
        let rx = SetPrescription(setCount: 3, targetRepsRange: 5...5, targetRIR: 2, increment: .pounds(5))
        let template = WorkoutTemplate(id: tId, name: "Squat", exercises: [
            TemplateExercise(exercise: squat, prescription: rx, order: 0)
        ])
        
        let plan = TrainingPlan(
            name: "Consistency",
            templates: [tId: template],
            schedule: .rotation(order: [tId]),
            progressionPolicies: [squat.id: .doubleProgression(config: .default)],
            inSessionPolicies: [:],
            substitutionPool: [],
            deloadConfig: nil,
            loadRoundingPolicy: .standardPounds,
            createdAt: makeDate(year: 2026, month: 1, day: 1)
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
        
        let date = makeDate(year: 2026, month: 2, day: 1)
        let state = LiftState(exerciseId: squat.id, lastWorkingWeight: .pounds(225), rollingE1RM: 275, lastSessionDate: makeDate(year: 2026, month: 1, day: 28))
        let history = WorkoutHistory(sessions: [], liftStates: [squat.id: state], readinessHistory: [], recentVolumeByDate: [:])
        
        let sessionPlan = Engine.recommendSession(
            date: date,
            userProfile: user,
            plan: plan,
            history: history,
            readiness: 80,
            calendar: calendar
        )
        
        let planned = sessionPlan.exercises.first!
        
        let computed = Engine.nextPrescription(
            exercise: squat,
            prescription: rx,
            progressionPolicy: .doubleProgression(config: .default),
            inSessionPolicy: planned.inSessionPolicy,
            history: history,
            liftState: state,
            isDeload: sessionPlan.isDeload,
            roundingPolicy: plan.loadRoundingPolicy,
            deloadConfig: plan.deloadConfig,
            date: date,
            calendar: calendar
        )
        
        XCTAssertEqual(planned.sets, computed.sets)
        XCTAssertEqual(planned.progressionPolicy, computed.progressionPolicy)
        XCTAssertEqual(planned.inSessionPolicy, computed.inSessionPolicy)
    }
    
    /// If `nextPrescription` is meant to be canonical, it should not require callers to remember
    /// to supply an in-session daily-max backoff policy when the progression config requests it.
    func testEntrypoints_TopSetBackoffDailyMax_nextPrescriptionDefaultsMatchRecommendSession() {
        let tId = UUID(uuidString: "00000000-0000-0000-0000-00000000E102")!
        
        let bench = Exercise(
            id: "bench",
            name: "Bench Press",
            equipment: .barbell,
            primaryMuscles: [.chest],
            secondaryMuscles: [.triceps],
            movementPattern: .horizontalPush
        )
        
        let cfg = TopSetBackoffConfig(backoffSetCount: 3, backoffPercentage: 0.75, loadIncrement: .pounds(5), useDailyMax: true, minimumTopSetReps: 1)
        let rx = SetPrescription(setCount: 4, targetRepsRange: 5...5, targetRIR: 1, restSeconds: 180, increment: .pounds(5))
        
        let template = WorkoutTemplate(id: tId, name: "Upper", exercises: [TemplateExercise(exercise: bench, prescription: rx, order: 0)])
        
        let plan = TrainingPlan(
            name: "TopSetConsistency",
            templates: [tId: template],
            schedule: .rotation(order: [tId]),
            progressionPolicies: [bench.id: .topSetBackoff(config: cfg)],
            inSessionPolicies: [:],
            substitutionPool: [],
            deloadConfig: nil,
            loadRoundingPolicy: .standardPounds
        )
        
        let user = UserProfile(sex: .male, experience: .intermediate, goals: [.strength], weeklyFrequency: 3, availableEquipment: .commercialGym, preferredUnit: .pounds)
        let date = makeDate(year: 2026, month: 2, day: 2)
        let state = LiftState(exerciseId: bench.id, lastWorkingWeight: .pounds(225), rollingE1RM: 275, lastSessionDate: makeDate(year: 2026, month: 1, day: 29))
        let history = WorkoutHistory(sessions: [], liftStates: [bench.id: state], readinessHistory: [], recentVolumeByDate: [:])
        
        let sessionPlan = Engine.recommendSession(date: date, userProfile: user, plan: plan, history: history, readiness: 80, calendar: calendar)
        let planned = sessionPlan.exercises.first!
        
        // Default inSessionPolicy should already be topSetBackoff when cfg.useDailyMax is true.
        XCTAssertEqual(planned.inSessionPolicy, .topSetBackoff(config: cfg))
        
        // Now compare against nextPrescription *without* explicitly passing inSessionPolicy.
        let computed = Engine.nextPrescription(
            exercise: bench,
            prescription: rx,
            progressionPolicy: .topSetBackoff(config: cfg),
            history: history,
            liftState: state,
            isDeload: false,
            roundingPolicy: plan.loadRoundingPolicy,
            deloadConfig: nil,
            date: date,
            calendar: calendar
        )
        
        XCTAssertEqual(computed.inSessionPolicy, planned.inSessionPolicy)
        XCTAssertEqual(computed.sets, planned.sets)
    }
    
    // MARK: - Concurrency determinism
    
    func testRecommendSession_IsDeterministicUnderConcurrency() async {
        let tId = UUID(uuidString: "00000000-0000-0000-0000-00000000E103")!
        let pushup = Exercise(id: "pushup", name: "Push-Up", equipment: .bodyweight, primaryMuscles: [.chest], secondaryMuscles: [.triceps], movementPattern: .horizontalPush)
        let rx = SetPrescription(setCount: 3, targetRepsRange: 8...12, targetRIR: 2, restSeconds: 90, loadStrategy: .rpeAutoregulated, increment: .pounds(5))
        let template = WorkoutTemplate(id: tId, name: "BW", exercises: [TemplateExercise(exercise: pushup, prescription: rx, order: 0)])
        
        let plan = TrainingPlan(
            name: "Concurrency",
            templates: [tId: template],
            schedule: .rotation(order: [tId]),
            progressionPolicies: [pushup.id: .none],
            inSessionPolicies: [:],
            substitutionPool: [],
            deloadConfig: nil,
            loadRoundingPolicy: .standardPounds
        )
        
        let user = UserProfile(sex: .male, experience: .intermediate, goals: [.generalFitness], weeklyFrequency: 3, availableEquipment: .bodyweightOnly, preferredUnit: .pounds)
        let history = WorkoutHistory()
        let date = makeDate(year: 2026, month: 2, day: 3)
        
        let expected = Engine.recommendSession(date: date, userProfile: user, plan: plan, history: history, readiness: 80, calendar: calendar)
        
        await withTaskGroup(of: SessionPlan.self) { group in
            for _ in 0..<200 {
                group.addTask {
                    Engine.recommendSession(
                        date: date,
                        userProfile: user,
                        plan: plan,
                        history: history,
                        readiness: 80,
                        calendar: self.calendar
                    )
                }
            }
            
            for await plan in group {
                XCTAssertEqual(plan, expected)
            }
        }
    }
    
    // MARK: - Migration / decoding robustness
    
    func testTrainingPlan_DecodesLegacyTemplatesArrayFormat() throws {
        // Legacy payload uses `[UUID: WorkoutTemplate]` default Codable representation (JSON array, not object).
        struct LegacyTrainingPlanPayload: Codable {
            let id: UUID
            let name: String
            let templates: [WorkoutTemplateId: WorkoutTemplate]
            let schedule: ScheduleType
            let progressionPolicies: [String: ProgressionPolicyType]
            let substitutionPool: [Exercise]
            let deloadConfig: DeloadConfig?
            let loadRoundingPolicy: LoadRoundingPolicy
            let createdAt: Date
        }
        
        let tId = UUID(uuidString: "00000000-0000-0000-0000-00000000E104")!
        let template = WorkoutTemplate(id: tId, name: "Legacy", exercises: [])
        
        let legacy = LegacyTrainingPlanPayload(
            id: UUID(uuidString: "00000000-0000-0000-0000-00000000E105")!,
            name: "Legacy",
            templates: [tId: template],
            schedule: .manual,
            progressionPolicies: [:],
            substitutionPool: [],
            deloadConfig: nil,
            loadRoundingPolicy: .standardPounds,
            createdAt: makeDate(year: 2026, month: 1, day: 1)
        )
        
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(legacy)
        
        let decoded = try JSONDecoder().decode(TrainingPlan.self, from: data)
        XCTAssertEqual(decoded.templates.count, 1)
        XCTAssertEqual(decoded.templates[tId]?.name, "Legacy")
        XCTAssertTrue(decoded.inSessionPolicies.isEmpty)
    }
    
    func testWorkoutHistory_DecodeNormalizesSessionOrdering() throws {
        // Production reality: persisted arrays can be out of order.
        struct UnsortedHistoryPayload: Codable {
            let sessions: [CompletedSession]
            let liftStates: [String: LiftState]
            let readinessHistory: [ReadinessRecord]
            let recentVolumeByDate: [Date: Double]
        }
        
        let d1 = makeDate(year: 2026, month: 2, day: 1)
        let d2 = makeDate(year: 2026, month: 2, day: 10)
        
        let newer = CompletedSession(date: d2, templateId: nil, name: "Newer", exerciseResults: [], startedAt: d2)
        let older = CompletedSession(date: d1, templateId: nil, name: "Older", exerciseResults: [], startedAt: d1)
        
        let payload = UnsortedHistoryPayload(
            sessions: [older, newer], // intentionally unsorted
            liftStates: [:],
            readinessHistory: [],
            recentVolumeByDate: [:]
        )
        
        let data = try JSONEncoder().encode(payload)
        let decoded = try JSONDecoder().decode(WorkoutHistory.self, from: data)
        
        XCTAssertEqual(decoded.sessions.count, 2)
        XCTAssertEqual(decoded.sessions[0].name, "Newer")
        XCTAssertEqual(decoded.sessions[1].name, "Older")
    }
}

