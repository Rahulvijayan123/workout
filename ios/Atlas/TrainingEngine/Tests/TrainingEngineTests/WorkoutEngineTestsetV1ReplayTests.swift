import Foundation
import XCTest
@testable import TrainingEngine

/// End-to-end supervised replay against `workout_engine_testset_v1/test_cases.jsonl`.
///
/// High-level goals:
/// - Treat the dataset as an external oracle for evaluation only (no hardcoded expected weights in production code).
/// - Feed the engine "user-like" inputs derived from each case's `input` section.
/// - Report aggregate deviation metrics without leaking per-case expected plans.
final class WorkoutEngineTestsetV1ReplayTests: XCTestCase {
    // Fixed calendar for deterministic date math (DST-safe).
    private let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(secondsFromGMT: 0)!
        return c
    }()
    
    func testWorkoutEngineTestsetV1_SupervisedScorecard_NoAnswerLeak() throws {
        let dataset = try Dataset.load(from: datasetRootURL())
        XCTAssertGreaterThan(dataset.cases.count, 0, "Dataset contained 0 cases (parsing/path issue)")
        
        let casesByUser = Dictionary(grouping: dataset.cases, by: { $0.input.userProfile.userId })
        XCTAssertGreaterThan(casesByUser.count, 0, "Dataset contained 0 users (parsing/grouping issue)")
        
        // Build one context per user (plan + catalogs).
        var contexts: [String: UserContext] = [:]
        contexts.reserveCapacity(casesByUser.count)
        for (userId, cases) in casesByUser {
            contexts[userId] = UserContext.build(for: userId, cases: cases, calendar: calendar)
        }
        
        // Evaluate all cases.
        var total = Scorecard()
        var perUser: [String: Scorecard] = [:]
        
        for (userId, cases) in casesByUser {
            guard let ctx = contexts[userId] else { continue }
            // Sort by date for deterministic aggregation.
            let ordered = cases.sorted { a, b in
                a.input.today.date < b.input.today.date
            }
            for tc in ordered {
                let sc = ctx.evaluate(testCase: tc, calendar: calendar)
                total.merge(sc)
                perUser[userId, default: Scorecard()].merge(sc)
            }
        }
        
        // Print an aggregate scorecard. This is intentionally high-level and does not print any per-case expected plans.
        let sortedUsers = perUser.keys.sorted()
        let perUserLine = sortedUsers.map { uid in
            let sc = perUser[uid] ?? Scorecard()
            return "\(uid):load=\(String(format: "%.2f", sc.loadAgreement)) " +
            "deloadAcc=\(String(format: "%.2f", sc.deloadAccuracy)) exp/pred=\(sc.expectedDeloadCount)/\(sc.predictedDeloadCount) P/R=\(String(format: "%.2f", sc.deloadPrecision))/\(String(format: "%.2f", sc.deloadRecall)) " +
            "consAcc=\(String(format: "%.2f", sc.conservativeAccuracy)) exp/pred=\(sc.expectedConservativeCount)/\(sc.predictedConservativeCount) P/R=\(String(format: "%.2f", sc.conservativePrecision))/\(String(format: "%.2f", sc.conservativeRecall))"
        }.joined(separator: " | ")
        
        print("🧪 workout_engine_testset_v1 scorecard (no answer leak):")
        print("  Cases scored: \(total.caseCount)")
        print("  Exercises scored: \(total.exerciseCount)")
        print("  Load agreement (within tolerance): \(total.loadWithinTolerance)/\(total.exerciseCount) = \(String(format: "%.2f", total.loadAgreement))")
        print("  Mean abs load error (lb): \(String(format: "%.2f", total.meanAbsLoadErrorLb))")
        print("  Mean abs % load error: \(String(format: "%.1f", total.meanAbsPctLoadError * 100))%")
        print("  Deload flag accuracy (vs deload_or_conservative label): \(total.deloadMatched)/\(total.caseCount) = \(String(format: "%.2f", total.deloadAccuracy))")
        print("  Deload flag label/predicted: \(total.expectedDeloadCount)/\(total.predictedDeloadCount) (P=\(String(format: "%.2f", total.deloadPrecision)) R=\(String(format: "%.2f", total.deloadRecall)))")
        print("  Conservative label accuracy (deload OR hold/down heuristic): \(total.conservativeMatched)/\(total.caseCount) = \(String(format: "%.2f", total.conservativeAccuracy))")
        print("  Conservative label/predicted: \(total.expectedConservativeCount)/\(total.predictedConservativeCount) (P=\(String(format: "%.2f", total.conservativePrecision)) R=\(String(format: "%.2f", total.conservativeRecall)))")
        print("  Missing exercises (engine omitted expected exercise): \(total.missingExerciseCount)")
        print("  Per-user: \(perUserLine)")
        
        // Harness sanity checks.
        XCTAssertGreaterThan(total.exerciseCount, 0, "Harness evaluated 0 exercises (translation/parsing likely broken)")
        
        // Soft guardrails (tuned to catch regressions, not to force-perfect matching).
        // If these fail, the printed scorecard should help diagnose where the engine diverges.
        XCTAssertGreaterThanOrEqual(
            total.loadAgreement,
            0.55,
            "Load agreement is too low vs supervised dataset. Per-user: \(perUserLine)"
        )
        XCTAssertGreaterThanOrEqual(
            total.deloadAccuracy,
            0.70,
            "Deload accuracy is too low vs supervised dataset. Per-user: \(perUserLine)"
        )
    }
}

// MARK: - Dataset decoding

private enum Dataset {
    static func load(from root: URL) throws -> LoadedDataset {
        let casesURL = root.appendingPathComponent("test_cases.jsonl")
        let usersURL = root.appendingPathComponent("users.json")
        
        let users = try decodeUsers(from: usersURL)
        let cases = try decodeJSONLines(from: casesURL, as: TestCase.self)
        
        return LoadedDataset(
            root: root,
            users: users,
            cases: cases
        )
    }
    
