// WorkoutEngineTestsetV3ReplayTests.swift
// Full E2E replay test for workout_engine_testset_v3_science dataset.

import XCTest
@testable import TrainingEngine
import Foundation

final class WorkoutEngineTestsetV3ReplayTests: XCTestCase {
    
    // MARK: - V3 Record Structures
    
    struct V3Record: Codable {
        let dataset_version: String
        let user_id: String
        let date: String
        let session_type: String
        let input: V3Input
        let expected: V3Expected
    }
    
    struct V3Input: Codable {
        let user_profile: V3UserProfile
        let equipment: V3Equipment
        let today_metrics: V3TodayMetrics
        let today_session_template: [V3TemplateExercise]
        let recent_lift_history: [String: [V3HistoryEntry]]
        let days_since_last_session: Int?
        let days_since_lift_exposure: [String: Int?]
        let event_flags: V3EventFlags
        let planned_deload_week: Bool
    }
    
    struct V3UserProfile: Codable {
        let sex: String
        let age: Int
        let height_cm: Int
        let experience_level: String
        let program: String
        let goal: String
    }
    
    struct V3Equipment: Codable {
        let units: String
        let bar_weight_lb: Double
        let load_step_lb: Double
    }
    
    struct V3TodayMetrics: Codable {
        let body_weight_lb: Double
        let sleep_hours: Double?
        let hrv_ms: Int?
        let resting_hr_bpm: Int?
        let soreness_1_to_10: Int?
        let stress_1_to_10: Int?
        let steps: Int?
        let calories_est: Int?
    }
    
    struct V3TemplateExercise: Codable {
        let lift: String
        let sets: Int
        let reps: Int
        let unit: String?
    }
    
    struct V3HistoryEntry: Codable {
        let date: String
        let session_type: String
        let weight_lb: Double?
        let target_reps: Int
        let top_set_reps: Int
        let top_rpe: Double?
        let outcome: String
        let decision: String
        let reason_code: String
        let variation: String?
        let substituted_to: String?
    }
    
    struct V3EventFlags: Codable {
        let missed_session: Bool
        let variation_overrides: [String: String]
        let substitutions: [String: String]
        let injury_flags: [String: String]
    }
    
    struct V3Expected: Codable {
        let session_prescription_for_today: [V3Prescription]
        let actual_logged_performance: [V3Performance]?
        let expected_next_session_prescription: V3NextPrescription?
        let scoring: V3Scoring?
    }
    
    struct V3Prescription: Codable {
        let lift: String
        let lift_variation: String?
        let substituted_to: String?
        let sets: Int
        let target_reps: Int
        let target_rpe: Double?
        let prescribed_weight_lb: Double?
        let acceptable_range_lb: [Double]?
        let decision: String
        let reason_code: String
        let readiness_flag: String?
    }
    
    struct V3Performance: Codable {
        let exercise: String
        let performed_sets: [V3PerformedSet]
        let top_set_rpe: Double?
        let top_set_reps: Int
        let outcome: String
    }
    
    struct V3PerformedSet: Codable {
        let set: Int
        let weight_lb: Double?
        let reps: Int
        let rpe: Double?
    }
    
    struct V3NextPrescription: Codable {
        let date: String
        let session_type: String
        let readiness_assumption_for_label: String
        let prescriptions: [V3Prescription]
    }
    
    struct V3Scoring: Codable {
        let main_lifts: [String]
        let strict_fields: [String]
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
        var estimateExpected = 0, estimatePredicted = 0, estimateCorrect = 0
        var prescribeExpected = 0, prescribePredicted = 0, prescribeCorrect = 0
        
        var perUser: [String: UserScorecard] = [:]
    }
    
    struct UserScorecard {
        var sessions = 0
        var mainLifts = 0
        var loadWithinRange = 0
        var decisionCorrect = 0
        var loadErrors: [Double] = []
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
    
