// WorkoutEngineTestsetV5ReplayTests.swift
// Full E2E replay test for workout_engine_testset_v5_science dataset.
// V5: Properly evolving history (no date contamination), body weight included, correct decision taxonomy.

import XCTest
@testable import TrainingEngine
import Foundation

final class WorkoutEngineTestsetV5ReplayTests: XCTestCase {
    
    // MARK: - V5 Record Structures
    
    struct V5Record: Codable {
        let dataset_version: String
        let user_id: String
        let date: String
        let session_type: String
        let input: V5Input
        let expected: V5Expected
    }
    
    struct V5Input: Codable {
        let user_profile: V5UserProfile
        let equipment: V5Equipment
        let today_metrics: V5TodayMetrics
        let today_session_template: [V5TemplateExercise]
        let recent_lift_history: [String: [V5HistoryEntry]]
        let days_since_last_session: Int?
        let days_since_lift_exposure: [String: Int?]
        let event_flags: V5EventFlags
        let planned_deload_week: Bool
    }
    
    struct V5UserProfile: Codable {
        let sex: String
        let age: Int
        let height_cm: Int
        let body_weight_lb: Double
        let experience_level: String
        let program: String
        let goal: String
    }
    
    struct V5Equipment: Codable {
        let units: String
        let bar_weight_lb: Double
        let load_step_lb: Double
    }
    
    struct V5TodayMetrics: Codable {
        let sleep_hours: Double?
        let hrv_ms: Int?
        let resting_hr_bpm: Int?
        let soreness_1_to_10: Int?
        let stress_1_to_10: Int?
        let steps: Int?
        let calories_est: Int?
    }
    
    struct V5TemplateExercise: Codable {
        let lift: String
        let sets: Int
        let reps: Int
        let unit: String?
    }
    
    struct V5HistoryEntry: Codable {
        let date: String
        let session_type: String
        let weight_lb: Double?
        let target_reps: Int
        let top_set_reps: Int
        let top_rpe: Double?
        let outcome: String
        let decision: String
        let reason_code: String
    }
    
