import XCTest
@testable import TrainingEngine

/// High-signal, user-like calibration replay tests that feed synthetic workout logs
/// through the real `Engine.recommendSessionForTemplate` + `Engine.updateLiftState` loop.
///
/// Goal:
/// - Validate that CAL1/CAL2 produce sensible baselines (week 1 prescriptions are not "zero" or absurd)
/// - Catch systemic issues: deload weeks not persisting, readiness-based holds/backoffs, microloading behavior
///
/// Notes:
/// - These tests intentionally avoid hardcoding "the right progression algorithm" into production code.
///   The dataset is used only as an external validation oracle inside tests.
final class SyntheticCalibrationReplayTests: XCTestCase {
    // Fixed calendar for deterministic "weeks".
    private let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(secondsFromGMT: 0)!
        return c
    }()
    
    // MARK: - Public Tests
    
    func testSyntheticUsers_CalibrationReplay_LoadsAndDeloads_AgreeAtHighLevel() throws {
        let exposures = try SyntheticCSV.parseAll(from: syntheticDatasetCSV)
        let users = Dictionary(grouping: exposures, by: \.userId)
        
        // Run each user end-to-end and collect summary metrics.
        var summaries: [ReplaySummary] = []
        summaries.reserveCapacity(users.count)
        
        for (userId, rows) in users {
            let summary = runReplay(forUserId: userId, exposures: rows)
            summaries.append(summary)
        }
        
        // Aggregate checks: we want *meaningful* agreement without requiring exact numbers.
        let totalEvaluated = summaries.map(\.evaluatedExerciseCount).reduce(0, +)
        let totalWithinTolerance = summaries.map(\.withinToleranceCount).reduce(0, +)
        
        let totalDeloadSessions = summaries.map(\.expectedDeloadSessionCount).reduce(0, +)
        let deloadSessionsMatched = summaries.map(\.matchedDeloadSessionCount).reduce(0, +)
        let sortedSummaries = summaries.sorted { $0.userId < $1.userId }
        let perUserLine = sortedSummaries.map(\.oneLine).joined(separator: " | ")
        
        // If we somehow didn't evaluate anything, the harness is broken.
        XCTAssertGreaterThan(totalEvaluated, 0, "Replay harness evaluated 0 exercise exposures (parsing/grouping likely broken)")
        
        // Load agreement: tolerate some drift, but should be broadly close.
        let loadAgreement = Double(totalWithinTolerance) / Double(totalEvaluated)
        print("🧪 Synthetic calibration replay scorecard:")
        print("  Exercises scored: \(totalEvaluated)")
        print("  Load agreement (within tolerance): \(totalWithinTolerance)/\(totalEvaluated) = \(String(format: "%.2f", loadAgreement))")
        
        XCTAssertGreaterThanOrEqual(
            loadAgreement,
            0.70,
            "Engine prescriptions diverge too often from synthetic replay (agreement=\(String(format: "%.2f", loadAgreement))).\n" +
            "Per-user: \(perUserLine)"
        )
        
        // Deload agreement: deload blocks are a core UX feature; these should be mostly correct.
        if totalDeloadSessions > 0 {
            let deloadAgreement = Double(deloadSessionsMatched) / Double(totalDeloadSessions)
            print("  Deload session agreement: \(deloadSessionsMatched)/\(totalDeloadSessions) = \(String(format: "%.2f", deloadAgreement))")
            print("  Per-user: \(perUserLine)")
            
            XCTAssertGreaterThanOrEqual(
                deloadAgreement,
                0.80,
                "Engine missed too many deload sessions vs replay (agreement=\(String(format: "%.2f", deloadAgreement))).\n" +
                "Per-user: \(perUserLine)"
            )
        } else {
            print("  Deload session agreement: n/a (no deload sessions in dataset subset)")
            print("  Per-user: \(perUserLine)")
        }
    }
    
    // MARK: - Replay Runner
    
    private func runReplay(forUserId userId: String, exposures: [SyntheticExposure]) -> ReplaySummary {
        // Sort by week then workout order then exercise name for determinism.
        let ordered = exposures.sorted { a, b in
            if a.week != b.week { return a.week < b.week }
            if a.workoutSortKey != b.workoutSortKey { return a.workoutSortKey < b.workoutSortKey }
            if a.exerciseName != b.exerciseName { return a.exerciseName < b.exerciseName }
            return a.outcome.rawValue < b.outcome.rawValue
        }
        
        // Build the training plan templates and a stable exercise catalog.
        let catalog = SyntheticCatalog()
        let templates = catalog.makeTemplates()
        
        // Use a 5-workout rotation so CAL1/CAL2 happen before A/B/C.
        // We call `recommendSessionForTemplate` directly, but the plan must still contain the templates.
        let rotationOrder = [
            templates.cal1.id,
            templates.cal2.id,
            templates.a.id,
            templates.b.id,
            templates.c.id
        ]
        
        // Configure deloads explicitly for this replay fixture.
        // (The dataset includes planned deload weeks; the engine must handle deloads robustly.)
        let deloadConfig = DeloadConfig(
            intensityReduction: 0.10,
            volumeReduction: 0,
            scheduledDeloadWeeks: 4,
            readinessThreshold: 50,
            lowReadinessDaysRequired: 3
        )
        
        let plan = TrainingPlan(
            name: "Synthetic Replay Plan",
            templates: [
                templates.cal1.id: templates.cal1,
                templates.cal2.id: templates.cal2,
                templates.a.id: templates.a,
                templates.b.id: templates.b,
                templates.c.id: templates.c
            ],
            schedule: .rotation(order: rotationOrder),
            progressionPolicies: catalog.progressionPolicies,
            inSessionPolicies: [:],
            substitutionPool: [],
            deloadConfig: deloadConfig,
            loadRoundingPolicy: .standardPounds,
            createdAt: calendar.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: 12))!
        )
        
        // State that evolves over the replay.
        var liftStates: [String: LiftState] = [:]
        var sessions: [CompletedSession] = [] // most recent first
        
        // Precompute week-level readiness + bodyweight (stable within a week in the synthetic dataset).
        let weekSignals = SyntheticWeekSignals.from(exposures: ordered)
        
        // Group exposures into sessions (week+workout).
        let sessionsByKey = Dictionary(grouping: ordered, by: { "\($0.week)|\($0.workout)" })
        
        // Iterate sessions in chronological order.
        let sessionKeysOrdered = sessionsByKey.keys.sorted { lhs, rhs in
            let l = lhs.split(separator: "|")
            let r = rhs.split(separator: "|")
            let lw = Int(l[0]) ?? 0
            let rw = Int(r[0]) ?? 0
            if lw != rw { return lw < rw }
            let lWorkout = String(l[1])
            let rWorkout = String(r[1])
            let lKey = SyntheticExposure.workoutSortKeyStatic(lWorkout)
            let rKey = SyntheticExposure.workoutSortKeyStatic(rWorkout)
            if lKey != rKey { return lKey < rKey }
            return lhs < rhs
        }
        
        // Metrics.
        var evaluatedExerciseCount = 0
        var withinToleranceCount = 0
        var expectedDeloadSessionCount = 0
        var matchedDeloadSessionCount = 0
        
        // Anchor date: Jan 5 2026 (Mon) so week boundaries are deterministic.
        let startDate = calendar.date(from: DateComponents(year: 2026, month: 1, day: 5, hour: 12))!
        
        for key in sessionKeysOrdered {
            guard let rows = sessionsByKey[key], let first = rows.first else { continue }
            let week = first.week
            let workout = first.workout
            
            // Skip pure "SKIPPED" sessions (no performed exercises).
            let performedRows = rows.filter { $0.isPerformed }
            if performedRows.isEmpty { continue }
            
            // Date this session occurs on.
            let date = SyntheticSchedule.sessionDate(
                startDate: startDate,
                week: week,
                workout: workout,
                calendar: calendar
            )
            
            // Build a user profile for this week (bodyweight matters for adaptive increments).
            let weekSig = weekSignals[userId]?[week]
            let userProfile = catalog.makeUserProfile(
                userId: userId,
                sex: first.sex,
                trainingLevel: first.trainingLevel,
                bodyWeightLb: weekSig?.bodyWeightLb
            )
            
            // Build readiness inputs for the engine (0-100).
            let readiness = weekSig?.readinessScore ?? 75
            let readinessHistory = weekSig?.readinessHistory ?? []
            
            // Construct history (volume omitted in this replay; deloads are schedule-driven here).
            let history = WorkoutHistory(
                sessions: sessions,
                liftStates: liftStates,
                readinessHistory: readinessHistory,
                recentVolumeByDate: [:]
            )
            
            // Derive the templateId for this workout.
            let templateId: WorkoutTemplateId = {
                switch workout {
                case "CAL1": return templates.cal1.id
                case "CAL2": return templates.cal2.id
                case "A": return templates.a.id
                case "B": return templates.b.id
                case "C": return templates.c.id
                default: return templates.a.id
                }
            }()
            
            // We *don’t* score recommendations for week 0 (calibration exposures are user-driven).
            let scoreThisSession = week >= 1
            
            // Ask the engine what it would prescribe.
            let planOut = Engine.recommendSessionForTemplate(
                date: date,
                templateId: templateId,
                userProfile: userProfile,
                plan: plan,
                history: history,
                readiness: readiness,
                excludingExerciseIds: [],
                calendar: calendar
            )
            
            // Determine whether this session is expected to be a deload in the dataset.
            let expectedDeload = performedRows.allSatisfy { $0.outcome == .deload }
            if expectedDeload {
                expectedDeloadSessionCount += 1
                if planOut.isDeload { matchedDeloadSessionCount += 1 }
            }
            
            if scoreThisSession {
                // Compare planned loads per exercise to dataset performed loads.
                for row in performedRows {
                    guard let planned = planOut.exercises.first(where: { $0.exercise.name == row.exerciseName || $0.exercise.id == catalog.id(forExerciseName: row.exerciseName) }) else {
                        continue
                    }
                    guard let expectedLoad = row.set1LoadLb else { continue }
                    
                    evaluatedExerciseCount += 1
                    
                    let predicted = planned.sets.first?.targetLoad.converted(to: .pounds).value ?? 0
                    let tol = SyntheticTolerances.loadToleranceLb(
                        exerciseName: row.exerciseName,
                        trainingLevel: row.trainingLevel
                    )
                    
                    if abs(predicted - expectedLoad) <= tol {
                        withinToleranceCount += 1
                    }
                }
            }
            
            // Now "log" the performed session (dataset truth) and update lift states.
            let exerciseResults: [ExerciseSessionResult] = performedRows.compactMap { row in
                guard let exercise = catalog.exercise(forName: row.exerciseName) else { return nil }
                guard let rx = catalog.prescription(forExerciseName: row.exerciseName) else { return nil }
                
                // Some rows (e.g., SKIPPED) have nil set loads/reps; skip them.
                guard let s1w = row.set1LoadLb, let s1r = row.set1Reps,
                      let s2w = row.set2LoadLb, let s2r = row.set2Reps,
                      let s3w = row.set3LoadLb, let s3r = row.set3Reps else {
                    return nil
                }
                
                let sets: [SetResult] = [
                    SetResult(reps: s1r, load: .pounds(s1w), completed: true),
                    SetResult(reps: s2r, load: .pounds(s2w), completed: true),
                    SetResult(reps: s3r, load: .pounds(s3w), completed: true),
                ]
                
                return ExerciseSessionResult(
                    exerciseId: exercise.id,
                    prescription: rx,
                    sets: sets,
                    order: catalog.order(forExerciseName: row.exerciseName),
                    notes: row.notes?.isEmpty == true ? nil : row.notes
                )
            }
            
            let completed = CompletedSession(
                date: date,
                templateId: templateId,
                name: workout,
                exerciseResults: exerciseResults,
                startedAt: date,
                endedAt: date,
                wasDeload: expectedDeload,
                previousLiftStates: liftStates,
                readinessScore: readiness,
                // This synthetic fixture marks deload sessions as "scheduled deload weeks".
                // Propagate the reason so the engine can correctly continue a 7-day deload block.
                deloadReason: expectedDeload ? .scheduledDeload : nil,
                notes: nil
            )
            
            let updatedStates = Engine.updateLiftState(afterSession: completed)
            for st in updatedStates {
                liftStates[st.exerciseId] = st
            }
            
            // Maintain most-recent-first ordering.
            sessions.insert(completed, at: 0)
        }
        
        return ReplaySummary(
            userId: userId,
            evaluatedExerciseCount: evaluatedExerciseCount,
            withinToleranceCount: withinToleranceCount,
            expectedDeloadSessionCount: expectedDeloadSessionCount,
            matchedDeloadSessionCount: matchedDeloadSessionCount
        )
    }
}

