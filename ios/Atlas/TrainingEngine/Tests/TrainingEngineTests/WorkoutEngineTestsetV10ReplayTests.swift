// WorkoutEngineTestsetV10ReplayTests.swift
// Full E2E replay test for workout_engine_testset_v10 dataset.
// V10: Microloading torture, cut/maintenance, isolation double progression, messy adherence, cross-signal conflicts.
//
// CRITICAL: This test is BLIND - no expected values are leaked to the engine.
// The engine receives ONLY input data and its output is compared post-hoc.

import XCTest
@testable import TrainingEngine
import Foundation

final class WorkoutEngineTestsetV10ReplayTests: XCTestCase {
    
    // MARK: - V10 Record Structures
    
    struct V10Record: Codable {
        let dataset_version: String?
        let user_id: String?
        let date: String?
        let session_type: String?
        let test_id: String
        let test_category: String
        let description: String
        let input: V10Input
        let expected_output: V10ExpectedOutput?
        let expected: V10Expected?
        let assertions: [V10Assertion]?
        let eval_metadata: V10EvalMetadata?
    }
    
    struct V10Input: Codable {
        let user_profile: V10UserProfile
        let equipment: [String]?
        let equipment_config: V10EquipmentConfig
        let today_metrics: V10TodayMetrics
        let today_session_template: [V10TemplateExercise]
        let recent_lift_history: [String: [V10HistoryEntry]]
        let lift_state: [String: V10LiftState]?
        let days_since_last_session: Int?
        let days_since_lift_exposure: [String: IntOrNull]?
        let event_flags: V10EventFlags
        let config_overrides: V10ConfigOverrides?
    }
    