    private static func decodeUsers(from url: URL) throws -> [UserMeta] {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        return try decoder.decode([UserMeta].self, from: data)
    }
    
    private static func decodeJSONLines<T: Decodable>(from url: URL, as type: T.Type) throws -> [T] {
        let raw = try String(contentsOf: url, encoding: .utf8)
        let decoder = JSONDecoder()
        
        var out: [T] = []
        out.reserveCapacity(128)
        
        for line in raw.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }
            let data = Data(trimmed.utf8)
            out.append(try decoder.decode(T.self, from: data))
        }
        
        return out
    }
}

private struct LoadedDataset {
    let root: URL
    let users: [UserMeta]
    let cases: [TestCase]
}

private struct UserMeta: Decodable {
    let userId: String
    let sex: String
    let age: Int
    let heightIn: Int
    let startBodyWeightLb: Double
    let bwTrendLbPerWeek: Double
    let trainingLevel: String
    let goal: String
    let plateIncrementLb: Double
    let program: String
    
    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case sex
        case age
        case heightIn = "height_in"
        case startBodyWeightLb = "start_body_weight_lb"
        case bwTrendLbPerWeek = "bw_trend_lb_per_week"
        case trainingLevel = "training_level"
        case goal
        case plateIncrementLb = "plate_increment_lb"
        case program
    }
}

private struct TestCase: Decodable {
    let caseId: String
    let input: CaseInput
    let expectedOutput: ExpectedOutput
    let groundTruthPerformance: GroundTruthPerformance?
    
    enum CodingKeys: String, CodingKey {
        case caseId = "case_id"
        case input
        case expectedOutput = "expected_output"
        case groundTruthPerformance = "ground_truth_performance"
    }
}

private struct CaseInput: Decodable {
    let userProfile: InputUserProfile
    let today: InputToday
    let recentSessions: [InputRecentSession]
    let engineContract: EngineContract?
    
    enum CodingKeys: String, CodingKey {
        case userProfile = "user_profile"
        case today
        case recentSessions = "recent_sessions"
        case engineContract = "engine_contract"
    }
}

private struct InputUserProfile: Decodable {
    let userId: String
    let sex: String
    let age: Int
    let heightIn: Int
    let trainingLevel: String
    let goal: String
    let program: String
    let equipment: InputEquipment
    let plateIncrementLb: Double
    
    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case sex
        case age
        case heightIn = "height_in"
        case trainingLevel = "training_level"
        case goal
        case program
        case equipment
        case plateIncrementLb = "plate_increment_lb"
    }
}

private struct InputEquipment: Decodable {
    let barbell: Bool?
    let rack: Bool?
    let cables: Bool?
    let dumbbells: Bool?
    let pullUpBar: Bool?
    let platesIncrementLb: Double?
    
    enum CodingKeys: String, CodingKey {
        case barbell
        case rack
        case cables
        case dumbbells
        case pullUpBar = "pull_up_bar"
        case platesIncrementLb = "plates_increment_lb"
    }
}

private struct InputToday: Decodable {
    let date: String
    let plannedWorkoutTemplateId: String
    let biometrics: InputBiometrics
    
    enum CodingKeys: String, CodingKey {
        case date
        case plannedWorkoutTemplateId = "planned_workout_template_id"
        case biometrics
    }
}

private struct InputBiometrics: Decodable {
    let date: String?
    let bodyWeightLb: Double?
    let sleepHours: Double?
    let sleepQuality1to5: Int?
    let restingHrBpm: Int?
    let hrvMs: Int?
    let stepsPrevDay: Int?
    let soreness0to10: Int?
    let stress0to10: Int?
    let readiness0to100: Int
    let cycleDay: Int?
    
    enum CodingKeys: String, CodingKey {
        case date
        case bodyWeightLb = "body_weight_lb"
        case sleepHours = "sleep_hours"
        case sleepQuality1to5 = "sleep_quality_1to5"
        case restingHrBpm = "resting_hr_bpm"
        case hrvMs = "hrv_ms"
        case stepsPrevDay = "steps_prev_day"
        case soreness0to10 = "soreness_0to10"
        case stress0to10 = "stress_0to10"
        case readiness0to100 = "readiness_0to100"
        case cycleDay = "cycle_day"
    }
}

private struct InputRecentSession: Decodable {
    let sessionId: String
    let date: String
    let templateId: String
    let biometrics: InputSessionBiometrics?
    let exerciseSummary: [InputExerciseSummary]
    
    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case date
        case templateId = "template_id"
        case biometrics
        case exerciseSummary = "exercise_summary"
    }
}

private struct InputSessionBiometrics: Decodable {
    let bodyWeightLb: Double?
    let sleepHours: Double?
    let restingHrBpm: Int?
    let hrvMs: Int?
    let soreness0to10: Int?
    let stress0to10: Int?
    let readiness0to100: Int?
    
    enum CodingKeys: String, CodingKey {
        case bodyWeightLb = "body_weight_lb"
        case sleepHours = "sleep_hours"
        case restingHrBpm = "resting_hr_bpm"
        case hrvMs = "hrv_ms"
        case soreness0to10 = "soreness_0to10"
        case stress0to10 = "stress_0to10"
        case readiness0to100 = "readiness_0to100"
    }
}

private struct InputExerciseSummary: Decodable {
    let exerciseKey: String
    let weightLb: Double
    let repsMin: Int
    let repsMax: Int
    let rpeMax: Double?
    
    enum CodingKeys: String, CodingKey {
        case exerciseKey = "exercise_key"
        case weightLb = "weight_lb"
        case repsMin = "reps_min"
        case repsMax = "reps_max"
        case rpeMax = "rpe_max"
    }
}

private struct EngineContract: Decodable {
    let task: String?
    let outputFormat: String?
    