// MARK: - Replay Summary

private struct ReplaySummary: Hashable {
    let userId: String
    let evaluatedExerciseCount: Int
    let withinToleranceCount: Int
    let expectedDeloadSessionCount: Int
    let matchedDeloadSessionCount: Int
    
    var oneLine: String {
        let loadAgreement = evaluatedExerciseCount > 0 ? Double(withinToleranceCount) / Double(evaluatedExerciseCount) : 0
        let deloadAgreement = expectedDeloadSessionCount > 0 ? Double(matchedDeloadSessionCount) / Double(expectedDeloadSessionCount) : 1
        return "\(userId):load=\(String(format: "%.2f", loadAgreement)) deload=\(String(format: "%.2f", deloadAgreement))"
    }
}

// MARK: - Synthetic Catalog / Prescriptions

private struct SyntheticTemplates {
    let cal1: WorkoutTemplate
    let cal2: WorkoutTemplate
    let a: WorkoutTemplate
    let b: WorkoutTemplate
    let c: WorkoutTemplate
}

private struct SyntheticCatalog {
    // Stable IDs for mapping.
    private let bench = Exercise(id: "bench", name: "Bench Press", equipment: .barbell, primaryMuscles: [.chest], secondaryMuscles: [.triceps], movementPattern: .horizontalPush)
    private let row = Exercise(id: "row", name: "Barbell Row", equipment: .barbell, primaryMuscles: [.back], secondaryMuscles: [.biceps], movementPattern: .horizontalPull)
    private let squat = Exercise(id: "squat", name: "Back Squat", equipment: .barbell, primaryMuscles: [.quadriceps, .glutes], secondaryMuscles: [.hamstrings, .lowerBack], movementPattern: .squat)
    private let rdl = Exercise(id: "rdl", name: "Romanian Deadlift", equipment: .barbell, primaryMuscles: [.hamstrings, .glutes], secondaryMuscles: [.lowerBack], movementPattern: .hipHinge)
    private let deadlift = Exercise(id: "deadlift", name: "Deadlift", equipment: .barbell, primaryMuscles: [.hamstrings, .glutes], secondaryMuscles: [.lowerBack], movementPattern: .hipHinge)
    private let ohp = Exercise(id: "ohp", name: "Overhead Press", equipment: .barbell, primaryMuscles: [.shoulders], secondaryMuscles: [.triceps], movementPattern: .verticalPush)
    
    // Prescriptions (shared across users in this test harness).
    // These are intentionally broad ranges; the engine should still behave sensibly.
    private let prescriptionsById: [String: SetPrescription] = [
        "bench": SetPrescription(setCount: 3, targetRepsRange: 6...8, targetRIR: 2, restSeconds: 150, increment: .pounds(5)),
        "row": SetPrescription(setCount: 3, targetRepsRange: 8...10, targetRIR: 2, restSeconds: 120, increment: .pounds(5)),
        "squat": SetPrescription(setCount: 3, targetRepsRange: 6...8, targetRIR: 2, restSeconds: 180, increment: .pounds(10)),
        "rdl": SetPrescription(setCount: 3, targetRepsRange: 8...10, targetRIR: 2, restSeconds: 150, increment: .pounds(10)),
        "deadlift": SetPrescription(setCount: 3, targetRepsRange: 4...6, targetRIR: 2, restSeconds: 180, increment: .pounds(20)),
        "ohp": SetPrescription(setCount: 3, targetRepsRange: 6...8, targetRIR: 2, restSeconds: 150, increment: .pounds(5)),
    ]
    
    var progressionPolicies: [String: ProgressionPolicyType] {
        // Mirror IronForge’s behavior: every lift uses double progression with per-exercise increments.
        func dp(for exId: String) -> ProgressionPolicyType {
            let rx = prescriptionsById[exId] ?? SetPrescription(setCount: 3, targetRepsRange: 6...8, targetRIR: 2, increment: .pounds(5))
            let cfg = DoubleProgressionConfig(
                sessionsAtTopBeforeIncrease: 1,
                loadIncrement: rx.increment,
                deloadPercentage: FailureThresholdDefaults.deloadPercentage,
                failuresBeforeDeload: FailureThresholdDefaults.failuresBeforeDeload
            )
            return .doubleProgression(config: cfg)
        }
        
        return [
            bench.id: dp(for: bench.id),
            row.id: dp(for: row.id),
            squat.id: dp(for: squat.id),
            rdl.id: dp(for: rdl.id),
            deadlift.id: dp(for: deadlift.id),
            ohp.id: dp(for: ohp.id),
        ]
    }
    
