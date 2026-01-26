// WorkoutEngineTestsetV2ReplayTests.swift
// Full E2E replay test for workout_engine_testset_v2.jsonl

import XCTest
@testable import TrainingEngine
import Foundation

final class WorkoutEngineTestsetV2ReplayTests: XCTestCase {
    
    // MARK: - Data Structures
    
    struct V2Record: Codable {
        let dataset_version: String
        let user_id: String
        let date: String
        let session_type: String
        let input: V2Input
        let expected: V2Expected
    }
    
    struct V2Input: Codable {
        let user_profile: V2UserProfile
        let equipment: V2Equipment
        let today_metrics: V2TodayMetrics
        let today_session_template: [V2TemplateExercise]
        let recent_lift_history: [String: [V2LiftHistoryEntry]]
        let days_since_last_session: Int?
        let days_since_lift_exposure: [String: Int?]
        let event_flags: V2EventFlags
    }
    
    struct V2UserProfile: Codable {
        let sex: String
        let age: Int
        let height_cm: Int
        let experience_level: String
        let program: String
        let goal: String
        let body_weight_lb: Double?
        let deficit_flag: Bool?
    }
    
    struct V2Equipment: Codable {
        let units: String
        let microplate_lb: Double?
        let bar_weight_lb: Double?
    }
    
    struct V2TodayMetrics: Codable {
        let body_weight_lb: Double
        let sleep_hours: Double?
        let hrv_ms: Int?
        let resting_hr_bpm: Int?
        let soreness_1_to_10: Int?
        let stress_1_to_10: Int?
        let steps: Int?
        let calories_est: Int?
    }
    
    struct V2TemplateExercise: Codable {
        let lift: String
        let sets: Int
        let reps: Int
        let unit: String?
        let intent: String?
    }
    
    struct V2LiftHistoryEntry: Codable {
        let date: String
        let weight_lb: Double?
        let reps: Int
        let top_rpe: Double?
        let outcome: String
        let tag: String?
        let variation: String?
        let substituted_to: String?
        let reason_code: String?
        let decision: String?
    }
    
    struct V2EventFlags: Codable {
        let missed_session: Bool?
        let injury_flags: [String: String]?
        let variation_overrides: [String: String]?
        let substitutions: [String: String]?
        let planned_deload: Bool?
    }
    
    struct V2Expected: Codable {
        let session_prescription_for_today: [V2Prescription]
        let actual_logged_performance: [V2Performance]?
        let expected_next_session_prescription: V2NextSession?
        let scoring: V2Scoring?
    }
    
    struct V2Prescription: Codable {
        let lift: String
        let lift_variation: String?
        let substituted_to: String?
        let sets: Int
        let target_reps: Int
        let target_rpe: Double?
        let prescribed_weight_lb: Double?
        let decision: String
        let delta_lb: Double?
        let reason_code: String?
    }
    
    struct V2Performance: Codable {
        let exercise: String
        let performed_sets: [V2PerformedSet]?
        let top_set_rpe: Double?
        let outcome: String
    }
    
    struct V2PerformedSet: Codable {
        let set: Int
        let weight_lb: Double?
        let reps: Int?
        let rpe: Double?
        let value: Int?
        let unit: String?
    }
    
    struct V2NextSession: Codable {
        let date: String
        let session_type: String
        let readiness_assumption_for_label: String?
        let prescriptions: [V2Prescription]
    }
    
    struct V2Scoring: Codable {
        let main_lifts: [String]
        let tolerance_lb: Double
        let strict_fields: [String]
        let notes: String?
    }
    
    // MARK: - Scorecard
    
    struct Scorecard {
        var totalSessions = 0
        var mainLiftPrescriptions = 0
        var loadAgreements = 0
        var decisionAgreements = 0
        var loadErrors: [Double] = []
        
        var deloadExpected = 0
        var deloadPredicted = 0
        var deloadCorrect = 0
        
