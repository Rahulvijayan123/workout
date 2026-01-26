import Foundation
import XCTest
@testable import TrainingEngine

/// End-to-end supervised replay against `workout_engine_testset_v1.jsonl` (workspace root).
///
/// Notes:
/// - This harness feeds **only** `input.*` into the engine.
/// - Ground truth (`expected.*`) is used strictly for scoring and for simulating logged performance
///   between sessions (what a real user would have in their history).
/// - Missed sessions are not scored (no "today prescription" label), and they do not update history.
final class WorkoutEngineTestsetV1JSONLReplayTests: XCTestCase {
    // Fixed calendar for deterministic date math (DST-safe).
    private let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(secondsFromGMT: 0)!
        return c
    }()
    
    func testWorkoutEngineTestsetV1_JSONL_Replay_MainLiftScorecard() throws {
        let records = try Dataset.loadRecords(from: datasetURL())
        XCTAssertGreaterThan(records.count, 0, "Dataset contained 0 records (parsing/path issue)")
        
        let byUser = Dictionary(grouping: records, by: \.userId)
        XCTAssertGreaterThan(byUser.count, 0, "Dataset contained 0 users (grouping issue)")
        
        var total = Scorecard()
        var perUser: [String: Scorecard] = [:]
        
        for (userId, recs) in byUser {
            let ordered = recs.sorted { a, b in
                a.date < b.date
            }
            let ctx = UserContext.build(for: userId, records: ordered, calendar: calendar)
            var sc = Scorecard()
            ctx.replay(records: ordered, into: &sc, calendar: calendar)
            total.merge(sc)
            perUser[userId] = sc
        }
        
        // Print a high-level scorecard (no per-record leakage).
        let perUserLine = perUser.keys.sorted().map { uid in
            let sc = perUser[uid] ?? Scorecard()
            return "\(uid): sessions=\(sc.scoredSessionCount) " +
            "mainLiftAgree=\(String(format: "%.2f", sc.mainLiftLoadAgreement)) " +
            "MAE=\(String(format: "%.1f", sc.meanAbsMainLiftErrorLb))lb " +
            "deloadAcc=\(String(format: "%.2f", sc.deloadAccuracy)) exp/pred=\(sc.expectedDeloadCount)/\(sc.predictedDeloadCount) " +
            "consAcc=\(String(format: "%.2f", sc.conservativeAccuracy)) exp/pred=\(sc.expectedConservativeCount)/\(sc.predictedConservativeCount) " +
            "missed=\(sc.missedSessionCount) varMain=\(sc.variationMainLiftCount)"
        }.joined(separator: " | ")
        
        print("🧪 workout_engine_testset_v1.jsonl scorecard (main lifts; no answer leak):")
        print("  Users: \(byUser.count)")
        print("  Records: \(records.count)")
        print("  Scored sessions: \(total.scoredSessionCount) (missed: \(total.missedSessionCount))")
        print("  Main-lift prescriptions scored: \(total.mainLiftCount)")
        print("  Main-lift load agreement (within tolerance): \(total.mainLiftWithinTolerance)/\(total.mainLiftCount) = \(String(format: "%.2f", total.mainLiftLoadAgreement))")
        print("  Main-lift mean abs error: \(String(format: "%.2f", total.meanAbsMainLiftErrorLb)) lb")
        print("  Main-lift mean abs % error: \(String(format: "%.1f", total.meanAbsMainLiftPctError * 100))%")
        print("  Deload flag accuracy (expected reason contains 'deload'): \(total.deloadMatched)/\(total.scoredSessionCount) = \(String(format: "%.2f", total.deloadAccuracy))")
        print("  Deload label/predicted: \(total.expectedDeloadCount)/\(total.predictedDeloadCount) (P=\(String(format: "%.2f", total.deloadPrecision)) R=\(String(format: "%.2f", total.deloadRecall)))")
        print("  Conservative label accuracy (deload OR non-increase majority): \(total.conservativeMatched)/\(total.scoredSessionCount) = \(String(format: "%.2f", total.conservativeAccuracy))")
        print("  Conservative label/predicted: \(total.expectedConservativeCount)/\(total.predictedConservativeCount) (P=\(String(format: "%.2f", total.conservativePrecision)) R=\(String(format: "%.2f", total.conservativeRecall)))")
        print("  Main-lift variation cases skipped from strict scoring: \(total.variationMainLiftCount)")
        print("  Missing main lifts in predicted plan: \(total.missingMainLiftCount)")
        print("  Per-user: \(perUserLine)")
        
        // Harness sanity checks.
        XCTAssertGreaterThan(total.scoredSessionCount, 0, "Harness scored 0 sessions (translation/parsing likely broken)")
        XCTAssertGreaterThan(total.mainLiftCount, 0, "Harness scored 0 main lift prescriptions (translation/parsing likely broken)")
    }
}

// MARK: - Dataset decoding