    func makeTemplates() -> SyntheticTemplates {
        func template(_ name: String, exercises: [Exercise]) -> WorkoutTemplate {
            let tes: [TemplateExercise] = exercises.enumerated().map { idx, ex in
                let rx = prescriptionsById[ex.id]!
                return TemplateExercise(exercise: ex, prescription: rx, order: idx)
            }
            return WorkoutTemplate(name: name, exercises: tes)
        }
        
        return SyntheticTemplates(
            cal1: template("CAL1", exercises: [squat, bench]),
            cal2: template("CAL2", exercises: [deadlift, ohp]),
            a: template("A", exercises: [bench, row]),
            b: template("B", exercises: [squat, rdl]),
            c: template("C", exercises: [deadlift, ohp])
        )
    }
    
    func exercise(forName name: String) -> Exercise? {
        switch name {
        case "Bench Press": return bench
        case "Barbell Row": return row
        case "Back Squat": return squat
        case "Romanian Deadlift": return rdl
        case "Deadlift": return deadlift
        case "Overhead Press": return ohp
        default: return nil
        }
    }
    
    func id(forExerciseName name: String) -> String {
        exercise(forName: name)?.id ?? name
    }
    
    func prescription(forExerciseName name: String) -> SetPrescription? {
        guard let ex = exercise(forName: name) else { return nil }
        return prescriptionsById[ex.id]
    }
    
    func order(forExerciseName name: String) -> Int {
        // Just provide a stable ordering for session results.
        switch name {
        case "Bench Press": return 0
        case "Barbell Row": return 1
        case "Back Squat": return 0
        case "Romanian Deadlift": return 1
        case "Deadlift": return 0
        case "Overhead Press": return 1
        default: return 0
        }
    }
    
    func makeUserProfile(
        userId: String,
        sex: BiologicalSex,
        trainingLevel: SyntheticTrainingLevel,
        bodyWeightLb: Double?
    ) -> UserProfile {
        let experience: ExperienceLevel = {
            switch trainingLevel {
            case .novice: return .beginner
            case .intermediate: return .intermediate
            case .advanced: return .advanced
            case .intermediateCut: return .intermediate
            }
        }()
        let goals: [TrainingGoal] = (trainingLevel == .intermediateCut) ? [.fatLoss] : [.hypertrophy]
        
        return UserProfile(
            id: userId,
            sex: sex,
            experience: experience,
            goals: goals,
            weeklyFrequency: 3,
            availableEquipment: .commercialGym,
            preferredUnit: .pounds,
            bodyWeight: bodyWeightLb.map { .pounds($0) }
        )
    }
}

// MARK: - Schedule + Tolerances

private enum SyntheticSchedule {
    static func sessionDate(startDate: Date, week: Int, workout: String, calendar: Calendar) -> Date {
        let base = calendar.date(byAdding: .day, value: week * 7, to: startDate) ?? startDate
        let offset: Int
        switch workout {
        case "CAL1": offset = 0
        case "CAL2": offset = 2
        case "A": offset = 0
        case "B": offset = 2
        case "C": offset = 4
        default: offset = 0
        }
        return calendar.date(byAdding: .day, value: offset, to: base) ?? base
    }
}

private enum SyntheticTolerances {
    static func loadToleranceLb(exerciseName: String, trainingLevel: SyntheticTrainingLevel) -> Double {
        // Plate-friendly tolerance:
        // - smaller for microloaded lifters/exercises
        // - larger for big barbell compounds
        switch exerciseName {
        case "Overhead Press":
            return 5
        case "Bench Press":
            return (trainingLevel == .advanced) ? 5 : 7.5
        case "Barbell Row":
            return 7.5
        case "Back Squat":
            return 10
        case "Romanian Deadlift":
            return 10
        case "Deadlift":
            return 12.5
        default:
            return 10
        }
    }
}

// MARK: - Week Signals

private struct WeekSignal: Hashable {
    let bodyWeightLb: Double?
    let readinessScore: Int
    let readinessHistory: [ReadinessRecord]
}

private enum SyntheticWeekSignals {
    static func from(exposures: [SyntheticExposure]) -> [String: [Int: WeekSignal]] {
        let byUser = Dictionary(grouping: exposures, by: \.userId)
        var out: [String: [Int: WeekSignal]] = [:]
        out.reserveCapacity(byUser.count)
        
        for (userId, rows) in byUser {
            let byWeek = Dictionary(grouping: rows, by: \.week)
            var weekMap: [Int: WeekSignal] = [:]
            weekMap.reserveCapacity(byWeek.count)
            
            // Choose a stable anchor for generating readiness history (used only for deload triggers).
            var cal = Calendar(identifier: .gregorian)
            cal.timeZone = TimeZone(secondsFromGMT: 0)!
            let startDate = cal.date(from: DateComponents(year: 2026, month: 1, day: 5, hour: 12))!
            
            for (week, weekRows) in byWeek {
                // Bodyweight is repeated per row; take the median (robust to small float drift).
                let weights = weekRows.compactMap(\.bodyWeightLb).sorted()
                let bw: Double? = {
                    guard !weights.isEmpty else { return nil }
                    return weights[weights.count / 2]
                }()
                
                // Readiness flag repeated; take the "most conservative" within week (LOW beats NORMAL beats HIGH).
                let flags = weekRows.map(\.readinessFlag)
                let flag: SyntheticReadinessFlag = {
                    if flags.contains(.low) { return .low }
                    if flags.contains(.normal) { return .normal }
                    return .high
                }()
                
                let score = flag.toScore()
                
                // Emit daily readiness records for this week window to allow deload triggers to operate.
                // Week 0 starts at startDate, then week N starts at startDate + 7*N.
                let weekStart = cal.date(byAdding: .day, value: week * 7, to: startDate) ?? startDate
                let daily: [ReadinessRecord] = (0..<7).compactMap { dayOffset in
                    guard let d = cal.date(byAdding: .day, value: dayOffset, to: weekStart) else { return nil }
                    return ReadinessRecord(date: d, score: score)
                }
                
                weekMap[week] = WeekSignal(bodyWeightLb: bw, readinessScore: score, readinessHistory: daily)
            }
            
            out[userId] = weekMap
        }
        
        return out
    }
}

// MARK: - CSV Types + Parser

private enum SyntheticTrainingLevel: String, Hashable {
    case novice
    case intermediate
    case advanced
    case intermediateCut = "intermediate_cut"
}

private enum SyntheticReadinessFlag: String, Hashable {
    case high = "HIGH"
    case normal = "NORMAL"
    case low = "LOW"
    
    func toScore() -> Int {
        // IMPORTANT: Keep "LOW" above deload threshold (50) so "low readiness"
        // drives holds/backoffs rather than hard deloads by default.
        switch self {
        case .high: return 85
        case .normal: return 75
        case .low: return 60
        }
    }
}

private enum SyntheticOutcome: String, Hashable {
    case cal = "CAL"
    case hit = "HIT"
    case stall = "STALL"
    case partial = "PARTIAL"
    case fail = "FAIL"
    case deload = "DELOAD"
    case skipped = "SKIPPED"
    case backoff = "BACKOFF"
    case overshoot = "OVERSHOOT"
    case hold = "HOLD"
    case reset = "RESET"
    case lowReadiness = "LOW_READINESS"
}

private struct SyntheticExposure: Hashable {
    let userId: String
    let name: String
    let sex: BiologicalSex
    let trainingLevel: SyntheticTrainingLevel
    
    let week: Int
    let workout: String
    let exerciseName: String
    
    let bodyWeightLb: Double?
    let sleepHrAvg: Double?
    let rhrBpmAvg: Int?
    let hrvRmssdMsAvg: Int?
    let readinessFlag: SyntheticReadinessFlag
    
    let set1LoadLb: Double?
    let set1Reps: Int?
    let set2LoadLb: Double?
    let set2Reps: Int?
    let set3LoadLb: Double?
    let set3Reps: Int?
    
    let outcome: SyntheticOutcome
    let notes: String?
    
    var isPerformed: Bool {
        outcome != .skipped && set1LoadLb != nil && set1Reps != nil
    }
    
    var workoutSortKey: Int {
        Self.workoutSortKeyStatic(workout)
    }
    
    static func workoutSortKeyStatic(_ workout: String) -> Int {
        switch workout {
        case "CAL1": return 0
        case "CAL2": return 1
        case "A": return 2
        case "B": return 3
        case "C": return 4
        default: return 99
        }
    }
}