        var holdExpected = 0
        var holdPredicted = 0
        var holdCorrect = 0
        
        var increaseExpected = 0
        var increasePredicted = 0
        var increaseCorrect = 0
        
        var decreaseSmallExpected = 0
        var decreaseSmallPredicted = 0
        var decreaseSmallCorrect = 0
        
        var coldStartCases = 0
        var coldStartLoadErrors: [Double] = []
        
        var microloadCases = 0
        var microloadCorrect = 0
        
        var perUser: [String: UserScorecard] = [:]
    }
    
    struct UserScorecard {
        var sessions = 0
        var mainLiftPrescriptions = 0
        var loadAgreements = 0
        var decisionAgreements = 0
        var loadErrors: [Double] = []
    }
    
    // MARK: - Test
    
    func testWorkoutEngineTestsetV2_FullE2EReplay() throws {
        let jsonlPath = "/Users/rahulvijayan/Atlas 3/workout_engine_testset_v2/workout_engine_testset_v2.jsonl"
        let content = try String(contentsOfFile: jsonlPath, encoding: .utf8)
        let lines = content.components(separatedBy: .newlines).filter { !$0.isEmpty }
        
        let decoder = JSONDecoder()
        var records: [V2Record] = []
        for line in lines {
            guard let data = line.data(using: .utf8) else { continue }
            if let record = try? decoder.decode(V2Record.self, from: data) {
                records.append(record)
            }
        }
        
        XCTAssertGreaterThan(records.count, 0, "Should have loaded records")
        
        var scorecard = Scorecard()
        let mainLifts: Set<String> = ["squat", "bench", "deadlift", "ohp"]
        let tolerance = 2.5
        
        // Group records by user for sequential replay
        var recordsByUser: [String: [V2Record]] = [:]
        for record in records {
            recordsByUser[record.user_id, default: []].append(record)
        }
        
        // Sort each user's records by date
        for (userId, userRecords) in recordsByUser {
            recordsByUser[userId] = userRecords.sorted { $0.date < $1.date }
        }
        
        // Process each user sequentially
        for (userId, userRecords) in recordsByUser.sorted(by: { $0.key < $1.key }) {
            var userScorecard = UserScorecard()
            
            guard let firstRecord = userRecords.first else { continue }
            var userContext = buildUserContext(from: firstRecord, userId: userId)
            
            for record in userRecords {
                scorecard.totalSessions += 1
                userScorecard.sessions += 1
                
                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "yyyy-MM-dd"
                dateFormatter.timeZone = TimeZone(secondsFromGMT: 0)
                guard let sessionDate = dateFormatter.date(from: record.date) else { continue }
                
                updateContextForSession(context: &userContext, record: record, date: sessionDate)
                
                let readiness = computeReadiness(from: record.input.today_metrics, input: record.input)
                let isPlannedDeload = record.input.event_flags.planned_deload ?? false
                
                // BLIND TEST: Pass plannedDeloadWeek from input (allowed - it's an input field)
                let enginePlan = Engine.recommendSessionForTemplate(
                    date: sessionDate,
                    templateId: userContext.templateId,
                    userProfile: userContext.userProfile,
                    plan: userContext.plan,
                    history: userContext.history,
                    readiness: readiness,
                    plannedDeloadWeek: isPlannedDeload,
                    calendar: Calendar(identifier: .gregorian)
                )
                
                // Score against expected (after getting engine output)
                for expectedPrescription in record.expected.session_prescription_for_today {
                    let liftName = expectedPrescription.lift.lowercased()
                    
                    guard mainLifts.contains(liftName) else { continue }
                    
                    scorecard.mainLiftPrescriptions += 1
                    userScorecard.mainLiftPrescriptions += 1
                    
                    let engineExercise = findMatchingExercise(
                        liftName: liftName,
                        variation: expectedPrescription.lift_variation,
                        substitutedTo: expectedPrescription.substituted_to,
                        in: enginePlan
                    )
                    
                    let expectedWeight = expectedPrescription.prescribed_weight_lb ?? 0
                    let expectedDecision = expectedPrescription.decision
                    
                    let predictedWeight: Double
                    let predictedDecision: String
                    
                    if let exercise = engineExercise {
                        predictedWeight = exercise.sets.first?.targetLoad.converted(to: .pounds).value ?? 0
                        predictedDecision = inferDecision(
                            plan: enginePlan,
                            liftState: userContext.history.liftStates[liftName],
                            predictedWeight: predictedWeight,
                            isPlannedDeload: isPlannedDeload
                        )
                    } else {
                        predictedWeight = 0
                        predictedDecision = "missing"
                    }
                    
                    let loadError = abs(predictedWeight - expectedWeight)
                    scorecard.loadErrors.append(loadError)
                    userScorecard.loadErrors.append(loadError)
                    
                    if loadError <= tolerance {
                        scorecard.loadAgreements += 1
                        userScorecard.loadAgreements += 1
                    }
                    
                    let decisionMatch = decisionsMatch(expected: expectedDecision, predicted: predictedDecision)
                    if decisionMatch {
                        scorecard.decisionAgreements += 1
                        userScorecard.decisionAgreements += 1
                    }
                    
                    trackDecisionCategory(expected: expectedDecision, predicted: predictedDecision, scorecard: &scorecard)
                    
                    let hasHistory = !(record.input.recent_lift_history[liftName]?.isEmpty ?? true)
                    if !hasHistory {
                        scorecard.coldStartCases += 1
                        scorecard.coldStartLoadErrors.append(loadError)
                    }
                    
                    if let delta = expectedPrescription.delta_lb, abs(abs(delta) - 1.25) < 0.01 {
                        scorecard.microloadCases += 1
                        if loadError <= 1.25 {
                            scorecard.microloadCorrect += 1
                        }
                    }
                }
                
                // Update history for next session
                if let performance = record.expected.actual_logged_performance {
                    updateHistoryWithPerformance(
                        context: &userContext,
                        enginePlan: enginePlan,
                        performance: performance,
                        expectedPrescriptions: record.expected.session_prescription_for_today,
                        date: sessionDate,
                        isDeload: enginePlan.isDeload || isPlannedDeload,
                        readiness: readiness
                    )
                }
            }
            
            scorecard.perUser[userId] = userScorecard
        }
        
        printScorecard(scorecard)
        XCTAssertGreaterThan(scorecard.totalSessions, 100, "Should have processed many sessions")
    }
    