    enum CodingKeys: String, CodingKey {
        case task
        case outputFormat = "output_format"
    }
}

private struct ExpectedOutput: Decodable {
    let workoutPlan: [ExpectedExercisePlan]
    let labels: ExpectedLabels
    
    enum CodingKeys: String, CodingKey {
        case workoutPlan = "workout_plan"
        case labels
    }
}

private struct ExpectedLabels: Decodable {
    let rationaleTags: [String: String]?
    let deloadOrConservative: Bool
    
    enum CodingKeys: String, CodingKey {
        case rationaleTags = "rationale_tags"
        case deloadOrConservative = "deload_or_conservative"
    }
}

private struct ExpectedExercisePlan: Decodable {
    let exerciseKey: String
    let exerciseName: String?
    let sets: Int
    let targetReps: Int
    let repRange: [Int]?
    let targetWeightLb: Double
    let restSeconds: Int
    let intensityGuidance: String?
    let planTag: String
    
    enum CodingKeys: String, CodingKey {
        case exerciseKey = "exercise_key"
        case exerciseName = "exercise_name"
        case sets
        case targetReps = "target_reps"
        case repRange = "rep_range"
        case targetWeightLb = "target_weight_lb"
        case restSeconds = "rest_seconds"
        case intensityGuidance = "intensity_guidance"
        case planTag = "plan_tag"
    }
    
    var decodedRepRange: ClosedRange<Int>? {
        guard let repRange, repRange.count == 2 else { return nil }
        let lo = repRange[0]
        let hi = repRange[1]
        guard lo <= hi else { return nil }
        return lo...hi
    }
}

private struct GroundTruthPerformance: Decodable {
    let performedWorkout: [PerformedExercise]
    
    enum CodingKeys: String, CodingKey {
        case performedWorkout = "performed_workout"
    }
}

private struct PerformedExercise: Decodable {
    let exerciseKey: String
    let sets: [PerformedSet]
    
    enum CodingKeys: String, CodingKey {
        case exerciseKey = "exercise_key"
        case sets
    }
}

private struct PerformedSet: Decodable {
    let set: Int
    let weightLb: Double
    let reps: Int
    let rpe: Double?
    
    enum CodingKeys: String, CodingKey {
        case set
        case weightLb = "weight_lb"
        case reps
        case rpe
    }
}

// MARK: - Engine integration + evaluation

private struct UserContext {
    let userId: String
    let rounding: LoadRoundingPolicy
    let templateUUIDByString: [String: WorkoutTemplateId]
    let plan: TrainingPlan
    let exercisesByKey: [String: Exercise]
    let prescriptionByExerciseKey: [String: SetPrescription]
    let progressionByExerciseKey: [String: ProgressionPolicyType]
    