private enum Dataset {
    static func loadRecords(from url: URL) throws -> [Record] {
        let raw = try String(contentsOf: url, encoding: .utf8)
        let decoder = JSONDecoder()
        
        var out: [Record] = []
        out.reserveCapacity(256)
        
        for line in raw.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }
            out.append(try decoder.decode(Record.self, from: Data(trimmed.utf8)))
        }
        return out
    }
}

private struct Record: Decodable {
    let userId: String
    let date: String
    let sessionType: String
    let input: Input
    let expected: Expected
    
    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case date
        case sessionType = "session_type"
        case input
        case expected
    }
}

private struct Input: Decodable {
    let userProfile: InputUserProfile
    let todayMetrics: TodayMetrics
    let todaySessionTemplate: [TemplateExerciseLite]
    let eventFlags: EventFlags
    
    enum CodingKeys: String, CodingKey {
        case userProfile = "user_profile"
        case todayMetrics = "today_metrics"
        case todaySessionTemplate = "today_session_template"
        case eventFlags = "event_flags"
    }
}

private struct InputUserProfile: Decodable {
    let sex: String
    let age: Int
    let heightCm: Int
    let experienceLevel: String
    let program: String
    let goal: String
    
    enum CodingKeys: String, CodingKey {
        case sex
        case age
        case heightCm = "height_cm"
        case experienceLevel = "experience_level"
        case program
        case goal
    }
}

private struct TodayMetrics: Decodable {
    let bodyWeightLb: Double?
    let sleepHours: Double?
    let hrvMs: Double?
    let restingHrBpm: Double?
    let soreness1To10: Double?
    let stress1To10: Double?
    let steps: Double?
    let caloriesEst: Double?
    
    enum CodingKeys: String, CodingKey {
        case bodyWeightLb = "body_weight_lb"
        case sleepHours = "sleep_hours"
        case hrvMs = "hrv_ms"
        case restingHrBpm = "resting_hr_bpm"
        case soreness1To10 = "soreness_1_to_10"
        case stress1To10 = "stress_1_to_10"
        case steps
        case caloriesEst = "calories_est"
    }
}

private struct TemplateExerciseLite: Decodable {
    let lift: String
    let sets: Int
    let reps: Int
    let unit: String?
    
    enum CodingKeys: String, CodingKey {
        case lift
        case sets
        case reps
        case unit
    }
}

private struct EventFlags: Decodable {
    let missedSession: Bool
    let injuryFlags: [String: Bool]
    
    enum CodingKeys: String, CodingKey {
        case missedSession = "missed_session"
        case injuryFlags = "injury_flags"
    }
}

private struct Expected: Decodable {
    // Present for non-missed sessions.
    let sessionPrescriptionForToday: [ExpectedPrescription]?
    let actualLoggedPerformance: [LoggedExercise]?
    let expectedNextSessionPrescription: NextSessionExpected?
    
    // Present for missed sessions.
    let nextSessionRule: String?
    let notes: String?
    
    enum CodingKeys: String, CodingKey {
        case sessionPrescriptionForToday = "session_prescription_for_today"
        case actualLoggedPerformance = "actual_logged_performance"
        case expectedNextSessionPrescription = "expected_next_session_prescription"
        case nextSessionRule = "next_session_rule"
        case notes
    }
}

private struct ExpectedPrescription: Decodable {
    let lift: String
    let sets: Int
    let targetReps: Int
    let prescribedWeightLb: Double?
    let reasonCode: String?
    let liftVariation: String?
    
    enum CodingKeys: String, CodingKey {
        case lift
        case sets
        case targetReps = "target_reps"
        case prescribedWeightLb = "prescribed_weight_lb"
        case reasonCode = "reason_code"
        case liftVariation = "lift_variation"
    }
}

private struct LoggedExercise: Decodable {
    let exercise: String
    let performedSets: [LoggedSet]
    let outcome: String?
    
    enum CodingKeys: String, CodingKey {
        case exercise
        case performedSets = "performed_sets"
        case outcome
    }
}

private struct LoggedSet: Decodable {
    let set: Int
    let weightLb: Double?
    let reps: Int?
    let value: Int?
    let unit: String?
    let rpe: Double?
    
    enum CodingKeys: String, CodingKey {
        case set
        case weightLb = "weight_lb"
        case reps
        case value
        case unit
        case rpe
    }
}

private struct NextSessionExpected: Decodable {
    let date: String
    let sessionType: String
    let prescriptions: [ExpectedPrescription]
    
    enum CodingKeys: String, CodingKey {
        case date
        case sessionType = "session_type"
        case prescriptions
    }
}

// MARK: - Engine integration + replay

private struct UserContext {
    let userId: String
    let rounding: LoadRoundingPolicy
    let templateIdBySessionType: [String: WorkoutTemplateId]
    let plan: TrainingPlan
    let exercisesById: [String: Exercise]
    let prescriptionByExerciseId: [String: SetPrescription]
    