private enum SyntheticCSV {
    static func parseAll(from csv: String) throws -> [SyntheticExposure] {
        let lines = csv
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        
        var out: [SyntheticExposure] = []
        out.reserveCapacity(lines.count)
        
        for line in lines {
            // Skip repeated header rows.
            if line.hasPrefix("user_id,") { continue }
            
            let fields = parseCSVLine(line)
            guard fields.count >= 19 else { continue }
            
            func s(_ i: Int) -> String { i < fields.count ? fields[i] : "" }
            func i(_ raw: String) -> Int? { Int(raw.trimmingCharacters(in: .whitespacesAndNewlines)) }
            func d(_ raw: String) -> Double? { Double(raw.trimmingCharacters(in: .whitespacesAndNewlines)) }
            func opt(_ raw: String) -> String? {
                let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                return t.isEmpty ? nil : t
            }
            
            let userId = s(0)
            let name = s(1)
            let sex: BiologicalSex = {
                switch s(2).lowercased() {
                case "male": return .male
                case "female": return .female
                default: return .other
                }
            }()
            let training = SyntheticTrainingLevel(rawValue: s(3)) ?? .intermediate
            
            let week = i(s(4)) ?? 0
            let workout = s(5)
            let exercise = s(6)
            
            let bw = d(s(7))
            let sleep = d(s(8))
            let rhr = i(s(9))
            let hrv = i(s(10))
            let readiness = SyntheticReadinessFlag(rawValue: s(11)) ?? .normal
            
            let set1Load = d(s(12))
            let set1Reps = i(s(13))
            let set2Load = d(s(14))
            let set2Reps = i(s(15))
            let set3Load = d(s(16))
            let set3Reps = i(s(17))
            
            let outcome = SyntheticOutcome(rawValue: s(18)) ?? .hit
            let notes = opt(s(19))
            
            out.append(SyntheticExposure(
                userId: userId,
                name: name,
                sex: sex,
                trainingLevel: training,
                week: week,
                workout: workout,
                exerciseName: exercise,
                bodyWeightLb: bw,
                sleepHrAvg: sleep,
                rhrBpmAvg: rhr,
                hrvRmssdMsAvg: hrv,
                readinessFlag: readiness,
                set1LoadLb: set1Load,
                set1Reps: set1Reps,
                set2LoadLb: set2Load,
                set2Reps: set2Reps,
                set3LoadLb: set3Load,
                set3Reps: set3Reps,
                outcome: outcome,
                notes: notes
            ))
        }
        
        return out
    }
    
    /// Minimal CSV parser that supports quoted fields and escaped quotes.
    private static func parseCSVLine(_ line: String) -> [String] {
        var fields: [String] = []
        fields.reserveCapacity(24)
        
        var current = ""
        current.reserveCapacity(line.count)
        
        var inQuotes = false
        var i = line.startIndex
        
        while i < line.endIndex {
            let ch = line[i]
            
            if ch == "\"" {
                // Double-quote escape inside a quoted string.
                let next = line.index(after: i)
                if inQuotes, next < line.endIndex, line[next] == "\"" {
                    current.append("\"")
                    i = line.index(after: next)
                    continue
                } else {
                    inQuotes.toggle()
                    i = next
                    continue
                }
            }
            
            if ch == ",", !inQuotes {
                fields.append(current)
                current = ""
                i = line.index(after: i)
                continue
            }
            
            current.append(ch)
            i = line.index(after: i)
        }
        
        fields.append(current)
        return fields
    }
}

// MARK: - Dataset Fixture