    func testWorkoutEngineTestsetV3_FullE2EReplay() throws {
        let jsonlPath = "/Users/rahulvijayan/Atlas 3/workout_engine_testset_v3_science/workout_engine_testset_v3.jsonl"
        let jsonlContent = try String(contentsOfFile: jsonlPath, encoding: .utf8)
        let lines = jsonlContent.components(separatedBy: .newlines).filter { !$0.isEmpty }
        
        let decoder = JSONDecoder()
        var records: [V3Record] = []
        for line in lines {
            guard let data = line.data(using: .utf8),
                  let record = try? decoder.decode(V3Record.self, from: data) else { continue }
            records.append(record)
        }
        
        XCTAssertFalse(records.isEmpty, "Should load v3 records")
        
        var scorecard = Scorecard()
        
        // Group by user
        var recordsByUser: [String: [V3Record]] = [:]
        for record in records {
            recordsByUser[record.user_id, default: []].append(record)
        }
        
        // Sort each user's records by date
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        dateFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        
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
                
                updateContextForSession(context: &userContext, record: record, date: sessionDate)
                
                let readiness = computeReadiness(from: record.input.today_metrics)
                
                // BLIND TEST: Pass plannedDeloadWeek from input (allowed - it's an input field)
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
                
                for expectedRx in record.expected.session_prescription_for_today {
                    let liftName = expectedRx.lift.lowercased()
                    guard mainLifts.contains(liftName) else { continue }
                    guard expectedRx.decision != "accessory" && expectedRx.decision != "accessory_unlabeled" else { continue }
                    
                    scorecard.mainLiftPrescriptions += 1
                    userScorecard.mainLifts += 1
                    scorecard.decisionTotal += 1
                    
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
                    
                    if let range = expectedRx.acceptable_range_lb, range.count == 2 {
                        if predictedWeight >= range[0] && predictedWeight <= range[1] {
                            scorecard.loadWithinRange += 1
                            userScorecard.loadWithinRange += 1
                        }
                    } else if loadError <= 2.5 {
                        scorecard.loadWithinRange += 1
                        userScorecard.loadWithinRange += 1
                    }
                    scorecard.loadTotal += 1
                    
                    let expectedDecision = normalizeDecision(expectedRx.decision)
                    let effectiveExerciseId: String = {
                        if let substituted = expectedRx.substituted_to?.lowercased(), !substituted.isEmpty {
                            return substituted
                        }
                        if let variation = expectedRx.lift_variation?.lowercased(), !variation.isEmpty {
                            return variation
                        }
                        return liftName
                    }()
                    
                    // Use lift-family state keys for baseline comparison (handles substitutions/variations).
                    let stateKeyResolution = LiftFamilyResolver.resolveStateKeys(fromId: effectiveExerciseId)
                    let baselineState = userContext.history.liftStates[stateKeyResolution.updateStateKey]
                        ?? userContext.history.liftStates[stateKeyResolution.referenceStateKey]
                        ?? userContext.history.liftStates[effectiveExerciseId]
                    let baselineCoefficient: Double = (baselineState?.exerciseId == stateKeyResolution.updateStateKey) ? 1.0 : stateKeyResolution.coefficient
                    
                    let predictedDecision = inferDecision(
                        plan: enginePlan,
                        liftState: baselineState,
                        baselineCoefficient: baselineCoefficient,
                        predictedWeight: predictedWeight,
                        loadStepLb: record.input.equipment.load_step_lb,
                        isPlannedDeload: record.input.planned_deload_week
                    )
                    
                    trackDecisions(expected: expectedDecision, predicted: predictedDecision, scorecard: &scorecard)
                    
                    if expectedDecision == predictedDecision {
                        scorecard.decisionCorrect += 1
                        userScorecard.decisionCorrect += 1
                    }
                }
                
                if let performance = record.expected.actual_logged_performance {
                    updateHistoryWithPerformance(
                        context: &userContext,
                        enginePlan: enginePlan,
                        performance: performance,
                        expectedPrescriptions: record.expected.session_prescription_for_today,
                        date: sessionDate,
                        isDeload: enginePlan.isDeload || record.input.planned_deload_week,
                        readiness: readiness
                    )
                }
            }
            
            scorecard.perUser[userId] = userScorecard
        }
        