    static func build(for userId: String, cases: [TestCase], calendar: Calendar) -> UserContext {
        // Determine rounding increment from profile (fallback 2.5).
        let plateIncrement = cases.first?.input.userProfile.plateIncrementLb ?? 2.5
        let rounding = LoadRoundingPolicy(increment: max(0.1, plateIncrement), unit: .pounds, mode: .nearest)
        
        // Collect template ids encountered.
        var templateIds: Set<String> = []
        for tc in cases {
            templateIds.insert(tc.input.today.plannedWorkoutTemplateId)
            for s in tc.input.recentSessions {
                templateIds.insert(s.templateId)
            }
        }
        
        // Assign stable IDs within this test run.
        var templateUUIDByString: [String: WorkoutTemplateId] = [:]
        templateUUIDByString.reserveCapacity(templateIds.count)
        for t in templateIds.sorted() {
            templateUUIDByString[t] = UUID()
        }
        
        // Build base exercise catalog using keys observed in the dataset (inputs + expected plans).
        var exerciseKeys: Set<String> = []
        for tc in cases {
            for s in tc.input.recentSessions {
                for ex in s.exerciseSummary {
                    exerciseKeys.insert(ex.exerciseKey)
                }
            }
            for ex in tc.expectedOutput.workoutPlan {
                exerciseKeys.insert(ex.exerciseKey)
            }
        }
        
        let exercisesByKey = buildExerciseCatalog(from: exerciseKeys.sorted())
        
        // Derive stable per-exercise prescriptions from expected outputs, ignoring target weights.
        var prescriptionByExerciseKey: [String: SetPrescription] = [:]
        prescriptionByExerciseKey.reserveCapacity(exerciseKeys.count)
        
        for key in exerciseKeys {
            let samples = cases.flatMap { tc in
                tc.expectedOutput.workoutPlan.filter { $0.exerciseKey == key }
            }
            // Defaults if this exercise never appears in expected output for some reason.
            let fallback = SetPrescription(
                setCount: 3,
                targetRepsRange: 8...12,
                targetRIR: 2,
                restSeconds: 120,
                loadStrategy: .absolute,
                increment: .pounds(plateIncrement)
            )
            
            guard !samples.isEmpty else {
                prescriptionByExerciseKey[key] = fallback
                continue
            }
            
            let setCount = max(1, samples.map(\.sets).max() ?? 3)
            let restSeconds = max(0, samples.map(\.restSeconds).max() ?? 120)
            
            // Rep range: prefer explicit rep_range; otherwise fixed reps (target_reps).
            let repRange: ClosedRange<Int> = {
                let ranges = samples.compactMap(\.decodedRepRange)
                if let best = ranges.sorted(by: { ($0.upperBound - $0.lowerBound) > ($1.upperBound - $1.lowerBound) }).first {
                    return best
                }
                // Use a deterministic "mode" of observed targets to avoid picking deload/conservative outliers.
                let reps = samples.map(\.targetReps)
                var counts: [Int: Int] = [:]
                for r in reps {
                    counts[r, default: 0] += 1
                }
                let fixed = counts.sorted {
                    if $0.value != $1.value { return $0.value > $1.value }
                    return $0.key < $1.key
                }.first?.key ?? reps.first ?? 8
                return fixed...fixed
            }()
            
            // Increment heuristic: respect plate increments, but allow 5 lb for big lower-body barbell lifts.
            let exercise = exercisesByKey[key]
            let inc: Double = {
                guard let exercise else { return plateIncrement }
                if exercise.movementPattern == .squat || exercise.movementPattern == .hipHinge {
                    return max(plateIncrement, 5.0)
                }
                return plateIncrement
            }()
            
            prescriptionByExerciseKey[key] = SetPrescription(
                setCount: setCount,
                targetRepsRange: repRange,
                targetRIR: 2,
                tempo: .standard,
                restSeconds: restSeconds,
                loadStrategy: .absolute,
                increment: .pounds(inc)
            )
        }
        
        // Progression policy: infer from rep range (fixed reps -> linear; rep range -> double progression).
        var progressionByExerciseKey: [String: ProgressionPolicyType] = [:]
        progressionByExerciseKey.reserveCapacity(exerciseKeys.count)
        
        for key in exerciseKeys {
            let rx = prescriptionByExerciseKey[key] ?? .hypertrophy
            let exercise = exercisesByKey[key] ?? Exercise(
                id: key,
                name: key,
                equipment: .unknown,
                primaryMuscles: [.unknown],
                movementPattern: .unknown
            )
            
            let isRange = rx.targetRepsRange.lowerBound != rx.targetRepsRange.upperBound
            if isRange {
                // Double progression: load increments follow plate increment defaults.
                let cfg = DoubleProgressionConfig(
                    sessionsAtTopBeforeIncrease: 1,
                    loadIncrement: rx.increment,
                    deloadPercentage: FailureThresholdDefaults.deloadPercentage,
                    failuresBeforeDeload: FailureThresholdDefaults.failuresBeforeDeload
                )
                progressionByExerciseKey[key] = .doubleProgression(config: cfg)
            } else {
                // Linear progression: choose increments based on movement pattern.
                let baseInc = rx.increment
                let inc: Load = {
                    if exercise.movementPattern == .squat || exercise.movementPattern == .hipHinge {
                        return .pounds(max(5.0, baseInc.value))
                    }
                    return .pounds(max(0.0, baseInc.value))
                }()
                
                let cfg = LinearProgressionConfig(
                    successIncrement: inc,
                    failureDecrement: nil,
                    deloadPercentage: FailureThresholdDefaults.deloadPercentage,
                    failuresBeforeDeload: FailureThresholdDefaults.failuresBeforeDeload
                )
                progressionByExerciseKey[key] = .linearProgression(config: cfg)
            }
        }
        
        // Templates: for each template id, use the first case where it appears as "today" to preserve order.
        var templates: [WorkoutTemplateId: WorkoutTemplate] = [:]
        templates.reserveCapacity(templateUUIDByString.count)
        
        for (templateString, tid) in templateUUIDByString {
            // Preferred source of exercise ordering: expected plan order for sessions that target this template id.
            let firstMatch = cases.first(where: { $0.input.today.plannedWorkoutTemplateId == templateString })
            let orderedKeys: [String] = {
                if let firstMatch {
                    let keys = firstMatch.expectedOutput.workoutPlan.map(\.exerciseKey)
                    if !keys.isEmpty { return keys }
                }
                // Fallback: derive from most recent session in inputs with this template id.
                let sessions = cases.flatMap(\.input.recentSessions).filter { $0.templateId == templateString }
                if let any = sessions.first {
                    return any.exerciseSummary.map(\.exerciseKey)
                }
                return []
            }()
            
            let templateExercises: [TemplateExercise] = orderedKeys.enumerated().compactMap { (idx, key) in
                guard let ex = exercisesByKey[key] else { return nil }
                let rx = prescriptionByExerciseKey[key] ?? .hypertrophy
                return TemplateExercise(exercise: ex, prescription: rx, order: idx)
            }
            
            templates[tid] = WorkoutTemplate(
                id: tid,
                name: templateString,
                exercises: templateExercises,
                estimatedDurationMinutes: nil,
                targetMuscleGroups: [],
                description: nil,
                createdAt: calendar.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: 12))!,
                updatedAt: calendar.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: 12))!
            )
        }
        
        // Deload config: avoid scheduled deloads here because this dataset's `input` does not provide explicit
        // "wasDeload" flags for past sessions (which would otherwise make scheduled deloads sticky forever).
        let deload = DeloadConfig(
            intensityReduction: 0.10,
            volumeReduction: 0,
            scheduledDeloadWeeks: nil,
            readinessThreshold: 50,
            lowReadinessDaysRequired: 3
        )
        
        let plan = TrainingPlan(
            name: "workout_engine_testset_v1 (\(userId))",
            templates: templates,
            schedule: .manual,
            progressionPolicies: progressionByExerciseKey,
            inSessionPolicies: [:],
            substitutionPool: [],
            deloadConfig: deload,
            loadRoundingPolicy: rounding,
            createdAt: calendar.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: 12))!
        )
        
        return UserContext(
            userId: userId,
            rounding: rounding,
            templateUUIDByString: templateUUIDByString,
            plan: plan,
            exercisesByKey: exercisesByKey,
            prescriptionByExerciseKey: prescriptionByExerciseKey,
            progressionByExerciseKey: progressionByExerciseKey
        )
    }
    
    func evaluate(testCase tc: TestCase, calendar: Calendar) -> Scorecard {
        var sc = Scorecard()
        sc.caseCount = 1
        
        // Build user profile for this case (use today's bodyweight for auto-increment scaling).
        let userProfile = Self.makeUserProfile(from: tc.input.userProfile, today: tc.input.today, rounding: rounding)
        
        // Build workout history from the case's "recent sessions" summaries.
        let history = Self.makeHistory(
            userId: userId,
            recentSessions: tc.input.recentSessions,
            today: tc.input.today,
            plan: plan,
            templateUUIDByString: templateUUIDByString,
            prescriptionByExerciseKey: prescriptionByExerciseKey,
            rounding: rounding,
            calendar: calendar
        )
        
        let date = Self.parseDay(tc.input.today.date, calendar: calendar)
        let templateId = templateUUIDByString[tc.input.today.plannedWorkoutTemplateId] ?? UUID()
        let readiness = tc.input.today.biometrics.readiness0to100
        
        let predicted = Engine.recommendSessionForTemplate(
            date: date,
            templateId: templateId,
            userProfile: userProfile,
            plan: plan,
            history: history,
            readiness: readiness,
            excludingExerciseIds: [],
            calendar: calendar
        )
        
        let lastByExercise = Self.mostRecentByExercise(from: tc.input.recentSessions)
        let expectedLabel = tc.expectedOutput.labels.deloadOrConservative
        
        // 1) Strict metric: expected label vs engine's explicit session-level deload flag.
        let predictedIsDeload = predicted.isDeload
        sc.deloadMatched = (expectedLabel == predictedIsDeload) ? 1 : 0
        sc.expectedDeloadCount = expectedLabel ? 1 : 0
        sc.predictedDeloadCount = predictedIsDeload ? 1 : 0
        if expectedLabel && predictedIsDeload {
            sc.deloadTruePositive = 1
        } else if !expectedLabel && predictedIsDeload {
            sc.deloadFalsePositive = 1
        } else if expectedLabel && !predictedIsDeload {
            sc.deloadFalseNegative = 1
        }
        
        // 2) Lenient metric: expected label vs "conservative plan" heuristic (covers conservative repeats).
        let predictedConservative = predictedIsDeload
            || Self.isConservativePlan(
                predicted: predicted,
                expectedWorkout: tc.expectedOutput.workoutPlan,
                lastByExercise: lastByExercise,
                rounding: rounding
            )
        sc.conservativeMatched = (expectedLabel == predictedConservative) ? 1 : 0
        sc.expectedConservativeCount = expectedLabel ? 1 : 0
        sc.predictedConservativeCount = predictedConservative ? 1 : 0
        if expectedLabel && predictedConservative {
            sc.conservativeTruePositive = 1
        } else if !expectedLabel && predictedConservative {
            sc.conservativeFalsePositive = 1
        } else if expectedLabel && !predictedConservative {
            sc.conservativeFalseNegative = 1
        }
        
        // Score exercise prescriptions vs expected.
        let plateIncrement = tc.input.userProfile.plateIncrementLb
        
        for expected in tc.expectedOutput.workoutPlan {
            sc.exerciseCount += 1
            
            guard let match = predicted.exercises.first(where: { $0.exercise.id == expected.exerciseKey }) else {
                sc.missingExerciseCount += 1
                continue
            }
            
            let predictedLb = match.sets.first?.targetLoad.converted(to: .pounds).value ?? 0
            let expectedLb = expected.targetWeightLb
            let absErr = abs(predictedLb - expectedLb)
            
            sc.absLoadErrorSumLb += absErr
            if abs(expectedLb) > 0.0001 {
                sc.absPctLoadErrorSum += absErr / abs(expectedLb)
                sc.absPctLoadErrorCount += 1
            }
            
            let tol = Self.toleranceLb(
                expectedLb: expectedLb,
                plateIncrement: plateIncrement,
                rounding: rounding
            )
            if absErr <= tol {
                sc.loadWithinTolerance += 1
            }
            
            // Directional agreement vs most recent exposure of that exercise (hold vs up vs down).
            if let last = lastByExercise[expected.exerciseKey] {
                let expectedDelta = expectedLb - last.weightLb
                let predictedDelta = predictedLb - last.weightLb
                if Self.deltaBucket(expectedDelta) == Self.deltaBucket(predictedDelta) {
                    sc.directionMatched += 1
                }
                sc.directionCount += 1
            }
        }
        
        return sc
    }
    
    // MARK: - Helpers (history translation)
    
    private static func makeUserProfile(from input: InputUserProfile, today: InputToday, rounding: LoadRoundingPolicy) -> UserProfile {
        let sex: BiologicalSex = (input.sex.lowercased() == "female") ? .female : .male
        
        let experience: ExperienceLevel = {
            switch input.trainingLevel {
            case "novice", "beginner", "novice_with_injury_history":
                return .beginner
            case "detrained_intermediate", "intermediate":
                return .intermediate
            case "advanced":
                return .advanced
            case "elite":
                return .elite
            default:
                return .beginner
            }
        }()
        
        let goals: [TrainingGoal] = {
            switch input.goal {
            case "strength":
                return [.strength]
            case "strength_and_hypertrophy":
                return [.strength, .hypertrophy]
            case "recomp":
                return [.fatLoss, .hypertrophy]
            case "strength_and_joint_health":
                return [.generalFitness, .strength]
            default:
                return [.generalFitness]
            }
        }()
        
        let weeklyFrequency: Int = {
            if input.program.contains("3xweek") { return 3 }
            if input.program.contains("4xweek") { return 4 }
            return 3
        }()
        
        // For this supervised dataset, equipment constraints are not the focus of the evaluation.
        // Use commercial-gym availability to avoid "missing exercise" artifacts driven by catalog heuristics.
        let availableEquipment: EquipmentAvailability = .commercialGym
        
        let bodyWeight: Load? = today.biometrics.bodyWeightLb.map { Load(value: $0, unit: .pounds).rounded(using: rounding) }
        
        return UserProfile(
            id: input.userId,
            sex: sex,
            experience: experience,
            goals: goals,
            weeklyFrequency: weeklyFrequency,
            availableEquipment: availableEquipment,
            preferredUnit: .pounds,
            bodyWeight: bodyWeight,
            age: input.age,
            limitations: []
        )
    }
    
    private static func makeHistory(
        userId: String,
        recentSessions: [InputRecentSession],
        today: InputToday,
        plan: TrainingPlan,
        templateUUIDByString: [String: WorkoutTemplateId],
        prescriptionByExerciseKey: [String: SetPrescription],
        rounding: LoadRoundingPolicy,
        calendar: Calendar
    ) -> WorkoutHistory {
        // Build CompletedSession list (we approximate full set logs from summary stats).
        let ordered = recentSessions.sorted { $0.date < $1.date }
        var sessions: [CompletedSession] = []
        sessions.reserveCapacity(ordered.count)
        
        // Approximate volume by date for fatigue tracking.
        var volumeByDate: [Date: Double] = [:]
        volumeByDate.reserveCapacity(min(ordered.count, 64))
        
        for s in ordered {
            let day = parseDay(s.date, calendar: calendar)
            let startedAt = day
            let templateId = templateUUIDByString[s.templateId]
            let readiness = s.biometrics?.readiness0to100
            
            var results: [ExerciseSessionResult] = []
            results.reserveCapacity(s.exerciseSummary.count)
            
            var sessionVolume = 0.0
            
            for (idx, ex) in s.exerciseSummary.enumerated() {
                let rx = prescriptionByExerciseKey[ex.exerciseKey] ?? .hypertrophy
                let sets = synthesizeSets(from: ex, prescription: rx, rounding: rounding)
                
                // Approx volume using working sets.
                sessionVolume += sets.filter { $0.completed && !$0.isWarmup }.reduce(0) { acc, set in
                    acc + set.volume
                }
                
                results.append(ExerciseSessionResult(
                    exerciseId: ex.exerciseKey,
                    prescription: rx,
                    sets: sets,
                    order: idx,
                    notes: nil
                ))
            }
            
            volumeByDate[day] = sessionVolume
            
            sessions.append(CompletedSession(
                date: day,
                templateId: templateId,
                name: "\(userId) \(s.templateId)",
                exerciseResults: results,
                startedAt: startedAt,
                endedAt: nil,
                wasDeload: false,
                previousLiftStates: [:],
                readinessScore: readiness,
                notes: nil
            ))
        }
        
        let readinessHistory = synthesizeReadinessHistory(
            recentSessions: ordered,
            today: today,
            calendar: calendar
        )
        
        // Compute lift states from the most recent exposures (do not treat any session as deload, since the input
        // does not include explicit deload flags).
        let liftStates = computeLiftStates(
            sessions: sessions,
            rounding: rounding,
            calendar: calendar
        )
        
        return WorkoutHistory(
            sessions: sessions,
            liftStates: liftStates,
            readinessHistory: readinessHistory,
            recentVolumeByDate: volumeByDate
        )
    }
    
    private static func synthesizeSets(from summary: InputExerciseSummary, prescription: SetPrescription, rounding: LoadRoundingPolicy) -> [SetResult] {
        let n = max(1, prescription.setCount)
        
        // Distribute reps to preserve min/max deterministically across sets.
        let lo = max(0, summary.repsMin)
        let hi = max(lo, summary.repsMax)
        let mid = (lo + hi) / 2
        
        func repsForIndex(_ i: Int) -> Int {
            if n == 1 { return hi }
            if i == 0 { return hi }
            if i == n - 1 { return lo }
            return mid
        }
        
        // IMPORTANT: Some dataset cases encode "assistance" as negative load (e.g., assisted pull-ups).
        // The engine currently clamps negative loads to 0 in `Load.init`. We preserve the raw value here
        // (the clamp happens inside TrainingEngine's `Load`), so the scorecard can surface this gap.
        let load = Load(value: summary.weightLb, unit: .pounds).rounded(using: rounding)
        
        return (0..<n).map { i in
            SetResult(
                reps: repsForIndex(i),
                load: load,
                rirObserved: nil,
                tempoObserved: nil,
                completed: true,
                isWarmup: false,
                completedAt: nil,
                notes: nil
            )
        }
    }
    
    private static func synthesizeReadinessHistory(
        recentSessions: [InputRecentSession],
        today: InputToday,
        calendar: Calendar
    ) -> [ReadinessRecord] {
        // The engine's low-readiness trigger counts consecutive *calendar days* with records.
        // The dataset provides readiness on session days (and "today"), so we forward-fill between
        // known days to create a daily series without inventing new extrema.
        let points: [(Date, Int)] = {
            var pts: [(Date, Int)] = []
            pts.reserveCapacity(recentSessions.count + 1)
            for s in recentSessions {
                let d = parseDay(s.date, calendar: calendar)
                if let r = s.biometrics?.readiness0to100 {
                    pts.append((d, r))
                }
            }
            pts.append((parseDay(today.date, calendar: calendar), today.biometrics.readiness0to100))
            return pts.sorted { $0.0 < $1.0 }
        }()
        
        guard let first = points.first else { return [] }
        guard let last = points.last else { return [] }
        
        // Build a map for "known" days.
        var known: [Date: Int] = [:]
        known.reserveCapacity(points.count)
        for (d, r) in points {
            known[calendar.startOfDay(for: d)] = r
        }
        
        // Forward-fill daily.
        var out: [ReadinessRecord] = []
        out.reserveCapacity(64)
        
        var cursor = calendar.startOfDay(for: first.0)
        let end = calendar.startOfDay(for: last.0)
        var current = first.1
        
        var guardIters = 0
        while cursor <= end && guardIters < 400 {
            if let v = known[cursor] {
                current = v
            }
            out.append(ReadinessRecord(date: cursor, score: current))
            cursor = calendar.date(byAdding: .day, value: 1, to: cursor) ?? cursor
            guardIters += 1
        }
        
        return out
    }
    
    private static func computeLiftStates(
        sessions: [CompletedSession],
        rounding: LoadRoundingPolicy,
        calendar: Calendar
    ) -> [String: LiftState] {
        struct DatedExposure {
            let date: Date
            let result: ExerciseSessionResult
        }
        
        // sessions here are chronological. Build dated exposures by exercise.
        var byExercise: [String: [DatedExposure]] = [:]
        for s in sessions {
            for r in s.exerciseResults {
                byExercise[r.exerciseId, default: []].append(DatedExposure(date: s.date, result: r))
            }
        }
        
        var out: [String: LiftState] = [:]
        out.reserveCapacity(byExercise.count)
        
        for (exerciseId, exposures) in byExercise {
            // Most recent exposure is last in chronological list.
            guard let last = exposures.last else { continue }
            let lastResult = last.result
            let working = lastResult.workingSets
            let maxLoad = working.map(\.load).max() ?? .zero
            let unit = maxLoad.unit
            
            // Failure count: consecutive exposures where reps < lower bound in any set.
            var failures = 0
            for exp in exposures.reversed() {
                let ws = exp.result.workingSets
                guard !ws.isEmpty else { continue }
                let lb = exp.result.prescription.targetRepsRange.lowerBound
                if ws.contains(where: { $0.reps < lb }) {
                    failures += 1
                } else {
                    break
                }
            }
            
            // e1RM history for trend (last up to 10), computed in the same unit as the lift state's baseline.
            var e1rmHistory: [E1RMSample] = []
            e1rmHistory.reserveCapacity(min(10, exposures.count))
            
            for exp in exposures.suffix(10) {
                let ws = exp.result.workingSets
                guard !ws.isEmpty else { continue }
                let best = ws.map { set in
                    let w = set.load.converted(to: unit).value
                    return E1RMCalculator.brzycki(weight: w, reps: set.reps)
                }.max() ?? 0
                if best > 0 {
                    e1rmHistory.append(E1RMSample(date: exp.date, value: best))
                }
            }
            
            let rolling = e1rmHistory.last?.value ?? 0
            let trend = TrendCalculator.compute(from: e1rmHistory)
            
            out[exerciseId] = LiftState(
                exerciseId: exerciseId,
                lastWorkingWeight: maxLoad.rounded(using: rounding),
                rollingE1RM: rolling,
                failureCount: failures,
                lastDeloadDate: nil,
                trend: trend,
                e1rmHistory: e1rmHistory,
                lastSessionDate: last.date,
                successfulSessionsCount: max(0, e1rmHistory.count - failures)
            )
        }
        
        return out
    }
    
    private static func mostRecentByExercise(from recentSessions: [InputRecentSession]) -> [String: InputExerciseSummary] {
        var out: [String: InputExerciseSummary] = [:]
        for s in recentSessions.sorted(by: { $0.date < $1.date }) {
            for ex in s.exerciseSummary {
                out[ex.exerciseKey] = ex
            }
        }
        return out
    }
    
    private static func toleranceLb(expectedLb: Double, plateIncrement: Double, rounding: LoadRoundingPolicy) -> Double {
        let absExpected = abs(expectedLb)
        let step = max(0.1, min(rounding.increment, max(0.1, plateIncrement)))
        // Allow either one rounding step or 5% (whichever is larger), with a small floor.
        return max(step, absExpected * 0.05, 2.5)
    }
    
    private static func deltaBucket(_ delta: Double) -> Int {
        // Bucket by ~1 lb to avoid noise.
        if delta > 1.0 { return 1 }
        if delta < -1.0 { return -1 }
        return 0
    }
    
    private static func parseDay(_ yyyyMMdd: String, calendar: Calendar) -> Date {
        // Parse day as noon UTC to avoid DST edge cases.
        let parts = yyyyMMdd.split(separator: "-").map(String.init)
        let y = Int(parts[safe: 0] ?? "") ?? 1970
        let m = Int(parts[safe: 1] ?? "") ?? 1
        let d = Int(parts[safe: 2] ?? "") ?? 1
        return calendar.date(from: DateComponents(year: y, month: m, day: d, hour: 12, minute: 0))!
    }
    
    private static func isConservativePlan(
        predicted: SessionPlan,
        expectedWorkout: [ExpectedExercisePlan],
        lastByExercise: [String: InputExerciseSummary],
        rounding: LoadRoundingPolicy
    ) -> Bool {
        // If we don't have enough prior exposures, conservatism is undefined.
        var considered = 0
        var nonIncrease = 0
        
        // Use a *small* epsilon so that normal plate increments (e.g., +2.5 lb) are treated as increases,
        // not as "holds" (otherwise we'd massively over-predict conservatism).
        let epsilon = 0.25
        
        for expected in expectedWorkout {
            guard let last = lastByExercise[expected.exerciseKey] else { continue }
            guard let match = predicted.exercises.first(where: { $0.exercise.id == expected.exerciseKey }) else { continue }
            let predictedLb = match.sets.first?.targetLoad.converted(to: .pounds).value ?? 0
            considered += 1
            if predictedLb <= last.weightLb + epsilon {
                nonIncrease += 1
            }
        }
        
        guard considered >= 2 else { return false }
        return Double(nonIncrease) / Double(considered) >= 0.75
    }
}