    static func build(for userId: String, records: [Record], calendar: Calendar) -> UserContext {
        let rounding = LoadRoundingPolicy.standardPounds
        
        // 1) Stable template IDs per session_type.
        let sessionTypes = Array(Set(records.map(\.sessionType))).sorted()
        var templateIdBySessionType: [String: WorkoutTemplateId] = [:]
        templateIdBySessionType.reserveCapacity(sessionTypes.count)
        for st in sessionTypes {
            templateIdBySessionType[st] = UUID()
        }
        
        // 2) Exercise catalog from input templates (no expected leakage).
        var exerciseIds: Set<String> = []
        for r in records {
            for te in r.input.todaySessionTemplate {
                exerciseIds.insert(te.lift)
            }
        }
        
        let exercisesById = buildExerciseCatalog(from: exerciseIds.sorted())
        
        // 3) Prescriptions derived from input templates (sets/reps only).
        var prescriptionByExerciseId: [String: SetPrescription] = [:]
        prescriptionByExerciseId.reserveCapacity(exerciseIds.count)
        
        for exId in exerciseIds {
            let samples = records.flatMap { r in
                r.input.todaySessionTemplate.filter { $0.lift == exId }
            }
            let setCount = max(1, samples.map(\.sets).max() ?? 3)
            let reps = max(1, samples.map(\.reps).max() ?? 8)
            let exercise = exercisesById[exId]
            
            let rest: Int = {
                guard let exercise else { return 120 }
                if exercise.movementPattern.isCompound { return 180 }
                return 90
            }()
            
            let incLb: Double = {
                guard let exercise else { return 2.5 }
                if exercise.equipment == .barbell || exercise.equipment == .trapBar || exercise.equipment == .ezBar {
                    if exercise.movementPattern == .squat || exercise.movementPattern == .hipHinge {
                        return 5.0
                    }
                    return 2.5
                }
                return 5.0
            }()
            
            prescriptionByExerciseId[exId] = SetPrescription(
                setCount: setCount,
                targetRepsRange: reps...reps,
                targetRIR: 2,
                tempo: .standard,
                restSeconds: rest,
                loadStrategy: .absolute,
                increment: .pounds(incLb)
            )
        }
        
        // 4) Progression policies inferred from prescription/movement (no expected leakage).
        var progressionByExerciseId: [String: ProgressionPolicyType] = [:]
        progressionByExerciseId.reserveCapacity(exerciseIds.count)
        
        for exId in exerciseIds {
            let ex = exercisesById[exId]
            let rx = prescriptionByExerciseId[exId] ?? .hypertrophy
            
            let isCompound = ex?.movementPattern.isCompound ?? false
            let fixedReps = rx.targetRepsRange.lowerBound == rx.targetRepsRange.upperBound
            let reps = rx.targetRepsRange.lowerBound
            
            if isCompound && fixedReps && reps <= 6 {
                let inc = rx.increment
                let cfg = LinearProgressionConfig(
                    successIncrement: inc,
                    failureDecrement: nil,
                    deloadPercentage: FailureThresholdDefaults.deloadPercentage,
                    failuresBeforeDeload: FailureThresholdDefaults.failuresBeforeDeload
                )
                progressionByExerciseId[exId] = .linearProgression(config: cfg)
            } else {
                let cfg = DoubleProgressionConfig(
                    sessionsAtTopBeforeIncrease: 1,
                    loadIncrement: rx.increment,
                    deloadPercentage: FailureThresholdDefaults.deloadPercentage,
                    failuresBeforeDeload: FailureThresholdDefaults.failuresBeforeDeload
                )
                progressionByExerciseId[exId] = .doubleProgression(config: cfg)
            }
        }
        
        // 5) Templates from the first record for each session_type (preserve exercise order).
        var templates: [WorkoutTemplateId: WorkoutTemplate] = [:]
        templates.reserveCapacity(sessionTypes.count)
        
        for st in sessionTypes {
            let tid = templateIdBySessionType[st] ?? UUID()
            let first = records.first(where: { $0.sessionType == st })
            let orderedIds = first?.input.todaySessionTemplate.map(\.lift) ?? []
            
            let tes: [TemplateExercise] = orderedIds.enumerated().compactMap { idx, exId in
                guard let ex = exercisesById[exId] else { return nil }
                let rx = prescriptionByExerciseId[exId] ?? .hypertrophy
                return TemplateExercise(exercise: ex, prescription: rx, order: idx)
            }
            
            templates[tid] = WorkoutTemplate(
                id: tid,
                name: st,
                exercises: tes,
                estimatedDurationMinutes: nil,
                targetMuscleGroups: [],
                description: nil,
                createdAt: calendar.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: 12))!,
                updatedAt: calendar.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: 12))!
            )
        }
        
        // 6) Deload config: match dataset modeling (intensity deload only).
        // Scheduled deloads are inferred from experience level (generic, not case-specific).
        let experience = experienceLevel(from: records.first?.input.userProfile.experienceLevel ?? "")
        let scheduled: Int? = (experience == .beginner) ? nil : experience.recommendedDeloadFrequencyWeeks
        
        let deload = DeloadConfig(
            intensityReduction: 0.10,
            volumeReduction: 0,
            scheduledDeloadWeeks: scheduled,
            readinessThreshold: 50,
            lowReadinessDaysRequired: 3
        )
        
        let plan = TrainingPlan(
            name: "workout_engine_testset_v1.jsonl (\(userId))",
            templates: templates,
            schedule: .manual,
            progressionPolicies: progressionByExerciseId,
            inSessionPolicies: [:],
            substitutionPool: [],
            deloadConfig: deload,
            loadRoundingPolicy: rounding,
            createdAt: calendar.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: 12))!
        )
        
        return UserContext(
            userId: userId,
            rounding: rounding,
            templateIdBySessionType: templateIdBySessionType,
            plan: plan,
            exercisesById: exercisesById,
            prescriptionByExerciseId: prescriptionByExerciseId
        )
    }
    
    func replay(records: [Record], into sc: inout Scorecard, calendar: Calendar) {
        // Replay state for this user.
        var sessions: [CompletedSession] = []
        var liftStates: [String: LiftState] = [:]
        var readinessHistory: [ReadinessRecord] = []
        var volumeByDate: [Date: Double] = [:]
        var metricHistory: [MetricsPoint] = []
        var earliestTrainingDay: Date?
        
        for r in records {
            let day = parseDay(r.date, calendar: calendar)
            
            // Compute readiness from today metrics (baseline-aware; deterministic).
            let readiness = computeReadiness(today: r.input.todayMetrics, prior: metricHistory, day: day, calendar: calendar)
            metricHistory.append(MetricsPoint(day: calendar.startOfDay(for: day), metrics: r.input.todayMetrics))
            upsertReadinessSeries(&readinessHistory, day: day, score: readiness, calendar: calendar)
            
            let isMissed = r.input.eventFlags.missedSession || r.expected.sessionPrescriptionForToday == nil
            if isMissed {
                sc.missedSessionCount += 1
                continue
            }
            
            sc.scoredSessionCount += 1
            
            // Build user profile for this day.
            let profile = makeUserProfile(userId: userId, input: r.input.userProfile, today: r.input.todayMetrics)
            let templateId = templateIdBySessionType[r.sessionType] ?? UUID()
            
            let history = WorkoutHistory(
                sessions: sessions,
                liftStates: liftStates,
                readinessHistory: readinessHistory,
                recentVolumeByDate: volumeByDate
            )
            
            let predicted = Engine.recommendSessionForTemplate(
                date: day,
                templateId: templateId,
                userProfile: profile,
                plan: plan,
                history: history,
                readiness: readiness,
                excludingExerciseIds: [],
                calendar: calendar
            )
            
            // Score main lifts vs expected.session_prescription_for_today.
            let expectedToday = r.expected.sessionPrescriptionForToday ?? []
            scoreSession(
                predicted: predicted,
                expected: expectedToday,
                liftStates: liftStates,
                into: &sc,
                rounding: rounding
            )
            
            // Update history from *logged* performance (what a real user would have).
            if let logged = r.expected.actualLoggedPerformance {
                let completed = makeCompletedSession(
                    userId: userId,
                    date: day,
                    templateId: templateId,
                    predictedWasDeload: predicted.isDeload,
                    readiness: readiness,
                    logged: logged,
                    rxById: prescriptionByExerciseId,
                    existingLiftStates: liftStates
                )
                
                // Update lift states using the engine's canonical updater.
                let updated = Engine.updateLiftState(afterSession: completed)
                for st in updated {
                    liftStates[st.exerciseId] = st
                }
                
                sessions.append(completed)
                
                // Update volume history (kg*reps) and ensure baseline coverage for fatigue trigger.
                let startDay = calendar.startOfDay(for: day)
                earliestTrainingDay = earliestTrainingDay ?? startDay
                volumeByDate[startDay] = sessionVolumeKgReps(completed)
                ensureVolumeCoverage(
                    &volumeByDate,
                    earliestTrainingDay: earliestTrainingDay,
                    referenceDay: startDay,
                    calendar: calendar,
                    ensureDays: 28
                )
            }
        }
    }
}