        printScorecard(scorecard)
        XCTAssertGreaterThan(scorecard.totalSessions, 100, "Should process many sessions")
    }
    
    // MARK: - Helpers
    
    private func buildUserContext(from record: V3Record, userId: String) -> UserContext {
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
        
        let bodyWeight = Load(value: input.today_metrics.body_weight_lb, unit: .pounds)
        
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
            deloadConfig: DeloadConfig(intensityReduction: 0.10, volumeReduction: 1, readinessThreshold: 45),
            loadRoundingPolicy: roundingPolicy
        )
        
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
                } else if let rpe = entry.top_rpe, rpe >= 8.5 {
                    highRpeStreak += 1
                    failStreak = 0
                } else {
                    failStreak = 0
                    highRpeStreak = 0
                }
                
                if entry.decision == "deload" {
                    state.lastDeloadDate = entryDate
                }
            }
            
            state.failureCount = failStreak
            state.highRpeStreak = highRpeStreak
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
        
        catalog["squat"] = Exercise(
            id: "squat", name: "Barbell Back Squat",
            equipment: .barbell,
            primaryMuscles: [.quadriceps, .glutes],
            secondaryMuscles: [.hamstrings, .lowerBack],
            movementPattern: .squat
        )
        
        catalog["bench"] = Exercise(
            id: "bench", name: "Barbell Bench Press",
            equipment: .barbell,
            primaryMuscles: [.chest, .frontDelts, .triceps],
            movementPattern: .horizontalPush
        )
        
        catalog["deadlift"] = Exercise(
            id: "deadlift", name: "Conventional Deadlift",
            equipment: .barbell,
            primaryMuscles: [.glutes, .hamstrings, .lowerBack],
            secondaryMuscles: [.quadriceps, .traps],
            movementPattern: .hipHinge
        )
        
        catalog["ohp"] = Exercise(
            id: "ohp", name: "Overhead Press",
            equipment: .barbell,
            primaryMuscles: [.frontDelts, .triceps],
            secondaryMuscles: [.chest],
            movementPattern: .verticalPush
        )
        
        catalog["row"] = Exercise(
            id: "row", name: "Barbell Row",
            equipment: .barbell,
            primaryMuscles: [.lats, .rhomboids],
            secondaryMuscles: [.biceps],
            movementPattern: .horizontalPull
        )
        
        catalog["pullup"] = Exercise(
            id: "pullup", name: "Pull-up",
            equipment: .bodyweight,
            primaryMuscles: [.lats, .biceps],
            movementPattern: .verticalPull
        )
        
        catalog["plank"] = Exercise(
            id: "plank", name: "Plank",
            equipment: .bodyweight,
            primaryMuscles: [.obliques],
            movementPattern: .coreFlexion
        )
        
        catalog["leg_press"] = Exercise(
            id: "leg_press", name: "Leg Press",
            equipment: .machine,
            primaryMuscles: [.quadriceps, .glutes],
            movementPattern: .squat
        )
        
        return catalog
    }
    
    private func updateContextForSession(context: inout UserContext, record: V3Record, date: Date) {
        let input = record.input
        let increment = input.equipment.load_step_lb
        
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
        
        let newTemplate = WorkoutTemplate(
            id: context.templateId,
            name: record.session_type,
            exercises: templateExercises
        )
        
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
    }
    
    private func computeReadiness(from metrics: V3TodayMetrics) -> Int {
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
        if lower.contains("estimate") || lower.contains("cold_start") { return "estimate" }
        if lower.contains("prescribe") { return "prescribe" }
        return lower
    }
    
    private func inferDecision(
        plan: SessionPlan,
        liftState: LiftState?,
        baselineCoefficient: Double,
        predictedWeight: Double,
        loadStepLb: Double,
        isPlannedDeload: Bool
    ) -> String {
        if isPlannedDeload { return "deload" }
        if plan.isDeload { return "deload" }
        
        guard let state = liftState, state.lastWorkingWeight.value > 0 else {
            return "estimate"
        }
        
        let baseline = state.lastWorkingWeight.converted(to: .pounds).value * baselineCoefficient
        guard baseline > 0 else { return "estimate" }
        
        let delta = predictedWeight - baseline
        let step = max(0.5, loadStepLb)
        
        // Prefer absolute thresholds for small adjustments (microloading/plate availability),
        // while keeping deload detection percentage-based.
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
        // 1) Substitution match takes precedence
        if let substitutedTo, !substitutedTo.isEmpty {
            let key = substitutedTo.lowercased()
            if let match = plan.exercises.first(where: { $0.exercise.id.lowercased() == key || $0.exercise.id.lowercased().contains(key) }) {
                return match
            }
        }
        
        // 2) Variation match
        if let variation, !variation.isEmpty {
            let key = variation.lowercased()
            if let match = plan.exercises.first(where: { $0.exercise.id.lowercased() == key || $0.exercise.id.lowercased().contains(key) }) {
                return match
            }
        }
        
        // 3) Base lift match
        if let match = plan.exercises.first(where: { $0.exercise.id.lowercased() == liftName || $0.exercise.id.lowercased().contains(liftName) }) {
            return match
        }
        
        // 4) Movement-pattern fallback
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
        case "estimate": scorecard.estimateExpected += 1
        case "prescribe": scorecard.prescribeExpected += 1
        default: break
        }
        
        switch predicted {
        case "deload": scorecard.deloadPredicted += 1
        case "hold": scorecard.holdPredicted += 1
        case "increase": scorecard.increasePredicted += 1
        case "decrease_small": scorecard.decreaseSmallPredicted += 1
        case "estimate": scorecard.estimatePredicted += 1
        case "prescribe": scorecard.prescribePredicted += 1
        default: break
        }
        
        if expected == predicted {
            switch expected {
            case "deload": scorecard.deloadCorrect += 1
            case "hold": scorecard.holdCorrect += 1
            case "increase": scorecard.increaseCorrect += 1
            case "decrease_small": scorecard.decreaseSmallCorrect += 1
            case "estimate": scorecard.estimateCorrect += 1
            case "prescribe": scorecard.prescribeCorrect += 1
            default: break
            }
        }
    }
    
    private func updateHistoryWithPerformance(
        context: inout UserContext,
        enginePlan: SessionPlan,
        performance: [V3Performance],
        expectedPrescriptions: [V3Prescription],
        date: Date,
        isDeload: Bool,
        readiness: Int
    ) {
        var exerciseResults: [ExerciseSessionResult] = []
        var sessions = context.history.sessions
        
        // Use the plan's rounding increment as the set prescription increment.
        let incrementLb = context.plan.loadRoundingPolicy.unit == .pounds ? context.plan.loadRoundingPolicy.increment : 2.5
        
        for perf in performance {
            let exerciseId = perf.exercise.lowercased()
            guard let _ = context.exerciseCatalog[exerciseId] else { continue }
            
            // Find matching engine exercise plan to propagate adjustment kind
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
            
            var setResults: [SetResult] = []
            for set in perf.performed_sets {
                let w = set.weight_lb ?? 0
                let rpe = set.rpe
                setResults.append(SetResult(
                    reps: set.reps,
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
            
            // BLIND TEST: Propagate engine's recommendedAdjustmentKind into ExerciseSessionResult
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
            readinessScore: readiness
        )
        
        sessions.append(session)
        
        // Use the production state updater to ensure canonical lift-family keys + coefficients are handled correctly.
        var updatedLiftStates = context.history.liftStates
        for state in Engine.updateLiftState(afterSession: session) {
            updatedLiftStates[state.exerciseId] = state
        }
        
        context.history = WorkoutHistory(
            sessions: sessions,
            liftStates: updatedLiftStates
        )
    }
    
    private func printScorecard(_ scorecard: Scorecard) {
        let loadPct = scorecard.loadTotal > 0 ? Double(scorecard.loadWithinRange) / Double(scorecard.loadTotal) * 100 : 0
        let mae = scorecard.loadErrors.isEmpty ? 0 : scorecard.loadErrors.reduce(0, +) / Double(scorecard.loadErrors.count)
        let decPct = scorecard.decisionTotal > 0 ? Double(scorecard.decisionCorrect) / Double(scorecard.decisionTotal) * 100 : 0
        
        // Exclude the known synthetic outlier user (U205 has leg_press values reaching >1M lb in the dataset).
        var exclMain = 0
        var exclWithin = 0
        var exclDecisionCorrect = 0
        var exclErrors: [Double] = []
        for (uid, stats) in scorecard.perUser where uid != "U205" {
            exclMain += stats.mainLifts
            exclWithin += stats.loadWithinRange
            exclDecisionCorrect += stats.decisionCorrect
            exclErrors.append(contentsOf: stats.loadErrors)
        }
        let exclLoadPct = exclMain > 0 ? Double(exclWithin) / Double(exclMain) * 100 : 0
        let exclMae = exclErrors.isEmpty ? 0 : exclErrors.reduce(0, +) / Double(exclErrors.count)
        let exclDecPct = exclMain > 0 ? Double(exclDecisionCorrect) / Double(exclMain) * 100 : 0
        
        print("""
        
        🧪 workout_engine_testset_v3 Full E2E Scorecard:
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
            Estimate: exp=\(scorecard.estimateExpected) pred=\(scorecard.estimatePredicted) correct=\(scorecard.estimateCorrect)
            Prescribe: exp=\(scorecard.prescribeExpected) pred=\(scorecard.prescribePredicted) correct=\(scorecard.prescribeCorrect)
            
          🚫 Excluding U205 (synthetic leg_press explosion):
            Load Agreement: \(String(format: "%.1f", exclLoadPct))% (MAE \(String(format: "%.2f", exclMae)) lb)
            Decision Agreement: \(String(format: "%.1f", exclDecPct))%
          
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
