// WorkoutEngineTestsetV4ReplayTests.swift
// Full E2E replay test for workout_engine_testset_v4_science dataset.

import XCTest
@testable import TrainingEngine
import Foundation

final class WorkoutEngineTestsetV4ReplayTests: XCTestCase {
    
    // MARK: - V4 Record Structures
    
    struct V4Record: Codable {
        let dataset_version: String
        let user_id: String
        let date: String
        let session_type: String
        let input: V4Input
        let expected: V4Expected
    }
    
    struct V4Input: Codable {
        let user_profile: V4UserProfile
        let equipment: V4Equipment
        let today_metrics: V4TodayMetrics
        let today_session_template: [V4TemplateExercise]
        let recent_lift_history: [String: [V4HistoryEntry]]
        let recent_exercise_history: [String: [V4ExerciseHistoryEntry]]?
        let days_since_last_session: Int?
        let days_since_lift_exposure: [String: Int?]
        let event_flags: V4EventFlags
        let planned_deload_week: Bool
    }
    
    struct V4UserProfile: Codable {
        let sex: String
        let age: Int
        let height_cm: Int
        let experience_level: String
        let program: String
        let goal: String
    }
    
    struct V4Equipment: Codable {
        let units: String
        let bar_weight_lb: Double
        let load_step_lb: Double
    }
    
    struct V4TodayMetrics: Codable {
        let body_weight_lb: Double
        let sleep_hours: Double?
        let hrv_ms: Int?
        let resting_hr_bpm: Int?
        let soreness_1_to_10: Int?
        let stress_1_to_10: Int?
        let steps: Int?
        let calories_est: Int?
    }
    
    struct V4TemplateExercise: Codable {
        let lift: String
        let sets: Int
        let reps: Int
        let unit: String?
    }
    
    struct V4HistoryEntry: Codable {
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
    
    struct V4ExerciseHistoryEntry: Codable {
        let date: String
        let session_type: String
        let base_lift: String?
        let weight_lb: Double?
        let target_reps: Int
        let top_set_reps: Int
        let top_rpe: Double?
        let outcome: String
        let decision: String
        let reason_code: String
    }
    