// MARK: - Scoring helpers

private struct Scorecard {
    var scoredSessionCount: Int = 0
    var missedSessionCount: Int = 0
    
    var mainLiftCount: Int = 0
    var mainLiftWithinTolerance: Int = 0
    var absMainLiftErrorSumLb: Double = 0
    var absMainLiftPctErrorSum: Double = 0
    var absMainLiftPctErrorCount: Int = 0
    
    var variationMainLiftCount: Int = 0
    var missingMainLiftCount: Int = 0
    
    // Deload label metrics (expected reason contains "deload" vs engine session-level deload flag).
    var deloadMatched: Int = 0
    var expectedDeloadCount: Int = 0
    var predictedDeloadCount: Int = 0
    var deloadTruePositive: Int = 0
    var deloadFalsePositive: Int = 0
    var deloadFalseNegative: Int = 0
    
    // Conservative label metrics (expected deload OR majority hold/down vs last weight).
    var conservativeMatched: Int = 0
    var expectedConservativeCount: Int = 0
    var predictedConservativeCount: Int = 0
    var conservativeTruePositive: Int = 0
    var conservativeFalsePositive: Int = 0
    var conservativeFalseNegative: Int = 0
    
    mutating func merge(_ other: Scorecard) {
        scoredSessionCount += other.scoredSessionCount
        missedSessionCount += other.missedSessionCount
        
        mainLiftCount += other.mainLiftCount
        mainLiftWithinTolerance += other.mainLiftWithinTolerance
        absMainLiftErrorSumLb += other.absMainLiftErrorSumLb
        absMainLiftPctErrorSum += other.absMainLiftPctErrorSum
        absMainLiftPctErrorCount += other.absMainLiftPctErrorCount
        
        variationMainLiftCount += other.variationMainLiftCount
        missingMainLiftCount += other.missingMainLiftCount
        
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
    }
    