    // MARK: - Helpers
    
    struct UserContext {
        var userProfile: UserProfile
        var plan: TrainingPlan
        var history: WorkoutHistory
        var templateId: WorkoutTemplateId
        var exerciseCatalog: [String: Exercise]
    }
    
    private func buildUserContext(from record: V2Record, userId: String) -> UserContext {
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
        let increment = input.equipment.microplate_lb ?? 2.5
        let templateExercises = input.today_session_template.compactMap { te -> TemplateExercise? in
            guard let exercise = exerciseCatalog[te.lift.lowercased()] else { return nil }
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
        
        // Build initial history from recent_lift_history
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
                
                let load = Load(value: weight, unit: .pounds)
                state.lastWorkingWeight = load
                state.lastSessionDate = entryDate
                
                let e1rm = E1RMCalculator.brzycki(weight: weight, reps: entry.reps)
                e1rmHistory.append(E1RMSample(date: entryDate, value: e1rm))
                
                let decision = entry.decision ?? ""
                let outcome = entry.outcome.lowercased()
                
                if outcome.contains("fail") || decision == "deload" {
                    failStreak += 1
                    highRpeStreak = 0
                } else if let rpe = entry.top_rpe, rpe >= 8.5 {
                    highRpeStreak += 1
                    failStreak = 0
                } else {
                    failStreak = 0
                    highRpeStreak = 0
                }
                
                if decision == "deload" {
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
        
        let history = WorkoutHistory(
            sessions: [],
            liftStates: liftStates
        )
        
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
            primaryMuscles: [.lats],
            secondaryMuscles: [.biceps],
            movementPattern: .verticalPull
        )
        
        catalog["split_squat"] = Exercise(
            id: "split_squat", name: "Split Squat",
            equipment: .dumbbell,
            primaryMuscles: [.quadriceps, .glutes],
            movementPattern: .squat
        )
        
        catalog["plank"] = Exercise(
            id: "plank", name: "Plank",
            equipment: .bodyweight,
            primaryMuscles: [.abdominals],
            movementPattern: .coreFlexion
        )
        
        catalog["leg_press"] = Exercise(
            id: "leg_press", name: "Leg Press",
            equipment: .machine,
            primaryMuscles: [.quadriceps, .glutes],
            movementPattern: .squat
        )
        
        catalog["incline_bench"] = Exercise(
            id: "incline_bench", name: "Incline Bench Press",
            equipment: .barbell,
            primaryMuscles: [.chest, .frontDelts],
            secondaryMuscles: [.triceps],
            movementPattern: .horizontalPush
        )
        
        catalog["rdl"] = Exercise(
            id: "rdl", name: "Romanian Deadlift",
            equipment: .barbell,
            primaryMuscles: [.hamstrings, .glutes],
            secondaryMuscles: [.lowerBack],
            movementPattern: .hipHinge
        )
        
        return catalog
    }
    
    private func updateContextForSession(context: inout UserContext, record: V2Record, date: Date) {
        let input = record.input
        let bodyWeight = Load(value: input.today_metrics.body_weight_lb, unit: .pounds)
        
        context.userProfile = UserProfile(
            id: context.userProfile.id,
            sex: context.userProfile.sex,
            experience: context.userProfile.experience,
            goals: context.userProfile.goals,
            weeklyFrequency: context.userProfile.weeklyFrequency,
            availableEquipment: context.userProfile.availableEquipment,
            preferredUnit: context.userProfile.preferredUnit,
            bodyWeight: bodyWeight,
            age: context.userProfile.age,
            limitations: context.userProfile.limitations
        )
        
        let increment = input.equipment.microplate_lb ?? 2.5
        let templateExercises = input.today_session_template.compactMap { te -> TemplateExercise? in
            var liftName = te.lift.lowercased()
            
            if let subTo = input.event_flags.substitutions?[te.lift] {
                liftName = subTo.lowercased()
            }
            if let variation = input.event_flags.variation_overrides?[te.lift] {
                liftName = variation.lowercased()
            }
            
            guard let exercise = context.exerciseCatalog[liftName] else { return nil }
            
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
            id: context.templateId,
            name: record.session_type,
            exercises: templateExercises
        )
        
        var templates = context.plan.templates
        templates[context.templateId] = template
        
        context.plan = TrainingPlan(
            id: context.plan.id,
            name: context.plan.name,
            templates: templates,
            schedule: context.plan.schedule,
            substitutionPool: context.plan.substitutionPool,
            deloadConfig: context.plan.deloadConfig,
            loadRoundingPolicy: context.plan.loadRoundingPolicy
        )
    }
    
    private func computeReadiness(from metrics: V2TodayMetrics, input: V2Input) -> Int {
        var score = 70
        
        if let sleep = metrics.sleep_hours {
            if sleep >= 7.5 { score += 10 }
            else if sleep >= 6.5 { score += 5 }
            else if sleep < 5.5 { score -= 15 }
            else if sleep < 6 { score -= 10 }
        }
        
        if let hrv = metrics.hrv_ms {
            if hrv >= 60 { score += 10 }
            else if hrv >= 50 { score += 5 }
            else if hrv < 35 { score -= 15 }
            else if hrv < 45 { score -= 5 }
        }
        
        if let rhr = metrics.resting_hr_bpm {
            if rhr <= 55 { score += 5 }
            else if rhr >= 75 { score -= 10 }
            else if rhr >= 70 { score -= 5 }
        }
        
        if let soreness = metrics.soreness_1_to_10 {
            if soreness >= 7 { score -= 15 }
            else if soreness >= 5 { score -= 5 }
            else if soreness <= 2 { score += 5 }
        }
        
        if let stress = metrics.stress_1_to_10 {
            if stress >= 8 { score -= 10 }
            else if stress >= 6 { score -= 5 }
            else if stress <= 2 { score += 5 }
        }
        
        return max(0, min(100, score))
    }
    
    private func findMatchingExercise(liftName: String, variation: String?, substitutedTo: String?, in plan: SessionPlan) -> ExercisePlan? {
        if let match = plan.exercises.first(where: { $0.exercise.id.lowercased() == liftName }) {
            return match
        }
        
        if let subTo = substitutedTo,
           let match = plan.exercises.first(where: { $0.exercise.id.lowercased() == subTo.lowercased() }) {
            return match
        }
        
        if let var_ = variation,
           let match = plan.exercises.first(where: { $0.exercise.id.lowercased() == var_.lowercased() }) {
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
    
    private func inferDecision(plan: SessionPlan, liftState: LiftState?, predictedWeight: Double, isPlannedDeload: Bool) -> String {
        if plan.isDeload || isPlannedDeload { return "deload" }
        
        guard let state = liftState else { return "cold_start" }
        
        let lastWeight = state.lastWorkingWeight.converted(to: .pounds).value
        guard lastWeight > 0 else { return "cold_start" }
        
        let delta = predictedWeight - lastWeight
        let percentChange = delta / lastWeight
        
        if percentChange < -0.07 { return "deload" }
        else if percentChange < -0.02 { return "decrease_small" }
        else if abs(percentChange) <= 0.02 { return "hold" }
        else { return "increase" }
    }
    
    private func decisionsMatch(expected: String, predicted: String) -> Bool {
        let e = expected.lowercased()
        let p = predicted.lowercased()
        
        if e == p { return true }
        
        let deloadGroup = ["deload", "reset"]
        let holdGroup = ["hold", "decrease_small"]
        let increaseGroup = ["increase", "progress"]
        
        if deloadGroup.contains(e) && deloadGroup.contains(p) { return true }
        if holdGroup.contains(e) && holdGroup.contains(p) { return true }
        if increaseGroup.contains(e) && increaseGroup.contains(p) { return true }
        
        return false
    }
    
    private func trackDecisionCategory(expected: String, predicted: String, scorecard: inout Scorecard) {
        let e = expected.lowercased()
        let p = predicted.lowercased()
        
        if e == "deload" || e == "reset" { scorecard.deloadExpected += 1 }
        else if e == "hold" { scorecard.holdExpected += 1 }
        else if e == "increase" || e == "progress" { scorecard.increaseExpected += 1 }
        else if e == "decrease_small" { scorecard.decreaseSmallExpected += 1 }
        
        if p == "deload" || p == "reset" { scorecard.deloadPredicted += 1 }
        else if p == "hold" { scorecard.holdPredicted += 1 }
        else if p == "increase" || p == "progress" { scorecard.increasePredicted += 1 }
        else if p == "decrease_small" { scorecard.decreaseSmallPredicted += 1 }
        
        if (e == "deload" || e == "reset") && (p == "deload" || p == "reset") { scorecard.deloadCorrect += 1 }
        else if e == "hold" && p == "hold" { scorecard.holdCorrect += 1 }
        else if (e == "increase" || e == "progress") && (p == "increase" || p == "progress") { scorecard.increaseCorrect += 1 }
        else if e == "decrease_small" && p == "decrease_small" { scorecard.decreaseSmallCorrect += 1 }
    }
    
    private func updateHistoryWithPerformance(context: inout UserContext, enginePlan: SessionPlan, performance: [V2Performance], expectedPrescriptions: [V2Prescription], date: Date, isDeload: Bool, readiness: Int) {
        var exerciseResults: [ExerciseSessionResult] = []
        var updatedLiftStates = context.history.liftStates
        
        for perf in performance {
            let exerciseId = perf.exercise.lowercased()
            guard let exercise = context.exerciseCatalog[exerciseId] else { continue }
            
            // Find matching engine exercise plan to propagate adjustment kind
            let engineExercise = enginePlan.exercises.first(where: { exPlan in
                let eid = exPlan.exercise.id.lowercased()
                return eid == exerciseId || eid.contains(exerciseId) || exerciseId.contains(eid)
            })
            
            let prescription = expectedPrescriptions.first(where: { $0.lift.lowercased() == exerciseId })
            let targetReps = prescription?.target_reps ?? 5
            
            var setResults: [SetResult] = []
            if let sets = perf.performed_sets {
                for set in sets {
                    let weight = set.weight_lb ?? 0
                    let reps = set.reps ?? 0
                    let rpe = set.rpe
                    
                    setResults.append(SetResult(
                        reps: reps,
                        load: Load(value: weight, unit: .pounds),
                        rirObserved: rpe.map { max(0, Int(10 - $0)) },
                        completed: true,
                        isWarmup: false
                    ))
                }
            }
            
            let setPrescription = SetPrescription(
                setCount: setResults.count,
                targetRepsRange: targetReps...targetReps,
                targetRIR: 2,
                restSeconds: 180,
                loadStrategy: .absolute,
                increment: Load(value: 2.5, unit: .pounds)
            )
            
            // BLIND TEST: Propagate engine's recommendedAdjustmentKind into ExerciseSessionResult
            exerciseResults.append(ExerciseSessionResult(
                exerciseId: exerciseId,
                prescription: setPrescription,
                sets: setResults,
                order: exerciseResults.count,
                adjustmentKind: engineExercise?.recommendedAdjustmentKind
            ))
            
            var state = updatedLiftStates[exerciseId] ?? LiftState(exerciseId: exerciseId)
            
            let workingSets = setResults.filter { $0.completed && $0.reps > 0 }
            guard !workingSets.isEmpty else { continue }
            
            let maxLoad = workingSets.map(\.load).max() ?? state.lastWorkingWeight
            let sessionE1RM = workingSets.map { E1RMCalculator.brzycki(weight: $0.load.value, reps: $0.reps) }.max() ?? 0
            
            let anyFailure = workingSets.contains { $0.reps < targetReps }
            let wasGrinder = perf.top_set_rpe.map { $0 >= 8.5 } ?? false
            
            if !isDeload {
                state.lastWorkingWeight = maxLoad
                state.rollingE1RM = state.rollingE1RM > 0 ? 0.3 * sessionE1RM + 0.7 * state.rollingE1RM : sessionE1RM
                state.e1rmHistory.append(E1RMSample(date: date, value: sessionE1RM))
                if state.e1rmHistory.count > 10 { state.e1rmHistory.removeFirst() }
                state.trend = TrendCalculator.compute(from: state.e1rmHistory)
                
                if anyFailure {
                    state.failureCount += 1
                    state.highRpeStreak = 0
                } else if wasGrinder {
                    state.highRpeStreak += 1
                    state.failureCount = 0
                } else {
                    state.failureCount = 0
                    state.highRpeStreak = 0
                    state.successfulSessionsCount += 1
                }
            } else {
                state.lastDeloadDate = date
                state.failureCount = 0
                state.highRpeStreak = 0
            }
            
            state.lastSessionDate = date
            state.appendReadinessScore(readiness)
            
            updatedLiftStates[exerciseId] = state
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
        
        var sessions = context.history.sessions
        sessions.append(session)
        
        context.history = WorkoutHistory(
            sessions: sessions,
            liftStates: updatedLiftStates
        )
    }
    
    private func printScorecard(_ scorecard: Scorecard) {
        let mae = scorecard.loadErrors.isEmpty ? 0 : scorecard.loadErrors.reduce(0, +) / Double(scorecard.loadErrors.count)
        
        let loadAgreementPct = scorecard.mainLiftPrescriptions > 0 ? Double(scorecard.loadAgreements) / Double(scorecard.mainLiftPrescriptions) : 0
        let decisionAgreementPct = scorecard.mainLiftPrescriptions > 0 ? Double(scorecard.decisionAgreements) / Double(scorecard.mainLiftPrescriptions) : 0
        
        let deloadPrecision = scorecard.deloadPredicted > 0 ? Double(scorecard.deloadCorrect) / Double(scorecard.deloadPredicted) : 0
        let deloadRecall = scorecard.deloadExpected > 0 ? Double(scorecard.deloadCorrect) / Double(scorecard.deloadExpected) : 0
        
        let coldStartMAE = scorecard.coldStartLoadErrors.isEmpty ? 0 : scorecard.coldStartLoadErrors.reduce(0, +) / Double(scorecard.coldStartLoadErrors.count)
        
        print("""
        
        🧪 workout_engine_testset_v2 Full E2E Scorecard:
          Total sessions: \(scorecard.totalSessions)
          Main-lift prescriptions scored: \(scorecard.mainLiftPrescriptions)
          
          📊 Load Agreement:
            Within 2.5 lb tolerance: \(scorecard.loadAgreements)/\(scorecard.mainLiftPrescriptions) = \(String(format: "%.1f", loadAgreementPct * 100))%
            Mean Absolute Error: \(String(format: "%.2f", mae)) lb
          
          🎯 Decision Agreement:
            Overall: \(scorecard.decisionAgreements)/\(scorecard.mainLiftPrescriptions) = \(String(format: "%.1f", decisionAgreementPct * 100))%
            
            Deload: exp=\(scorecard.deloadExpected) pred=\(scorecard.deloadPredicted) correct=\(scorecard.deloadCorrect) P=\(String(format: "%.2f", deloadPrecision)) R=\(String(format: "%.2f", deloadRecall))
            Hold: exp=\(scorecard.holdExpected) pred=\(scorecard.holdPredicted) correct=\(scorecard.holdCorrect)
            Increase: exp=\(scorecard.increaseExpected) pred=\(scorecard.increasePredicted) correct=\(scorecard.increaseCorrect)
            Decrease Small: exp=\(scorecard.decreaseSmallExpected) pred=\(scorecard.decreaseSmallPredicted) correct=\(scorecard.decreaseSmallCorrect)
          
          🆕 Cold Start:
            Cases: \(scorecard.coldStartCases)
            MAE: \(String(format: "%.2f", coldStartMAE)) lb
          
          🔬 Microloading:
            Cases: \(scorecard.microloadCases)
            Correct: \(scorecard.microloadCorrect)/\(scorecard.microloadCases)
          
          👤 Per-User Breakdown:
        """)
        
        for (userId, user) in scorecard.perUser.sorted(by: { $0.key < $1.key }) {
            let userLoadPct = user.mainLiftPrescriptions > 0 ? Double(user.loadAgreements) / Double(user.mainLiftPrescriptions) : 0
            let userDecPct = user.mainLiftPrescriptions > 0 ? Double(user.decisionAgreements) / Double(user.mainLiftPrescriptions) : 0
            let userMAE = user.loadErrors.isEmpty ? 0 : user.loadErrors.reduce(0, +) / Double(user.loadErrors.count)
            
            print("    \(userId): sessions=\(user.sessions) mainLifts=\(user.mainLiftPrescriptions) loadAgree=\(String(format: "%.0f", userLoadPct * 100))% decAgree=\(String(format: "%.0f", userDecPct * 100))% MAE=\(String(format: "%.1f", userMAE))lb")
        }
        
        print("")
    }
}