    // Helper for nullable ints in days_since_lift_exposure
    enum IntOrNull: Codable {
        case int(Int)
        case null
        
        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if container.decodeNil() { self = .null; return }
            if let i = try? container.decode(Int.self) { self = .int(i); return }
            self = .null
        }
        
        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case .int(let i): try container.encode(i)
            case .null: try container.encodeNil()
            }
        }
        
        var value: Int? {
            switch self {
            case .int(let i): return i
            case .null: return nil
            }
        }
    }
    
    struct V10UserProfile: Codable {
        let sex: String
        let age: Int
        let height_cm: Int
        let body_weight_lb: Double
        let experience_level: String
        let program: String
        let goal: String
    }
    
    struct V10EquipmentConfig: Codable {
        let units: String
        let bar_weight_lb: Double
        let load_step_lb: Double
        let plate_profile: String?
        let available_plates_lb: [Double]?
    }
    
    struct V10TodayMetrics: Codable {
        let session_date: String?
        let body_weight_lb: Double?
        let sleep_hours: Double?
        let hrv_ms: Int?
        let resting_hr_bpm: Int?
        let soreness_1_to_10: Int?
        let stress_1_to_10: Int?
        let steps: Int?
        let calories_est: Int?
    }
    
    struct V10TemplateExercise: Codable {
        let lift: String
        let sets: Int
        let reps: Int
        let reps_range: [Int]?
    }
    
    struct V10HistoryEntry: Codable {
        let date: String
        let weight_lb: Double
        let reps: Int
        let top_rpe: Double?
        let outcome: String
        let variation: String?
        let session_type: String?
        let logged_at: String?
    }
    
    struct V10LiftStateWeight: Codable {
        let value: Double
        let unit: String
    }
    
    struct V10LiftState: Codable {
        let exerciseId: String
        let lastWorkingWeight: V10LiftStateWeight
        let rollingE1RM: Double?
        let failureCount: Int
        let highRpeStreak: Int
        let lastDeloadDate: String?
        let trend: String
        let successStreak: Int
        let successfulSessionsCount: Int
        let recentReadinessScores: [Int]?
        let recentSessionRIRs: [Double]?
        let recentEasySessionCount: Int?
    }
    
    struct V10EventFlags: Codable {
        let missed_session: Bool
        let injury_flags: [String: V10InjuryFlag]?
        let planned_deload_week: Bool?
        let variation_overrides: [String: String]?
        let substitutions: [String: String]?
        let gym: String?
        let break_reset_days: Int?
        let cut_mode: Bool?
        let phase: String?
        let deficit: String?
    }
    
    enum V10InjuryFlag: Codable {
        case bool(Bool)
        case string(String)
        
        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let b = try? container.decode(Bool.self) { self = .bool(b); return }
            if let s = try? container.decode(String.self) { self = .string(s); return }
            throw DecodingError.typeMismatch(V10InjuryFlag.self, .init(codingPath: decoder.codingPath, debugDescription: "Expected Bool or String"))
        }
        
        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case .bool(let b): try container.encode(b)
            case .string(let s): try container.encode(s)
            }
        }
    }
    
    struct V10ConfigOverrides: Codable {
        let progression_policy: String?
        let deload_config: V10DeloadConfig?
        let sex_bw_scaling_enabled: Bool?
        let enable_microloading: Bool?
    }
    
    struct V10DeloadConfig: Codable {
        let intensityReduction: Double?
        let volumeReduction: Int?
        let failuresBeforeDeload: Int?
    }
    
    struct V10ExpectedOutput: Codable {
        let session_prescription_for_today: [V10Prescription]?
    }
    
    struct V10Expected: Codable {
        let session_prescription_for_today: [V10Prescription]?
    }
    
    struct V10Prescription: Codable {
        let lift: String
        let prescribed_weight_lb: Double?
        let sets: Int?
        let target_reps: Int?
        let target_rpe: Double?
        let decision: String
        let reason_code: String?
        let adjustment_kind: String?
        let relative_strength: Double?
        let tier: String?
        let acceptable_range_lb: [Double]?
    }
    
    struct V10Assertion: Codable {
        let field: String
        let expected: V10AssertionValue?
        let expected_range: [Double]?
        let expected_one_of: [String]?
    }
    
    enum V10AssertionValue: Codable {
        case string(String)
        case number(Double)
        case bool(Bool)
        
        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let s = try? container.decode(String.self) { self = .string(s); return }
            if let n = try? container.decode(Double.self) { self = .number(n); return }
            if let b = try? container.decode(Bool.self) { self = .bool(b); return }
            throw DecodingError.typeMismatch(V10AssertionValue.self, .init(codingPath: decoder.codingPath, debugDescription: "Unknown type"))
        }
        
        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case .string(let s): try container.encode(s)
            case .number(let n): try container.encode(n)
            case .bool(let b): try container.encode(b)
            }
        }
    }
    
    struct V10EvalMetadata: Codable {
        let scenario_week: Int?
        let plate_profile: String?
        let phase: String?
    }
    
    struct V10Manifest: Codable {
        let version: String
        let created: String
        let dataset_version: String?
        let files: [V10ManifestFile]
        let total_cases: Int
        let coverage: V10Coverage?
    }
    
    struct V10ManifestFile: Codable {
        let path: String
        let count: Int
        let tags: [String]?
    }
    
    struct V10Coverage: Codable {
        let primary_suites: [String]?
        let secondary_suites: [String]?
        let plate_profiles: [String]?
        let time_horizons: V10TimeHorizons?
    }
    
    struct V10TimeHorizons: Codable {
        let microloading_weeks: Int?
        let cut_weeks: Int?
        let isolation_weeks: Int?
    }
    
    // MARK: - Scorecard
    
    struct Scorecard {
        var totalTests = 0
        var mainLiftPrescriptions = 0
        var loadWithinRange = 0
        var loadTotal = 0
        var loadErrors: [Double] = []
        var decisionCorrect = 0
        var decisionTotal = 0
        var assertionsPassed = 0
        var assertionsTotal = 0
        var loadStepViolations = 0
        
        var perCategory: [String: CategoryStats] = [:]
        var perScenario: [String: CategoryStats] = [:]
        var perSex: [String: CategoryStats] = [:]
        var perExperience: [String: CategoryStats] = [:]
        var perMovementType: [String: CategoryStats] = [:]
        var perPlateProfile: [String: CategoryStats] = [:]
    }
    
    struct CategoryStats {
        var tests = 0
        var lifts = 0
        var loadWithinRange = 0
        var decisionCorrect = 0
        var loadErrors: [Double] = []
        var loadStepViolations = 0
        
        var loadAgreement: Double { lifts > 0 ? Double(loadWithinRange) / Double(lifts) : 0 }
        var decisionAgreement: Double { lifts > 0 ? Double(decisionCorrect) / Double(lifts) : 0 }
        var mae: Double { loadErrors.isEmpty ? 0 : loadErrors.reduce(0, +) / Double(loadErrors.count) }
    }
    
    struct MismatchSample {
        let testId: String
        let category: String
        let lift: String
        let sex: String
        let experience: String
        let expectedDecision: String
        let expectedReasonCode: String
        let predictedDecision: String
        let engineDirection: String
        let engineDirectionReason: String
        let loadError: Double
        let expectedWeight: Double?
        let predictedWeight: Double
        let readiness: Int
        let daysSinceExposure: Int?
        let isCutMode: Bool
        let isIsolation: Bool
        let plateProfile: String
    }
    
    // All lifts (including isolations)
    let allLifts: Set<String> = ["squat", "bench", "deadlift", "ohp", "row", "lat_pulldown", "rdl", "incline_db", 
                                  "lateral_raise", "biceps_curl", "bicep_curl", "tricep_pushdown", "tricep_extension",
                                  "leg_curl", "leg_extension", "face_pull", "cable_row", "dumbbell_row",
                                  "curl", "hammer_curl", "overhead_tricep"]
    let compoundLifts: Set<String> = ["squat", "bench", "deadlift", "ohp", "row", "lat_pulldown", "rdl", "incline_db", "dumbbell_row", "cable_row"]
    
    static let baseDate: Date = {
        var components = DateComponents()
        components.year = 2025
        components.month = 9
        components.day = 1
        components.hour = 12
        components.minute = 0
        components.second = 0
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar.date(from: components)!
    }()
    
    static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()
    
    // MARK: - Test
    
    func testWorkoutEngineTestsetV10_FullE2EReplay() throws {
        let basePath = "/Users/rahulvijayan/Atlas 3/workout_engine_testset_v10"
        let manifestPath = "\(basePath)/manifest.json"
        
        guard let manifestData = try? Data(contentsOf: URL(fileURLWithPath: manifestPath)),
              let manifest = try? JSONDecoder().decode(V10Manifest.self, from: manifestData) else {
            XCTFail("Failed to read manifest.json")
            return
        }
        
        let expectedTotalCases = manifest.total_cases
        print("📋 V10 Manifest: \(manifest.files.count) scenario files, \(expectedTotalCases) expected cases")
        print("📌 V10 Coverage: \(manifest.coverage?.primary_suites?.joined(separator: ", ") ?? "unknown")")
        print("📌 V10 Plate profiles: \(manifest.coverage?.plate_profiles?.joined(separator: ", ") ?? "unknown")")
        
        let decoder = JSONDecoder()
        var allRecords: [(scenario: String, record: V10Record)] = []
        var decodeFailures: [(file: String, line: Int, error: String)] = []
        
        for fileEntry in manifest.files {
            let filePath = "\(basePath)/\(fileEntry.path)"
            guard let content = try? String(contentsOfFile: filePath, encoding: .utf8) else {
                decodeFailures.append((fileEntry.path, 0, "Could not read file"))
                continue
            }
            
            let scenarioName = URL(fileURLWithPath: fileEntry.path).lastPathComponent
            let lines = content.components(separatedBy: .newlines).filter { !$0.isEmpty }
            
            for (idx, line) in lines.enumerated() {
                guard let data = line.data(using: .utf8) else { continue }
                do {
                    let record = try decoder.decode(V10Record.self, from: data)
                    allRecords.append((scenarioName, record))
                } catch {
                    decodeFailures.append((scenarioName, idx + 1, "Line \(idx + 1): decode error - \(error.localizedDescription)"))
                }
            }
        }
        
        if !decodeFailures.isEmpty {
            print("❌ DECODE FAILURES (\(decodeFailures.count)):")
            for f in decodeFailures.prefix(20) {
                print("  \(f.file):\(f.line) - \(f.error)")
            }
            if decodeFailures.count > 20 {
                print("  ... and \(decodeFailures.count - 20) more")
            }
        }
        
        XCTAssertTrue(decodeFailures.isEmpty, "All JSONL lines must decode successfully. \(decodeFailures.count) failures.")
        XCTAssertEqual(allRecords.count, expectedTotalCases, "Must load exactly \(expectedTotalCases) test cases from manifest. Got \(allRecords.count).")
        
        print("✅ Loaded \(allRecords.count)/\(expectedTotalCases) test cases")
        
        var scorecard = Scorecard()
        var mismatchSamples: [MismatchSample] = []
        var confusion: [String: [String: Int]] = [:]
        let decisionLabels = ["deload", "hold", "increase", "decrease_small"]
        
        let exerciseCatalog = buildExerciseCatalog()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        
        for (scenario, record) in allRecords {
            scorecard.totalTests += 1
            
            let input = record.input
            let sex = input.user_profile.sex.lowercased()
            let experience = input.user_profile.experience_level.lowercased()
            let isCutMode = input.event_flags.cut_mode ?? (input.event_flags.phase?.lowercased().contains("cut") ?? false)
            let plateProfile = input.equipment_config.plate_profile ?? "standard"
            
            let userProfile = buildUserProfile(from: input.user_profile, isCutMode: isCutMode)
            let sessionDate = computeSessionDate(from: input, recordDate: record.date, calendar: calendar)
            let history = buildWorkoutHistory(from: input, sessionDate: sessionDate, exerciseCatalog: exerciseCatalog, calendar: calendar)
            let (plan, templateId) = buildTrainingPlan(from: input, exerciseCatalog: exerciseCatalog)
            let readiness = computeReadiness(from: input.today_metrics)
            let isPlannedDeload = input.event_flags.planned_deload_week ?? false
            
            let enginePlan = Engine.recommendSessionForTemplate(
                date: sessionDate,
                templateId: templateId,
                userProfile: userProfile,
                plan: plan,
                history: history,
                readiness: readiness,
                plannedDeloadWeek: isPlannedDeload,
                calendar: calendar
            )
            
            let engineExerciseMap: [String: ExercisePlan] = Dictionary(
                uniqueKeysWithValues: enginePlan.exercises.map { ($0.exercise.id.lowercased(), $0) }
            )
            
            // Get expected prescriptions from either expected_output or expected
            let expectedPrescriptions = record.expected_output?.session_prescription_for_today ?? record.expected?.session_prescription_for_today ?? []
            
            for (_, expectedRx) in expectedPrescriptions.enumerated() {
                let liftName = expectedRx.lift.lowercased()
                
                guard let expectedWeight = expectedRx.prescribed_weight_lb else { continue }
                
                let isCompound = compoundLifts.contains(liftName) || 
                    exerciseCatalog[liftName]?.movementPattern.isCompound == true
                let movementType = isCompound ? "compound" : "isolation"
                
                scorecard.mainLiftPrescriptions += 1
                scorecard.decisionTotal += 1
                scorecard.loadTotal += 1
                
                var catStats = scorecard.perCategory[record.test_category] ?? CategoryStats()
                catStats.tests += 1
                catStats.lifts += 1
                
                var scenarioStats = scorecard.perScenario[scenario] ?? CategoryStats()
                scenarioStats.tests += 1
                scenarioStats.lifts += 1
                
                var sexStats = scorecard.perSex[sex] ?? CategoryStats()
                sexStats.tests += 1
                sexStats.lifts += 1
                
                var expStats = scorecard.perExperience[experience] ?? CategoryStats()
                expStats.tests += 1
                expStats.lifts += 1
                
                var moveStats = scorecard.perMovementType[movementType] ?? CategoryStats()
                moveStats.tests += 1
                moveStats.lifts += 1
                
                var plateStats = scorecard.perPlateProfile[plateProfile] ?? CategoryStats()
                plateStats.tests += 1
                plateStats.lifts += 1
                
                let engineExercise = engineExerciseMap[liftName] ?? 
                    enginePlan.exercises.first(where: { $0.exercise.id.lowercased().contains(liftName) })
                
                let predictedWeight = engineExercise?.sets.first?.targetLoad.converted(to: .pounds).value ?? 0
                
                let loadError = abs(predictedWeight - expectedWeight)
                scorecard.loadErrors.append(loadError)
                catStats.loadErrors.append(loadError)
                scenarioStats.loadErrors.append(loadError)
                sexStats.loadErrors.append(loadError)
                expStats.loadErrors.append(loadError)
                moveStats.loadErrors.append(loadError)
                plateStats.loadErrors.append(loadError)
                
                // Check load step violation (V10 constraint)
                let loadStep = input.equipment_config.load_step_lb
                let isMultipleOfStep = abs(predictedWeight.truncatingRemainder(dividingBy: loadStep)) < 0.01 ||
                                       abs(loadStep - predictedWeight.truncatingRemainder(dividingBy: loadStep)) < 0.01
                if !isMultipleOfStep && predictedWeight > 0 {
                    scorecard.loadStepViolations += 1
                    catStats.loadStepViolations += 1
                    plateStats.loadStepViolations += 1
                }
                
                let withinRange: Bool = {
                    if let range = expectedRx.acceptable_range_lb, range.count == 2 {
                        return predictedWeight >= range[0] && predictedWeight <= range[1]
                    }
                    return loadError <= loadStep
                }()
                
                if withinRange {
                    scorecard.loadWithinRange += 1
                    catStats.loadWithinRange += 1
                    scenarioStats.loadWithinRange += 1
                    sexStats.loadWithinRange += 1
                    expStats.loadWithinRange += 1
                    moveStats.loadWithinRange += 1
                    plateStats.loadWithinRange += 1
                }
                
                let expectedDecision = normalizeDecision(expectedRx.decision)
                let liftState = history.liftStates[liftName]
                let predictedDecision = inferDecision(
                    exercisePlan: engineExercise,
                    liftState: liftState,
                    predictedWeight: predictedWeight,
                    loadStepLb: loadStep,
                    isPlannedDeload: isPlannedDeload,
                    isSessionDeload: enginePlan.isDeload
                )
                
                var row = confusion[expectedDecision, default: [:]]
                row[predictedDecision, default: 0] += 1
                confusion[expectedDecision] = row
                
                if expectedDecision == predictedDecision {
                    scorecard.decisionCorrect += 1
                    catStats.decisionCorrect += 1
                    scenarioStats.decisionCorrect += 1
                    sexStats.decisionCorrect += 1
                    expStats.decisionCorrect += 1
                    moveStats.decisionCorrect += 1
                    plateStats.decisionCorrect += 1
                } else if mismatchSamples.count < 100 {
                    let dir = engineExercise?.direction?.rawValue ?? "nil"
                    let reason = engineExercise?.directionReason?.rawValue ?? "nil"
                    let daysExposure = input.days_since_lift_exposure?[liftName]?.value
                    mismatchSamples.append(MismatchSample(
                        testId: record.test_id,
                        category: record.test_category,
                        lift: liftName,
                        sex: sex,
                        experience: experience,
                        expectedDecision: expectedDecision,
                        expectedReasonCode: expectedRx.reason_code ?? "unknown",
                        predictedDecision: predictedDecision,
                        engineDirection: dir,
                        engineDirectionReason: reason,
                        loadError: loadError,
                        expectedWeight: expectedWeight,
                        predictedWeight: predictedWeight,
                        readiness: readiness,
                        daysSinceExposure: daysExposure,
                        isCutMode: isCutMode,
                        isIsolation: !isCompound,
                        plateProfile: plateProfile
                    ))
                }
                
                scorecard.perCategory[record.test_category] = catStats
                scorecard.perScenario[scenario] = scenarioStats
                scorecard.perSex[sex] = sexStats
                scorecard.perExperience[experience] = expStats
                scorecard.perMovementType[movementType] = moveStats
                scorecard.perPlateProfile[plateProfile] = plateStats
            }
            
            if let assertions = record.assertions {
                for assertion in assertions {
                    scorecard.assertionsTotal += 1
                    if checkAssertion(assertion, enginePlan: enginePlan, input: input, engineExerciseMap: engineExerciseMap) {
                        scorecard.assertionsPassed += 1
                    }
                }
            }
        }
        
        printDiagnostics(
            scorecard: scorecard,
            confusion: confusion,
            mismatchSamples: mismatchSamples,
            decisionLabels: decisionLabels
        )
        
        XCTAssertEqual(scorecard.totalTests, expectedTotalCases, "Must process all \(expectedTotalCases) test cases")
    }
    
    // MARK: - Session Date Computation
    
    private func computeSessionDate(from input: V10Input, recordDate: String?, calendar: Calendar) -> Date {
        // First try to use the session_date from today_metrics
        if let dateStr = input.today_metrics.session_date, let date = Self.dateFormatter.date(from: dateStr) {
            return date
        }
        
        // Then try to use the record's date field
        if let dateStr = recordDate, let date = Self.dateFormatter.date(from: dateStr) {
            return date
        }
        
        var maxHistoryDate: Date? = nil
        
        for (_, entries) in input.recent_lift_history {
            for entry in entries {
                if let entryDate = Self.dateFormatter.date(from: entry.date) {
                    // Ignore future dates (V10 constraint: ignore_future_date_and_unit_mix_history)
                    if entryDate <= Self.baseDate.addingTimeInterval(365 * 24 * 60 * 60) {
                        if maxHistoryDate == nil || entryDate > maxHistoryDate! {
                            maxHistoryDate = entryDate
                        }
                    }
                }
            }
        }
        
        if let latestHistory = maxHistoryDate {
            let daysSince = input.days_since_last_session ?? 2
            return calendar.date(byAdding: .day, value: daysSince, to: latestHistory) ?? Self.baseDate
        }
        
        return Self.baseDate
    }
    
    // MARK: - Helpers
    
    private func buildUserProfile(from profile: V10UserProfile, isCutMode: Bool) -> UserProfile {
        let sex: BiologicalSex = {
            switch profile.sex.lowercased() {
            case "male": return .male
            case "female": return .female
            default: return .other
            }
        }()
        
        let experience: ExperienceLevel = {
            switch profile.experience_level.lowercased() {
            case "beginner", "novice": return .beginner
            case "intermediate": return .intermediate
            case "advanced": return .advanced
            case "elite": return .elite
            default: return .intermediate
            }
        }()
        
        let goals: [TrainingGoal] = {
            let goal = profile.goal.lowercased()
            if isCutMode || goal.contains("fat_loss") || goal.contains("cut") {
                return [.fatLoss]
            }
            switch goal {
            case "strength": return [.strength]
            case "hypertrophy": return [.hypertrophy]
            case "strength_hypertrophy": return [.strength, .hypertrophy]
            default: return [.strength, .hypertrophy]
            }
        }()
        
        return UserProfile(
            id: "v10_test_user",
            sex: sex,
            experience: experience,
            goals: goals,
            weeklyFrequency: 4,
            availableEquipment: .commercialGym,
            preferredUnit: .pounds,
            bodyWeight: Load(value: profile.body_weight_lb, unit: .pounds),
            age: profile.age,
            limitations: []
        )
    }
    
    private func buildExerciseCatalog() -> [String: Exercise] {
        var catalog: [String: Exercise] = [:]
        
        // Main compounds
        catalog["squat"] = Exercise(id: "squat", name: "Barbell Back Squat", equipment: .barbell, primaryMuscles: [.quadriceps, .glutes], secondaryMuscles: [.hamstrings, .lowerBack], movementPattern: .squat)
        catalog["bench"] = Exercise(id: "bench", name: "Barbell Bench Press", equipment: .barbell, primaryMuscles: [.chest, .frontDelts, .triceps], movementPattern: .horizontalPush)
        catalog["deadlift"] = Exercise(id: "deadlift", name: "Conventional Deadlift", equipment: .barbell, primaryMuscles: [.glutes, .hamstrings, .lowerBack], secondaryMuscles: [.quadriceps, .traps], movementPattern: .hipHinge)
        catalog["ohp"] = Exercise(id: "ohp", name: "Overhead Press", equipment: .barbell, primaryMuscles: [.frontDelts, .triceps], secondaryMuscles: [.chest], movementPattern: .verticalPush)
        catalog["row"] = Exercise(id: "row", name: "Barbell Row", equipment: .barbell, primaryMuscles: [.lats, .rhomboids], secondaryMuscles: [.biceps], movementPattern: .horizontalPull)
        
        // Compound accessories
        catalog["lat_pulldown"] = Exercise(id: "lat_pulldown", name: "Lat Pulldown", equipment: .cable, primaryMuscles: [.lats, .biceps], movementPattern: .verticalPull)
        catalog["rdl"] = Exercise(id: "rdl", name: "Romanian Deadlift", equipment: .barbell, primaryMuscles: [.hamstrings, .glutes], movementPattern: .hipHinge)
        catalog["incline_db"] = Exercise(id: "incline_db", name: "Incline Dumbbell Press", equipment: .dumbbell, primaryMuscles: [.chest, .frontDelts], movementPattern: .horizontalPush)
        catalog["dumbbell_row"] = Exercise(id: "dumbbell_row", name: "Dumbbell Row", equipment: .dumbbell, primaryMuscles: [.lats, .rhomboids], movementPattern: .horizontalPull)
        catalog["cable_row"] = Exercise(id: "cable_row", name: "Cable Row", equipment: .cable, primaryMuscles: [.lats, .rhomboids], movementPattern: .horizontalPull)
        
        // Isolation exercises
        catalog["lateral_raise"] = Exercise(id: "lateral_raise", name: "Lateral Raise", equipment: .dumbbell, primaryMuscles: [.sideDelts], movementPattern: .shoulderAbduction)
        catalog["biceps_curl"] = Exercise(id: "biceps_curl", name: "Biceps Curl", equipment: .dumbbell, primaryMuscles: [.biceps], movementPattern: .elbowFlexion)
        catalog["bicep_curl"] = Exercise(id: "bicep_curl", name: "Bicep Curl", equipment: .dumbbell, primaryMuscles: [.biceps], movementPattern: .elbowFlexion)
        catalog["curl"] = Exercise(id: "curl", name: "Bicep Curl", equipment: .dumbbell, primaryMuscles: [.biceps], movementPattern: .elbowFlexion)
        catalog["hammer_curl"] = Exercise(id: "hammer_curl", name: "Hammer Curl", equipment: .dumbbell, primaryMuscles: [.biceps], movementPattern: .elbowFlexion)
        catalog["tricep_pushdown"] = Exercise(id: "tricep_pushdown", name: "Tricep Pushdown", equipment: .cable, primaryMuscles: [.triceps], movementPattern: .elbowExtension)
        catalog["tricep_extension"] = Exercise(id: "tricep_extension", name: "Tricep Extension", equipment: .cable, primaryMuscles: [.triceps], movementPattern: .elbowExtension)
        catalog["overhead_tricep"] = Exercise(id: "overhead_tricep", name: "Overhead Tricep Extension", equipment: .cable, primaryMuscles: [.triceps], movementPattern: .elbowExtension)
        catalog["leg_curl"] = Exercise(id: "leg_curl", name: "Leg Curl", equipment: .machine, primaryMuscles: [.hamstrings], movementPattern: .kneeFlexion)
        catalog["leg_extension"] = Exercise(id: "leg_extension", name: "Leg Extension", equipment: .machine, primaryMuscles: [.quadriceps], movementPattern: .kneeExtension)
        catalog["face_pull"] = Exercise(id: "face_pull", name: "Face Pull", equipment: .cable, primaryMuscles: [.rearDelts, .rhomboids], movementPattern: .horizontalPull)
        
        return catalog
    }
    
    private func makeExercise(id: String) -> Exercise {
        let lower = id.lowercased()
        
        let pattern: MovementPattern = {
            if lower.contains("squat") { return .squat }
            if lower.contains("deadlift") || lower.contains("rdl") || lower.contains("hinge") { return .hipHinge }
            if lower.contains("bench") || (lower.contains("press") && !lower.contains("leg") && !lower.contains("shoulder")) { return .horizontalPush }
            if lower.contains("ohp") || lower.contains("overhead") && !lower.contains("tricep") || lower.contains("shoulder_press") { return .verticalPush }
            if lower.contains("row") || (lower.contains("pull") && lower.contains("horizontal")) { return .horizontalPull }
            if lower.contains("pulldown") || lower.contains("pullup") || lower.contains("chin") || lower.contains("lat_pull") { return .verticalPull }
            if lower.contains("curl") && !lower.contains("leg") { return .elbowFlexion }
            if lower.contains("extension") && !lower.contains("leg") { return .elbowExtension }
            if lower.contains("tricep") || lower.contains("pushdown") { return .elbowExtension }
            if lower.contains("lateral") || lower.contains("raise") { return .shoulderAbduction }
            if lower.contains("leg_curl") { return .kneeFlexion }
            if lower.contains("leg_extension") { return .kneeExtension }
            return .unknown
        }()
        
        let equipment: Equipment = {
            if lower.contains("db") || lower.contains("dumbbell") || lower.contains("lateral") || lower.contains("curl") { return .dumbbell }
            if lower.contains("cable") || lower.contains("pushdown") || lower.contains("face_pull") { return .cable }
            if lower.contains("machine") || lower.contains("leg_press") || lower.contains("hack") || lower.contains("leg_curl") || lower.contains("leg_extension") { return .machine }
            if lower.contains("body") || lower.contains("dip") || lower.contains("pullup") { return .bodyweight }
            return .barbell
        }()
        
        let primaryMuscles: [MuscleGroup] = {
            if pattern == .squat { return [.quadriceps, .glutes] }
            if pattern == .hipHinge { return [.hamstrings, .glutes] }
            if pattern == .horizontalPush { return [.chest, .triceps] }
            if pattern == .verticalPush { return [.frontDelts, .triceps] }
            if pattern == .horizontalPull { return [.lats, .rhomboids] }
            if pattern == .verticalPull { return [.lats, .biceps] }
            if pattern == .elbowFlexion { return [.biceps] }
            if pattern == .elbowExtension { return [.triceps] }
            if pattern == .shoulderAbduction { return [.sideDelts] }
            if pattern == .kneeFlexion { return [.hamstrings] }
            if pattern == .kneeExtension { return [.quadriceps] }
            return [.chest]
        }()
        
        return Exercise(
            id: id,
            name: id.replacingOccurrences(of: "_", with: " ").capitalized,
            equipment: equipment,
            primaryMuscles: primaryMuscles,
            movementPattern: pattern
        )
    }
    
    private func buildWorkoutHistory(
        from input: V10Input,
        sessionDate: Date,
        exerciseCatalog: [String: Exercise],
        calendar: Calendar
    ) -> WorkoutHistory {
        var liftStates: [String: LiftState] = [:]
        var sessionsByDate: [String: [(lift: String, entry: V10HistoryEntry)]] = [:]
        
        if let providedStates = input.lift_state {
            for (liftName, state) in providedStates {
                let liftKey = liftName.lowercased()
                var ls = LiftState(exerciseId: liftKey)
                ls.lastWorkingWeight = Load(value: state.lastWorkingWeight.value, unit: .pounds)
                ls.rollingE1RM = state.rollingE1RM ?? 0
                ls.failureCount = state.failureCount
                ls.highRpeStreak = state.highRpeStreak
                ls.successStreak = state.successStreak
                ls.successfulSessionsCount = state.successfulSessionsCount
                
                if let dateStr = state.lastDeloadDate, let date = Self.dateFormatter.date(from: dateStr) {
                    ls.lastDeloadDate = date
                }
                
                ls.trend = {
                    switch state.trend.lowercased() {
                    case "improving": return .improving
                    case "declining": return .declining
                    case "stable": return .stable
                    default: return .insufficient
                    }
                }()
                
                liftStates[liftKey] = ls
            }
        }
        
        for (liftName, entries) in input.recent_lift_history {
            guard !entries.isEmpty else { continue }
            let liftKey = liftName.lowercased()
            
            var state = liftStates[liftKey] ?? LiftState(exerciseId: liftKey)
            var e1rmHistory: [E1RMSample] = []
            
            // Filter out invalid entries (future dates, etc.) - V10 constraint
            let validEntries = entries.filter { entry in
                guard let entryDate = Self.dateFormatter.date(from: entry.date) else { return false }
                // Ignore entries dated more than 2 years in the future from baseDate
                return entryDate <= Self.baseDate.addingTimeInterval(2 * 365 * 24 * 60 * 60)
            }
            
            let sortedEntries = validEntries.sorted { $0.date < $1.date }
            
            for entry in sortedEntries {
                guard let entryDate = Self.dateFormatter.date(from: entry.date) else { continue }
                
                if state.lastWorkingWeight.value == 0 {
                    state.lastWorkingWeight = Load(value: entry.weight_lb, unit: .pounds)
                } else if entry.date >= (sortedEntries.last?.date ?? "") {
                    state.lastWorkingWeight = Load(value: entry.weight_lb, unit: .pounds)
                }
                state.lastSessionDate = entryDate
                
                let e1rm = E1RMCalculator.brzycki(weight: entry.weight_lb, reps: entry.reps)
                e1rmHistory.append(E1RMSample(date: entryDate, value: e1rm))
                
                sessionsByDate[entry.date, default: []].append((lift: liftKey, entry: entry))
            }
            
            if !e1rmHistory.isEmpty && state.rollingE1RM == 0 {
                state.e1rmHistory = Array(e1rmHistory.suffix(10))
                state.rollingE1RM = e1rmHistory.last!.value
                state.trend = TrendCalculator.compute(from: state.e1rmHistory)
            }
            
            liftStates[liftKey] = state
        }
        
        if let daysSinceExposure = input.days_since_lift_exposure {
            for (liftName, daysSinceValue) in daysSinceExposure {
                let liftKey = liftName.lowercased()
                if let days = daysSinceValue.value, days >= 0 {
                    let lastDate = calendar.date(byAdding: .day, value: -days, to: sessionDate) ?? sessionDate
                    if var state = liftStates[liftKey] {
                        if state.lastSessionDate == nil || lastDate > state.lastSessionDate! {
                            state.lastSessionDate = lastDate
                            liftStates[liftKey] = state
                        }
                    } else {
                        var newState = LiftState(exerciseId: liftKey)
                        newState.lastSessionDate = lastDate
                        liftStates[liftKey] = newState
                    }
                }
            }
        }
        
        var completedSessions: [CompletedSession] = []
        
        for (dateStr, liftEntries) in sessionsByDate.sorted(by: { $0.key < $1.key }) {
            guard let sessionDateValue = Self.dateFormatter.date(from: dateStr) else { continue }
            
            var exerciseResults: [ExerciseSessionResult] = []
            
            for (liftKey, entry) in liftEntries {
                let exercise = exerciseCatalog[liftKey] ?? makeExercise(id: liftKey)
                
                let templateSets = input.today_session_template.first(where: { $0.lift.lowercased() == liftKey })?.sets ?? 3
                
                var setResults: [SetResult] = []
                for _ in 0..<templateSets {
                    let rirObserved: Int? = {
                        guard let rpe = entry.top_rpe else { return nil }
                        return max(0, min(5, Int(round(10.0 - rpe))))
                    }()
                    
                    let setResult = SetResult(
                        reps: entry.reps,
                        load: Load(value: entry.weight_lb, unit: .pounds),
                        rirObserved: rirObserved
                    )
                    setResults.append(setResult)
                }
                
                let prescription = SetPrescription(
                    setCount: templateSets,
                    targetRepsRange: entry.reps...entry.reps,
                    targetRIR: 2,
                    restSeconds: 180,
                    loadStrategy: .absolute,
                    increment: Load(value: 5.0, unit: .pounds)
                )
                
                let exerciseResult = ExerciseSessionResult(
                    exerciseId: exercise.id,
                    prescription: prescription,
                    sets: setResults,
                    notes: nil
                )
                exerciseResults.append(exerciseResult)
            }
            
            if !exerciseResults.isEmpty {
                let session = CompletedSession(
                    id: UUID(),
                    date: sessionDateValue,
                    templateId: nil,
                    name: "V10 Historical Session",
                    exerciseResults: exerciseResults,
                    startedAt: sessionDateValue,
                    readinessScore: 70
                )
                completedSessions.append(session)
            }
        }
        
        return WorkoutHistory(sessions: completedSessions, liftStates: liftStates)
    }
    
    private func buildTrainingPlan(from input: V10Input, exerciseCatalog: [String: Exercise]) -> (TrainingPlan, UUID) {
        let templateId = UUID()
        let increment = input.equipment_config.load_step_lb
        
        let experience: ExperienceLevel = {
            switch input.user_profile.experience_level.lowercased() {
            case "beginner", "novice": return .beginner
            case "intermediate": return .intermediate
            case "advanced": return .advanced
            case "elite": return .elite
            default: return .intermediate
            }
        }()
        
        let templateExercises = input.today_session_template.map { te -> TemplateExercise in
            let liftId = te.lift.lowercased()
            let exercise = exerciseCatalog[liftId] ?? exerciseCatalog[liftId.replacingOccurrences(of: "_", with: "")] ?? makeExercise(id: liftId)
            
            let targetRIR = inferRIRFromReps(te.reps)
            
            // Use the actual load step from equipment config
            let exerciseIncrement: Double = exercise.movementPattern.isCompound ? increment : min(increment, 2.5)
            
            // Handle rep range if provided
            let repRange: ClosedRange<Int> = {
                if let range = te.reps_range, range.count == 2 {
                    return range[0]...range[1]
                }
                return te.reps...te.reps
            }()
            
            let loadStrategy: LoadStrategy = {
                if let policy = input.config_overrides?.progression_policy?.lowercased() {
                    if policy == "percentage_e1rm" || policy == "percent_e1rm" {
                        if experience != .beginner && exercise.movementPattern.isCompound {
                            return .percentageE1RM
                        }
                    }
                }
                let isCompound = exercise.movementPattern.isCompound
                let isIntermediatePlus = experience != .beginner
                let isHeavyWork = te.reps <= 5
                return (isCompound && isIntermediatePlus && isHeavyWork) ? .percentageE1RM : .absolute
            }()
            
            let prescription = SetPrescription(
                setCount: te.sets,
                targetRepsRange: repRange,
                targetRIR: targetRIR,
                restSeconds: 180,
                loadStrategy: loadStrategy,
                increment: Load(value: exerciseIncrement, unit: .pounds)
            )
            return TemplateExercise(exercise: exercise, prescription: prescription)
        }
        
        let template = WorkoutTemplate(
            id: templateId,
            name: input.user_profile.program,
            exercises: templateExercises
        )
        
        let roundingPolicy = LoadRoundingPolicy(increment: increment, unit: .pounds, mode: .nearest)
        
        var templates: [WorkoutTemplateId: WorkoutTemplate] = [:]
        templates[templateId] = template
        
        var progressionPolicies: [String: ProgressionPolicyType] = [:]
        
        if let policyStr = input.config_overrides?.progression_policy?.lowercased() {
            for te in input.today_session_template {
                let liftId = te.lift.lowercased()
                let exercise = exerciseCatalog[liftId] ?? makeExercise(id: liftId)
                
                switch policyStr {
                case "linear":
                    let lpConfig: LinearProgressionConfig = exercise.movementPattern == .squat || exercise.movementPattern == .hipHinge 
                        ? .lowerBody 
                        : .upperBody
                    progressionPolicies[liftId] = .linearProgression(config: lpConfig)
                    
                case "double_progression":
                    if exercise.movementPattern.isCompound {
                        progressionPolicies[liftId] = .doubleProgression(config: .default)
                    } else {
                        progressionPolicies[liftId] = .doubleProgression(config: .smallIncrement)
                    }
                    
                case "percentage_e1rm", "percent_e1rm":
                    progressionPolicies[liftId] = .rirAutoregulation(config: .default)
                    
                default:
                    break
                }
            }
        }
        
        let deloadConfig = DeloadConfig(
            intensityReduction: input.config_overrides?.deload_config?.intensityReduction ?? 0.10,
            volumeReduction: input.config_overrides?.deload_config?.volumeReduction ?? 1,
            readinessThreshold: 50
        )
        
        let plan = TrainingPlan(
            name: input.user_profile.program,
            templates: templates,
            schedule: .rotation(order: [templateId]),
            progressionPolicies: progressionPolicies,
            substitutionPool: Array(exerciseCatalog.values),
            deloadConfig: deloadConfig,
            loadRoundingPolicy: roundingPolicy
        )
        
        return (plan, templateId)
    }
    
    private func inferRIRFromReps(_ reps: Int) -> Int {
        if reps <= 3 { return 1 }
        else if reps <= 5 { return 2 }
        else if reps <= 8 { return 2 }
        else { return 3 }
    }
    
    private func computeReadiness(from metrics: V10TodayMetrics) -> Int {
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
        if lower.contains("estimate") { return "hold" } // V10: treat cold-start "estimate" as a conservative hold category
        return lower
    }
    
    private func normalizeAdjustmentKind(_ kind: SessionAdjustmentKind?) -> String {
        guard let kind else { return "none" }
        switch kind {
        case .none:
            return "none"
        case .deload:
            return "deload"
        case .readinessCut:
            // Dataset uses camelCase; engine uses snake_case raw values.
            return "readinessCut"
        case .breakReset:
            return "breakReset"
        }
    }
    
    private func inferDecision(
        exercisePlan: ExercisePlan?,
        liftState: LiftState?,
        predictedWeight: Double,
        loadStepLb: Double,
        isPlannedDeload: Bool,
        isSessionDeload: Bool
    ) -> String {
        if isPlannedDeload || isSessionDeload { return "deload" }
        
        if let direction = exercisePlan?.direction {
            switch direction {
            case .increase: return "increase"
            case .hold: return "hold"
            case .decreaseSlightly: return "decrease_small"
            case .deload: return "deload"
            case .resetAfterBreak: return "decrease_small"
            }
        }
        
        guard let state = liftState, state.lastWorkingWeight.value > 0 else {
            return "hold"
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
    
    private func checkAssertion(
        _ assertion: V10Assertion,
        enginePlan: SessionPlan,
        input: V10Input,
        engineExerciseMap: [String: ExercisePlan]
    ) -> Bool {
        let parts = assertion.field.components(separatedBy: ".")
        guard parts.count >= 2 else { return false }
        
        let firstPart = parts[0]
        guard let indexStart = firstPart.firstIndex(of: "["),
              let indexEnd = firstPart.firstIndex(of: "]"),
              let index = Int(firstPart[firstPart.index(after: indexStart)..<indexEnd]) else {
            return false
        }
        
        guard index < input.today_session_template.count else { return false }
        let liftName = input.today_session_template[index].lift.lowercased()
        
        guard let exercise = engineExerciseMap[liftName] ?? 
            enginePlan.exercises.first(where: { $0.exercise.id.lowercased().contains(liftName) }) else {
            return false
        }
        
        let fieldName = parts[1]
        
        switch fieldName {
        case "decision":
            let predictedDecision = inferDecision(
                exercisePlan: exercise,
                liftState: nil,
                predictedWeight: exercise.sets.first?.targetLoad.converted(to: .pounds).value ?? 0,
                loadStepLb: input.equipment_config.load_step_lb,
                isPlannedDeload: input.event_flags.planned_deload_week ?? false,
                isSessionDeload: enginePlan.isDeload
            )
            let predictedNorm = normalizeDecision(predictedDecision)
            
            if let oneOf = assertion.expected_one_of, !oneOf.isEmpty {
                return oneOf.map { normalizeDecision($0) }.contains(predictedNorm)
            }
            
            if let expected = assertion.expected, case .string(let expectedStr) = expected {
                return predictedNorm == normalizeDecision(expectedStr)
            }
            
        case "adjustment_kind":
            let predictedKind = normalizeAdjustmentKind(exercise.recommendedAdjustmentKind)
            
            if let oneOf = assertion.expected_one_of, !oneOf.isEmpty {
                return oneOf.map { $0.lowercased() }.contains(predictedKind.lowercased())
            }
            
            if let expected = assertion.expected, case .string(let expectedStr) = expected {
                return predictedKind.lowercased() == expectedStr.lowercased()
            }
            
        case "prescribed_weight_lb":
            let predictedWeight = exercise.sets.first?.targetLoad.converted(to: .pounds).value ?? 0
            if let range = assertion.expected_range, range.count == 2 {
                return predictedWeight >= range[0] && predictedWeight <= range[1]
            }
            
        default:
            break
        }
        
        return false
    }
    
    // MARK: - Diagnostics Output
    
    private func printDiagnostics(
        scorecard: Scorecard,
        confusion: [String: [String: Int]],
        mismatchSamples: [MismatchSample],
        decisionLabels: [String]
    ) {
        let isVerbose = ProcessInfo.processInfo.environment["V10_VERBOSE"] == "1"
        let now = ISO8601DateFormatter().string(from: Date())
        var logLines: [String] = []
        
        logLines.append("=" * 80)
        logLines.append("V10 FULL E2E REPLAY DIAGNOSTICS (microloading, cut, isolation DP) @ \(now)")
        logLines.append("=" * 80)
        logLines.append("")
        
        let loadPct = scorecard.loadTotal > 0 ? Double(scorecard.loadWithinRange) / Double(scorecard.loadTotal) * 100 : 0
        let decPct = scorecard.decisionTotal > 0 ? Double(scorecard.decisionCorrect) / Double(scorecard.decisionTotal) * 100 : 0
        let mae = scorecard.loadErrors.isEmpty ? 0 : scorecard.loadErrors.reduce(0, +) / Double(scorecard.loadErrors.count)
        let assertPct = scorecard.assertionsTotal > 0 ? Double(scorecard.assertionsPassed) / Double(scorecard.assertionsTotal) * 100 : 0
        
        logLines.append("OVERALL SUMMARY:")
        logLines.append("  Total test cases: \(scorecard.totalTests)")
        logLines.append("  Total prescriptions scored: \(scorecard.mainLiftPrescriptions)")
        logLines.append("")
        logLines.append("  📊 Load Agreement: \(scorecard.loadWithinRange)/\(scorecard.loadTotal) = \(String(format: "%.1f", loadPct))%")
        logLines.append("  🎯 Decision Agreement: \(scorecard.decisionCorrect)/\(scorecard.decisionTotal) = \(String(format: "%.1f", decPct))%")
        logLines.append("  📏 Mean Absolute Error: \(String(format: "%.2f", mae)) lb")
        logLines.append("  ✅ Assertions Passed: \(scorecard.assertionsPassed)/\(scorecard.assertionsTotal) = \(String(format: "%.1f", assertPct))%")
        logLines.append("  ⚠️ Load Step Violations: \(scorecard.loadStepViolations)")
        logLines.append("")
        
        // Decision confusion matrix
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
        
        // Per-plate-profile breakdown (V10 specific)
        logLines.append("-" * 80)
        logLines.append("PER-PLATE-PROFILE BREAKDOWN (V10 microloading focus):")
        for (profile, stats) in scorecard.perPlateProfile.sorted(by: { $0.key < $1.key }) {
            logLines.append("  \(profile):")
            logLines.append("    lifts=\(stats.lifts) load=\(String(format: "%.1f%%", stats.loadAgreement * 100)) dec=\(String(format: "%.1f%%", stats.decisionAgreement * 100)) mae=\(String(format: "%.1f", stats.mae))lb stepViolations=\(stats.loadStepViolations)")
        }
        logLines.append("")
        
        // Per-experience breakdown
        logLines.append("-" * 80)
        logLines.append("PER-EXPERIENCE BREAKDOWN:")
        for (exp, stats) in scorecard.perExperience.sorted(by: { $0.key < $1.key }) {
            logLines.append("  \(exp):")
            logLines.append("    lifts=\(stats.lifts) load=\(String(format: "%.1f%%", stats.loadAgreement * 100)) dec=\(String(format: "%.1f%%", stats.decisionAgreement * 100)) mae=\(String(format: "%.1f", stats.mae))lb")
        }
        logLines.append("")
        
        // Per-movement-type breakdown (compound vs isolation)
        logLines.append("-" * 80)
        logLines.append("PER-MOVEMENT-TYPE BREAKDOWN (compound vs isolation):")
        for (moveType, stats) in scorecard.perMovementType.sorted(by: { $0.key < $1.key }) {
            logLines.append("  \(moveType):")
            logLines.append("    lifts=\(stats.lifts) load=\(String(format: "%.1f%%", stats.loadAgreement * 100)) dec=\(String(format: "%.1f%%", stats.decisionAgreement * 100)) mae=\(String(format: "%.1f", stats.mae))lb")
        }
        logLines.append("")
        
        // Per-sex breakdown
        logLines.append("-" * 80)
        logLines.append("PER-SEX BREAKDOWN:")
        for (sex, stats) in scorecard.perSex.sorted(by: { $0.key < $1.key }) {
            logLines.append("  \(sex):")
            logLines.append("    lifts=\(stats.lifts) load=\(String(format: "%.1f%%", stats.loadAgreement * 100)) dec=\(String(format: "%.1f%%", stats.decisionAgreement * 100)) mae=\(String(format: "%.1f", stats.mae))lb")
        }
        logLines.append("")
        
        // Per-scenario breakdown
        logLines.append("-" * 80)
        logLines.append("PER-SCENARIO BREAKDOWN:")
        for (scenario, stats) in scorecard.perScenario.sorted(by: { $0.key < $1.key }) {
            let scenarioName = scenario.replacingOccurrences(of: ".jsonl", with: "")
            logLines.append("  \(scenarioName):")
            logLines.append("    lifts=\(stats.lifts) load=\(String(format: "%.1f%%", stats.loadAgreement * 100)) dec=\(String(format: "%.1f%%", stats.decisionAgreement * 100)) mae=\(String(format: "%.1f", stats.mae))lb")
        }
        logLines.append("")
        
        // Per-category breakdown
        logLines.append("-" * 80)
        logLines.append("PER-CATEGORY BREAKDOWN:")
        for (category, stats) in scorecard.perCategory.sorted(by: { $0.key < $1.key }) {
            logLines.append("  \(category): lifts=\(stats.lifts) load=\(String(format: "%.1f%%", stats.loadAgreement * 100)) dec=\(String(format: "%.1f%%", stats.decisionAgreement * 100)) mae=\(String(format: "%.1f", stats.mae))lb")
        }
        logLines.append("")
        
        // Mismatch samples only in verbose mode
        if isVerbose {
            logLines.append("-" * 80)
            logLines.append("SAMPLE MISMATCHES (up to 100) [V10_VERBOSE=1]:")
            for sample in mismatchSamples.prefix(100) {
                logLines.append("  [\(sample.testId)] \(sample.lift) (\(sample.sex)/\(sample.experience)/\(sample.plateProfile))")
                logLines.append("    exp=\(sample.expectedDecision)(\(sample.expectedReasonCode)) pred=\(sample.predictedDecision)")
                logLines.append("    engine: dir=\(sample.engineDirection) reason=\(sample.engineDirectionReason)")
                logLines.append("    pred_weight=\(String(format: "%.1f", sample.predictedWeight))lb exp_weight=\(sample.expectedWeight.map { String(format: "%.1f", $0) } ?? "nil")lb err=\(String(format: "%.1f", sample.loadError))lb rdns=\(sample.readiness) days=\(sample.daysSinceExposure.map { String($0) } ?? "nil")")
                logLines.append("    cut_mode=\(sample.isCutMode) isolation=\(sample.isIsolation)")
            }
        } else {
            logLines.append("-" * 80)
            logLines.append("MISMATCH SAMPLES: \(mismatchSamples.count) total (set V10_VERBOSE=1 for details)")
        }
        
        let logText = logLines.joined(separator: "\n")
        print("\n" + logText)
        
        // Save to file
        let logURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("v10_replay_diagnostics.log")
        do {
            try logText.write(to: logURL, atomically: true, encoding: .utf8)
            print("\n  💾 Saved detailed v10 diagnostics to: \(logURL.path)")
        } catch {
            print("\n  ⚠️ Failed to write v10 diagnostics log: \(error)")
        }
        
        // Print final scorecard
        print("""
        
        ================================================================================
        🧪 workout_engine_testset_v10 FULL E2E SCORECARD:
        ================================================================================
          Total test cases: \(scorecard.totalTests)
          Total prescriptions scored: \(scorecard.mainLiftPrescriptions)
          
          📊 Load Agreement:
            Within acceptable range: \(scorecard.loadWithinRange)/\(scorecard.loadTotal) = \(String(format: "%.1f", loadPct))%
            Mean Absolute Error: \(String(format: "%.2f", mae)) lb
          
          🎯 Decision Agreement:
            Overall: \(scorecard.decisionCorrect)/\(scorecard.decisionTotal) = \(String(format: "%.1f", decPct))%
          
          ✅ Assertions:
            Passed: \(scorecard.assertionsPassed)/\(scorecard.assertionsTotal) = \(String(format: "%.1f", assertPct))%
          
          ⚠️ Constraint Violations:
            Load step violations: \(scorecard.loadStepViolations)
        ================================================================================
        """)
    }
}

// MARK: - String extension
private extension String {
    static func * (lhs: String, rhs: Int) -> String {
        return String(repeating: lhs, count: rhs)
    }
}