    var mainLiftLoadAgreement: Double {
        guard mainLiftCount > 0 else { return 0 }
        return Double(mainLiftWithinTolerance) / Double(mainLiftCount)
    }
    
    var meanAbsMainLiftErrorLb: Double {
        guard mainLiftCount > 0 else { return 0 }
        return absMainLiftErrorSumLb / Double(mainLiftCount)
    }
    
    var meanAbsMainLiftPctError: Double {
        guard absMainLiftPctErrorCount > 0 else { return 0 }
        return absMainLiftPctErrorSum / Double(absMainLiftPctErrorCount)
    }
    
    var deloadAccuracy: Double {
        guard scoredSessionCount > 0 else { return 0 }
        return Double(deloadMatched) / Double(scoredSessionCount)
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
        guard scoredSessionCount > 0 else { return 0 }
        return Double(conservativeMatched) / Double(scoredSessionCount)
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

private func scoreSession(
    predicted: SessionPlan,
    expected: [ExpectedPrescription],
    liftStates: [String: LiftState],
    into sc: inout Scorecard,
    rounding: LoadRoundingPolicy
) {
    // Expected deload label: any main lift reason contains "deload".
    let expectedIsDeload = expected.contains { p in
        guard isMainLift(p.lift) else { return false }
        let rc = p.reasonCode?.lowercased() ?? ""
        return rc.contains("deload")
    }
    let predictedIsDeload = predicted.isDeload
    
    sc.expectedDeloadCount += expectedIsDeload ? 1 : 0
    sc.predictedDeloadCount += predictedIsDeload ? 1 : 0
    sc.deloadMatched += (expectedIsDeload == predictedIsDeload) ? 1 : 0
    if expectedIsDeload && predictedIsDeload { sc.deloadTruePositive += 1 }
    if !expectedIsDeload && predictedIsDeload { sc.deloadFalsePositive += 1 }
    if expectedIsDeload && !predictedIsDeload { sc.deloadFalseNegative += 1 }
    
    // Conservative label: deload OR (>= 75% of main lifts are hold/down vs last weight).
    let predictedConservative = predictedIsDeload || isConservativePlan(predicted: predicted, liftStates: liftStates)
    let expectedConservative = expectedIsDeload || expected.contains { p in
        guard isMainLift(p.lift) else { return false }
        let rc = p.reasonCode?.lowercased() ?? ""
        return rc.contains("hold") || rc.contains("repeat") || rc.contains("reset")
    }
    
    sc.expectedConservativeCount += expectedConservative ? 1 : 0
    sc.predictedConservativeCount += predictedConservative ? 1 : 0
    sc.conservativeMatched += (expectedConservative == predictedConservative) ? 1 : 0
    if expectedConservative && predictedConservative { sc.conservativeTruePositive += 1 }
    if !expectedConservative && predictedConservative { sc.conservativeFalsePositive += 1 }
    if expectedConservative && !predictedConservative { sc.conservativeFalseNegative += 1 }
    
    // Main lift load scoring: strict only for canonical lifts without variation swaps.
    for p in expected {
        guard isMainLift(p.lift) else { continue }
        guard let expectedLb = p.prescribedWeightLb else { continue }
        
        // If expected indicates a variation swap (e.g., close grip bench, leg press instead of squat),
        // do not compare against the canonical main lift weight.
        if isVariationPrescription(p) {
            sc.variationMainLiftCount += 1
            continue
        }
        
        sc.mainLiftCount += 1
        
        guard let match = predicted.exercises.first(where: { $0.exercise.id == p.lift }) else {
            sc.missingMainLiftCount += 1
            continue
        }
        
        let predictedLb = match.sets.first?.targetLoad.converted(to: .pounds).value ?? 0
        let absErr = abs(predictedLb - expectedLb)
        sc.absMainLiftErrorSumLb += absErr
        if abs(expectedLb) > 0.0001 {
            sc.absMainLiftPctErrorSum += absErr / abs(expectedLb)
            sc.absMainLiftPctErrorCount += 1
        }
        
        let tol = toleranceLb(expectedLb: expectedLb, rounding: rounding)
        if absErr <= tol {
            sc.mainLiftWithinTolerance += 1
        }
    }
}

private func isConservativePlan(predicted: SessionPlan, liftStates: [String: LiftState]) -> Bool {
    var considered = 0
    var nonIncrease = 0
    
    let epsilon = 0.25
    for ep in predicted.exercises {
        guard isMainLift(ep.exercise.id) else { continue }
        guard let last = liftStates[ep.exercise.id]?.lastWorkingWeight.converted(to: .pounds).value, last > 0 else { continue }
        let predictedLb = ep.sets.first?.targetLoad.converted(to: .pounds).value ?? 0
        considered += 1
        if predictedLb <= last + epsilon {
            nonIncrease += 1
        }
    }
    
    guard considered >= 2 else { return false }
    return Double(nonIncrease) / Double(considered) >= 0.75
}

private func toleranceLb(expectedLb: Double, rounding: LoadRoundingPolicy) -> Double {
    let absExpected = abs(expectedLb)
    let step = max(0.1, rounding.increment)
    return max(step, absExpected * 0.05, 2.5)
}

private func isMainLift(_ key: String) -> Bool {
    switch key.lowercased() {
    case "bench", "squat", "deadlift", "ohp":
        return true
    default:
        return false
    }
}

private func isVariationPrescription(_ p: ExpectedPrescription) -> Bool {
    if p.liftVariation != nil { return true }
    let l = p.lift.lowercased()
    if l.contains("instead_of") { return true }
    if l.contains("due_to") { return true }
    if l.contains("close_grip") { return true }
    if l.contains("leg_press") && p.lift == "squat" { return true }
    return false
}

// MARK: - Replay utilities (history + readiness)

private struct MetricsPoint {
    let day: Date
    let metrics: TodayMetrics
}

private func computeReadiness(today: TodayMetrics, prior: [MetricsPoint], day: Date, calendar: Calendar) -> Int {
    // Neutral default (good enough to train, not a green light to PR).
    var score = 75
    
    // Baseline window: last 7 calendar days (exclusive of today).
    let endDay = calendar.startOfDay(for: day)
    let startDay = calendar.date(byAdding: .day, value: -7, to: endDay) ?? endDay
    let pool = prior.filter { $0.day >= startDay && $0.day < endDay }
    
    func avg(_ values: [Double], minSamples: Int = 3) -> Double? {
        guard values.count >= minSamples else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }
    
    let baseSleep = avg(pool.compactMap { $0.metrics.sleepHours }.map { $0 * 60 })
    let baseHRV = avg(pool.compactMap { $0.metrics.hrvMs })
    let baseRHR = avg(pool.compactMap { $0.metrics.restingHrBpm })
    let baseSteps = avg(pool.compactMap { $0.metrics.steps })
    
    // Sleep (primary)
    if let todayH = today.sleepHours, let baseM = baseSleep, baseM > 0 {
        let todayM = todayH * 60
        let ratio = todayM / baseM
        if ratio < 0.85 {
            score -= 15
        } else if ratio < 1.0 {
            score -= Int(((1.0 - ratio) / 0.15 * 15.0).rounded())
        } else if ratio > 1.10 {
            score += 5
        } else {
            score += Int(((ratio - 1.0) / 0.10 * 5.0).rounded())
        }
    }
    
    // HRV (primary)
    if let todayHRV = today.hrvMs, let baseHRV, baseHRV > 0 {
        let ratio = todayHRV / baseHRV
        if ratio < 0.90 {
            score -= 15
        } else if ratio < 1.0 {
            score -= Int(((1.0 - ratio) / 0.10 * 15.0).rounded())
        } else if ratio > 1.10 {
            score += 5
        } else {
            score += Int(((ratio - 1.0) / 0.10 * 5.0).rounded())
        }
    }
    
    // Resting HR (primary; higher is worse)
    if let todayRHR = today.restingHrBpm, let baseRHR, baseRHR > 0 {
        let ratio = todayRHR / baseRHR
        if ratio > 1.05 {
            score -= 10
        } else if ratio > 1.0 {
            score -= Int(((ratio - 1.0) / 0.05 * 10.0).rounded())
        } else if ratio < 0.95 {
            score += 3
        } else {
            score += Int(((1.0 - ratio) / 0.05 * 3.0).rounded())
        }
    }
    
    // Activity (minor): very high steps can reduce readiness.
    if let todaySteps = today.steps, let baseSteps, baseSteps > 0 {
        let ratio = todaySteps / baseSteps
        if ratio > 1.40 {
            score -= 5
        } else if ratio > 1.15 {
            score -= 2
        }
    }
    
    // Soreness + stress (minor): use absolute scaling since we don't have per-user baselines.
    if let soreness = today.soreness1To10 {
        if soreness >= 7 { score -= 6 }
        else if soreness >= 6 { score -= 3 }
        else if soreness <= 2 { score += 2 }
    }
    if let stress = today.stress1To10 {
        if stress >= 7 { score -= 6 }
        else if stress >= 6 { score -= 3 }
        else if stress <= 2 { score += 2 }
    }
    
    return max(0, min(100, score))
}

private func upsertReadinessSeries(_ out: inout [ReadinessRecord], day: Date, score: Int, calendar: Calendar) {
    let today = calendar.startOfDay(for: day)
    if let last = out.last {
        var cursor = calendar.startOfDay(for: last.date)
        var lastScore = last.score
        var guardIters = 0
        while cursor < today && guardIters < 400 {
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = calendar.startOfDay(for: next)
            if cursor < today {
                out.append(ReadinessRecord(date: cursor, score: lastScore))
            }
            guardIters += 1
        }
        lastScore = score
    }
    // Avoid duplicates on the same day.
    if out.last.map({ calendar.startOfDay(for: $0.date) }) != today {
        out.append(ReadinessRecord(date: today, score: score))
    } else {
        // Replace last day's score deterministically.
        _ = out.popLast()
        out.append(ReadinessRecord(date: today, score: score))
    }
}

private func sessionVolumeKgReps(_ session: CompletedSession) -> Double {
    var v = 0.0
    for ex in session.exerciseResults {
        for s in ex.workingSets {
            v += s.load.inKilograms * Double(s.reps)
        }
    }
    return v
}

private func ensureVolumeCoverage(
    _ volume: inout [Date: Double],
    earliestTrainingDay: Date?,
    referenceDay: Date,
    calendar: Calendar,
    ensureDays: Int
) {
    guard ensureDays > 0 else { return }
    guard let earliestTrainingDay else { return }
    
    let endDay = calendar.startOfDay(for: referenceDay)
    let desiredStart = calendar.date(byAdding: .day, value: -(ensureDays - 1), to: endDay) ?? endDay
    let coverageStart = max(desiredStart, earliestTrainingDay)
    
    var cursor = endDay
    var guardIters = 0
    while cursor >= coverageStart && guardIters < 500 {
        if volume[cursor] == nil { volume[cursor] = 0 }
        guard let next = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
        cursor = calendar.startOfDay(for: next)
        guardIters += 1
    }
}

private func makeCompletedSession(
    userId: String,
    date: Date,
    templateId: WorkoutTemplateId,
    predictedWasDeload: Bool,
    readiness: Int,
    logged: [LoggedExercise],
    rxById: [String: SetPrescription],
    existingLiftStates: [String: LiftState]
) -> CompletedSession {
    var results: [ExerciseSessionResult] = []
    results.reserveCapacity(logged.count)
    
    var prevStates: [String: LiftState] = [:]
    prevStates.reserveCapacity(logged.count)
    
    for (idx, ex) in logged.enumerated() {
        let exId = ex.exercise
        let rx = rxById[exId] ?? synthesizePrescription(from: ex)
        
        let sets: [SetResult] = ex.performedSets.map { s in
            let load: Load = {
                if let w = s.weightLb { return .pounds(w) }
                return .zero
            }()
            let reps: Int = s.reps ?? s.value ?? 0
            let rir: Int? = s.rpe.map { rpe in
                // RPE 10 ≈ 0 RIR, 9 ≈ 1 RIR, etc.
                max(0, min(10, Int((10.0 - rpe).rounded())))
            }
            return SetResult(reps: reps, load: load, rirObserved: rir, completed: true, isWarmup: false)
        }
        
        prevStates[exId] = existingLiftStates[exId] ?? LiftState(exerciseId: exId)
        
        results.append(ExerciseSessionResult(
            exerciseId: exId,
            prescription: rx,
            sets: sets,
            order: idx,
            notes: nil
        ))
    }
    
    return CompletedSession(
        date: date,
        templateId: templateId,
        name: "\(userId) \(templateId.uuidString)",
        exerciseResults: results,
        startedAt: date,
        endedAt: nil,
        wasDeload: predictedWasDeload,
        previousLiftStates: prevStates,
        readinessScore: readiness,
        notes: nil
    )
}

private func synthesizePrescription(from logged: LoggedExercise) -> SetPrescription {
    // Heuristic fallback for exercises not in the planned template (e.g., variation swaps).
    let reps = logged.performedSets.compactMap(\.reps)
    let values = logged.performedSets.compactMap(\.value)
    let target = max(1, (reps + values).max() ?? 8)
    
    return SetPrescription(
        setCount: max(1, logged.performedSets.count),
        targetRepsRange: target...target,
        targetRIR: 2,
        tempo: .standard,
        restSeconds: 120,
        loadStrategy: .absolute,
        increment: .pounds(5)
    )
}

private func makeUserProfile(userId: String, input: InputUserProfile, today: TodayMetrics) -> UserProfile {
    let sex: BiologicalSex = {
        switch input.sex.lowercased() {
        case "female": return .female
        case "male": return .male
        default: return .other
        }
    }()
    let experience = experienceLevel(from: input.experienceLevel)
    let goals: [TrainingGoal] = {
        switch input.goal {
        case "strength_hypertrophy":
            return [.strength, .hypertrophy]
        case "fat_loss_strength_maintenance":
            return [.fatLoss, .strength]
        default:
            return [.generalFitness]
        }
    }()
    let weeklyFrequency: Int = {
        if input.program.contains("4") { return 4 }
        if input.program.contains("3") { return 3 }
        return 3
    }()
    let bodyWeight = today.bodyWeightLb.map { Load(value: $0, unit: .pounds).rounded(using: .standardPounds) }
    
    return UserProfile(
        id: userId,
        sex: sex,
        experience: experience,
        goals: goals,
        weeklyFrequency: weeklyFrequency,
        availableEquipment: .commercialGym,
        preferredUnit: .pounds,
        bodyWeight: bodyWeight,
        age: input.age,
        limitations: []
    )
}

private func experienceLevel(from raw: String) -> ExperienceLevel {
    switch raw.lowercased() {
    case "novice", "beginner":
        return .beginner
    case "intermediate":
        return .intermediate
    case "advanced":
        return .advanced
    case "elite":
        return .elite
    default:
        return .beginner
    }
}

private func buildExerciseCatalog(from ids: [String]) -> [String: Exercise] {
    var out: [String: Exercise] = [:]
    out.reserveCapacity(ids.count)
    
    for id in ids {
        let lower = id.lowercased()
        
        func contains(_ s: String) -> Bool { lower.contains(s) }
        
        let movement: MovementPattern = {
            if lower == "bench" || contains("bench") { return .horizontalPush }
            if lower == "ohp" || contains("overhead") || contains("shoulder_press") { return .verticalPush }
            if lower == "squat" || contains("squat") || contains("leg_press") { return .squat }
            if lower == "deadlift" || contains("deadlift") || contains("rdl") || contains("hinge") { return .hipHinge }
            if contains("row") { return .horizontalPull }
            if contains("pullup") || contains("pulldown") { return .verticalPull }
            if contains("plank") { return .coreStability }
            if contains("split_squat") || contains("lunge") { return .lunge }
            return .unknown
        }()
        
        let equipment: Equipment = {
            if contains("plank") { return .bodyweight }
            if contains("pullup") { return .pullUpBar }
            if contains("pulldown") || contains("cable") { return .cable }
            if contains("db") || contains("dumbbell") { return .dumbbell }
            if contains("leg_press") { return .machine }
            if movement.isCompound { return .barbell }
            return .machine
        }()
        
        out[id] = Exercise(
            id: id,
            name: id,
            equipment: equipment,
            primaryMuscles: [.unknown],
            movementPattern: movement
        )
    }
    
    return out
}

private func parseDay(_ yyyyMMdd: String, calendar: Calendar) -> Date {
    let parts = yyyyMMdd.split(separator: "-").map(String.init)
    let y = Int(parts[safe: 0] ?? "") ?? 1970
    let m = Int(parts[safe: 1] ?? "") ?? 1
    let d = Int(parts[safe: 2] ?? "") ?? 1
    return calendar.date(from: DateComponents(year: y, month: m, day: d, hour: 12, minute: 0))!
}

// MARK: - Paths

private func datasetURL() -> URL {
    // This file lives at:
    //   ios/Atlas/TrainingEngine/Tests/TrainingEngineTests/WorkoutEngineTestsetV1JSONLReplayTests.swift
    // Dataset lives at workspace root:
    //   workout_engine_testset_v1.jsonl
    let this = URL(fileURLWithPath: #filePath)
    let workspace = this
        .deletingLastPathComponent() // TrainingEngineTests
        .deletingLastPathComponent() // Tests
        .deletingLastPathComponent() // TrainingEngine
        .deletingLastPathComponent() // Atlas
        .deletingLastPathComponent() // ios
        .deletingLastPathComponent() // workspace root
    return workspace.appendingPathComponent("workout_engine_testset_v1.jsonl")
}

// MARK: - Small utilities

private extension Array where Element == String {
    subscript(safe idx: Int) -> String? {
        guard idx >= 0 && idx < count else { return nil }
        return self[idx]
    }
}

