// WorkoutEngineTestsetV6ReplayTests.swift
// Full E2E replay test for workout_engine_testset_v6_science dataset.
// V6: Evidence-aligned %1RM mapping, explicit readiness_cut/break_reset labeling, RPE→RIR mapping.

import XCTest
@testable import TrainingEngine
import Foundation

final class WorkoutEngineTestsetV6ReplayTests: XCTestCase {
    
    // MARK: - V6 Record Structures
    
    struct V6Record: Codable {
        let dataset_version: String
        let user_id: String
        let date: String
        let session_type: String
        let input: V6Input
        let expected: V6Expected
    }
    
    struct V6Input: Codable {
        let user_profile: V6UserProfile
        let equipment: V6Equipment
        let today_metrics: V6TodayMetrics
        let today_session_template: [V6TemplateExercise]
        let recent_lift_history: [String: [V6HistoryEntry]]
        let days_since_last_session: Int?
        let days_since_lift_exposure: [String: Int?]
        let event_flags: V6EventFlags
        let planned_deload_week: Bool
    }
    
    struct V6UserProfile: Codable {
        let sex: String
        let age: Int
        let height_cm: Int
        let body_weight_lb: Double
        let experience_level: String
        let program: String
        let goal: String
    }
    
    struct V6Equipment: Codable {
        let units: String
        let bar_weight_lb: Double
        let load_step_lb: Double
    }
    
    struct V6TodayMetrics: Codable {
        let sleep_hours: Double?
        let hrv_ms: Int?
        let resting_hr_bpm: Int?
        let soreness_1_to_10: Int?
        let stress_1_to_10: Int?
        let steps: Int?
        let calories_est: Int?
    }
    
    struct V6TemplateExercise: Codable {
        let lift: String
        let sets: Int
        let reps: Int
        let unit: String?
    }
    
    struct V6HistoryEntry: Codable {
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
    