    enum V4StringOrBool: Codable, Sendable, Hashable {
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
            throw DecodingError.typeMismatch(
                V4StringOrBool.self,
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Expected Bool or String"
                )
            )
        }
        
        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case .bool(let b): try container.encode(b)
            case .string(let s): try container.encode(s)
            }
        }
    }
    
    struct V4EventFlags: Codable {
        let missed_session: Bool
        let variation_overrides: [String: String]
        let substitutions: [String: String]
        let injury_flags: [String: V4StringOrBool]
    }
    
    struct V4Expected: Codable {
        let session_prescription_for_today: [V4Prescription]?
        let actual_logged_performance: [V4Performance]?
        let expected_next_session_prescription: V4NextPrescription?
        let scoring: V4Scoring?
    }
    
    struct V4UpdatesStateFor: Codable {
        let type: String  // "lift" or "exercise"
        let name: String
    }
    
    struct V4Prescription: Codable {
        let lift: String
        let performed_exercise: String?
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
        let updates_state_for: V4UpdatesStateFor?
        let coefficient_applied: Double?
    }
    
    struct V4Performance: Codable {
        let exercise: String
        let performed_sets: [V4PerformedSet]
        let top_set_rpe: Double?
        let top_set_reps: Int
        let outcome: String
    }
    
    struct V4PerformedSet: Codable {
        let set: Int
        let weight_lb: Double?
        let reps: Int
        let rpe: Double?
    }
    
    struct V4NextPrescription: Codable {
        let date: String
        let session_type: String
        let readiness_assumption_for_label: String
        let prescriptions: [V4Prescription]
    }
    
    struct V4Scoring: Codable {
        let main_lifts: [String]
        let strict_fields: [String]
        let load_agreement: String?
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
        
        var coldStartCases = 0
        var coldStartMAE: [Double] = []
        var microloadCases = 0
        var microloadCorrect = 0
        
        var perUser: [String: UserScorecard] = [:]
    }
    
    struct UserScorecard {
        var sessions = 0
        var mainLifts = 0
        var loadWithinRange = 0
        var decisionCorrect = 0
        var loadErrors: [Double] = []
    }
    
    // MARK: - Diagnostics buckets (for debug output only)
    
    struct BucketStats {
        var count = 0
        var decisionCorrect = 0
        
        var loadTotal = 0
        var loadWithinRange = 0
        var loadErrors: [Double] = []
        
        var expectedCounts: [String: Int] = [:]
        var predictedCounts: [String: Int] = [:]
        var confusion: [String: [String: Int]] = [:]
        
        mutating func record(
            expected: String,
            predicted: String,
            loadError: Double,
            withinRange: Bool
        ) {
            count += 1
            if expected == predicted { decisionCorrect += 1 }
            
            loadTotal += 1
            if withinRange { loadWithinRange += 1 }
            loadErrors.append(loadError)
            
            expectedCounts[expected, default: 0] += 1
            predictedCounts[predicted, default: 0] += 1
            
            var row = confusion[expected, default: [:]]
            row[predicted, default: 0] += 1
            confusion[expected] = row
        }
        
        var decisionAccuracy: Double {
            guard count > 0 else { return 0 }
            return Double(decisionCorrect) / Double(count)
        }
        
        var loadAgreement: Double {
            guard loadTotal > 0 else { return 0 }
            return Double(loadWithinRange) / Double(loadTotal)
        }
        
        var mae: Double {
            guard !loadErrors.isEmpty else { return 0 }
            return loadErrors.reduce(0, +) / Double(loadErrors.count)
        }
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
    
    func testWorkoutEngineTestsetV4_FullE2EReplay() throws {
        let jsonlPath = "/Users/rahulvijayan/Atlas 3/workout_engine_testset_v4_science/workout_engine_testset_v4.jsonl"
        let jsonlContent = try String(contentsOfFile: jsonlPath, encoding: .utf8)
        let lines = jsonlContent.components(separatedBy: .newlines).filter { !$0.isEmpty }
        
        let decoder = JSONDecoder()
        var records: [V4Record] = []
        var decodeFailures: [(index: Int, message: String)] = []
        for (idx, line) in lines.enumerated() {
            guard let data = line.data(using: .utf8) else { continue }
            do {
                let record = try decoder.decode(V4Record.self, from: data)
                records.append(record)
            } catch {
                if decodeFailures.count < 5 {
                    decodeFailures.append((idx, "\(error) | prefix=\(line.prefix(180))"))
                }
            }
        }
        
        XCTAssertTrue(decodeFailures.isEmpty, "Decode failures (sample): \(decodeFailures)")
        XCTAssertEqual(records.count, lines.count, "Should decode every v4 JSONL line")
        
        XCTAssertFalse(records.isEmpty, "Should load v4 records")
        
        var scorecard = Scorecard()
        var plannedDeloadSessions = 0
        var engineDeloadSessions = 0
        var engineDeloadSessionsNotPlanned = 0
        var directionCounts: [ProgressionDirection: Int] = [:]
        var missingDirectionCount = 0
        var deloadReasonCounts: [DirectionReason: Int] = [:]
        var decreaseReasonCounts: [DirectionReason: Int] = [:]
        var holdReasonCounts: [DirectionReason: Int] = [:]
        var increaseReasonCounts: [DirectionReason: Int] = [:]
        var resetReasonCounts: [DirectionReason: Int] = [:]
        var mismatchSamples: [String] = []
        
        // ----------------------------
        // Deeper diagnostics (bounded)
        // ----------------------------
        let decisionLabels: [String] = ["deload", "hold", "increase", "decrease_small", "estimate", "prescribe"]
        
        var confusion: [String: [String: Int]] = [:]
        var mismatchPairCounts: [String: Int] = [:]                         // "exp->pred"
        var mismatchPairReasonCounts: [String: [String: Int]] = [:]          // "exp->pred" -> reason_code -> count
        var mismatchPairSamples: [String: [String]] = [:]                    // "exp->pred" -> sample lines (bounded)
        
        var byLift: [String: BucketStats] = [:]
        var byReadinessFlag: [String: BucketStats] = [:]                     // expectedRx.readiness_flag
        var byLoadStepBucket: [String: BucketStats] = [:]                    // <=1.25, <=2.5, >2.5
        var byUser: [String: BucketStats] = [:]
        
        var missingEngineExerciseMatch = 0
        var missingExpectedReadinessFlag = 0
        
        func bucketKeyForLoadStep(_ stepLb: Double) -> String {
            if stepLb <= 1.25 { return "step<=1.25" }
            if stepLb <= 2.5 { return "step<=2.5" }
            return "step>2.5"
        }
        
        func incMatrix(_ matrix: inout [String: [String: Int]], expected: String, predicted: String) {
            var row = matrix[expected, default: [:]]
            row[predicted, default: 0] += 1
            matrix[expected] = row
        }
        
        func addMismatchSample(pairKey: String, line: String, maxPerPair: Int = 4) {
            var arr = mismatchPairSamples[pairKey, default: []]
            if arr.count < maxPerPair {
                arr.append(line)
                mismatchPairSamples[pairKey] = arr
            }
        }
        
        // Group by user
        var recordsByUser: [String: [V4Record]] = [:]
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
                // but do NOT leak expected decisions/reason_codes to the engine
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
                
                if record.input.planned_deload_week { plannedDeloadSessions += 1 }
                if enginePlan.isDeload {
                    engineDeloadSessions += 1
                    if !record.input.planned_deload_week { engineDeloadSessionsNotPlanned += 1 }
                }
                
                for expectedRx in record.expected.session_prescription_for_today ?? [] {
                    let liftName = expectedRx.lift.lowercased()
                    guard mainLifts.contains(liftName) else { continue }
                    guard expectedRx.decision != "accessory" && expectedRx.decision != "accessory_unlabeled" else { continue }
                    
                    scorecard.mainLiftPrescriptions += 1
                    userScorecard.mainLifts += 1
                    scorecard.decisionTotal += 1
                    
                    // V4: use performed_exercise if available
                    let performedExercise = expectedRx.performed_exercise?.lowercased() ?? expectedRx.substituted_to?.lowercased() ?? liftName
                    
                    let engineExercise = findMatchingExercise(
                        liftName: liftName,
                        performedExercise: performedExercise,
                        variation: expectedRx.lift_variation,
                        substitutedTo: expectedRx.substituted_to,
                        in: enginePlan
                    )
                    if engineExercise == nil { missingEngineExerciseMatch += 1 }
                    
                    let expectedWeight = expectedRx.prescribed_weight_lb ?? 0
                    let predictedWeight = engineExercise?.sets.first?.targetLoad.converted(to: .pounds).value ?? 0
                    
                    let loadError = abs(predictedWeight - expectedWeight)
                    scorecard.loadErrors.append(loadError)
                    userScorecard.loadErrors.append(loadError)
                    
                    // Track cold starts
                    if expectedRx.reason_code.contains("cold_start") || expectedRx.decision == "estimate" {
                        scorecard.coldStartCases += 1
                        scorecard.coldStartMAE.append(loadError)
                    }
                    
                    // Track microloading (1.25 lb increments)
                    if record.input.equipment.load_step_lb <= 1.25 {
                        scorecard.microloadCases += 1
                    }
                    
                    let withinRange: Bool = {
                        if let range = expectedRx.acceptable_range_lb, range.count == 2 {
                            return predictedWeight >= range[0] && predictedWeight <= range[1]
                        }
                        // Fallback tolerance (only used when dataset didn't provide acceptable_range_lb)
                        return loadError <= 2.5
                    }()
                    if withinRange {
                        scorecard.loadWithinRange += 1
                        userScorecard.loadWithinRange += 1
                        if record.input.equipment.load_step_lb <= 1.25 {
                            scorecard.microloadCorrect += 1
                        }
                    }
                    scorecard.loadTotal += 1
                    
                    let expectedDecision = normalizeDecision(expectedRx.decision)
                    
                    // V4: Use updates_state_for to determine the correct state key
                    let stateKey: String = {
                        if let updates = expectedRx.updates_state_for {
                            return updates.name.lowercased()
                        }
                        return performedExercise
                    }()
                    
                    let stateKeyResolution = LiftFamilyResolver.resolveStateKeys(fromId: stateKey)
                    let baselineState = userContext.history.liftStates[stateKeyResolution.updateStateKey]
                        ?? userContext.history.liftStates[stateKeyResolution.referenceStateKey]
                        ?? userContext.history.liftStates[stateKey]
                    let baselineCoefficient: Double = (baselineState?.exerciseId == stateKeyResolution.updateStateKey) ? 1.0 : stateKeyResolution.coefficient
                    
                    if let dir = engineExercise?.direction {
                        directionCounts[dir, default: 0] += 1
                    } else {
                        missingDirectionCount += 1
                    }
                    if let dir = engineExercise?.direction, let reason = engineExercise?.directionReason {
                        switch dir {
                        case .deload: deloadReasonCounts[reason, default: 0] += 1
                        case .decreaseSlightly: decreaseReasonCounts[reason, default: 0] += 1
                        case .hold: holdReasonCounts[reason, default: 0] += 1
                        case .increase: increaseReasonCounts[reason, default: 0] += 1
                        case .resetAfterBreak: resetReasonCounts[reason, default: 0] += 1
                        }
                    }
                    
                    let predictedDecision = inferDecision(
                        plan: enginePlan,
                        exercisePlan: engineExercise,
                        liftState: baselineState,
                        baselineCoefficient: baselineCoefficient,
                        predictedWeight: predictedWeight,
                        loadStepLb: record.input.equipment.load_step_lb,
                        isPlannedDeload: record.input.planned_deload_week
                    )
                    
                    trackDecisions(expected: expectedDecision, predicted: predictedDecision, scorecard: &scorecard)
                    
                    // ----------------------------
                    // Diagnostics capture
                    // ----------------------------
                    incMatrix(&confusion, expected: expectedDecision, predicted: predictedDecision)
                    
                    let userKey = userId
                    let liftKey = liftName
                    let readinessFlag = expectedRx.readiness_flag ?? ""
                    if readinessFlag.isEmpty { missingExpectedReadinessFlag += 1 }
                    let loadStepBucket = bucketKeyForLoadStep(record.input.equipment.load_step_lb)
                    
                    byUser[userKey, default: BucketStats()].record(
                        expected: expectedDecision,
                        predicted: predictedDecision,
                        loadError: loadError,
                        withinRange: withinRange
                    )
                    byLift[liftKey, default: BucketStats()].record(
                        expected: expectedDecision,
                        predicted: predictedDecision,
                        loadError: loadError,
                        withinRange: withinRange
                    )
                    byLoadStepBucket[loadStepBucket, default: BucketStats()].record(
                        expected: expectedDecision,
                        predicted: predictedDecision,
                        loadError: loadError,
                        withinRange: withinRange
                    )
                    if !readinessFlag.isEmpty {
                        byReadinessFlag[readinessFlag, default: BucketStats()].record(
                            expected: expectedDecision,
                            predicted: predictedDecision,
                            loadError: loadError,
                            withinRange: withinRange
                        )
                    }
                    
                    if expectedDecision != predictedDecision {
                        let pairKey = "\(expectedDecision)->\(predictedDecision)"
                        mismatchPairCounts[pairKey, default: 0] += 1
                        let rc = expectedRx.reason_code
                        var rcCounts = mismatchPairReasonCounts[pairKey, default: [:]]
                        rcCounts[rc, default: 0] += 1
                        mismatchPairReasonCounts[pairKey] = rcCounts
                        
                        // Include richer context for *bounded* mismatch samples
                        let dir = engineExercise?.direction?.rawValue ?? "nil"
                        let dirReason = engineExercise?.directionReason?.rawValue ?? "nil"
                        let adj = engineExercise?.recommendedAdjustmentKind?.rawValue ?? "nil"
                        let step = record.input.equipment.load_step_lb
                        let rf = expectedRx.readiness_flag ?? "nil"
                        let rangeStr: String = {
                            if let r = expectedRx.acceptable_range_lb, r.count == 2 {
                                return "[\(String(format: "%.2f", r[0]))..\(String(format: "%.2f", r[1]))]"
                            }
                            return "n/a"
                        }()
                        let baselineStr: String = {
                            guard let s = baselineState else { return "nil" }
                            let w = s.lastWorkingWeight.converted(to: .pounds).value
                            let e = s.rollingE1RM
                            let fs = s.failStreak
                            let hs = s.highRpeStreak
                            let ss = s.successStreak
                            let last = s.lastSessionDate.map { dateFormatter.string(from: $0) } ?? "nil"
                            return "w=\(String(format: "%.2f", w)) e1rm=\(String(format: "%.1f", e)) fail=\(fs) grinder=\(hs) streak=\(ss) last=\(last)"
                        }()
                        // NOTE: Removed wExp and range from sample to prevent answer leakage
                        // Use error bucket instead of raw expected weight
                        let errBucket: String = {
                            if loadError <= step { return "err<=step" }
                            if loadError <= 2 * step { return "err<=2step" }
                            return "err>2step"
                        }()
                        let sample = "\(userId) \(record.date) \(record.session_type) lift=\(liftName) performed=\(performedExercise) rf=\(rf) ready=\(readiness) step=\(String(format: "%.2f", step)) exp=\(expectedDecision)(\(expectedRx.reason_code)) pred=\(predictedDecision) \(errBucket) dir=\(dir) dirReason=\(dirReason) adj=\(adj) baseState{\(baselineStr)}"
                        addMismatchSample(pairKey: pairKey, line: sample)
                    }
                    
                    if expectedDecision == predictedDecision {
                        scorecard.decisionCorrect += 1
                        userScorecard.decisionCorrect += 1
                    } else if mismatchSamples.count < 12 {
                        let dir = engineExercise?.direction?.rawValue ?? "nil"
                        let reason = engineExercise?.directionReason?.rawValue ?? "nil"
                        let adj = engineExercise?.recommendedAdjustmentKind?.rawValue ?? "nil"
                        // NOTE: Removed wExp/wPred from sample to prevent answer leakage
                        // Use error bucket instead
                        let step = record.input.equipment.load_step_lb
                        let errBucket: String = {
                            if loadError <= step { return "err<=step" }
                            if loadError <= 2 * step { return "err<=2step" }
                            return "err>2step"
                        }()
                        mismatchSamples.append(
                            "\(userId) \(record.date) \(record.session_type) lift=\(liftName) performed=\(performedExercise) exp=\(expectedDecision) pred=\(predictedDecision) \(errBucket) dir=\(dir) reason=\(reason) adj=\(adj)"
                        )
                    }
                }
                
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
        
        let directionSummary = directionCounts
            .map { "\($0.key.rawValue)=\($0.value)" }
            .sorted()
            .joined(separator: ", ")
        let deloadReasonSummary = deloadReasonCounts
            .sorted(by: { $0.value > $1.value })
            .prefix(8)
            .map { "\($0.key.rawValue)=\($0.value)" }
            .joined(separator: ", ")
        let decreaseReasonSummary = decreaseReasonCounts
            .sorted(by: { $0.value > $1.value })
            .prefix(8)
            .map { "\($0.key.rawValue)=\($0.value)" }
            .joined(separator: ", ")
        let holdReasonSummary = holdReasonCounts
            .sorted(by: { $0.value > $1.value })
            .prefix(8)
            .map { "\($0.key.rawValue)=\($0.value)" }
            .joined(separator: ", ")
        let mismatchSummary = mismatchSamples.joined(separator: "\n    ")
        
        print("""
        
        🔎 v4 replay diagnostics:
          Planned-deload sessions (input): \(plannedDeloadSessions)/\(scorecard.totalSessions)
          Engine session-level deloads: \(engineDeloadSessions)/\(scorecard.totalSessions) (not planned: \(engineDeloadSessionsNotPlanned))
          Direction counts (main lifts, from ExercisePlan.direction): \(directionSummary)
          Deload reasons (top): \(deloadReasonSummary)
          Decrease-slightly reasons (top): \(decreaseReasonSummary)
          Hold reasons (top): \(holdReasonSummary)
          Missing ExercisePlan.direction: \(missingDirectionCount)
          Missing engine exercise match (scored main lifts): \(missingEngineExerciseMatch)
          Missing expected readiness_flag (main lifts): \(missingExpectedReadinessFlag)
          Sample mismatches (up to 12):
            \(mismatchSummary)
        """)
        
        // ----------------------------
        // Print + persist richer diagnostics
        // ----------------------------
        let now = ISO8601DateFormatter().string(from: Date())
        var logLines: [String] = []
        logLines.append("v4 replay detailed diagnostics @ \(now)")
        logLines.append("sessions=\(scorecard.totalSessions) mainLiftPrescriptions=\(scorecard.mainLiftPrescriptions)")
        logLines.append("decisionAgree=\(scorecard.decisionCorrect)/\(scorecard.decisionTotal) loadAgree=\(scorecard.loadWithinRange)/\(scorecard.loadTotal) mae=\(String(format: "%.2f", scorecard.loadErrors.reduce(0, +) / Double(max(1, scorecard.loadErrors.count))))")
        logLines.append("")
        
        // Confusion matrix
        logLines.append("Decision confusion matrix (rows=expected, cols=predicted):")
        let header = (["exp\\\\pred"] + decisionLabels).map { String(format: "%14s", ($0 as NSString).utf8String!) }.joined()
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
        
        // Top mismatch pairs + reason codes + samples
        let topPairs = mismatchPairCounts
            .sorted(by: { $0.value > $1.value })
            .prefix(10)
        logLines.append("Top mismatch pairs (expected->predicted):")
        for (pair, n) in topPairs {
            logLines.append("  \(pair): \(n)")
            if let rc = mismatchPairReasonCounts[pair] {
                let topRC = rc.sorted(by: { $0.value > $1.value }).prefix(6)
                let rcLine = topRC.map { "\($0.key)=\($0.value)" }.joined(separator: ", ")
                logLines.append("    top reason_code: \(rcLine)")
            }
            if let samples = mismatchPairSamples[pair] {
                logLines.append("    samples:")
                for s in samples.prefix(3) { logLines.append("      \(s)") }
            }
        }
        logLines.append("")
        
        func bucketLine(name: String, stats: BucketStats) -> String {
            let n = stats.count
            let dec = stats.decisionAccuracy
            let la = stats.loadAgreement
            return "  \(name): n=\(n) dec=\(String(format: "%.2f", dec)) load=\(String(format: "%.2f", la)) mae=\(String(format: "%.1f", stats.mae))"
        }
        
        // Buckets: readiness_flag
        logLines.append("Buckets by expected readiness_flag:")
        for key in ["low", "ok", "good"] {
            if let s = byReadinessFlag[key] {
                logLines.append(bucketLine(name: key, stats: s))
                let expDist = s.expectedCounts.sorted(by: { $0.value > $1.value }).map { "\($0.key)=\($0.value)" }.joined(separator: ", ")
                let predDist = s.predictedCounts.sorted(by: { $0.value > $1.value }).map { "\($0.key)=\($0.value)" }.joined(separator: ", ")
                logLines.append("    exp: \(expDist)")
                logLines.append("    pred: \(predDist)")
            }
        }
        logLines.append("")
        
        // Buckets: lift
        logLines.append("Buckets by lift:")
        for key in ["squat", "bench", "deadlift", "ohp"] {
            if let s = byLift[key] {
                logLines.append(bucketLine(name: key, stats: s))
                let predDist = s.predictedCounts.sorted(by: { $0.value > $1.value }).map { "\($0.key)=\($0.value)" }.joined(separator: ", ")
                logLines.append("    pred: \(predDist)")
            }
        }
        logLines.append("")
        
        // Buckets: load step
        logLines.append("Buckets by load_step_lb:")
        for key in ["step<=1.25", "step<=2.5", "step>2.5"] {
            if let s = byLoadStepBucket[key] {
                logLines.append(bucketLine(name: key, stats: s))
                let predDist = s.predictedCounts.sorted(by: { $0.value > $1.value }).map { "\($0.key)=\($0.value)" }.joined(separator: ", ")
                logLines.append("    pred: \(predDist)")
            }
        }
        logLines.append("")
        
        // Per-user quick stats (bounded)
        logLines.append("Per-user buckets (decision accuracy + predicted dist):")
        for userKey in byUser.keys.sorted() {
            if let s = byUser[userKey] {
                logLines.append(bucketLine(name: userKey, stats: s))
                let predDist = s.predictedCounts.sorted(by: { $0.value > $1.value }).map { "\($0.key)=\($0.value)" }.joined(separator: ", ")
                logLines.append("    pred: \(predDist)")
            }
        }
        
        let logText = logLines.joined(separator: "\n")
        let logURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("v4_replay_diagnostics.log")
        do {
            try logText.write(to: logURL, atomically: true, encoding: .utf8)
            print("  Saved detailed v4 diagnostics to: \(logURL.path)")
        } catch {
            print("  Failed to write v4 diagnostics log: \(error)")
        }
        
        printScorecard(scorecard)
        XCTAssertGreaterThan(scorecard.totalSessions, 50, "Should process many sessions")
    }
    
    // MARK: - Helpers
    
    private func buildUserContext(from record: V4Record, userId: String) -> UserContext {
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
        
        catalog["close_grip_bench"] = Exercise(
            id: "close_grip_bench", name: "Close-Grip Bench Press",
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
    
    private func updateContextForSession(context: inout UserContext, record: V4Record, date: Date) {
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
    
    private func computeReadiness(from metrics: V4TodayMetrics) -> Int {
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
        exercisePlan: ExercisePlan?,
        liftState: LiftState?,
        baselineCoefficient: Double,
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
            case .resetAfterBreak:
                // Dataset doesn't have a separate reset label; treat as a meaningful reduction.
                return "deload"
            }
        }
        
        guard let state = liftState, state.lastWorkingWeight.value > 0 else {
            return "estimate"
        }
        
        let baseline = state.lastWorkingWeight.converted(to: .pounds).value * baselineCoefficient
        guard baseline > 0 else { return "estimate" }
        
        let delta = predictedWeight - baseline
        let step = max(0.5, loadStepLb)
        
        if delta >= step * 0.5 { return "increase" }
        if (delta / baseline) <= -0.08 { return "deload" }
        if delta <= -step * 0.5 { return "decrease_small" }
        return "hold"
    }
    
    private func findMatchingExercise(
        liftName: String,
        performedExercise: String,
        variation: String?,
        substitutedTo: String?,
        in plan: SessionPlan
    ) -> ExercisePlan? {
        // 1) Performed exercise match (v4 priority)
        if !performedExercise.isEmpty && performedExercise != liftName {
            if let match = plan.exercises.first(where: { $0.exercise.id.lowercased() == performedExercise || $0.exercise.id.lowercased().contains(performedExercise) }) {
                return match
            }
        }
        
        // 2) Substitution match
        if let substitutedTo, !substitutedTo.isEmpty {
            let key = substitutedTo.lowercased()
            if let match = plan.exercises.first(where: { $0.exercise.id.lowercased() == key || $0.exercise.id.lowercased().contains(key) }) {
                return match
            }
        }
        
        // 3) Variation match
        if let variation, !variation.isEmpty {
            let key = variation.lowercased()
            if let match = plan.exercises.first(where: { $0.exercise.id.lowercased() == key || $0.exercise.id.lowercased().contains(key) }) {
                return match
            }
        }
        
        // 4) Base lift match
        if let match = plan.exercises.first(where: { $0.exercise.id.lowercased() == liftName || $0.exercise.id.lowercased().contains(liftName) }) {
            return match
        }
        
        // 5) Movement-pattern fallback
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
        performance: [V4Performance],
        expectedPrescriptions: [V4Prescription],
        date: Date,
        isDeload: Bool,
        readiness: Int
    ) {
        var exerciseResults: [ExerciseSessionResult] = []
        var sessions = context.history.sessions
        
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
                let performed = $0.performed_exercise?.lowercased()
                let substituted = $0.substituted_to?.lowercased()
                let variation = $0.lift_variation?.lowercased()
                return lift == exerciseId || performed == exerciseId || substituted == exerciseId || variation == exerciseId
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
            // This prevents the engine from treating intentional deloads/cuts as failures
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
    
    private func printScorecard(_ scorecard: Scorecard) {
        let loadPct = scorecard.loadTotal > 0 ? Double(scorecard.loadWithinRange) / Double(scorecard.loadTotal) * 100 : 0
        let mae = scorecard.loadErrors.isEmpty ? 0 : scorecard.loadErrors.reduce(0, +) / Double(scorecard.loadErrors.count)
        let decPct = scorecard.decisionTotal > 0 ? Double(scorecard.decisionCorrect) / Double(scorecard.decisionTotal) * 100 : 0
        
        let coldStartMAE = scorecard.coldStartMAE.isEmpty ? 0 : scorecard.coldStartMAE.reduce(0, +) / Double(scorecard.coldStartMAE.count)
        
        print("""
        
        🧪 workout_engine_testset_v4 Full E2E Scorecard:
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
          
          🆕 Cold Start:
            Cases: \(scorecard.coldStartCases)
            MAE: \(String(format: "%.2f", coldStartMAE)) lb
          
          🔬 Microloading:
            Cases: \(scorecard.microloadCases)
            Correct: \(scorecard.microloadCorrect)/\(scorecard.microloadCases)
          
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
