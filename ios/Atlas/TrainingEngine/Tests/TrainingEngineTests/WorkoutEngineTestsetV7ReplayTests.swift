// WorkoutEngineTestsetV7ReplayTests.swift
// Full E2E replay test for workout_engine_testset_v7_science dataset.
// V7: Test-case oriented with embedded history and lift_state; self-contained scenarios.
//
// CRITICAL: This test is BLIND - no expected values are leaked to the engine.
// The engine receives ONLY input data and its output is compared post-hoc.
//
// Phase 0 fixes applied:
// - 0.1: Supports null weights for accessories, validates 116 cases from manifest
// - 0.2: Deterministic time semantics (sessionDate computed from history, not Date())
// - 0.3: Builds WorkoutHistory.sessions from recent_lift_history
// - 0.4: Preserves exercise ordering, includes accessories via fallback
// - 0.5: Applies config_overrides (progression_policy, deload_config)
// - 0.6: Clean output with V7_VERBOSE env flag for detailed dumps

import XCTest
@testable import TrainingEngine
import Foundation

final class WorkoutEngineTestsetV7ReplayTests: XCTestCase {
    
    // MARK: - V7 Record Structures
    
    struct V7Record: Codable {
        let test_id: String
        let test_category: String
        let description: String
        let input: V7Input
        let expected_output: V7ExpectedOutput
        let assertions: [V7Assertion]?
    }
    
    struct V7Input: Codable {
        let user_profile: V7UserProfile
        let equipment: [String]?
        let equipment_config: V7EquipmentConfig
        let today_metrics: V7TodayMetrics
        let today_session_template: [V7TemplateExercise]
        let recent_lift_history: [String: [V7HistoryEntry]]
        let lift_state: [String: V7LiftState]?
        let days_since_last_session: Int?
        let days_since_lift_exposure: [String: Int?]
        let event_flags: V7EventFlags
        let config_overrides: V7ConfigOverrides?
    }
    
    struct V7UserProfile: Codable {
        let sex: String
        let age: Int
        let height_cm: Int
        let body_weight_lb: Double
        let experience_level: String
        let program: String
        let goal: String
    }
    
    struct V7EquipmentConfig: Codable {
        let units: String
        let bar_weight_lb: Double
        let load_step_lb: Double
    }
    
    struct V7TodayMetrics: Codable {
        let body_weight_lb: Double?
        let sleep_hours: Double?
        let hrv_ms: Int?
        let resting_hr_bpm: Int?
        let soreness_1_to_10: Int?
        let stress_1_to_10: Int?
        let steps: Int?
        let calories_est: Int?
    }
    
    struct V7TemplateExercise: Codable {
        let lift: String
        let sets: Int
        let reps: Int
    }
    
    struct V7HistoryEntry: Codable {
        let date: String
        let weight_lb: Double
        let reps: Int
        let top_rpe: Double?
        let outcome: String
        let variation: String?
    }
    
    struct V7LiftStateWeight: Codable {
        let value: Double
        let unit: String
    }
    
    struct V7LiftState: Codable {
        let exerciseId: String
        let lastWorkingWeight: V7LiftStateWeight
        let rollingE1RM: Double?
        let failureCount: Int
        let highRpeStreak: Int
        let lastDeloadDate: String?
        let trend: String
        let successStreak: Int
        let successfulSessionsCount: Int
        let recentReadinessScores: [Int]?
    }
    
    struct V7EventFlags: Codable {
        let missed_session: Bool
        let injury_flags: [String: V7InjuryFlag]?  // Can be Bool or String
        let planned_deload_week: Bool?
        let variation_overrides: [String: String]?
        let substitutions: [String: String]?
    }
    