private func buildExerciseCatalog(from keys: [String]) -> [String: Exercise] {
    var out: [String: Exercise] = [:]
    out.reserveCapacity(keys.count)
    
    for key in keys {
        let lower = key.lowercased()
        
        func contains(_ s: String) -> Bool { lower.contains(s) }
        
        let movement: MovementPattern = {
            if contains("squat") { return .squat }
            if contains("deadlift") || contains("hinge") { return .hipHinge }
            if contains("bench") || contains("press") { return .horizontalPush }
            if contains("ohp") || contains("overhead") { return .verticalPush }
            if contains("row") { return .horizontalPull }
            if contains("pullup") || contains("pulldown") { return .verticalPull }
            if contains("curl") { return .elbowFlexion }
            if contains("extension") { return .elbowExtension }
            if contains("plank") { return .coreStability }
            if contains("carry") { return .carry }
            return .unknown
        }()
        
        let equipment: Equipment = {
            if contains("plank") { return .bodyweight }
            if contains("pullup") { return .pullUpBar }
            if contains("pulldown") || contains("cable") { return .cable }
            if contains("db") || contains("dumbbell") { return .dumbbell }
            if contains("machine") { return .machine }
            if contains("carry") { return .dumbbell }
            // Default to barbell for common compound keys.
            if movement.isCompound { return .barbell }
            // Fallback: treat unknowns as machine-based so they remain executable in commercial gyms.
            return .machine
        }()
        
        out[key] = Exercise(
            id: key,
            name: key,
            equipment: equipment,
            primaryMuscles: [.unknown],
            secondaryMuscles: [],
            movementPattern: movement
        )
    }
    
    return out
}