    enum V5StringOrBool: Codable, Sendable, Hashable {
        case string(String)
        case bool(Bool)
        
        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let b = try? container.decode(Bool.self) {
                self = .bool(b)
                return
            }
            if let s = try? container.decode(String.self) {
                self = .string(s)
                return
            }
            throw DecodingError.typeMismatch(V5StringOrBool.self, DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Expected Bool or String"))
        }
        
        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case .bool(let b): try container.encode(b)
            case .string(let s): try container.encode(s)
            }
        }
    }
    
    struct V5EventFlags: Codable {
        let missed_session: Bool
        let variation_overrides: [String: String]
        let substitutions: [String: String]
        let injury_flags: [String: V5StringOrBool]
    }
    
    struct V5Expected: Codable {
        let session_prescription_for_today: [V5Prescription]?
        let actual_logged_performance: [V5Performance]?
        let scoring: V5Scoring?
    }
    
    struct V5Prescription: Codable {
        let lift: String
        let sets: Int
        let target_reps: Int
        let target_rpe: Double?
        let prescribed_weight_lb: Double?
        let acceptable_range_lb: [Double]?
        let decision: String
        let reason_code: String
        let adjustment_kind: String?
        let lift_variation: String?
        let substituted_to: String?
    }
    
    struct V5Performance: Codable {
        let lift: String
        let performed_weight_lb: Double?
        let top_set_reps: Int
        let top_rpe: Double?
        let outcome: String
    }
    
    struct V5Scoring: Codable {
        let main_lifts: [String]
        let load_agreement: String?
        let decision_agreement: String?
    }
    
    // MARK: - Scorecard
    
    struct Scorecard {
        var totalSessions = 0
        var mainLiftPrescriptions = 0
        var loadWithinRange = 0
        var loadTotal = 0
        var loadErrors: [Double] = []
        var decisionCorrect = 0
        var decisionTotal = 0
        
        var deloadExpected = 0, deloadPredicted = 0, deloadCorrect = 0
        var holdExpected = 0, holdPredicted = 0, holdCorrect = 0
        var increaseExpected = 0, increasePredicted = 0, increaseCorrect = 0
        var decreaseSmallExpected = 0, decreaseSmallPredicted = 0, decreaseSmallCorrect = 0
        
        var coldStartCases = 0
        var coldStartMAE: [Double] = []
        
        var perUser: [String: UserScorecard] = [:]
    }
    
    struct UserScorecard {
        var sessions = 0
        var mainLifts = 0
        var loadWithinRange = 0
        var decisionCorrect = 0
        var loadErrors: [Double] = []
    }
    
    // MARK: - Diagnostics
    
    struct BucketStats {
        var count = 0
        var decisionCorrect = 0
        var loadTotal = 0
        var loadWithinRange = 0
        var loadErrors: [Double] = []
        var expectedCounts: [String: Int] = [:]
        var predictedCounts: [String: Int] = [:]
        
        mutating func record(expected: String, predicted: String, loadError: Double, withinRange: Bool) {
            count += 1
            if expected == predicted { decisionCorrect += 1 }
            loadTotal += 1
            if withinRange { loadWithinRange += 1 }
            loadErrors.append(loadError)
            expectedCounts[expected, default: 0] += 1
            predictedCounts[predicted, default: 0] += 1
        }
        
        var decisionAccuracy: Double { count > 0 ? Double(decisionCorrect) / Double(count) : 0 }
        var loadAgreement: Double { loadTotal > 0 ? Double(loadWithinRange) / Double(loadTotal) : 0 }
        var mae: Double { loadErrors.isEmpty ? 0 : loadErrors.reduce(0, +) / Double(loadErrors.count) }
    }
    
    struct UserContext {
        var userProfile: UserProfile
        var plan: TrainingPlan
        var history: WorkoutHistory
        var templateId: WorkoutTemplateId
        var exerciseCatalog: [String: Exercise]
    }
    
    let mainLifts: Set<String> = ["squat", "bench", "deadlift", "ohp"]
    
    // MARK: - Test
    
    func testWorkoutEngineTestsetV5_FullE2EReplay() throws {
        let jsonlPath = "/Users/rahulvijayan/Atlas 3/workout_engine_testset_v5_science/workout_engine_testset_v5.jsonl"
        let jsonlContent = try String(contentsOfFile: jsonlPath, encoding: .utf8)
        let lines = jsonlContent.components(separatedBy: .newlines).filter { !$0.isEmpty }
        
        let decoder = JSONDecoder()
        var records: [V5Record] = []
        var decodeFailures: [(index: Int, message: String)] = []
        for (idx, line) in lines.enumerated() {
            guard let data = line.data(using: .utf8) else { continue }
            do {
                let record = try decoder.decode(V5Record.self, from: data)
                records.append(record)
            } catch {
                if decodeFailures.count < 5 {
                    decodeFailures.append((idx, "\(error) | prefix=\(line.prefix(180))"))
                }
            }
        }
        
        XCTAssertTrue(decodeFailures.isEmpty, "Decode failures (sample): \(decodeFailures)")
        XCTAssertEqual(records.count, lines.count, "Should decode every v5 JSONL line")
        XCTAssertFalse(records.isEmpty, "Should load v5 records")
        
        var scorecard = Scorecard()
        var mismatchSamples: [String] = []
        var confusion: [String: [String: Int]] = [:]
        var byLift: [String: BucketStats] = [:]
        var byUser: [String: BucketStats] = [:]
        
        let decisionLabels = ["deload", "hold", "increase", "decrease_small"]
        
        // Group by user
        var recordsByUser: [String: [V5Record]] = [:]
        for record in records {
            recordsByUser[record.user_id, default: []].append(record)
        }
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        dateFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        
        // Sort each user's records by date
        for (userId, userRecords) in recordsByUser {
            recordsByUser[userId] = userRecords.sorted { $0.date < $1.date }
        }
        
        for (userId, userRecords) in recordsByUser.sorted(by: { $0.key < $1.key }) {
            var userScorecard = UserScorecard()
            
            guard let firstRecord = userRecords.first else { continue }
            var userContext = buildUserContext(from: firstRecord, userId: userId)
            
            for record in userRecords {
                scorecard.totalSessions += 1
                userScorecard.sessions += 1
                
                guard let sessionDate = dateFormatter.date(from: record.date) else { continue }
                
                // Update context for this session (template, body weight, etc.)
                updateContextForSession(context: &userContext, record: record, date: sessionDate)
                
                // Compute readiness from today_metrics (BLIND - no expected values used)
                let readiness = computeReadiness(from: record.input.today_metrics)
                
                // Call engine with ONLY input data - NO expected values leaked
                let enginePlan = Engine.recommendSessionForTemplate(
                    date: sessionDate,
                    templateId: userContext.templateId,
                    userProfile: userContext.userProfile,
                    plan: userContext.plan,
                    history: userContext.history,
                    readiness: readiness,
                    plannedDeloadWeek: record.input.planned_deload_week,
                    calendar: Calendar(identifier: .gregorian)
                )
                
                // Score main lift prescriptions
                for expectedRx in record.expected.session_prescription_for_today ?? [] {
                    let liftName = expectedRx.lift.lowercased()
                    guard mainLifts.contains(liftName) else { continue }
                    guard expectedRx.decision != "accessory" && !expectedRx.reason_code.contains("accessory") else { continue }
                    
                    scorecard.mainLiftPrescriptions += 1
                    userScorecard.mainLifts += 1
                    scorecard.decisionTotal += 1
                    
                    // Find matching engine exercise
                    let engineExercise = findMatchingExercise(
                        liftName: liftName,
                        variation: expectedRx.lift_variation,
                        substitutedTo: expectedRx.substituted_to,
                        in: enginePlan
                    )
                    
                    let expectedWeight = expectedRx.prescribed_weight_lb ?? 0
                    let predictedWeight = engineExercise?.sets.first?.targetLoad.converted(to: .pounds).value ?? 0
                    
                    let loadError = abs(predictedWeight - expectedWeight)
                    scorecard.loadErrors.append(loadError)
                    userScorecard.loadErrors.append(loadError)
                    
                    // Track cold starts
                    if expectedRx.reason_code.contains("cold_start") || expectedRx.adjustment_kind == "cold_start" {
                        scorecard.coldStartCases += 1
                        scorecard.coldStartMAE.append(loadError)
                    }
                    
                    let withinRange: Bool = {
                        if let range = expectedRx.acceptable_range_lb, range.count == 2 {
                            return predictedWeight >= range[0] && predictedWeight <= range[1]
                        }
                        return loadError <= 2.5
                    }()
                    
                    if withinRange {
                        scorecard.loadWithinRange += 1
                        userScorecard.loadWithinRange += 1
                    }
                    scorecard.loadTotal += 1
                    
                    // Normalize decisions
                    let expectedDecision = normalizeDecision(expectedRx.decision)
                    let predictedDecision = inferDecision(
                        plan: enginePlan,
                        exercisePlan: engineExercise,
                        liftState: userContext.history.liftStates[liftName],
                        predictedWeight: predictedWeight,
                        loadStepLb: record.input.equipment.load_step_lb,
                        isPlannedDeload: record.input.planned_deload_week
                    )
                    
                    trackDecisions(expected: expectedDecision, predicted: predictedDecision, scorecard: &scorecard)
                    
                    // Confusion matrix
                    var row = confusion[expectedDecision, default: [:]]
                    row[predictedDecision, default: 0] += 1
                    confusion[expectedDecision] = row
                    
                    // Buckets
                    byLift[liftName, default: BucketStats()].record(
                        expected: expectedDecision,
                        predicted: predictedDecision,
                        loadError: loadError,
                        withinRange: withinRange
                    )
                    byUser[userId, default: BucketStats()].record(
                        expected: expectedDecision,
                        predicted: predictedDecision,
                        loadError: loadError,
                        withinRange: withinRange
                    )
                    
                    if expectedDecision == predictedDecision {
                        scorecard.decisionCorrect += 1
                        userScorecard.decisionCorrect += 1
                    } else if mismatchSamples.count < 20 {
                        let dir = engineExercise?.direction?.rawValue ?? "nil"
                        let reason = engineExercise?.directionReason?.rawValue ?? "nil"
                        let step = record.input.equipment.load_step_lb
                        let errBucket = loadError <= step ? "err<=step" : (loadError <= 2*step ? "err<=2step" : "err>2step")
                        mismatchSamples.append(
                            "\(userId) \(record.date) \(record.session_type) lift=\(liftName) exp=\(expectedDecision)(\(expectedRx.reason_code)) pred=\(predictedDecision) \(errBucket) dir=\(dir) reason=\(reason)"
                        )
                    }
                }
                
                // Update history with actual performance for next session (sequential replay)
                if let performance = record.expected.actual_logged_performance {
                    updateHistoryWithPerformance(
                        context: &userContext,
                        enginePlan: enginePlan,
                        performance: performance,
                        expectedPrescriptions: record.expected.session_prescription_for_today ?? [],
                        date: sessionDate,
                        isDeload: enginePlan.isDeload || record.input.planned_deload_week,
                        readiness: readiness
                    )
                }
            }
            
            scorecard.perUser[userId] = userScorecard
        }
        
        // Print diagnostics
        printDiagnostics(
            scorecard: scorecard,
            confusion: confusion,
            byLift: byLift,
            byUser: byUser,
            mismatchSamples: mismatchSamples,
            decisionLabels: decisionLabels
        )
        
        printScorecard(scorecard)
        
        XCTAssertGreaterThan(scorecard.totalSessions, 50, "Should process many sessions")
    }
    
    // MARK: - Helpers
    
    private func buildUserContext(from record: V5Record, userId: String) -> UserContext {
        let input = record.input
        
        let sex: BiologicalSex = {
            switch input.user_profile.sex.lowercased() {
            case "male": return .male
            case "female": return .female
            default: return .other
            }
        }()
        
        let experience: ExperienceLevel = {
            switch input.user_profile.experience_level.lowercased() {
            case "beginner", "novice": return .beginner
            case "intermediate": return .intermediate
            case "advanced": return .advanced
            case "elite": return .elite
            default: return .intermediate
            }
        }()
        
        let goals: [TrainingGoal] = {
            switch input.user_profile.goal.lowercased() {
            case "strength": return [.strength]
            case "hypertrophy": return [.hypertrophy]
            case "strength_hypertrophy": return [.strength, .hypertrophy]
            default: return [.strength, .hypertrophy]
            }
        }()
        
        let bodyWeight = Load(value: input.user_profile.body_weight_lb, unit: .pounds)
        
        let userProfile = UserProfile(
            id: userId,
            sex: sex,
            experience: experience,
            goals: goals,
            weeklyFrequency: 3,
            availableEquipment: .commercialGym,
            preferredUnit: .pounds,
            bodyWeight: bodyWeight,
            age: input.user_profile.age,
            limitations: []
        )
        
        let exerciseCatalog = buildExerciseCatalog()
        
        let templateId = UUID()
        let increment = input.equipment.load_step_lb
        let templateExercises = input.today_session_template.compactMap { te -> TemplateExercise? in
            let baseLiftId = te.lift.lowercased()
            let substitutedLiftId = input.event_flags.substitutions[baseLiftId]?.lowercased()
            let variationLiftId = input.event_flags.variation_overrides[baseLiftId]?.lowercased()
            let effectiveLiftId = substitutedLiftId ?? variationLiftId ?? baseLiftId
            
            guard let exercise = exerciseCatalog[effectiveLiftId] ?? exerciseCatalog[baseLiftId] else { return nil }
            let prescription = SetPrescription(
                setCount: te.sets,
                targetRepsRange: te.reps...te.reps,
                targetRIR: 2,
                restSeconds: 180,
                loadStrategy: .absolute,
                increment: Load(value: increment, unit: .pounds)
            )
            return TemplateExercise(exercise: exercise, prescription: prescription)
        }
        
        let template = WorkoutTemplate(
            id: templateId,
            name: record.session_type,
            exercises: templateExercises
        )
        
        let roundingPolicy = LoadRoundingPolicy(increment: increment, unit: .pounds, mode: .nearest)
        
        var templates: [WorkoutTemplateId: WorkoutTemplate] = [:]
        templates[templateId] = template
        
        let plan = TrainingPlan(
            name: input.user_profile.program,
            templates: templates,
            schedule: .rotation(order: [templateId]),
            substitutionPool: Array(exerciseCatalog.values),
            deloadConfig: DeloadConfig(intensityReduction: 0.10, volumeReduction: 1, readinessThreshold: 50),
            loadRoundingPolicy: roundingPolicy
        )
        
        // Build initial lift states from record's history
        var liftStates: [String: LiftState] = [:]
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        dateFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        
        for (liftName, entries) in input.recent_lift_history {
            guard !entries.isEmpty else { continue }
            let sortedEntries = entries.sorted { $0.date < $1.date }
            
            var state = LiftState(exerciseId: liftName.lowercased())
            var e1rmHistory: [E1RMSample] = []
            var failStreak = 0
            var highRpeStreak = 0
            var successStreak = 0
            
            for entry in sortedEntries {
                guard let entryDate = dateFormatter.date(from: entry.date),
                      let weight = entry.weight_lb else { continue }
                
                state.lastWorkingWeight = Load(value: weight, unit: .pounds)
                state.lastSessionDate = entryDate
                
                let e1rm = E1RMCalculator.brzycki(weight: weight, reps: entry.top_set_reps)
                e1rmHistory.append(E1RMSample(date: entryDate, value: e1rm))
                
                let outcome = entry.outcome.lowercased()
                if outcome.contains("fail") || entry.decision == "deload" {
                    failStreak += 1
                    highRpeStreak = 0
                    successStreak = 0
                } else if let rpe = entry.top_rpe, rpe >= 8.5 {
                    highRpeStreak += 1
                    failStreak = 0
                    successStreak = 0
                } else {
                    failStreak = 0
                    highRpeStreak = 0
                    successStreak += 1
                }
                
                if entry.decision == "deload" {
                    state.lastDeloadDate = entryDate
                }
            }
            
            state.failureCount = failStreak
            state.highRpeStreak = highRpeStreak
            state.successStreak = successStreak
            state.e1rmHistory = Array(e1rmHistory.suffix(10))
            if !e1rmHistory.isEmpty {
                state.rollingE1RM = e1rmHistory.last!.value
            }
            state.trend = TrendCalculator.compute(from: state.e1rmHistory)
            
            liftStates[liftName.lowercased()] = state
        }
        
        let history = WorkoutHistory(sessions: [], liftStates: liftStates)
        
        return UserContext(
            userProfile: userProfile,
            plan: plan,
            history: history,
            templateId: templateId,
            exerciseCatalog: exerciseCatalog
        )
    }
    
    private func buildExerciseCatalog() -> [String: Exercise] {
        var catalog: [String: Exercise] = [:]
        
        catalog["squat"] = Exercise(id: "squat", name: "Barbell Back Squat", equipment: .barbell, primaryMuscles: [.quadriceps, .glutes], secondaryMuscles: [.hamstrings, .lowerBack], movementPattern: .squat)
        catalog["bench"] = Exercise(id: "bench", name: "Barbell Bench Press", equipment: .barbell, primaryMuscles: [.chest, .frontDelts, .triceps], movementPattern: .horizontalPush)
        catalog["close_grip_bench"] = Exercise(id: "close_grip_bench", name: "Close-Grip Bench Press", equipment: .barbell, primaryMuscles: [.chest, .frontDelts, .triceps], movementPattern: .horizontalPush)
        catalog["deadlift"] = Exercise(id: "deadlift", name: "Conventional Deadlift", equipment: .barbell, primaryMuscles: [.glutes, .hamstrings, .lowerBack], secondaryMuscles: [.quadriceps, .traps], movementPattern: .hipHinge)
        catalog["ohp"] = Exercise(id: "ohp", name: "Overhead Press", equipment: .barbell, primaryMuscles: [.frontDelts, .triceps], secondaryMuscles: [.chest], movementPattern: .verticalPush)
        catalog["row"] = Exercise(id: "row", name: "Barbell Row", equipment: .barbell, primaryMuscles: [.lats, .rhomboids], secondaryMuscles: [.biceps], movementPattern: .horizontalPull)
        catalog["pullup"] = Exercise(id: "pullup", name: "Pull-up", equipment: .bodyweight, primaryMuscles: [.lats, .biceps], movementPattern: .verticalPull)
        catalog["plank"] = Exercise(id: "plank", name: "Plank", equipment: .bodyweight, primaryMuscles: [.obliques], movementPattern: .coreFlexion)
        catalog["leg_press"] = Exercise(id: "leg_press", name: "Leg Press", equipment: .machine, primaryMuscles: [.quadriceps, .glutes], movementPattern: .squat)
        
        return catalog
    }
    
    private func updateContextForSession(context: inout UserContext, record: V5Record, date: Date) {
        let input = record.input
        let increment = input.equipment.load_step_lb
        
        // Update body weight if changed
        let newBodyWeight = Load(value: input.user_profile.body_weight_lb, unit: .pounds)
        if context.userProfile.bodyWeight?.value != newBodyWeight.value {
            context.userProfile = UserProfile(
                id: context.userProfile.id,
                sex: context.userProfile.sex,
                experience: context.userProfile.experience,
                goals: context.userProfile.goals,
                weeklyFrequency: context.userProfile.weeklyFrequency,
                availableEquipment: context.userProfile.availableEquipment,
                preferredUnit: context.userProfile.preferredUnit,
                bodyWeight: newBodyWeight,
                age: context.userProfile.age,
                limitations: context.userProfile.limitations
            )
        }
        
        // Update template for today's session
        let templateExercises = input.today_session_template.compactMap { te -> TemplateExercise? in
            let baseLiftId = te.lift.lowercased()
            let substitutedLiftId = input.event_flags.substitutions[baseLiftId]?.lowercased()
            let variationLiftId = input.event_flags.variation_overrides[baseLiftId]?.lowercased()
            let effectiveLiftId = substitutedLiftId ?? variationLiftId ?? baseLiftId
            
            guard let exercise = context.exerciseCatalog[effectiveLiftId] ?? context.exerciseCatalog[baseLiftId] else { return nil }
            let prescription = SetPrescription(
                setCount: te.sets,
                targetRepsRange: te.reps...te.reps,
                targetRIR: 2,
                restSeconds: 180,
                loadStrategy: .absolute,
                increment: Load(value: increment, unit: .pounds)
            )
            return TemplateExercise(exercise: exercise, prescription: prescription)
        }
        
        let newTemplate = WorkoutTemplate(id: context.templateId, name: record.session_type, exercises: templateExercises)
        var templates = context.plan.templates
        templates[context.templateId] = newTemplate
        
        context.plan = TrainingPlan(
            name: input.user_profile.program,
            templates: templates,
            schedule: .rotation(order: [context.templateId]),
            substitutionPool: context.plan.substitutionPool,
            deloadConfig: context.plan.deloadConfig,
            loadRoundingPolicy: context.plan.loadRoundingPolicy
        )
        
        // Rebuild lift states from this record's history (V5 provides per-session evolving history)
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        dateFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        
        for (liftName, entries) in input.recent_lift_history {
            let sortedEntries = entries.sorted { $0.date < $1.date }
            
            var state = context.history.liftStates[liftName.lowercased()] ?? LiftState(exerciseId: liftName.lowercased())
            var e1rmHistory: [E1RMSample] = []
            var failStreak = 0
            var highRpeStreak = 0
            var successStreak = 0
            
            for entry in sortedEntries {
                guard let entryDate = dateFormatter.date(from: entry.date),
                      let weight = entry.weight_lb else { continue }
                
                state.lastWorkingWeight = Load(value: weight, unit: .pounds)
                state.lastSessionDate = entryDate
                
                let e1rm = E1RMCalculator.brzycki(weight: weight, reps: entry.top_set_reps)
                e1rmHistory.append(E1RMSample(date: entryDate, value: e1rm))
                
                let outcome = entry.outcome.lowercased()
                if outcome.contains("fail") || entry.decision == "deload" {
                    failStreak += 1
                    highRpeStreak = 0
                    successStreak = 0
                } else if let rpe = entry.top_rpe, rpe >= 8.5 {
                    highRpeStreak += 1
                    failStreak = 0
                    successStreak = 0
                } else {
                    failStreak = 0
                    highRpeStreak = 0
                    successStreak += 1
                }
                
                if entry.decision == "deload" {
                    state.lastDeloadDate = entryDate
                }
            }
            
            if !entries.isEmpty {
                state.failureCount = failStreak
                state.highRpeStreak = highRpeStreak
                state.successStreak = successStreak
                state.e1rmHistory = Array(e1rmHistory.suffix(10))
                if !e1rmHistory.isEmpty {
                    state.rollingE1RM = e1rmHistory.last!.value
                }
                state.trend = TrendCalculator.compute(from: state.e1rmHistory)
            }
            
            context.history = WorkoutHistory(
                sessions: context.history.sessions,
                liftStates: {
                    var states = context.history.liftStates
                    states[liftName.lowercased()] = state
                    return states
                }()
            )
        }
    }
    
    private func computeReadiness(from metrics: V5TodayMetrics) -> Int {
        var score = 70
        
        if let sleep = metrics.sleep_hours {
            if sleep >= 7.5 { score += 10 }
            else if sleep >= 6.5 { score += 5 }
            else if sleep < 5.5 { score -= 15 }
            else if sleep < 6.0 { score -= 10 }
        }
        
        if let hrv = metrics.hrv_ms {
            if hrv > 65 { score += 10 }
            else if hrv > 55 { score += 5 }
            else if hrv < 40 { score -= 15 }
            else if hrv < 50 { score -= 5 }
        }
        
        if let soreness = metrics.soreness_1_to_10 {
            if soreness >= 8 { score -= 15 }
            else if soreness >= 6 { score -= 5 }
            else if soreness <= 3 { score += 5 }
        }
        
        if let stress = metrics.stress_1_to_10 {
            if stress >= 8 { score -= 10 }
            else if stress >= 6 { score -= 5 }
            else if stress <= 3 { score += 5 }
        }
        
        return max(20, min(100, score))
    }
    
    private func normalizeDecision(_ decision: String) -> String {
        let lower = decision.lowercased()
        if lower.contains("deload") { return "deload" }
        if lower.contains("decrease") { return "decrease_small" }
        if lower.contains("increase") { return "increase" }
        if lower.contains("hold") || lower.contains("consolidat") { return "hold" }
        return lower
    }
    
    private func inferDecision(
        plan: SessionPlan,
        exercisePlan: ExercisePlan?,
        liftState: LiftState?,
        predictedWeight: Double,
        loadStepLb: Double,
        isPlannedDeload: Bool
    ) -> String {
        if isPlannedDeload { return "deload" }
        if plan.isDeload { return "deload" }
        
        if let direction = exercisePlan?.direction {
            switch direction {
            case .increase: return "increase"
            case .hold: return "hold"
            case .decreaseSlightly: return "decrease_small"
            case .deload: return "deload"
            case .resetAfterBreak: return "deload"
            }
        }
        
        guard let state = liftState, state.lastWorkingWeight.value > 0 else {
            return "hold" // Cold start treated as hold
        }
        
        let baseline = state.lastWorkingWeight.converted(to: .pounds).value
        guard baseline > 0 else { return "hold" }
        
        let delta = predictedWeight - baseline
        let step = max(0.5, loadStepLb)
        
        if delta >= step * 0.5 { return "increase" }
        if (delta / baseline) <= -0.08 { return "deload" }
        if delta <= -step * 0.5 { return "decrease_small" }
        return "hold"
    }
    
    private func findMatchingExercise(
        liftName: String,
        variation: String?,
        substitutedTo: String?,
        in plan: SessionPlan
    ) -> ExercisePlan? {
        if let substitutedTo, !substitutedTo.isEmpty {
            let key = substitutedTo.lowercased()
            if let match = plan.exercises.first(where: { $0.exercise.id.lowercased() == key || $0.exercise.id.lowercased().contains(key) }) {
                return match
            }
        }
        
        if let variation, !variation.isEmpty {
            let key = variation.lowercased()
            if let match = plan.exercises.first(where: { $0.exercise.id.lowercased() == key || $0.exercise.id.lowercased().contains(key) }) {
                return match
            }
        }
        
        if let match = plan.exercises.first(where: { $0.exercise.id.lowercased() == liftName || $0.exercise.id.lowercased().contains(liftName) }) {
            return match
        }
        
        let targetPattern: MovementPattern? = {
            switch liftName {
            case "squat": return .squat
            case "bench": return .horizontalPush
            case "deadlift": return .hipHinge
            case "ohp": return .verticalPush
            default: return nil
            }
        }()
        
        if let pattern = targetPattern {
            return plan.exercises.first(where: { $0.exercise.movementPattern == pattern })
        }
        
        return nil
    }
    
    private func trackDecisions(expected: String, predicted: String, scorecard: inout Scorecard) {
        switch expected {
        case "deload": scorecard.deloadExpected += 1
        case "hold": scorecard.holdExpected += 1
        case "increase": scorecard.increaseExpected += 1
        case "decrease_small": scorecard.decreaseSmallExpected += 1
        default: break
        }
        
        switch predicted {
        case "deload": scorecard.deloadPredicted += 1
        case "hold": scorecard.holdPredicted += 1
        case "increase": scorecard.increasePredicted += 1
        case "decrease_small": scorecard.decreaseSmallPredicted += 1
        default: break
        }
        
        if expected == predicted {
            switch expected {
            case "deload": scorecard.deloadCorrect += 1
            case "hold": scorecard.holdCorrect += 1
            case "increase": scorecard.increaseCorrect += 1
            case "decrease_small": scorecard.decreaseSmallCorrect += 1
            default: break
            }
        }
    }
    
    private func updateHistoryWithPerformance(
        context: inout UserContext,
        enginePlan: SessionPlan,
        performance: [V5Performance],
        expectedPrescriptions: [V5Prescription],
        date: Date,
        isDeload: Bool,
        readiness: Int
    ) {
        var exerciseResults: [ExerciseSessionResult] = []
        var sessions = context.history.sessions
        
        let incrementLb = context.plan.loadRoundingPolicy.unit == .pounds ? context.plan.loadRoundingPolicy.increment : 2.5
        
        for perf in performance {
            let exerciseId = perf.lift.lowercased()
            guard let _ = context.exerciseCatalog[exerciseId] else { continue }
            
            let engineExercise = enginePlan.exercises.first(where: { exPlan in
                let eid = exPlan.exercise.id.lowercased()
                return eid == exerciseId || eid.contains(exerciseId) || exerciseId.contains(eid)
            })
            
            let prescription = expectedPrescriptions.first(where: {
                let lift = $0.lift.lowercased()
                let substituted = $0.substituted_to?.lowercased()
                let variation = $0.lift_variation?.lowercased()
                return lift == exerciseId || substituted == exerciseId || variation == exerciseId
            })
            let targetReps = prescription?.target_reps ?? perf.top_set_reps
            
            let w = perf.performed_weight_lb ?? 0
            let rpe = perf.top_rpe
            var setResults: [SetResult] = []
            
            // Create set results based on actual performance
            let setCount = prescription?.sets ?? 3
            for setIdx in 0..<setCount {
                setResults.append(SetResult(
                    reps: perf.top_set_reps,
                    load: Load(value: w, unit: .pounds),
                    rirObserved: rpe.map { max(0, Int(10 - $0)) },
                    completed: true,
                    isWarmup: false
                ))
            }
            
            let setPrescription = SetPrescription(
                setCount: setResults.count,
                targetRepsRange: targetReps...targetReps,
                targetRIR: 2,
                restSeconds: 180,
                loadStrategy: .absolute,
                increment: Load(value: incrementLb, unit: .pounds)
            )
            
            exerciseResults.append(ExerciseSessionResult(
                exerciseId: exerciseId,
                prescription: setPrescription,
                sets: setResults,
                order: exerciseResults.count,
                adjustmentKind: engineExercise?.recommendedAdjustmentKind
            ))
        }
        
        let session = CompletedSession(
            date: date,
            templateId: context.templateId,
            name: "Session",
            exerciseResults: exerciseResults,
            startedAt: date,
            endedAt: date,
            wasDeload: isDeload,
            adjustmentKind: isDeload ? .deload : SessionAdjustmentKind.none,
            previousLiftStates: context.history.liftStates,
            readinessScore: readiness,
            deloadReason: enginePlan.deloadReason
        )
        
        sessions.append(session)
        
        var updatedLiftStates = context.history.liftStates
        for state in Engine.updateLiftState(afterSession: session) {
            updatedLiftStates[state.exerciseId] = state
        }
        
        context.history = WorkoutHistory(
            sessions: sessions,
            liftStates: updatedLiftStates
        )
    }
    
    private func printDiagnostics(
        scorecard: Scorecard,
        confusion: [String: [String: Int]],
        byLift: [String: BucketStats],
        byUser: [String: BucketStats],
        mismatchSamples: [String],
        decisionLabels: [String]
    ) {
        let now = ISO8601DateFormatter().string(from: Date())
        var logLines: [String] = []
        logLines.append("v5 replay detailed diagnostics @ \(now)")
        logLines.append("sessions=\(scorecard.totalSessions) mainLiftPrescriptions=\(scorecard.mainLiftPrescriptions)")
        logLines.append("decisionAgree=\(scorecard.decisionCorrect)/\(scorecard.decisionTotal) loadAgree=\(scorecard.loadWithinRange)/\(scorecard.loadTotal) mae=\(String(format: "%.2f", scorecard.loadErrors.reduce(0, +) / Double(max(1, scorecard.loadErrors.count))))")
        logLines.append("")
        
        // Confusion matrix
        logLines.append("Decision confusion matrix (rows=expected, cols=predicted):")
        let header = (["exp\\pred"] + decisionLabels).map { String(format: "%14s", ($0 as NSString).utf8String!) }.joined()
        logLines.append(header)
        for exp in decisionLabels {
            var rowParts: [String] = []
            rowParts.append(String(format: "%14s", (exp as NSString).utf8String!))
            for pred in decisionLabels {
                let n = confusion[exp]?[pred] ?? 0
                rowParts.append(String(format: "%14d", n))
            }
            logLines.append(rowParts.joined())
        }
        logLines.append("")
        
        // By lift
        logLines.append("Buckets by lift:")
        for key in ["squat", "bench", "deadlift", "ohp"] {
            if let s = byLift[key] {
                logLines.append("  \(key): n=\(s.count) dec=\(String(format: "%.2f", s.decisionAccuracy)) load=\(String(format: "%.2f", s.loadAgreement)) mae=\(String(format: "%.1f", s.mae))")
            }
        }
        logLines.append("")
        
        // By user
        logLines.append("Per-user buckets:")
        for userKey in byUser.keys.sorted() {
            if let s = byUser[userKey] {
                logLines.append("  \(userKey): n=\(s.count) dec=\(String(format: "%.2f", s.decisionAccuracy)) load=\(String(format: "%.2f", s.loadAgreement)) mae=\(String(format: "%.1f", s.mae))")
            }
        }
        logLines.append("")
        
        // Mismatch samples
        logLines.append("Sample mismatches (up to 20):")
        for s in mismatchSamples.prefix(20) {
            logLines.append("  \(s)")
        }
        
        let logText = logLines.joined(separator: "\n")
        print("\n" + logText)
        
        // Save to file
        let logURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("v5_replay_diagnostics.log")
        do {
            try logText.write(to: logURL, atomically: true, encoding: .utf8)
            print("\n  Saved detailed v5 diagnostics to: \(logURL.path)")
        } catch {
            print("\n  Failed to write v5 diagnostics log: \(error)")
        }
    }
    
    private func printScorecard(_ scorecard: Scorecard) {
        let loadPct = scorecard.loadTotal > 0 ? Double(scorecard.loadWithinRange) / Double(scorecard.loadTotal) * 100 : 0
        let mae = scorecard.loadErrors.isEmpty ? 0 : scorecard.loadErrors.reduce(0, +) / Double(scorecard.loadErrors.count)
        let decPct = scorecard.decisionTotal > 0 ? Double(scorecard.decisionCorrect) / Double(scorecard.decisionTotal) * 100 : 0
        let coldStartMAE = scorecard.coldStartMAE.isEmpty ? 0 : scorecard.coldStartMAE.reduce(0, +) / Double(scorecard.coldStartMAE.count)
        
        print("""
        
        🧪 workout_engine_testset_v5 Full E2E Scorecard:
          Total sessions: \(scorecard.totalSessions)
          Main-lift prescriptions scored: \(scorecard.mainLiftPrescriptions)
          
          📊 Load Agreement:
            Within acceptable range: \(scorecard.loadWithinRange)/\(scorecard.loadTotal) = \(String(format: "%.1f", loadPct))%
            Mean Absolute Error: \(String(format: "%.2f", mae)) lb
          
          🎯 Decision Agreement:
            Overall: \(scorecard.decisionCorrect)/\(scorecard.decisionTotal) = \(String(format: "%.1f", decPct))%
            
            Deload: exp=\(scorecard.deloadExpected) pred=\(scorecard.deloadPredicted) correct=\(scorecard.deloadCorrect) P=\(scorecard.deloadPredicted > 0 ? String(format: "%.2f", Double(scorecard.deloadCorrect)/Double(scorecard.deloadPredicted)) : "N/A") R=\(scorecard.deloadExpected > 0 ? String(format: "%.2f", Double(scorecard.deloadCorrect)/Double(scorecard.deloadExpected)) : "N/A")
            Hold: exp=\(scorecard.holdExpected) pred=\(scorecard.holdPredicted) correct=\(scorecard.holdCorrect)
            Increase: exp=\(scorecard.increaseExpected) pred=\(scorecard.increasePredicted) correct=\(scorecard.increaseCorrect)
            Decrease Small: exp=\(scorecard.decreaseSmallExpected) pred=\(scorecard.decreaseSmallPredicted) correct=\(scorecard.decreaseSmallCorrect)
          
          🆕 Cold Start:
            Cases: \(scorecard.coldStartCases)
            MAE: \(String(format: "%.2f", coldStartMAE)) lb
          
          👤 Per-User Breakdown:
        """)
        
        for (userId, stats) in scorecard.perUser.sorted(by: { $0.key < $1.key }) {
            let userLoadPct = stats.mainLifts > 0 ? Double(stats.loadWithinRange) / Double(stats.mainLifts) * 100 : 0
            let userDecPct = stats.mainLifts > 0 ? Double(stats.decisionCorrect) / Double(stats.mainLifts) * 100 : 0
            let userMAE = stats.loadErrors.isEmpty ? 0 : stats.loadErrors.reduce(0, +) / Double(stats.loadErrors.count)
            print("    \(userId): sessions=\(stats.sessions) mainLifts=\(stats.mainLifts) loadAgree=\(String(format: "%.0f", userLoadPct))% decAgree=\(String(format: "%.0f", userDecPct))% MAE=\(String(format: "%.1f", userMAE))lb")
        }
    }
}