    enum V6StringOrBool: Codable, Sendable, Hashable {
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
            throw DecodingError.typeMismatch(V6StringOrBool.self, DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Expected Bool or String"))
        }
        
        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case .bool(let b): try container.encode(b)
            case .string(let s): try container.encode(s)
            }
        }
    }
    
    struct V6EventFlags: Codable {
        let missed_session: Bool
        let variation_overrides: [String: String]
        let substitutions: [String: String]
        let injury_flags: [String: V6StringOrBool]
    }
    
    struct V6Expected: Codable {
        let session_prescription_for_today: [V6Prescription]?
        let actual_logged_performance: [V6Performance]?
        let scoring: V6Scoring?
    }
    
    struct V6Prescription: Codable {
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
    
    struct V6Performance: Codable {
        let lift: String
        let performed_weight_lb: Double?
        let top_set_reps: Int
        let top_rpe: Double?
        let outcome: String
    }
    
    struct V6Scoring: Codable {
        let main_lifts: [String]
        let load_agreement: String?
        let decision_agreement: String?
        let notes: String?
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
    
    /// Mismatch sample with detailed engine state
    struct MismatchSample {
        let userId: String
        let date: String
        let sessionType: String
        let lift: String
        let expectedDecision: String
        let expectedReasonCode: String
        let predictedDecision: String
        let engineDirection: String
        let engineDirectionReason: String
        let loadError: Double
        let expectedWeight: Double
        let predictedWeight: Double
        let readiness: Int
    }
    
    struct UserContext {
        var userProfile: UserProfile
        var plan: TrainingPlan
        var history: WorkoutHistory
        var templateId: WorkoutTemplateId
        var exerciseCatalog: [String: Exercise]
    }
    
    let mainLifts: Set<String> = ["squat", "bench", "deadlift", "ohp"]
    
    // MARK: - RPE to RIR Mapping
    
    /// Convert target RPE to target RIR.
    /// Standard coaching convention: RPE 10 = 0 RIR, RPE 9 = 1 RIR, RPE 8 = 2 RIR, etc.
    /// Clamped to 0-5 for practical training purposes.
    private func rpeToRIR(_ rpe: Double) -> Int {
        let rir = Int(round(10.0 - rpe))
        return max(0, min(5, rir))
    }
    
    /// Infer a reasonable target RIR from rep target when target_rpe is not available.
    /// Heuristic based on common programming patterns:
    /// - Heavy work (≤5 reps): RPE ~8.5 → RIR ~1-2
    /// - Moderate work (6-8 reps): RPE ~8 → RIR ~2
    /// - Higher reps (9+ reps): RPE ~7.5 → RIR ~2-3
    private func inferRIRFromReps(_ targetReps: Int) -> Int {
        if targetReps <= 3 {
            return 1  // Heavy work, closer to failure
        } else if targetReps <= 5 {
            return 2  // Strength work
        } else if targetReps <= 8 {
            return 2  // Moderate work
        } else {
            return 3  // Higher rep work, more buffer
        }
    }
    
    // MARK: - Test
    
    func testWorkoutEngineTestsetV6_FullE2EReplay() throws {
        let jsonlPath = "/Users/rahulvijayan/Atlas 3/workout_engine_testset_v6_science/workout_engine_testset_v6.jsonl"
        let jsonlContent = try String(contentsOfFile: jsonlPath, encoding: .utf8)
        let lines = jsonlContent.components(separatedBy: .newlines).filter { !$0.isEmpty }
        
        let decoder = JSONDecoder()
        var records: [V6Record] = []
        var decodeFailures: [(index: Int, message: String)] = []
        for (idx, line) in lines.enumerated() {
            guard let data = line.data(using: .utf8) else { continue }
            do {
                let record = try decoder.decode(V6Record.self, from: data)
                records.append(record)
            } catch {
                if decodeFailures.count < 5 {
                    decodeFailures.append((idx, "\(error) | prefix=\(line.prefix(180))"))
                }
            }
        }
        
        XCTAssertTrue(decodeFailures.isEmpty, "Decode failures (sample): \(decodeFailures)")
        XCTAssertEqual(records.count, lines.count, "Should decode every v6 JSONL line")
        XCTAssertFalse(records.isEmpty, "Should load v6 records")
        
        var scorecard = Scorecard()
        var mismatchSamples: [MismatchSample] = []
        var confusion: [String: [String: Int]] = [:]
        var byLift: [String: BucketStats] = [:]
        var byUser: [String: BucketStats] = [:]
        
        // Track mismatch pairs with reason codes for analysis
        var mismatchPairs: [String: Int] = [:] // "exp→pred:reason" → count
        
        let decisionLabels = ["deload", "hold", "increase", "decrease_small"]
        
        // Group by user
        var recordsByUser: [String: [V6Record]] = [:]
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
                    } else {
                        // Track mismatch pair with engine reason
                        let dir = engineExercise?.direction?.rawValue ?? "nil"
                        let reason = engineExercise?.directionReason?.rawValue ?? "nil"
                        let pairKey = "\(expectedDecision)→\(predictedDecision):\(reason)"
                        mismatchPairs[pairKey, default: 0] += 1
                        
                        // Collect detailed mismatch sample
                        if mismatchSamples.count < 50 {
                            mismatchSamples.append(MismatchSample(
                                userId: userId,
                                date: record.date,
                                sessionType: record.session_type,
                                lift: liftName,
                                expectedDecision: expectedDecision,
                                expectedReasonCode: expectedRx.reason_code,
                                predictedDecision: predictedDecision,
                                engineDirection: dir,
                                engineDirectionReason: reason,
                                loadError: loadError,
                                expectedWeight: expectedWeight,
                                predictedWeight: predictedWeight,
                                readiness: readiness
                            ))
                        }
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
            mismatchPairs: mismatchPairs,
            decisionLabels: decisionLabels
        )
        
        printScorecard(scorecard)
        
        XCTAssertGreaterThan(scorecard.totalSessions, 50, "Should process many sessions")
    }
    
    // MARK: - Helpers
    
    private func buildUserContext(from record: V6Record, userId: String) -> UserContext {
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
            
            // V6: Infer targetRIR from rep target (template doesn't have target_rpe)
            let targetRIR = inferRIRFromReps(te.reps)
            
            // V6: Use %e1RM for compound lifts with intermediate+ users
            let isCompound = exercise.movementPattern.isCompound
            let isIntermediatePlus = experience != .beginner
            let isHeavyWork = te.reps <= 5
            let loadStrategy: LoadStrategy = (isCompound && isIntermediatePlus && isHeavyWork) ? .percentageE1RM : .absolute
            
            let prescription = SetPrescription(
                setCount: te.sets,
                targetRepsRange: te.reps...te.reps,
                targetRIR: targetRIR,
                restSeconds: 180,
                loadStrategy: loadStrategy,
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
        catalog["sumo_deadlift"] = Exercise(id: "sumo_deadlift", name: "Sumo Deadlift", equipment: .barbell, primaryMuscles: [.glutes, .hamstrings, .quadriceps], secondaryMuscles: [.lowerBack, .traps], movementPattern: .hipHinge)
        catalog["ohp"] = Exercise(id: "ohp", name: "Overhead Press", equipment: .barbell, primaryMuscles: [.frontDelts, .triceps], secondaryMuscles: [.chest], movementPattern: .verticalPush)
        catalog["row"] = Exercise(id: "row", name: "Barbell Row", equipment: .barbell, primaryMuscles: [.lats, .rhomboids], secondaryMuscles: [.biceps], movementPattern: .horizontalPull)
        catalog["pullup"] = Exercise(id: "pullup", name: "Pull-up", equipment: .bodyweight, primaryMuscles: [.lats, .biceps], movementPattern: .verticalPull)
        catalog["plank"] = Exercise(id: "plank", name: "Plank", equipment: .bodyweight, primaryMuscles: [.obliques], movementPattern: .coreFlexion)
        catalog["leg_press"] = Exercise(id: "leg_press", name: "Leg Press", equipment: .machine, primaryMuscles: [.quadriceps, .glutes], movementPattern: .squat)
        catalog["front_squat"] = Exercise(id: "front_squat", name: "Front Squat", equipment: .barbell, primaryMuscles: [.quadriceps, .glutes], secondaryMuscles: [.lowerBack], movementPattern: .squat)
        catalog["incline_db"] = Exercise(id: "incline_db", name: "Incline Dumbbell Press", equipment: .dumbbell, primaryMuscles: [.chest, .frontDelts], movementPattern: .horizontalPush)
        
        return catalog
    }
    
    private func updateContextForSession(context: inout UserContext, record: V6Record, date: Date) {
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
        
        // Update template for today's session, including RPE→RIR mapping
        let templateExercises = input.today_session_template.compactMap { te -> TemplateExercise? in
            let baseLiftId = te.lift.lowercased()
            let substitutedLiftId = input.event_flags.substitutions[baseLiftId]?.lowercased()
            let variationLiftId = input.event_flags.variation_overrides[baseLiftId]?.lowercased()
            let effectiveLiftId = substitutedLiftId ?? variationLiftId ?? baseLiftId
            
            guard let exercise = context.exerciseCatalog[effectiveLiftId] ?? context.exerciseCatalog[baseLiftId] else { return nil }
            
            // V6: Infer targetRIR from rep target
            let targetRIR = inferRIRFromReps(te.reps)
            
            // V6: Use %e1RM for compound lifts with intermediate+ users
            let isCompound = exercise.movementPattern.isCompound
            let isIntermediatePlus = context.userProfile.experience != .beginner
            let isHeavyWork = te.reps <= 5
            let loadStrategy: LoadStrategy = (isCompound && isIntermediatePlus && isHeavyWork) ? .percentageE1RM : .absolute
            
            let prescription = SetPrescription(
                setCount: te.sets,
                targetRepsRange: te.reps...te.reps,
                targetRIR: targetRIR,
                restSeconds: 180,
                loadStrategy: loadStrategy,
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
        
        // Rebuild lift states from this record's history (V6 provides per-session evolving history)
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
    
    private func computeReadiness(from metrics: V6TodayMetrics) -> Int {
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
    
    /// V6: Map engine direction to external decision label.
    /// Key change: `.resetAfterBreak` maps to `decrease_small` (not `deload`) per v6 rulebook.
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
            // V6 key change: resetAfterBreak is a conservative cut (~10%), maps to decrease_small
            case .resetAfterBreak: return "decrease_small"
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
        performance: [V6Performance],
        expectedPrescriptions: [V6Prescription],
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
            
            // V6: Derive targetRIR from target_rpe if available, else infer from reps
            let targetRIR: Int = {
                if let rpe = prescription?.target_rpe {
                    return rpeToRIR(rpe)
                }
                return inferRIRFromReps(targetReps)
            }()
            
            let w = perf.performed_weight_lb ?? 0
            let rpe = perf.top_rpe
            var setResults: [SetResult] = []
            
            // Create set results based on actual performance
            let setCount = prescription?.sets ?? 3
            for _ in 0..<setCount {
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
                targetRIR: targetRIR,
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
        mismatchSamples: [MismatchSample],
        mismatchPairs: [String: Int],
        decisionLabels: [String]
    ) {
        let now = ISO8601DateFormatter().string(from: Date())
        var logLines: [String] = []
        logLines.append("=" * 80)
        logLines.append("V6 REPLAY DETAILED DIAGNOSTICS @ \(now)")
        logLines.append("=" * 80)
        logLines.append("")
        logLines.append("SUMMARY:")
        logLines.append("  sessions=\(scorecard.totalSessions) mainLiftPrescriptions=\(scorecard.mainLiftPrescriptions)")
        
        let loadPct = scorecard.loadTotal > 0 ? Double(scorecard.loadWithinRange) / Double(scorecard.loadTotal) * 100 : 0
        let decPct = scorecard.decisionTotal > 0 ? Double(scorecard.decisionCorrect) / Double(scorecard.decisionTotal) * 100 : 0
        let mae = scorecard.loadErrors.isEmpty ? 0 : scorecard.loadErrors.reduce(0, +) / Double(scorecard.loadErrors.count)
        
        logLines.append("  Load Agreement: \(scorecard.loadWithinRange)/\(scorecard.loadTotal) = \(String(format: "%.1f", loadPct))%")
        logLines.append("  Decision Agreement: \(scorecard.decisionCorrect)/\(scorecard.decisionTotal) = \(String(format: "%.1f", decPct))%")
        logLines.append("  MAE: \(String(format: "%.2f", mae)) lb")
        logLines.append("")
        
        // Confusion matrix
        logLines.append("-" * 80)
        logLines.append("DECISION CONFUSION MATRIX (rows=expected, cols=predicted):")
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
        
        // Top mismatch pairs with engine reason
        logLines.append("-" * 80)
        logLines.append("TOP MISMATCH PAIRS (exp→pred:engineReason):")
        let sortedPairs = mismatchPairs.sorted { $0.value > $1.value }
        for (pair, count) in sortedPairs.prefix(15) {
            logLines.append("  \(count)x  \(pair)")
        }
        logLines.append("")
        
        // By lift
        logLines.append("-" * 80)
        logLines.append("BUCKETS BY LIFT:")
        for key in ["squat", "bench", "deadlift", "ohp"] {
            if let s = byLift[key] {
                logLines.append("  \(key): n=\(s.count) dec=\(String(format: "%.1f%%", s.decisionAccuracy * 100)) load=\(String(format: "%.1f%%", s.loadAgreement * 100)) mae=\(String(format: "%.1f", s.mae))lb")
            }
        }
        logLines.append("")
        
        // By user
        logLines.append("-" * 80)
        logLines.append("PER-USER BUCKETS:")
        for userKey in byUser.keys.sorted() {
            if let s = byUser[userKey] {
                logLines.append("  \(userKey): n=\(s.count) dec=\(String(format: "%.1f%%", s.decisionAccuracy * 100)) load=\(String(format: "%.1f%%", s.loadAgreement * 100)) mae=\(String(format: "%.1f", s.mae))lb")
            }
        }
        logLines.append("")
        
        // Detailed mismatch samples
        logLines.append("-" * 80)
        logLines.append("SAMPLE MISMATCHES (up to 50):")
        for sample in mismatchSamples.prefix(50) {
            let errStr = String(format: "%.1f", sample.loadError)
            logLines.append("  \(sample.userId) \(sample.date) \(sample.sessionType) lift=\(sample.lift)")
            logLines.append("    exp=\(sample.expectedDecision)(\(sample.expectedReasonCode)) pred=\(sample.predictedDecision)")
            logLines.append("    engine: dir=\(sample.engineDirection) reason=\(sample.engineDirectionReason)")
            logLines.append("    weight: exp=\(String(format: "%.1f", sample.expectedWeight))lb pred=\(String(format: "%.1f", sample.predictedWeight))lb err=\(errStr)lb readiness=\(sample.readiness)")
        }
        
        let logText = logLines.joined(separator: "\n")
        print("\n" + logText)
        
        // Save to file
        let logURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("v6_replay_diagnostics.log")
        do {
            try logText.write(to: logURL, atomically: true, encoding: .utf8)
            print("\n  Saved detailed v6 diagnostics to: \(logURL.path)")
        } catch {
            print("\n  Failed to write v6 diagnostics log: \(error)")
        }
    }
    
    private func printScorecard(_ scorecard: Scorecard) {
        let loadPct = scorecard.loadTotal > 0 ? Double(scorecard.loadWithinRange) / Double(scorecard.loadTotal) * 100 : 0
        let mae = scorecard.loadErrors.isEmpty ? 0 : scorecard.loadErrors.reduce(0, +) / Double(scorecard.loadErrors.count)
        let decPct = scorecard.decisionTotal > 0 ? Double(scorecard.decisionCorrect) / Double(scorecard.decisionTotal) * 100 : 0
        let coldStartMAE = scorecard.coldStartMAE.isEmpty ? 0 : scorecard.coldStartMAE.reduce(0, +) / Double(scorecard.coldStartMAE.count)
        
        print("""
        
        🧪 workout_engine_testset_v6 Full E2E Scorecard:
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

// MARK: - String extension for diagnostics formatting
private extension String {
    static func * (lhs: String, rhs: Int) -> String {
        return String(repeating: lhs, count: rhs)
    }
}