// MARK: - Scorecard

private struct Scorecard {
    var caseCount: Int = 0
    var exerciseCount: Int = 0
    
    var loadWithinTolerance: Int = 0
    var missingExerciseCount: Int = 0
    
    var absLoadErrorSumLb: Double = 0
    var absPctLoadErrorSum: Double = 0
    var absPctLoadErrorCount: Int = 0
    
    var deloadMatched: Int = 0
    var expectedDeloadCount: Int = 0
    var predictedDeloadCount: Int = 0
    var deloadTruePositive: Int = 0
    var deloadFalsePositive: Int = 0
    var deloadFalseNegative: Int = 0
    
    // Conservative label metrics (lenient heuristic: deload OR majority hold/down vs last).
    var conservativeMatched: Int = 0
    var expectedConservativeCount: Int = 0
    var predictedConservativeCount: Int = 0
    var conservativeTruePositive: Int = 0
    var conservativeFalsePositive: Int = 0
    var conservativeFalseNegative: Int = 0
    
    var directionMatched: Int = 0
    var directionCount: Int = 0
    
    mutating func merge(_ other: Scorecard) {
        caseCount += other.caseCount
        exerciseCount += other.exerciseCount
        
        loadWithinTolerance += other.loadWithinTolerance
        missingExerciseCount += other.missingExerciseCount
        
        absLoadErrorSumLb += other.absLoadErrorSumLb
        absPctLoadErrorSum += other.absPctLoadErrorSum
        absPctLoadErrorCount += other.absPctLoadErrorCount
        
        deloadMatched += other.deloadMatched
        expectedDeloadCount += other.expectedDeloadCount
        predictedDeloadCount += other.predictedDeloadCount
        deloadTruePositive += other.deloadTruePositive
        deloadFalsePositive += other.deloadFalsePositive
        deloadFalseNegative += other.deloadFalseNegative
        
        conservativeMatched += other.conservativeMatched
        expectedConservativeCount += other.expectedConservativeCount
        predictedConservativeCount += other.predictedConservativeCount
        conservativeTruePositive += other.conservativeTruePositive
        conservativeFalsePositive += other.conservativeFalsePositive
        conservativeFalseNegative += other.conservativeFalseNegative
        
        directionMatched += other.directionMatched
        directionCount += other.directionCount
    }
    