private let syntheticDatasetCSV = """
user_id,name,gender,training_level,week,workout,exercise,body_weight_lb,sleep_hr_avg,rhr_bpm_avg,hrv_rmssd_ms_avg,readiness,set1_load_lb,set1_reps,set2_load_lb,set2_reps,set3_load_lb,set3_reps,outcome,notes
U1,Leah,female,advanced,0,CAL1,Back Squat,100.0,7.8,54,78,HIGH,165.0,6,165.0,6,165.0,6,CAL,"Calibration exposure; estimate e1RM; target RIR~2."
U1,Leah,female,advanced,0,CAL1,Bench Press,100.0,7.8,54,78,HIGH,125.0,6,125.0,6,125.0,6,CAL,"Calibration exposure; estimate e1RM; target RIR~2."
U1,Leah,female,advanced,0,CAL2,Deadlift,100.0,7.8,54,78,HIGH,205.0,4,205.0,4,205.0,4,CAL,"Calibration exposure; estimate e1RM; target RIR~2."
U1,Leah,female,advanced,0,CAL2,Overhead Press,100.0,7.8,54,78,HIGH,70.0,6,70.0,6,70.0,6,CAL,"Calibration exposure; estimate e1RM; target RIR~2."
U1,Leah,female,advanced,1,A,Bench Press,100.0,7.8,54,78,HIGH,125.0,6,125.0,6,125.0,6,HIT,"RIR~2; microload strategy."
U1,Leah,female,advanced,1,A,Barbell Row,100.0,7.8,54,78,HIGH,95.0,8,95.0,8,95.0,8,HIT,
U1,Leah,female,advanced,1,B,Back Squat,100.0,7.8,54,78,HIGH,165.0,6,165.0,6,165.0,6,HIT,
U1,Leah,female,advanced,1,B,Romanian Deadlift,100.0,7.8,54,78,HIGH,115.0,8,115.0,8,115.0,8,HIT,
U1,Leah,female,advanced,1,C,Deadlift,100.0,7.8,54,78,HIGH,205.0,4,205.0,4,205.0,4,HIT,
U1,Leah,female,advanced,1,C,Overhead Press,100.0,7.8,54,78,HIGH,70.0,6,70.0,6,70.0,6,HIT,
U1,Leah,female,advanced,2,A,Bench Press,100.5,7.5,55,75,NORMAL,125.0,7,125.0,7,125.0,6,HIT,"Added reps within range (double progression)."
U1,Leah,female,advanced,2,A,Barbell Row,100.5,7.5,55,75,NORMAL,95.0,9,95.0,9,95.0,8,HIT,"Added reps; keep torso angle consistent."
U1,Leah,female,advanced,2,B,Back Squat,100.5,7.5,55,75,NORMAL,165.0,7,165.0,6,165.0,6,HIT,"Added 1 rep on set1; keep RIR~2."
U1,Leah,female,advanced,2,B,Romanian Deadlift,100.5,7.5,55,75,NORMAL,115.0,9,115.0,9,115.0,8,HIT,"Added reps."
U1,Leah,female,advanced,2,C,Deadlift,100.5,7.5,55,75,NORMAL,205.0,5,205.0,4,205.0,4,HIT,"Added rep on set1; keep bar speed."
U1,Leah,female,advanced,2,C,Overhead Press,100.5,7.5,55,75,NORMAL,70.0,7,70.0,6,70.0,6,HIT,"Added rep on set1."
U1,Leah,female,advanced,3,A,Bench Press,101.0,7.4,55,73,NORMAL,127.5,6,127.5,6,127.5,6,HIT,"Load +2.5 lb after exceeding target reps."
U1,Leah,female,advanced,3,A,Barbell Row,101.0,7.4,55,73,NORMAL,97.5,8,97.5,8,97.5,8,HIT,"Microload +2.5 lb."
U1,Leah,female,advanced,3,B,Back Squat,101.0,7.4,55,73,NORMAL,167.5,6,167.5,6,167.5,6,HIT,"Microload +2.5 lb."
U1,Leah,female,advanced,3,B,Romanian Deadlift,101.0,7.4,55,73,NORMAL,117.5,8,117.5,8,117.5,8,HIT,"Microload."
U1,Leah,female,advanced,3,C,Deadlift,101.0,7.4,55,73,NORMAL,210.0,4,210.0,4,210.0,4,HIT,"Load +5 lb."
U1,Leah,female,advanced,3,C,Overhead Press,101.0,7.4,55,73,NORMAL,72.5,6,72.5,6,72.5,6,HIT,"Microload."
U1,Leah,female,advanced,4,A,Bench Press,100.0,8.2,52,85,HIGH,112.5,6,112.5,6,112.5,6,DELOAD,"Planned deload: -10% load, focus technique."
U1,Leah,female,advanced,4,A,Barbell Row,100.0,8.2,52,85,HIGH,85.0,8,85.0,8,85.0,8,DELOAD,"Deload."
U1,Leah,female,advanced,4,B,Back Squat,100.0,8.2,52,85,HIGH,145.0,6,145.0,6,145.0,6,DELOAD,"Deload."
U1,Leah,female,advanced,4,B,Romanian Deadlift,100.0,8.2,52,85,HIGH,100.0,8,100.0,8,100.0,8,DELOAD,"Deload."
U1,Leah,female,advanced,4,C,Deadlift,100.0,8.2,52,85,HIGH,180.0,4,180.0,4,180.0,4,DELOAD,"Deload."
U1,Leah,female,advanced,4,C,Overhead Press,100.0,8.2,52,85,HIGH,62.5,6,62.5,6,62.5,6,DELOAD,"Deload."
U1,Leah,female,advanced,5,A,Bench Press,100.5,7.6,54,76,NORMAL,130.0,6,130.0,6,130.0,6,HIT,"New block, small PR from week3."
U1,Leah,female,advanced,5,A,Barbell Row,100.5,7.6,54,76,NORMAL,100.0,8,100.0,8,100.0,8,HIT,"New block."
U1,Leah,female,advanced,5,B,Back Squat,100.5,7.6,54,76,NORMAL,170.0,6,170.0,6,170.0,6,HIT,"New block."
U1,Leah,female,advanced,5,B,Romanian Deadlift,100.5,7.6,54,76,NORMAL,120.0,8,120.0,8,120.0,8,HIT,"New block."
U1,Leah,female,advanced,5,C,Deadlift,100.5,7.6,54,76,NORMAL,215.0,4,215.0,4,215.0,4,HIT,"New block."
U1,Leah,female,advanced,5,C,Overhead Press,100.5,7.6,54,76,NORMAL,75.0,6,75.0,6,75.0,6,HIT,"New block."
U1,Leah,female,advanced,6,A,Bench Press,100.2,6.5,57,60,LOW,132.5,6,132.5,5,132.5,5,STALL,"Fatigue: last two sets below target. Hold load next exposure."
U1,Leah,female,advanced,6,A,Barbell Row,100.2,6.5,57,60,LOW,102.5,8,102.5,7,102.5,7,STALL,"Grip fatigue limited reps."
U1,Leah,female,advanced,6,B,Back Squat,100.2,6.5,57,60,LOW,172.5,6,172.5,6,172.5,5,PARTIAL,"Set3 grindy (RIR~0-1). Keep load next week."
U1,Leah,female,advanced,6,B,Romanian Deadlift,100.2,6.5,57,60,LOW,122.5,8,122.5,8,122.5,7,PARTIAL,"Hamstring soreness: small rep drop on set3."
U1,Leah,female,advanced,6,C,Deadlift,100.2,6.5,57,60,LOW,220.0,4,220.0,3,220.0,3,STALL,"CNS fatigue: sets 2-3 dropped. Hold load."
U1,Leah,female,advanced,6,C,Overhead Press,100.2,6.5,57,60,LOW,77.5,6,77.5,5,77.5,5,STALL,"Stalled; keep load."
U1,Leah,female,advanced,7,A,Bench Press,100.8,7.1,56,68,LOW,132.5,6,132.5,6,132.5,5,PARTIAL,"Improving but not fully recovered. Hold load again."
U1,Leah,female,advanced,7,A,Barbell Row,100.8,7.1,56,68,LOW,102.5,8,102.5,8,102.5,7,PARTIAL,"Rep quality acceptable; continue holding load."
U1,Leah,female,advanced,7,B,Back Squat,100.8,7.1,56,68,LOW,172.5,6,172.5,6,172.5,6,HIT,"Recovered; hit all reps."
U1,Leah,female,advanced,7,B,Romanian Deadlift,100.8,7.1,56,68,LOW,122.5,9,122.5,8,122.5,8,HIT,"Adaptation: reps up at same load."
U1,Leah,female,advanced,7,C,Deadlift,100.8,7.1,56,68,LOW,220.0,4,220.0,4,220.0,3,PARTIAL,"Small improvement; hold again."
U1,Leah,female,advanced,7,C,Overhead Press,100.8,7.1,56,68,LOW,77.5,6,77.5,6,77.5,5,PARTIAL,"Partial progress; keep load."
U1,Leah,female,advanced,8,A,Bench Press,100.0,8.0,53,82,HIGH,117.5,6,117.5,6,117.5,6,DELOAD,"Second deload to manage cumulative fatigue."
U1,Leah,female,advanced,8,A,Barbell Row,100.0,8.0,53,82,HIGH,90.0,8,90.0,8,90.0,8,DELOAD,"Deload."
U1,Leah,female,advanced,8,B,Back Squat,100.0,8.0,53,82,HIGH,150.0,6,150.0,6,150.0,6,DELOAD,"Deload."
U1,Leah,female,advanced,8,B,Romanian Deadlift,100.0,8.0,53,82,HIGH,105.0,8,105.0,8,105.0,8,DELOAD,"Deload."
U1,Leah,female,advanced,8,C,Deadlift,100.0,8.0,53,82,HIGH,190.0,4,190.0,4,190.0,4,DELOAD,"Deload."
U1,Leah,female,advanced,8,C,Overhead Press,100.0,8.0,53,82,HIGH,65.0,6,65.0,6,65.0,6,DELOAD,"Deload."

user_id,name,gender,training_level,week,workout,exercise,body_weight_lb,sleep_hr_avg,rhr_bpm_avg,hrv_rmssd_ms_avg,readiness,set1_load_lb,set1_reps,set2_load_lb,set2_reps,set3_load_lb,set3_reps,outcome,notes
U2,Marcus,male,novice,0,CAL1,Back Squat,230.0,6.5,72,45,NORMAL,135.0,8,135.0,8,135.0,8,CAL,"Calibration exposure; estimate e1RM; target RIR~2."
U2,Marcus,male,novice,0,CAL1,Bench Press,230.0,6.5,72,45,NORMAL,95.0,8,95.0,8,95.0,8,CAL,"Calibration exposure; estimate e1RM; target RIR~2."
U2,Marcus,male,novice,0,CAL2,Deadlift,230.0,6.5,72,45,NORMAL,155.0,6,155.0,6,155.0,6,CAL,"Calibration exposure; estimate e1RM; target RIR~2."
U2,Marcus,male,novice,0,CAL2,Overhead Press,230.0,6.5,72,45,NORMAL,65.0,8,65.0,8,65.0,8,CAL,"Calibration exposure; estimate e1RM; target RIR~2."
U2,Marcus,male,novice,1,A,Bench Press,230.0,6.5,72,45,NORMAL,95.0,8,95.0,8,95.0,8,HIT,"Start conservative for technique (RIR~2)."
U2,Marcus,male,novice,1,A,Barbell Row,230.0,6.5,72,45,NORMAL,95.0,10,95.0,10,95.0,10,HIT,
U2,Marcus,male,novice,1,B,Back Squat,230.0,6.5,72,45,NORMAL,135.0,8,135.0,8,135.0,8,HIT,"Technique focus: depth and bracing."
U2,Marcus,male,novice,1,B,Romanian Deadlift,230.0,6.5,72,45,NORMAL,115.0,10,115.0,10,115.0,10,HIT,
U2,Marcus,male,novice,1,C,Deadlift,230.0,6.5,72,45,NORMAL,155.0,6,155.0,6,155.0,6,HIT,"Trap bar variant to reduce low-back fatigue."
U2,Marcus,male,novice,1,C,Overhead Press,230.0,6.5,72,45,NORMAL,65.0,8,65.0,8,65.0,8,HIT,
U2,Marcus,male,novice,2,A,Bench Press,231.0,6.7,71,47,NORMAL,100.0,8,100.0,8,100.0,7,HIT,"+5 lb after exceeding rep target (ACSM 2-10% rule)."
U2,Marcus,male,novice,2,A,Barbell Row,231.0,6.7,71,47,NORMAL,100.0,10,100.0,9,100.0,9,HIT,
U2,Marcus,male,novice,2,B,Back Squat,231.0,6.7,71,47,NORMAL,145.0,8,145.0,8,145.0,7,HIT,"+10 lb first jump (novice adaptation)."
U2,Marcus,male,novice,2,B,Romanian Deadlift,231.0,6.7,71,47,NORMAL,125.0,10,125.0,9,125.0,9,HIT,
U2,Marcus,male,novice,2,C,Deadlift,231.0,6.7,71,47,NORMAL,175.0,6,175.0,6,175.0,5,HIT,"+20 lb early jump; bar speed acceptable."
U2,Marcus,male,novice,2,C,Overhead Press,231.0,6.7,71,47,NORMAL,70.0,8,70.0,8,70.0,7,HIT,
U2,Marcus,male,novice,3,A,Bench Press,232.0,6.0,75,38,LOW,105.0,7,105.0,7,105.0,6,HIT,"Approaching limit: reps down but within range."
U2,Marcus,male,novice,3,A,Barbell Row,232.0,6.0,75,38,LOW,105.0,9,105.0,9,105.0,8,HIT,"Grip limiting. Keep strict."
U2,Marcus,male,novice,3,B,Back Squat,232.0,6.0,75,38,LOW,155.0,8,155.0,7,155.0,6,HIT,"+10 lb; fatigue shows in later sets."
U2,Marcus,male,novice,3,B,Romanian Deadlift,232.0,6.0,75,38,LOW,135.0,9,135.0,9,135.0,8,HIT,
U2,Marcus,male,novice,3,C,Deadlift,232.0,6.0,75,38,LOW,185.0,6,185.0,5,185.0,5,HIT,"+10 lb; keep RIR~1-2."
U2,Marcus,male,novice,3,C,Overhead Press,232.0,6.0,75,38,LOW,75.0,7,75.0,7,75.0,6,HIT,
U2,Marcus,male,novice,4,A,Bench Press,231.0,7.8,69,55,HIGH,90.0,8,90.0,8,90.0,8,DELOAD,"Deload for knee soreness and fatigue."
U2,Marcus,male,novice,4,A,Barbell Row,231.0,7.8,69,55,HIGH,90.0,10,90.0,10,90.0,10,DELOAD,"Deload."
U2,Marcus,male,novice,4,B,Back Squat,231.0,7.8,69,55,HIGH,135.0,6,135.0,6,135.0,6,DELOAD,"Deload: cut load and reps, practice form."
U2,Marcus,male,novice,4,B,Romanian Deadlift,231.0,7.8,69,55,HIGH,115.0,8,115.0,8,115.0,8,DELOAD,"Deload."
U2,Marcus,male,novice,4,C,Deadlift,231.0,7.8,69,55,HIGH,155.0,5,155.0,5,155.0,5,DELOAD,"Deload."
U2,Marcus,male,novice,4,C,Overhead Press,231.0,7.8,69,55,HIGH,60.0,8,60.0,8,60.0,8,DELOAD,"Deload."
U2,Marcus,male,novice,5,A,Bench Press,232.0,6.8,71,46,NORMAL,105.0,8,105.0,8,105.0,7,HIT,"Post-deload rebound, repeat week3 load with higher reps."
U2,Marcus,male,novice,5,A,Barbell Row,232.0,6.8,71,46,NORMAL,105.0,10,105.0,10,105.0,9,HIT,
U2,Marcus,male,novice,5,B,Back Squat,232.0,6.8,71,46,NORMAL,155.0,8,155.0,8,155.0,7,HIT,"Back to week3 load with better reps."
U2,Marcus,male,novice,5,B,Romanian Deadlift,232.0,6.8,71,46,NORMAL,135.0,10,135.0,9,135.0,9,HIT,
U2,Marcus,male,novice,5,C,Deadlift,232.0,6.8,71,46,NORMAL,185.0,6,185.0,6,185.0,5,HIT,"Return to week3 load with better reps."
U2,Marcus,male,novice,5,C,Overhead Press,232.0,6.8,71,46,NORMAL,75.0,8,75.0,8,75.0,7,HIT,
U2,Marcus,male,novice,6,A,Bench Press,233.0,6.6,72,44,NORMAL,110.0,7,110.0,7,110.0,6,HIT,"+5 lb, still within target."
U2,Marcus,male,novice,6,A,Barbell Row,233.0,6.6,72,44,NORMAL,110.0,9,110.0,9,110.0,8,HIT,
U2,Marcus,male,novice,6,B,Back Squat,233.0,6.6,72,44,NORMAL,165.0,7,165.0,7,165.0,6,HIT,"+10 lb; still in range."
U2,Marcus,male,novice,6,B,Romanian Deadlift,233.0,6.6,72,44,NORMAL,145.0,9,145.0,9,145.0,8,HIT,
U2,Marcus,male,novice,6,C,Deadlift,233.0,6.6,72,44,NORMAL,195.0,6,195.0,5,195.0,5,HIT,"+10 lb."
U2,Marcus,male,novice,6,C,Overhead Press,233.0,6.6,72,44,NORMAL,80.0,7,80.0,7,80.0,6,HIT,
U2,Marcus,male,novice,7,A,Bench Press,233.0,5.8,76,35,LOW,110.0,8,110.0,7,110.0,7,HOLD,"Sleep debt: hold load to protect shoulder."
U2,Marcus,male,novice,7,A,Barbell Row,233.0,5.8,76,35,LOW,110.0,10,110.0,9,110.0,9,HIT,
U2,Marcus,male,novice,7,B,Back Squat,233.0,5.8,76,35,LOW,170.0,6,170.0,6,170.0,5,OVERSHOOT,"Too aggressive: reps near failure. Repeat or back-off next week."
U2,Marcus,male,novice,7,B,Romanian Deadlift,233.0,5.8,76,35,LOW,145.0,10,145.0,9,145.0,9,HIT,
U2,Marcus,male,novice,7,C,Deadlift,233.0,5.8,76,35,LOW,195.0,6,195.0,6,195.0,5,HIT,"Hold load for technique consistency."
U2,Marcus,male,novice,7,C,Overhead Press,233.0,5.8,76,35,LOW,80.0,8,80.0,7,80.0,7,HIT,
U2,Marcus,male,novice,8,A,Bench Press,233.5,6.4,73,42,NORMAL,115.0,7,115.0,7,115.0,6,HIT,"+5 lb, reps stable."
U2,Marcus,male,novice,8,A,Barbell Row,233.5,6.4,73,42,NORMAL,115.0,9,115.0,9,115.0,8,HIT,
U2,Marcus,male,novice,8,B,Back Squat,233.5,6.4,73,42,NORMAL,170.0,7,170.0,6,170.0,6,HIT,"Held load and improved reps."
U2,Marcus,male,novice,8,B,Romanian Deadlift,233.5,6.4,73,42,NORMAL,155.0,9,155.0,9,155.0,8,HIT,
U2,Marcus,male,novice,8,C,Deadlift,233.5,6.4,73,42,NORMAL,205.0,5,205.0,5,205.0,5,HIT,"+10 lb; reps at low end of range."
U2,Marcus,male,novice,8,C,Overhead Press,233.5,6.4,73,42,NORMAL,85.0,6,85.0,6,85.0,6,HIT,"Reps fell to low end; hold next week if extending past 8 weeks."

user_id,name,gender,training_level,week,workout,exercise,body_weight_lb,sleep_hr_avg,rhr_bpm_avg,hrv_rmssd_ms_avg,readiness,set1_load_lb,set1_reps,set2_load_lb,set2_reps,set3_load_lb,set3_reps,outcome,notes
U3,Alex,nonbinary,intermediate,0,CAL1,Back Squat,165.0,7.2,62,55,NORMAL,185.0,6,185.0,6,185.0,6,CAL,"Calibration exposure; estimate e1RM; target RIR~2."
U3,Alex,nonbinary,intermediate,0,CAL1,Bench Press,165.0,7.2,62,55,NORMAL,145.0,6,145.0,6,145.0,6,CAL,"Calibration exposure; estimate e1RM; target RIR~2."
U3,Alex,nonbinary,intermediate,0,CAL2,Deadlift,165.0,7.2,62,55,NORMAL,225.0,4,225.0,4,225.0,4,CAL,"Calibration exposure; estimate e1RM; target RIR~2."
U3,Alex,nonbinary,intermediate,0,CAL2,Overhead Press,165.0,7.2,62,55,NORMAL,95.0,6,95.0,6,95.0,6,CAL,"Calibration exposure; estimate e1RM; target RIR~2."
U3,Alex,nonbinary,intermediate,1,A,Bench Press,165.0,7.2,62,55,NORMAL,145.0,6,145.0,6,145.0,6,HIT,"Baseline week, RIR~2."
U3,Alex,nonbinary,intermediate,1,A,Barbell Row,165.0,7.2,62,55,NORMAL,115.0,8,115.0,8,115.0,8,HIT,
U3,Alex,nonbinary,intermediate,1,B,Back Squat,165.0,7.2,62,55,NORMAL,185.0,6,185.0,6,185.0,6,HIT,
U3,Alex,nonbinary,intermediate,1,B,Romanian Deadlift,165.0,7.2,62,55,NORMAL,135.0,8,135.0,8,135.0,8,HIT,
U3,Alex,nonbinary,intermediate,1,C,Deadlift,165.0,7.2,62,55,NORMAL,225.0,4,225.0,4,225.0,4,HIT,
U3,Alex,nonbinary,intermediate,1,C,Overhead Press,165.0,7.2,62,55,NORMAL,95.0,6,95.0,6,95.0,6,HIT,
U3,Alex,nonbinary,intermediate,2,A,Bench Press,165.2,5.5,68,40,LOW,147.5,6,147.5,6,147.5,5,PARTIAL,"Sleep low, reps drop. Repeat load next week."
U3,Alex,nonbinary,intermediate,2,A,Barbell Row,165.2,5.5,68,40,LOW,117.5,8,117.5,8,117.5,7,PARTIAL,
U3,Alex,nonbinary,intermediate,2,B,Back Squat,165.2,5.5,68,40,LOW,,,,,,SKIPPED,"Session skipped (travel/illness)."
U3,Alex,nonbinary,intermediate,2,B,Romanian Deadlift,165.2,5.5,68,40,LOW,,,,,,SKIPPED,"Session skipped (travel/illness)."
U3,Alex,nonbinary,intermediate,2,C,Deadlift,165.2,5.5,68,40,LOW,230.0,4,230.0,4,230.0,3,PARTIAL,"Technique drift; stopped 1 rep short to avoid breakdown."
U3,Alex,nonbinary,intermediate,2,C,Overhead Press,165.2,5.5,68,40,LOW,97.5,6,97.5,5,97.5,5,PARTIAL,
U3,Alex,nonbinary,intermediate,3,A,Bench Press,164.8,6.8,64,50,NORMAL,147.5,6,147.5,6,147.5,6,HIT,"Recovered slightly, completed reps."
U3,Alex,nonbinary,intermediate,3,A,Barbell Row,164.8,6.8,64,50,NORMAL,117.5,9,117.5,8,117.5,8,HIT,
U3,Alex,nonbinary,intermediate,3,B,Back Squat,164.8,6.8,64,50,NORMAL,185.0,7,185.0,6,185.0,6,HIT,"Returned after missed week; kept load and added reps."
U3,Alex,nonbinary,intermediate,3,B,Romanian Deadlift,164.8,6.8,64,50,NORMAL,135.0,9,135.0,8,135.0,8,HIT,
U3,Alex,nonbinary,intermediate,3,C,Deadlift,164.8,6.8,64,50,NORMAL,230.0,4,230.0,4,230.0,4,HIT,
U3,Alex,nonbinary,intermediate,3,C,Overhead Press,164.8,6.8,64,50,NORMAL,97.5,6,97.5,6,97.5,5,PARTIAL,
U3,Alex,nonbinary,intermediate,4,A,Bench Press,165.0,7.9,58,65,HIGH,130.0,6,130.0,6,130.0,6,DELOAD,"Deload week."
U3,Alex,nonbinary,intermediate,4,A,Barbell Row,165.0,7.9,58,65,HIGH,102.5,8,102.5,8,102.5,8,DELOAD,"Deload."
U3,Alex,nonbinary,intermediate,4,B,Back Squat,165.0,7.9,58,65,HIGH,165.0,6,165.0,6,165.0,6,DELOAD,"Deload."
U3,Alex,nonbinary,intermediate,4,B,Romanian Deadlift,165.0,7.9,58,65,HIGH,120.0,8,120.0,8,120.0,8,DELOAD,"Deload."
U3,Alex,nonbinary,intermediate,4,C,Deadlift,165.0,7.9,58,65,HIGH,200.0,4,200.0,4,200.0,4,DELOAD,"Deload."
U3,Alex,nonbinary,intermediate,4,C,Overhead Press,165.0,7.9,58,65,HIGH,85.0,6,85.0,6,85.0,6,DELOAD,"Deload."
U3,Alex,nonbinary,intermediate,5,A,Bench Press,165.5,6.2,65,45,LOW,150.0,6,150.0,5,150.0,5,STALL,"High stress: stalled. Hold load."
U3,Alex,nonbinary,intermediate,5,A,Barbell Row,165.5,6.2,65,45,LOW,120.0,8,120.0,8,120.0,7,HIT,
U3,Alex,nonbinary,intermediate,5,B,Back Squat,165.5,6.2,65,45,LOW,190.0,6,190.0,6,190.0,5,PARTIAL,"Set3 short; hold load."
U3,Alex,nonbinary,intermediate,5,B,Romanian Deadlift,165.5,6.2,65,45,LOW,140.0,8,140.0,8,140.0,7,PARTIAL,
U3,Alex,nonbinary,intermediate,5,C,Deadlift,165.5,6.2,65,45,LOW,235.0,4,235.0,3,235.0,3,STALL,"Stalled. Hold and improve positioning."
U3,Alex,nonbinary,intermediate,5,C,Overhead Press,165.5,6.2,65,45,LOW,100.0,5,100.0,5,100.0,4,FAIL,"Stress week: missed minimum reps."
U3,Alex,nonbinary,intermediate,6,A,Bench Press,165.0,6.5,63,52,NORMAL,150.0,6,150.0,6,150.0,5,PARTIAL,"Partial progress at same load."
U3,Alex,nonbinary,intermediate,6,A,Barbell Row,165.0,6.5,63,52,NORMAL,120.0,9,120.0,8,120.0,8,HIT,
U3,Alex,nonbinary,intermediate,6,B,Back Squat,165.0,6.5,63,52,NORMAL,190.0,7,190.0,6,190.0,6,HIT,"Improving."
U3,Alex,nonbinary,intermediate,6,B,Romanian Deadlift,165.0,6.5,63,52,NORMAL,140.0,9,140.0,8,140.0,8,HIT,
U3,Alex,nonbinary,intermediate,6,C,Deadlift,165.0,6.5,63,52,NORMAL,235.0,4,235.0,4,235.0,3,PARTIAL,"Partial improvement."
U3,Alex,nonbinary,intermediate,6,C,Overhead Press,165.0,6.5,63,52,NORMAL,97.5,6,97.5,6,97.5,5,RESET,"Back-off 2.5% and rebuild."
U3,Alex,nonbinary,intermediate,7,A,Bench Press,164.5,5.2,70,35,LOW,152.5,5,152.5,5,152.5,4,FAIL,"Missed minimum reps on set3. Back-off recommended."
U3,Alex,nonbinary,intermediate,7,A,Barbell Row,164.5,5.2,70,35,LOW,122.5,8,122.5,7,122.5,7,STALL,"Grip and low back fatigue. Hold or reduce."
U3,Alex,nonbinary,intermediate,7,B,Back Squat,164.5,5.2,70,35,LOW,195.0,6,195.0,5,195.0,5,STALL,"Fatigue. Consider reducing 2.5-5%."
U3,Alex,nonbinary,intermediate,7,B,Romanian Deadlift,164.5,5.2,70,35,LOW,145.0,8,145.0,7,145.0,7,STALL,
U3,Alex,nonbinary,intermediate,7,C,Deadlift,164.5,5.2,70,35,LOW,240.0,3,240.0,3,240.0,3,FAIL,"Failed reps; reduce load and rebuild."
U3,Alex,nonbinary,intermediate,7,C,Overhead Press,164.5,5.2,70,35,LOW,100.0,5,100.0,5,100.0,5,HIT,"Regained."
U3,Alex,nonbinary,intermediate,8,A,Bench Press,165.0,7.6,60,60,HIGH,145.0,6,145.0,6,145.0,6,RESET,"Back-off ~5% and rebuild reps."
U3,Alex,nonbinary,intermediate,8,A,Barbell Row,165.0,7.6,60,60,HIGH,115.0,9,115.0,9,115.0,8,RESET,"Back-off and add reps."
U3,Alex,nonbinary,intermediate,8,B,Back Squat,165.0,7.6,60,60,HIGH,187.5,6,187.5,6,187.5,6,RESET,"Back-off after plateau."
U3,Alex,nonbinary,intermediate,8,B,Romanian Deadlift,165.0,7.6,60,60,HIGH,135.0,9,135.0,9,135.0,8,RESET,
U3,Alex,nonbinary,intermediate,8,C,Deadlift,165.0,7.6,60,60,HIGH,225.0,4,225.0,4,225.0,4,RESET,"Back-off to week1 load and focus bar speed."
U3,Alex,nonbinary,intermediate,8,C,Overhead Press,165.0,7.6,60,60,HIGH,95.0,6,95.0,6,95.0,6,RESET,"Keep here until reps increase."

user_id,name,gender,training_level,week,workout,exercise,body_weight_lb,sleep_hr_avg,rhr_bpm_avg,hrv_rmssd_ms_avg,readiness,set1_load_lb,set1_reps,set2_load_lb,set2_reps,set3_load_lb,set3_reps,outcome,notes
U4,Sofia,female,intermediate_cut,0,CAL1,Back Squat,145.0,7.0,64,52,NORMAL,135.0,8,135.0,8,135.0,8,CAL,"Calibration exposure; estimate e1RM; target RIR~2."
U4,Sofia,female,intermediate_cut,0,CAL1,Bench Press,145.0,7.0,64,52,NORMAL,95.0,8,95.0,8,95.0,8,CAL,"Calibration exposure; estimate e1RM; target RIR~2."
U4,Sofia,female,intermediate_cut,0,CAL2,Deadlift,145.0,7.0,64,52,NORMAL,165.0,6,165.0,6,165.0,6,CAL,"Calibration exposure; estimate e1RM; target RIR~2."
U4,Sofia,female,intermediate_cut,0,CAL2,Overhead Press,145.0,7.0,64,52,NORMAL,55.0,8,55.0,8,55.0,8,CAL,"Calibration exposure; estimate e1RM; target RIR~2."
U4,Sofia,female,intermediate_cut,1,A,Bench Press,145.0,7.0,64,52,NORMAL,95.0,8,95.0,8,95.0,8,HIT,"Baseline week, RIR~2."
U4,Sofia,female,intermediate_cut,1,A,Barbell Row,145.0,7.0,64,52,NORMAL,80.0,10,80.0,10,80.0,10,HIT,
U4,Sofia,female,intermediate_cut,1,B,Back Squat,145.0,7.0,64,52,NORMAL,135.0,8,135.0,8,135.0,8,HIT,
U4,Sofia,female,intermediate_cut,1,B,Romanian Deadlift,145.0,7.0,64,52,NORMAL,115.0,10,115.0,10,115.0,10,HIT,
U4,Sofia,female,intermediate_cut,1,C,Deadlift,145.0,7.0,64,52,NORMAL,165.0,6,165.0,6,165.0,6,HIT,
U4,Sofia,female,intermediate_cut,1,C,Overhead Press,145.0,7.0,64,52,NORMAL,55.0,8,55.0,8,55.0,8,HIT,
U4,Sofia,female,intermediate_cut,2,A,Bench Press,144.0,6.9,65,50,NORMAL,97.5,8,97.5,8,97.5,7,HIT,"Microload +2.5 lb."
U4,Sofia,female,intermediate_cut,2,A,Barbell Row,144.0,6.9,65,50,NORMAL,85.0,10,85.0,9,85.0,9,HIT,
U4,Sofia,female,intermediate_cut,2,B,Back Squat,144.0,6.9,65,50,NORMAL,140.0,8,140.0,7,140.0,7,HIT,"+5 lb."
U4,Sofia,female,intermediate_cut,2,B,Romanian Deadlift,144.0,6.9,65,50,NORMAL,120.0,10,120.0,9,120.0,9,HIT,
U4,Sofia,female,intermediate_cut,2,C,Deadlift,144.0,6.9,65,50,NORMAL,170.0,6,170.0,6,170.0,5,HIT,"+5 lb."
U4,Sofia,female,intermediate_cut,2,C,Overhead Press,144.0,6.9,65,50,NORMAL,57.5,8,57.5,8,57.5,7,HIT,"+2.5 lb."
U4,Sofia,female,intermediate_cut,3,A,Bench Press,143.0,6.8,66,48,NORMAL,100.0,7,100.0,7,100.0,6,HIT,"Load +2.5 lb; reps at low end but within range."
U4,Sofia,female,intermediate_cut,3,A,Barbell Row,143.0,6.8,66,48,NORMAL,85.0,10,85.0,10,85.0,9,HIT,
U4,Sofia,female,intermediate_cut,3,B,Back Squat,143.0,6.8,66,48,NORMAL,145.0,7,145.0,7,145.0,6,HIT,"+5 lb."
U4,Sofia,female,intermediate_cut,3,B,Romanian Deadlift,143.0,6.8,66,48,NORMAL,125.0,9,125.0,9,125.0,8,HIT,
U4,Sofia,female,intermediate_cut,3,C,Deadlift,143.0,6.8,66,48,NORMAL,175.0,6,175.0,5,175.0,5,HIT,"+5 lb; reps down slightly."
U4,Sofia,female,intermediate_cut,3,C,Overhead Press,143.0,6.8,66,48,NORMAL,60.0,7,60.0,7,60.0,6,HIT,"+2.5 lb."
U4,Sofia,female,intermediate_cut,4,A,Bench Press,142.0,7.8,61,60,HIGH,87.5,8,87.5,8,87.5,8,DELOAD,"Deload."
U4,Sofia,female,intermediate_cut,4,A,Barbell Row,142.0,7.8,61,60,HIGH,75.0,10,75.0,10,75.0,10,DELOAD,"Deload."
U4,Sofia,female,intermediate_cut,4,B,Back Squat,142.0,7.8,61,60,HIGH,120.0,8,120.0,8,120.0,8,DELOAD,"Deload."
U4,Sofia,female,intermediate_cut,4,B,Romanian Deadlift,142.0,7.8,61,60,HIGH,105.0,10,105.0,10,105.0,10,DELOAD,"Deload."
U4,Sofia,female,intermediate_cut,4,C,Deadlift,142.0,7.8,61,60,HIGH,150.0,6,150.0,6,150.0,6,DELOAD,"Deload."
U4,Sofia,female,intermediate_cut,4,C,Overhead Press,142.0,7.8,61,60,HIGH,50.0,8,50.0,8,50.0,8,DELOAD,"Deload."
U4,Sofia,female,intermediate_cut,5,A,Bench Press,141.0,6.7,66,47,LOW,100.0,8,100.0,7,100.0,7,HIT,"Post-deload rebound; still cutting so keep jumps small."
U4,Sofia,female,intermediate_cut,5,A,Barbell Row,141.0,6.7,66,47,LOW,87.5,10,87.5,9,87.5,9,HIT,
U4,Sofia,female,intermediate_cut,5,B,Back Squat,141.0,6.7,66,47,LOW,145.0,8,145.0,7,145.0,7,HIT,"Regained week3 load after deload."
U4,Sofia,female,intermediate_cut,5,B,Romanian Deadlift,141.0,6.7,66,47,LOW,125.0,10,125.0,9,125.0,9,HIT,
U4,Sofia,female,intermediate_cut,5,C,Deadlift,141.0,6.7,66,47,LOW,175.0,6,175.0,6,175.0,5,HIT,"Regained week3 load after deload."
U4,Sofia,female,intermediate_cut,5,C,Overhead Press,141.0,6.7,66,47,LOW,60.0,8,60.0,7,60.0,7,HIT,
U4,Sofia,female,intermediate_cut,6,A,Bench Press,140.0,6.2,69,40,LOW,100.0,7,100.0,7,100.0,6,LOW_READINESS,"Low readiness signals (sleep/HRV): hold load."
U4,Sofia,female,intermediate_cut,6,A,Barbell Row,140.0,6.2,69,40,LOW,87.5,9,87.5,9,87.5,8,LOW_READINESS,"Grip fatigue; keep strict."
U4,Sofia,female,intermediate_cut,6,B,Back Squat,140.0,6.2,69,40,LOW,145.0,7,145.0,6,145.0,6,LOW_READINESS,"Low readiness: keep load, accept lower reps."
U4,Sofia,female,intermediate_cut,6,B,Romanian Deadlift,140.0,6.2,69,40,LOW,125.0,9,125.0,8,125.0,8,LOW_READINESS,
U4,Sofia,female,intermediate_cut,6,C,Deadlift,140.0,6.2,69,40,LOW,175.0,5,175.0,5,175.0,5,LOW_READINESS,"Deficit fatigue: reps at minimum, hold load."
U4,Sofia,female,intermediate_cut,6,C,Overhead Press,140.0,6.2,69,40,LOW,57.5,8,57.5,7,57.5,7,BACKOFF,"Back-off due to shoulder tightness and low HRV."
U4,Sofia,female,intermediate_cut,7,A,Bench Press,139.0,6.5,68,42,LOW,97.5,8,97.5,8,97.5,7,BACKOFF,"Back-off 2.5 lb to keep reps in range while losing BW."
U4,Sofia,female,intermediate_cut,7,A,Barbell Row,139.0,6.5,68,42,LOW,85.0,10,85.0,9,85.0,9,BACKOFF,"Slight back-off."
U4,Sofia,female,intermediate_cut,7,B,Back Squat,139.0,6.5,68,42,LOW,140.0,8,140.0,7,140.0,7,BACKOFF,"Back-off to protect recovery during deficit."
U4,Sofia,female,intermediate_cut,7,B,Romanian Deadlift,139.0,6.5,68,42,LOW,120.0,10,120.0,9,120.0,9,BACKOFF,
U4,Sofia,female,intermediate_cut,7,C,Deadlift,139.0,6.5,68,42,LOW,170.0,6,170.0,6,170.0,5,BACKOFF,"Back-off to maintain bar speed."
U4,Sofia,female,intermediate_cut,7,C,Overhead Press,139.0,6.5,68,42,LOW,57.5,8,57.5,8,57.5,7,HIT,"Recovered."
U4,Sofia,female,intermediate_cut,8,A,Bench Press,138.0,7.4,64,55,HIGH,100.0,7,100.0,7,100.0,6,HIT,"Return to 100 lb; stable strength."
U4,Sofia,female,intermediate_cut,8,A,Barbell Row,138.0,7.4,64,55,HIGH,87.5,9,87.5,9,87.5,9,HIT,
U4,Sofia,female,intermediate_cut,8,B,Back Squat,138.0,7.4,64,55,HIGH,145.0,7,145.0,7,145.0,6,HIT,"Return to 145 with stable reps."
U4,Sofia,female,intermediate_cut,8,B,Romanian Deadlift,138.0,7.4,64,55,HIGH,125.0,9,125.0,9,125.0,8,HIT,
U4,Sofia,female,intermediate_cut,8,C,Deadlift,138.0,7.4,64,55,HIGH,175.0,5,175.0,5,175.0,5,HIT,"Return to 175; still close to limit so hold if extending."
U4,Sofia,female,intermediate_cut,8,C,Overhead Press,138.0,7.4,64,55,HIGH,60.0,7,60.0,7,60.0,6,HIT,
"""