    // V7InjuryFlag can be a boolean (true/false) or a string (injury type)
    enum V7InjuryFlag: Codable {
        case bool(Bool)
        case string(String)
        
        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let b = try? container.decode(Bool.self) { self = .bool(b); return }
            if let s = try? container.decode(String.self) { self = .string(s); return }
            throw DecodingError.typeMismatch(V7InjuryFlag.self, .init(codingPath: decoder.codingPath, debugDescription: "Expected Bool or String"))
        }
        
        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case .bool(let b): try container.encode(b)
            case .string(let s): try container.encode(s)
            }
        }
    }
    
    struct V7ConfigOverrides: Codable {
        let progression_policy: String?
        let deload_config: V7DeloadConfig?
    }
    
    struct V7DeloadConfig: Codable {
        let intensityReduction: Double?
        let volumeReduction: Int?
        let failuresBeforeDeload: Int?
    }
    
    struct V7ExpectedOutput: Codable {
        let session_prescription_for_today: [V7Prescription]
    }
    
    // MARK: - Phase 0.1 Fix: prescribed_weight_lb is now optional for accessories
    struct V7Prescription: Codable {
        let lift: String
        let prescribed_weight_lb: Double?  // Optional - accessories have null
        let sets: Int
        let target_reps: Int
        let target_rpe: Double?
        let decision: String
        let reason_code: String
        let adjustment_kind: String?
        let acceptable_range_lb: [Double]?
    }
    
    struct V7Assertion: Codable {
        let field: String
        let expected: V7AssertionValue?
        let expected_range: [Double]?
    }
    
    enum V7AssertionValue: Codable {
        case string(String)
        case number(Double)
        case bool(Bool)
        
        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let s = try? container.decode(String.self) { self = .string(s); return }
            if let n = try? container.decode(Double.self) { self = .number(n); return }
            if let b = try? container.decode(Bool.self) { self = .bool(b); return }
            throw DecodingError.typeMismatch(V7AssertionValue.self, .init(codingPath: decoder.codingPath, debugDescription: "Unknown type"))
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
    
    // Manifest structure for Phase 0.1
    struct V7Manifest: Codable {
        let version: String
        let created: String
        let files: [V7ManifestFile]
        let total_cases: Int
        let tags: [String]
    }
    
    struct V7ManifestFile: Codable {
        let path: String
        let count: Int
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
        
        var perCategory: [String: CategoryStats] = [:]
        var perScenario: [String: CategoryStats] = [:]
    }
    
    struct CategoryStats {
        var tests = 0
        var lifts = 0
        var loadWithinRange = 0
        var decisionCorrect = 0
        var loadErrors: [Double] = []
        
        var loadAgreement: Double { lifts > 0 ? Double(loadWithinRange) / Double(lifts) : 0 }
        var decisionAgreement: Double { lifts > 0 ? Double(decisionCorrect) / Double(lifts) : 0 }
        var mae: Double { loadErrors.isEmpty ? 0 : loadErrors.reduce(0, +) / Double(loadErrors.count) }
    }
    
    struct MismatchSample {
        let testId: String
        let category: String
        let lift: String
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
    }
    
    let mainLifts: Set<String> = ["squat", "bench", "deadlift", "ohp"]
    
    // Phase 0.2: Fixed base date for deterministic tests (UTC noon)
    static let baseDate: Date = {
        var components = DateComponents()
        components.year = 2026
        components.month = 1
        components.day = 26
        components.hour = 12
        components.minute = 0
        components.second = 0
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar.date(from: components)!
    }()
    
    // Date formatter for V7 history dates
    static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()
    
    // MARK: - Test
    
    func testWorkoutEngineTestsetV7_FullE2EReplay() throws {
        let basePath = "/Users/rahulvijayan/Atlas 3/workout_engine_testset_v7_science"
        let manifestPath = "\(basePath)/manifest.json"
        
        // Phase 0.1: Read manifest and validate
        guard let manifestData = try? Data(contentsOf: URL(fileURLWithPath: manifestPath)),
              let manifest = try? JSONDecoder().decode(V7Manifest.self, from: manifestData) else {
            XCTFail("Failed to read manifest.json")
            return
        }
        
        let expectedTotalCases = manifest.total_cases
        print("📋 V7 Manifest: \(manifest.files.count) scenario files, \(expectedTotalCases) expected cases")
        
        let decoder = JSONDecoder()
        var allRecords: [(scenario: String, record: V7Record)] = []
        var decodeFailures: [(file: String, line: Int, error: String)] = []
        
        // Phase 0.1: Dynamically discover scenario files from manifest
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
                    let record = try decoder.decode(V7Record.self, from: data)
                    allRecords.append((scenarioName, record))
                } catch {
                    // Phase 0.1: Show file+line but NOT expected values to avoid leaking
                    decodeFailures.append((scenarioName, idx + 1, "Line \(idx + 1): decode error"))
                }
            }
        }
        
        // Phase 0.1: Fail if any decode errors or count mismatch
        if !decodeFailures.isEmpty {
            print("❌ DECODE FAILURES (\(decodeFailures.count)):")
            for f in decodeFailures {
                print("  \(f.file):\(f.line) - \(f.error)")
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
            
            // Build user context from input (BLIND - no expected values)
            let userProfile = buildUserProfile(from: input.user_profile)
            
            // Phase 0.2: Compute deterministic sessionDate
            let sessionDate = computeSessionDate(from: input, calendar: calendar)
            
            // Phase 0.3: Build history WITH sessions (not just liftStates)
            let history = buildWorkoutHistory(from: input, sessionDate: sessionDate, exerciseCatalog: exerciseCatalog, calendar: calendar)
            
            // Phase 0.4 & 0.5: Build plan with all exercises and config overrides
            let (plan, templateId) = buildTrainingPlan(from: input, exerciseCatalog: exerciseCatalog)
            
            let readiness = computeReadiness(from: input.today_metrics)
            let isPlannedDeload = input.event_flags.planned_deload_week ?? false
            
            // Call engine with ONLY input data - NO expected values leaked
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
            
            // Phase 0.4: Build lift-to-index mapping for expected output to handle accessories
            // We map by lift name, not by index, to avoid ordering issues
            let engineExerciseMap: [String: ExercisePlan] = Dictionary(
                uniqueKeysWithValues: enginePlan.exercises.map { ($0.exercise.id.lowercased(), $0) }
            )
            
            // Score against expected output (post-hoc comparison)
            for (_, expectedRx) in record.expected_output.session_prescription_for_today.enumerated() {
                let liftName = expectedRx.lift.lowercased()
                
                // Only score main lifts (accessories have null weights and are not scored)
                guard mainLifts.contains(liftName), let expectedWeight = expectedRx.prescribed_weight_lb else { continue }
                
                scorecard.mainLiftPrescriptions += 1
                scorecard.decisionTotal += 1
                scorecard.loadTotal += 1
                
                // Update per-category stats
                var catStats = scorecard.perCategory[record.test_category] ?? CategoryStats()
                catStats.tests += 1
                catStats.lifts += 1
                
                var scenarioStats = scorecard.perScenario[scenario] ?? CategoryStats()
                scenarioStats.tests += 1
                scenarioStats.lifts += 1
                
                // Find matching engine exercise by lift name
                let engineExercise = engineExerciseMap[liftName] ?? 
                    enginePlan.exercises.first(where: { $0.exercise.id.lowercased().contains(liftName) })
                
                let predictedWeight = engineExercise?.sets.first?.targetLoad.converted(to: .pounds).value ?? 0
                
                let loadError = abs(predictedWeight - expectedWeight)
                scorecard.loadErrors.append(loadError)
                catStats.loadErrors.append(loadError)
                scenarioStats.loadErrors.append(loadError)
                
                let withinRange: Bool = {
                    if let range = expectedRx.acceptable_range_lb, range.count == 2 {
                        return predictedWeight >= range[0] && predictedWeight <= range[1]
                    }
                    return loadError <= input.equipment_config.load_step_lb
                }()
                
                if withinRange {
                    scorecard.loadWithinRange += 1
                    catStats.loadWithinRange += 1
                    scenarioStats.loadWithinRange += 1
                }
                
                // Decision comparison
                let expectedDecision = normalizeDecision(expectedRx.decision)
                let liftState = history.liftStates[liftName]
                let predictedDecision = inferDecision(
                    exercisePlan: engineExercise,
                    liftState: liftState,
                    predictedWeight: predictedWeight,
                    loadStepLb: input.equipment_config.load_step_lb,
                    isPlannedDeload: isPlannedDeload,
                    isSessionDeload: enginePlan.isDeload
                )
                
                // Confusion matrix
                var row = confusion[expectedDecision, default: [:]]
                row[predictedDecision, default: 0] += 1
                confusion[expectedDecision] = row
                
                if expectedDecision == predictedDecision {
                    scorecard.decisionCorrect += 1
                    catStats.decisionCorrect += 1
                    scenarioStats.decisionCorrect += 1
                } else if mismatchSamples.count < 100 {
                    let dir = engineExercise?.direction?.rawValue ?? "nil"
                    let reason = engineExercise?.directionReason?.rawValue ?? "nil"
                    let daysExposure = input.days_since_lift_exposure[liftName] ?? nil
                    mismatchSamples.append(MismatchSample(
                        testId: record.test_id,
                        category: record.test_category,
                        lift: liftName,
                        expectedDecision: expectedDecision,
                        expectedReasonCode: expectedRx.reason_code,
                        predictedDecision: predictedDecision,
                        engineDirection: dir,
                        engineDirectionReason: reason,
                        loadError: loadError,
                        expectedWeight: expectedWeight,
                        predictedWeight: predictedWeight,
                        readiness: readiness,
                        daysSinceExposure: daysExposure
                    ))
                }
                
                scorecard.perCategory[record.test_category] = catStats
                scorecard.perScenario[scenario] = scenarioStats
            }
            
            // Check assertions if present (Phase 0.4: use lift name matching)
            if let assertions = record.assertions {
                for assertion in assertions {
                    scorecard.assertionsTotal += 1
                    if checkAssertion(assertion, enginePlan: enginePlan, input: input, engineExerciseMap: engineExerciseMap) {
                        scorecard.assertionsPassed += 1
                    }
                }
            }
        }
        
        // Print diagnostics (Phase 0.6: controlled verbosity)
        printDiagnostics(
            scorecard: scorecard,
            confusion: confusion,
            mismatchSamples: mismatchSamples,
            decisionLabels: decisionLabels
        )
        
        // Gate: Phase 0 validation
        XCTAssertEqual(scorecard.totalTests, expectedTotalCases, "Must process all \(expectedTotalCases) test cases")
    }
    
    // MARK: - Phase 0.2: Deterministic Session Date
    
    /// Computes a deterministic sessionDate from the input data.
    /// Uses max(date in recent_lift_history) + days_since_last_session, or base date for cold starts.
    private func computeSessionDate(from input: V7Input, calendar: Calendar) -> Date {
        // Find the most recent date across all lift histories
        var maxHistoryDate: Date? = nil
        
        for (_, entries) in input.recent_lift_history {
            for entry in entries {
                if let entryDate = Self.dateFormatter.date(from: entry.date) {
                    if maxHistoryDate == nil || entryDate > maxHistoryDate! {
                        maxHistoryDate = entryDate
                    }
                }
            }
        }
        
        // If we have history, sessionDate = maxHistoryDate + days_since_last_session
        if let latestHistory = maxHistoryDate {
            let daysSince = input.days_since_last_session ?? 3
            return calendar.date(byAdding: .day, value: daysSince, to: latestHistory) ?? Self.baseDate
        }
        
        // Cold start: use fixed base date
        return Self.baseDate
    }
    
    // MARK: - Helpers
    
    private func buildUserProfile(from profile: V7UserProfile) -> UserProfile {
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
            switch profile.goal.lowercased() {
            case "strength": return [.strength]
            case "hypertrophy": return [.hypertrophy]
            case "strength_hypertrophy": return [.strength, .hypertrophy]
            case "fat_loss_strength_maintenance": return [.strength]
            default: return [.strength, .hypertrophy]
            }
        }()
        
        return UserProfile(
            id: "v7_test_user",
            sex: sex,
            experience: experience,
            goals: goals,
            weeklyFrequency: 3,
            availableEquipment: .commercialGym,
            preferredUnit: .pounds,
            bodyWeight: Load(value: profile.body_weight_lb, unit: .pounds),
            age: profile.age,
            limitations: []
        )
    }
    
    private func buildExerciseCatalog() -> [String: Exercise] {
        var catalog: [String: Exercise] = [:]
        
        // Main lifts
        catalog["squat"] = Exercise(id: "squat", name: "Barbell Back Squat", equipment: .barbell, primaryMuscles: [.quadriceps, .glutes], secondaryMuscles: [.hamstrings, .lowerBack], movementPattern: .squat)
        catalog["bench"] = Exercise(id: "bench", name: "Barbell Bench Press", equipment: .barbell, primaryMuscles: [.chest, .frontDelts, .triceps], movementPattern: .horizontalPush)
        catalog["deadlift"] = Exercise(id: "deadlift", name: "Conventional Deadlift", equipment: .barbell, primaryMuscles: [.glutes, .hamstrings, .lowerBack], secondaryMuscles: [.quadriceps, .traps], movementPattern: .hipHinge)
        catalog["ohp"] = Exercise(id: "ohp", name: "Overhead Press", equipment: .barbell, primaryMuscles: [.frontDelts, .triceps], secondaryMuscles: [.chest], movementPattern: .verticalPush)
        
        // Variations
        catalog["front_squat"] = Exercise(id: "front_squat", name: "Front Squat", equipment: .barbell, primaryMuscles: [.quadriceps, .glutes], movementPattern: .squat)
        catalog["pause_bench"] = Exercise(id: "pause_bench", name: "Pause Bench Press", equipment: .barbell, primaryMuscles: [.chest, .frontDelts, .triceps], movementPattern: .horizontalPush)
        catalog["close_grip_bench"] = Exercise(id: "close_grip_bench", name: "Close-Grip Bench Press", equipment: .barbell, primaryMuscles: [.chest, .triceps], movementPattern: .horizontalPush)
        catalog["sumo_deadlift"] = Exercise(id: "sumo_deadlift", name: "Sumo Deadlift", equipment: .barbell, primaryMuscles: [.glutes, .hamstrings, .quadriceps], movementPattern: .hipHinge)
        catalog["trap_bar_deadlift"] = Exercise(id: "trap_bar_deadlift", name: "Trap Bar Deadlift", equipment: .trapBar, primaryMuscles: [.glutes, .hamstrings, .quadriceps], movementPattern: .hipHinge)
        
        // Substitutions
        catalog["leg_press"] = Exercise(id: "leg_press", name: "Leg Press", equipment: .machine, primaryMuscles: [.quadriceps, .glutes], movementPattern: .squat)
        catalog["hack_squat"] = Exercise(id: "hack_squat", name: "Hack Squat", equipment: .machine, primaryMuscles: [.quadriceps, .glutes], movementPattern: .squat)
        
        // Accessories (Phase 0.4)
        catalog["row"] = Exercise(id: "row", name: "Barbell Row", equipment: .barbell, primaryMuscles: [.lats, .rhomboids], secondaryMuscles: [.biceps], movementPattern: .horizontalPull)
        catalog["rdl"] = Exercise(id: "rdl", name: "Romanian Deadlift", equipment: .barbell, primaryMuscles: [.hamstrings, .glutes], movementPattern: .hipHinge)
        catalog["lat_pulldown"] = Exercise(id: "lat_pulldown", name: "Lat Pulldown", equipment: .cable, primaryMuscles: [.lats, .biceps], movementPattern: .verticalPull)
        catalog["incline_db"] = Exercise(id: "incline_db", name: "Incline Dumbbell Press", equipment: .dumbbell, primaryMuscles: [.chest, .frontDelts], movementPattern: .horizontalPush)
        catalog["dips"] = Exercise(id: "dips", name: "Dips", equipment: .bodyweight, primaryMuscles: [.chest, .triceps], movementPattern: .horizontalPush)
        catalog["cable_row"] = Exercise(id: "cable_row", name: "Cable Row", equipment: .cable, primaryMuscles: [.lats, .rhomboids], movementPattern: .horizontalPull)
        catalog["face_pull"] = Exercise(id: "face_pull", name: "Face Pull", equipment: .cable, primaryMuscles: [.rearDelts, .rhomboids], movementPattern: .horizontalPull)
        catalog["curl"] = Exercise(id: "curl", name: "Bicep Curl", equipment: .dumbbell, primaryMuscles: [.biceps], movementPattern: .elbowFlexion)
        catalog["tricep_pushdown"] = Exercise(id: "tricep_pushdown", name: "Tricep Pushdown", equipment: .cable, primaryMuscles: [.triceps], movementPattern: .elbowExtension)
        
        return catalog
    }
    
    // Phase 0.4: Fallback exercise creation for unknown lifts
    private func makeExercise(id: String) -> Exercise {
        let lower = id.lowercased()
        
        // Infer movement pattern from ID
        let pattern: MovementPattern = {
            if lower.contains("squat") { return .squat }
            if lower.contains("deadlift") || lower.contains("rdl") || lower.contains("hinge") { return .hipHinge }
            if lower.contains("bench") || lower.contains("press") && !lower.contains("leg") { return .horizontalPush }
            if lower.contains("ohp") || lower.contains("overhead") || lower.contains("shoulder") { return .verticalPush }
            if lower.contains("row") || lower.contains("pull") && lower.contains("horizontal") { return .horizontalPull }
            if lower.contains("pulldown") || lower.contains("pullup") || lower.contains("chin") { return .verticalPull }
            if lower.contains("curl") { return .elbowFlexion }
            if lower.contains("extension") || lower.contains("tricep") { return .elbowExtension }
            if lower.contains("fly") { return .horizontalPush }
            return .unknown // Default for accessories
        }()
        
        // Infer equipment
        let equipment: Equipment = {
            if lower.contains("db") || lower.contains("dumbbell") { return .dumbbell }
            if lower.contains("cable") { return .cable }
            if lower.contains("machine") || lower.contains("leg_press") || lower.contains("hack") { return .machine }
            if lower.contains("body") || lower.contains("dip") || lower.contains("pullup") { return .bodyweight }
            return .barbell
        }()
        
        // Infer primary muscles
        let primaryMuscles: [MuscleGroup] = {
            if pattern == .squat { return [.quadriceps, .glutes] }
            if pattern == .hipHinge { return [.hamstrings, .glutes] }
            if pattern == .horizontalPush { return [.chest, .triceps] }
            if pattern == .verticalPush { return [.frontDelts, .triceps] }
            if pattern == .horizontalPull { return [.lats, .rhomboids] }
            if pattern == .verticalPull { return [.lats, .biceps] }
            if pattern == .elbowFlexion { return [.biceps] }
            if pattern == .elbowExtension { return [.triceps] }
            return [.chest] // Default
        }()
        
        return Exercise(
            id: id,
            name: id.replacingOccurrences(of: "_", with: " ").capitalized,
            equipment: equipment,
            primaryMuscles: primaryMuscles,
            movementPattern: pattern
        )
    }
    
    // MARK: - Phase 0.3: Build WorkoutHistory WITH sessions
    
    private func buildWorkoutHistory(
        from input: V7Input,
        sessionDate: Date,
        exerciseCatalog: [String: Exercise],
        calendar: Calendar
    ) -> WorkoutHistory {
        var liftStates: [String: LiftState] = [:]
        var sessionsByDate: [String: [(lift: String, entry: V7HistoryEntry)]] = [:]
        
        // Build lift states from provided lift_state if available
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
        
        // Process recent_lift_history: build lift states AND group by date for sessions
        for (liftName, entries) in input.recent_lift_history {
            guard !entries.isEmpty else { continue }
            let liftKey = liftName.lowercased()
            
            var state = liftStates[liftKey] ?? LiftState(exerciseId: liftKey)
            var e1rmHistory: [E1RMSample] = []
            
            let sortedEntries = entries.sorted { $0.date < $1.date }
            
            for entry in sortedEntries {
                guard let entryDate = Self.dateFormatter.date(from: entry.date) else { continue }
                
                // Update lift state
                if state.lastWorkingWeight.value == 0 {
                    state.lastWorkingWeight = Load(value: entry.weight_lb, unit: .pounds)
                } else if entry.date >= (sortedEntries.last?.date ?? "") {
                    state.lastWorkingWeight = Load(value: entry.weight_lb, unit: .pounds)
                }
                state.lastSessionDate = entryDate
                
                let e1rm = E1RMCalculator.brzycki(weight: entry.weight_lb, reps: entry.reps)
                e1rmHistory.append(E1RMSample(date: entryDate, value: e1rm))
                
                // Phase 0.3: Group entries by date for session construction
                sessionsByDate[entry.date, default: []].append((lift: liftKey, entry: entry))
            }
            
            if !e1rmHistory.isEmpty && state.rollingE1RM == 0 {
                state.e1rmHistory = Array(e1rmHistory.suffix(10))
                state.rollingE1RM = e1rmHistory.last!.value
                state.trend = TrendCalculator.compute(from: state.e1rmHistory)
            }
            
            liftStates[liftKey] = state
        }
        
        // Phase 0.2: Set lastSessionDate from days_since_lift_exposure
        for (liftName, daysSince) in input.days_since_lift_exposure {
            let liftKey = liftName.lowercased()
            if let days = daysSince, days >= 0 {
                let lastDate = calendar.date(byAdding: .day, value: -days, to: sessionDate) ?? sessionDate
                if var state = liftStates[liftKey] {
                    // Only update if not already set or if this is more recent
                    if state.lastSessionDate == nil || lastDate > state.lastSessionDate! {
                        state.lastSessionDate = lastDate
                        liftStates[liftKey] = state
                    }
                } else {
                    // Create minimal state with just the date
                    var newState = LiftState(exerciseId: liftKey)
                    newState.lastSessionDate = lastDate
                    liftStates[liftKey] = newState
                }
            }
        }
        
        // Phase 0.3: Build CompletedSession objects from grouped history
        var completedSessions: [CompletedSession] = []
        
        for (dateStr, liftEntries) in sessionsByDate.sorted(by: { $0.key < $1.key }) {
            guard let sessionDateValue = Self.dateFormatter.date(from: dateStr) else { continue }
            
            var exerciseResults: [ExerciseSessionResult] = []
            
            for (liftKey, entry) in liftEntries {
                let exercise = exerciseCatalog[liftKey] ?? makeExercise(id: liftKey)
                
                // Find set count from template if available
                let templateSets = input.today_session_template.first(where: { $0.lift.lowercased() == liftKey })?.sets ?? 3
                
                // Create set results - replicate top set for simplicity
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
                
                // Build a minimal prescription for this exercise
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
                    name: "V7 Historical Session",
                    exerciseResults: exerciseResults,
                    startedAt: sessionDateValue,
                    readinessScore: 70
                )
                completedSessions.append(session)
            }
        }
        
        return WorkoutHistory(sessions: completedSessions, liftStates: liftStates)
    }
    
    // MARK: - Phase 0.4 & 0.5: Build Training Plan with all exercises and config overrides
    
    private func buildTrainingPlan(from input: V7Input, exerciseCatalog: [String: Exercise]) -> (TrainingPlan, UUID) {
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
        
        // Phase 0.4: Include ALL template exercises (no filtering)
        let templateExercises = input.today_session_template.map { te -> TemplateExercise in
            let liftId = te.lift.lowercased()
            let exercise = exerciseCatalog[liftId] ?? exerciseCatalog[liftId.replacingOccurrences(of: "_", with: "")] ?? makeExercise(id: liftId)
            
            // Infer targetRIR from reps
            let targetRIR = inferRIRFromReps(te.reps)
            
            // Phase 0.5: Determine load strategy based on config_overrides
            let loadStrategy: LoadStrategy = {
                if let policy = input.config_overrides?.progression_policy?.lowercased() {
                    if policy == "percentage_e1rm" || policy == "percent_e1rm" {
                        // Percentage-based for intermediate+
                        if experience != .beginner && exercise.movementPattern.isCompound {
                            return .percentageE1RM
                        }
                    }
                }
                // Default logic: use %E1RM for heavy compound work for intermediate+
                let isCompound = exercise.movementPattern.isCompound
                let isIntermediatePlus = experience != .beginner
                let isHeavyWork = te.reps <= 5
                return (isCompound && isIntermediatePlus && isHeavyWork) ? .percentageE1RM : .absolute
            }()
            
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
            name: input.user_profile.program,
            exercises: templateExercises
        )
        
        // Phase 0.5: Apply equipment config to rounding policy
        let roundingPolicy = LoadRoundingPolicy(increment: increment, unit: .pounds, mode: .nearest)
        
        var templates: [WorkoutTemplateId: WorkoutTemplate] = [:]
        templates[templateId] = template
        
        // Phase 0.5: Build progression policies based on config_overrides
        var progressionPolicies: [String: ProgressionPolicyType] = [:]
        
        if let policyStr = input.config_overrides?.progression_policy?.lowercased() {
            for te in input.today_session_template {
                let liftId = te.lift.lowercased()
                let exercise = exerciseCatalog[liftId] ?? makeExercise(id: liftId)
                
                switch policyStr {
                case "linear":
                    // Linear progression for beginners/novices
                    let lpConfig: LinearProgressionConfig = exercise.movementPattern == .squat || exercise.movementPattern == .hipHinge 
                        ? .lowerBody 
                        : .upperBody
                    progressionPolicies[liftId] = .linearProgression(config: lpConfig)
                    
                case "double_progression":
                    progressionPolicies[liftId] = .doubleProgression(config: .default)
                    
                case "percentage_e1rm", "percent_e1rm":
                    // RIR autoregulation with percentage basis
                    progressionPolicies[liftId] = .rirAutoregulation(config: .default)
                    
                default:
                    // Use default policy selection
                    break
                }
            }
        }
        
        // Phase 0.5: Apply deload config
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
    
    private func computeReadiness(from metrics: V7TodayMetrics) -> Int {
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
    
    // Phase 0.4: Updated assertion checking with lift name mapping
    private func checkAssertion(
        _ assertion: V7Assertion,
        enginePlan: SessionPlan,
        input: V7Input,
        engineExerciseMap: [String: ExercisePlan]
    ) -> Bool {
        // Parse field path like "session_prescription_for_today[0].decision"
        let parts = assertion.field.components(separatedBy: ".")
        guard parts.count >= 2 else { return false }
        
        // Extract index from first part
        let firstPart = parts[0]
        guard let indexStart = firstPart.firstIndex(of: "["),
              let indexEnd = firstPart.firstIndex(of: "]"),
              let index = Int(firstPart[firstPart.index(after: indexStart)..<indexEnd]) else {
            return false
        }
        
        // Get the lift name from expected output at this index
        guard index < input.today_session_template.count else { return false }
        let liftName = input.today_session_template[index].lift.lowercased()
        
        // Find matching engine exercise by lift name (Phase 0.4: avoid index mismatch)
        guard let exercise = engineExerciseMap[liftName] ?? 
            enginePlan.exercises.first(where: { $0.exercise.id.lowercased().contains(liftName) }) else {
            return false
        }
        
        let fieldName = parts[1]
        
        switch fieldName {
        case "decision":
            if let expected = assertion.expected {
                let predictedDecision = inferDecision(
                    exercisePlan: exercise,
                    liftState: nil,
                    predictedWeight: exercise.sets.first?.targetLoad.converted(to: .pounds).value ?? 0,
                    loadStepLb: input.equipment_config.load_step_lb,
                    isPlannedDeload: input.event_flags.planned_deload_week ?? false,
                    isSessionDeload: enginePlan.isDeload
                )
                if case .string(let expectedStr) = expected {
                    return normalizeDecision(predictedDecision) == normalizeDecision(expectedStr)
                }
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
    
    // MARK: - Phase 0.6: Controlled Diagnostics Output
    
    private func printDiagnostics(
        scorecard: Scorecard,
        confusion: [String: [String: Int]],
        mismatchSamples: [MismatchSample],
        decisionLabels: [String]
    ) {
        let isVerbose = ProcessInfo.processInfo.environment["V7_VERBOSE"] == "1"
        let now = ISO8601DateFormatter().string(from: Date())
        var logLines: [String] = []
        
        logLines.append("=" * 80)
        logLines.append("V7 FULL E2E REPLAY DIAGNOSTICS @ \(now)")
        logLines.append("=" * 80)
        logLines.append("")
        
        let loadPct = scorecard.loadTotal > 0 ? Double(scorecard.loadWithinRange) / Double(scorecard.loadTotal) * 100 : 0
        let decPct = scorecard.decisionTotal > 0 ? Double(scorecard.decisionCorrect) / Double(scorecard.decisionTotal) * 100 : 0
        let mae = scorecard.loadErrors.isEmpty ? 0 : scorecard.loadErrors.reduce(0, +) / Double(scorecard.loadErrors.count)
        let assertPct = scorecard.assertionsTotal > 0 ? Double(scorecard.assertionsPassed) / Double(scorecard.assertionsTotal) * 100 : 0
        
        logLines.append("OVERALL SUMMARY:")
        logLines.append("  Total test cases: \(scorecard.totalTests)")
        logLines.append("  Main lift prescriptions scored: \(scorecard.mainLiftPrescriptions)")
        logLines.append("")
        logLines.append("  📊 Load Agreement: \(scorecard.loadWithinRange)/\(scorecard.loadTotal) = \(String(format: "%.1f", loadPct))%")
        logLines.append("  🎯 Decision Agreement: \(scorecard.decisionCorrect)/\(scorecard.decisionTotal) = \(String(format: "%.1f", decPct))%")
        logLines.append("  📏 Mean Absolute Error: \(String(format: "%.2f", mae)) lb")
        logLines.append("  ✅ Assertions Passed: \(scorecard.assertionsPassed)/\(scorecard.assertionsTotal) = \(String(format: "%.1f", assertPct))%")
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
        
        // Phase 0.6: Mismatch samples only in verbose mode (without expected weights to avoid leaking)
        if isVerbose {
            logLines.append("-" * 80)
            logLines.append("SAMPLE MISMATCHES (up to 100) [V7_VERBOSE=1]:")
            for sample in mismatchSamples.prefix(100) {
                logLines.append("  [\(sample.testId)] \(sample.lift)")
                logLines.append("    exp=\(sample.expectedDecision)(\(sample.expectedReasonCode)) pred=\(sample.predictedDecision)")
                logLines.append("    engine: dir=\(sample.engineDirection) reason=\(sample.engineDirectionReason)")
                logLines.append("    pred_weight=\(String(format: "%.1f", sample.predictedWeight))lb err=\(String(format: "%.1f", sample.loadError))lb rdns=\(sample.readiness) days=\(sample.daysSinceExposure.map { String($0) } ?? "nil")")
            }
        } else {
            logLines.append("-" * 80)
            logLines.append("MISMATCH SAMPLES: \(mismatchSamples.count) total (set V7_VERBOSE=1 for details)")
        }
        
        let logText = logLines.joined(separator: "\n")
        print("\n" + logText)
        
        // Save to file
        let logURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("v7_replay_diagnostics.log")
        do {
            try logText.write(to: logURL, atomically: true, encoding: .utf8)
            print("\n  💾 Saved detailed v7 diagnostics to: \(logURL.path)")
        } catch {
            print("\n  ⚠️ Failed to write v7 diagnostics log: \(error)")
        }
        
        // Print final scorecard
        print("""
        
        ================================================================================
        🧪 workout_engine_testset_v7 FULL E2E SCORECARD:
        ================================================================================
          Total test cases: \(scorecard.totalTests)
          Main-lift prescriptions scored: \(scorecard.mainLiftPrescriptions)
          
          📊 Load Agreement:
            Within acceptable range: \(scorecard.loadWithinRange)/\(scorecard.loadTotal) = \(String(format: "%.1f", loadPct))%
            Mean Absolute Error: \(String(format: "%.2f", mae)) lb
          
          🎯 Decision Agreement:
            Overall: \(scorecard.decisionCorrect)/\(scorecard.decisionTotal) = \(String(format: "%.1f", decPct))%
          
          ✅ Assertions:
            Passed: \(scorecard.assertionsPassed)/\(scorecard.assertionsTotal) = \(String(format: "%.1f", assertPct))%
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