    var loadAgreement: Double {
        guard exerciseCount > 0 else { return 0 }
        return Double(loadWithinTolerance) / Double(exerciseCount)
    }
    
    var meanAbsLoadErrorLb: Double {
        guard exerciseCount > 0 else { return 0 }
        return absLoadErrorSumLb / Double(exerciseCount)
    }
    
    var meanAbsPctLoadError: Double {
        guard absPctLoadErrorCount > 0 else { return 0 }
        return absPctLoadErrorSum / Double(absPctLoadErrorCount)
    }
    
    var deloadAccuracy: Double {
        guard caseCount > 0 else { return 0 }
        return Double(deloadMatched) / Double(caseCount)
    }
    
    var deloadPrecision: Double {
        let denom = deloadTruePositive + deloadFalsePositive
        guard denom > 0 else { return 0 }
        return Double(deloadTruePositive) / Double(denom)
    }
    
    var deloadRecall: Double {
        let denom = deloadTruePositive + deloadFalseNegative
        guard denom > 0 else { return 0 }
        return Double(deloadTruePositive) / Double(denom)
    }
    
    var conservativeAccuracy: Double {
        guard caseCount > 0 else { return 0 }
        return Double(conservativeMatched) / Double(caseCount)
    }
    
    var conservativePrecision: Double {
        let denom = conservativeTruePositive + conservativeFalsePositive
        guard denom > 0 else { return 0 }
        return Double(conservativeTruePositive) / Double(denom)
    }
    
    var conservativeRecall: Double {
        let denom = conservativeTruePositive + conservativeFalseNegative
        guard denom > 0 else { return 0 }
        return Double(conservativeTruePositive) / Double(denom)
    }
}

// MARK: - Paths

private func datasetRootURL() -> URL {
    // This file lives at:
    //   ios/Atlas/TrainingEngine/Tests/TrainingEngineTests/WorkoutEngineTestsetV1ReplayTests.swift
    // Dataset lives at workspace root:
    //   workout_engine_testset_v1/
    let this = URL(fileURLWithPath: #filePath)
    let workspace = this
        .deletingLastPathComponent() // TrainingEngineTests
        .deletingLastPathComponent() // Tests
        .deletingLastPathComponent() // TrainingEngine
        .deletingLastPathComponent() // Atlas
        .deletingLastPathComponent() // ios
        .deletingLastPathComponent() // workspace root
    return workspace.appendingPathComponent("workout_engine_testset_v1", isDirectory: true)
}

// MARK: - Small utilities

private extension Array where Element == String {
    subscript(safe idx: Int) -> String? {
        guard idx >= 0 && idx < count else { return nil }
        return self[idx]
    }
}

