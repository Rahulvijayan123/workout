import Foundation
import CryptoKit
import TrainingEngine

// MARK: - TrainingEngine Type Aliases
// Now that the TrainingEngine enum is renamed to `Engine`, we can use TrainingEngine.Type
// to access module-level types without shadowing issues.
typealias TEEquipment = TrainingEngine.Equipment
typealias TEMuscleGroup = TrainingEngine.MuscleGroup
typealias TEMovementPattern = TrainingEngine.MovementPattern
typealias TEExercise = TrainingEngine.Exercise
typealias TEBiologicalSex = TrainingEngine.BiologicalSex
typealias TEExperienceLevel = TrainingEngine.ExperienceLevel
typealias TETrainingGoal = TrainingEngine.TrainingGoal
typealias TEEquipmentAvailability = TrainingEngine.EquipmentAvailability
typealias TEUserProfile = TrainingEngine.UserProfile
typealias TESetPrescription = TrainingEngine.SetPrescription
typealias TETemplateExercise = TrainingEngine.TemplateExercise
typealias TEWorkoutTemplate = TrainingEngine.WorkoutTemplate
typealias TEProgressionPolicyType = TrainingEngine.ProgressionPolicyType
typealias TETrainingPlan = TrainingEngine.TrainingPlan
typealias TELiftState = TrainingEngine.LiftState
typealias TEWorkoutHistory = TrainingEngine.WorkoutHistory
typealias TESessionPlan = TrainingEngine.SessionPlan
typealias TECompletedSession = TrainingEngine.CompletedSession
typealias TESetResult = TrainingEngine.SetResult
typealias TEExerciseSessionResult = TrainingEngine.ExerciseSessionResult
typealias TELoad = TrainingEngine.Load
typealias TEScheduleType = TrainingEngine.ScheduleType
typealias TEDoubleProgressionConfig = TrainingEngine.DoubleProgressionConfig
typealias TEExercisePlan = TrainingEngine.ExercisePlan
typealias TETempo = TrainingEngine.Tempo
typealias TEReadinessRecord = TrainingEngine.ReadinessRecord

// MARK: - TrainingEngineBridge
/// Bridges IronForge UI models to TrainingEngine domain models.
/// This keeps `import TrainingEngine` contained and handles all type conversions.
enum TrainingEngineBridge {
    
    // MARK: - Deterministic IDs (ML join keys)
    
    /// Generates a deterministic UUID from a namespace UUID + name string.
    ///
    /// Used for ML join keys that must be stable if the same plan is materialized
    /// multiple times (e.g. UI rebuilds, retries).
    private static func deterministicUUID(namespace: UUID, name: String) -> UUID {
        var data = Data()
        var ns = namespace.uuid
        withUnsafeBytes(of: &ns) { data.append(contentsOf: $0) }
        data.append(contentsOf: name.utf8)
        
        let digest = SHA256.hash(data: data)
        var bytes = Array(digest.prefix(16))
        
        // Set RFC 4122 variant + a "name-based" version nibble (v5-style).
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
    
    // MARK: - Equipment Mapping
    
    static func mapEquipment(_ equipment: String) -> TEEquipment {
        let normalized = equipment.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        switch normalized {
        case "barbell":
            return .barbell
        case "dumbbell", "dumbbells":
            return .dumbbell
        case "kettlebell", "kettlebells":
            return .kettlebell
        case "cable", "cables":
            return .cable
        case "machine":
            return .machine
        case "smith machine":
            return .smithMachine
        case "body weight", "body only", "bodyweight", "none", "":
            return .bodyweight
        case "resistance band", "band", "bands":
            return .resistanceBand
        case "ez bar", "e-z curl bar":
            return .ezBar
        case "trap bar":
            return .trapBar
        case "landmine":
            return .landmine
        case "suspension trainer", "trx":
            return .suspensionTrainer
        case "medicine ball":
            return .medicineBall
        case "stability ball", "exercise ball":
            return .medicineBall
        case "pull up bar", "pull-up bar":
            return .pullUpBar
        case "dip station":
            return .dipStation
        case "bench":
            return .bench
        default:
            return .unknown
        }
    }
    
    // MARK: - Muscle Group Mapping
    
    static func mapMuscleGroup(_ muscle: String) -> TEMuscleGroup {
        let normalized = muscle.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        switch normalized {
        case "chest", "pectorals", "pecs":
            return .chest
        case "back", "mid back", "middle back":
            return .back
        case "shoulders", "delts", "deltoids":
            return .shoulders
        case "biceps":
            return .biceps
        case "triceps":
            return .triceps
        case "forearms":
            return .forearms
        case "quadriceps", "quads":
            return .quadriceps
        case "hamstrings":
            return .hamstrings
        case "glutes", "gluteus":
            return .glutes
        case "calves":
            return .calves
        case "abdominals", "abs", "core":
            return .abdominals
        case "obliques":
            return .obliques
        case "lower back", "erector spinae":
            return .lowerBack
        case "traps", "trapezius":
            return .traps
        case "lats", "latissimus dorsi":
            return .lats
        case "rhomboids":
            return .rhomboids
        case "rear delts", "rear deltoids", "posterior deltoid":
            return .rearDelts
        case "front delts", "front deltoids", "anterior deltoid":
            return .frontDelts
        case "side delts", "lateral deltoid":
            return .sideDelts
        case "hip flexors":
            return .hipFlexors
        case "adductors":
            return .adductors
        case "abductors":
            return .abductors
        case "rotator cuff":
            return .rotatorCuff
        case "neck":
            return .neck
        default:
            return .unknown
        }
    }
    
    // MARK: - Movement Pattern Inference
    
    static func inferMovementPattern(from exerciseName: String, equipment: String, target: String) -> TEMovementPattern {
        let name = exerciseName.lowercased()
        _ = equipment.lowercased() // Equipment might be used for more specific inference in the future
        let tgt = target.lowercased()
        
        // Compound movements
        if name.contains("bench press") || name.contains("chest press") {
            return .horizontalPush
        }
        if name.contains("overhead press") || name.contains("shoulder press") || name.contains("military press") {
            return .verticalPush
        }
        if name.contains("push up") || name.contains("push-up") || name.contains("pushup") {
            return .horizontalPush
        }
        if name.contains("row") || name.contains("rowing") {
            return .horizontalPull
        }
        if name.contains("pull up") || name.contains("pull-up") || name.contains("pullup") ||
           name.contains("lat pulldown") || name.contains("chin up") || name.contains("chin-up") {
            return .verticalPull
        }
        if name.contains("squat") || name.contains("leg press") {
            return .squat
        }
        if name.contains("deadlift") || name.contains("rdl") || name.contains("hip hinge") ||
           name.contains("good morning") || name.contains("hip thrust") {
            return .hipHinge
        }
        if name.contains("lunge") || name.contains("split squat") || name.contains("step up") {
            return .lunge
        }
        
        // Isolation movements
        if name.contains("curl") && (tgt.contains("bicep") || name.contains("bicep")) {
            return .elbowFlexion
        }
        if name.contains("extension") && (tgt.contains("tricep") || name.contains("tricep")) {
            return .elbowExtension
        }
        if name.contains("pushdown") || name.contains("push down") {
            return .elbowExtension
        }
        if name.contains("front raise") {
            return .shoulderFlexion
        }
        if name.contains("lateral raise") || name.contains("side raise") {
            return .shoulderAbduction
        }
        if name.contains("leg extension") {
            return .kneeExtension
        }
        if name.contains("leg curl") || name.contains("hamstring curl") {
            return .kneeFlexion
        }
        if name.contains("hip abduct") {
            return .hipAbduction
        }
        if name.contains("hip adduct") {
            return .hipAdduction
        }
        if name.contains("crunch") || name.contains("sit up") || name.contains("leg raise") {
            return .coreFlexion
        }
        if name.contains("twist") || name.contains("rotation") || name.contains("woodchop") {
            return .coreRotation
        }
        if name.contains("plank") || name.contains("dead bug") || name.contains("hollow") {
            return .coreStability
        }
        if name.contains("carry") || name.contains("farmer") {
            return .carry
        }
        
        // Fallback based on target muscle
        switch tgt {
        case "chest", "pectorals":
            return .horizontalPush
        case "lats", "latissimus dorsi":
            return .verticalPull
        case "back", "mid back":
            return .horizontalPull
        case "shoulders", "delts":
            return .verticalPush
        case "quads", "quadriceps":
            return .squat
        case "hamstrings", "glutes":
            return .hipHinge
        case "biceps":
            return .elbowFlexion
        case "triceps":
            return .elbowExtension
        case "abs", "abdominals", "core":
            return .coreFlexion
        default:
            return .unknown
        }
    }
    
    // MARK: - Exercise Conversion (IronForge → TrainingEngine)
    
    static func convertExercise(_ exercise: Exercise) -> TEExercise {
        let equipment = mapEquipment(exercise.equipment)
        let primaryMuscles = [mapMuscleGroup(exercise.target)]
        let secondaryMuscles = exercise.secondaryMuscles.map { mapMuscleGroup($0) }
        let movementPattern = inferMovementPattern(
            from: exercise.name,
            equipment: exercise.equipment,
            target: exercise.target
        )
        
        return TEExercise(
            id: exercise.id,
            name: exercise.name,
            equipment: equipment,
            primaryMuscles: primaryMuscles,
            secondaryMuscles: secondaryMuscles,
            movementPattern: movementPattern,
            instructions: exercise.instructions,
            mediaUrl: exercise.gifUrl
        )
    }
    
    static func convertExerciseRef(_ ref: ExerciseRef) -> TEExercise {
        let equipment = mapEquipment(ref.equipment)
        let primaryMuscles = [mapMuscleGroup(ref.target)]
        let movementPattern = inferMovementPattern(
            from: ref.name,
            equipment: ref.equipment,
            target: ref.target
        )
        
        return TEExercise(
            id: ref.id,
            name: ref.name,
            equipment: equipment,
            primaryMuscles: primaryMuscles,
            secondaryMuscles: [],
            movementPattern: movementPattern,
            instructions: nil,
            mediaUrl: nil
        )
    }
    
    // MARK: - User Profile Conversion
    
    static func convertSex(_ sex: Sex) -> TEBiologicalSex {
        switch sex {
        case .male:
            return .male
        case .female:
            return .female
        }
    }
    
    static func convertExperience(_ experience: WorkoutExperience) -> TEExperienceLevel {
        switch experience {
        case .newbie, .beginner:
            return .beginner
        case .intermediate:
            return .intermediate
        case .advanced:
            return .advanced
        case .expert:
            return .elite
        }
    }
    
    static func convertGoal(_ goal: FitnessGoal) -> TETrainingGoal {
        switch goal {
        case .buildMuscle:
            return .hypertrophy
        case .loseFat:
            return .fatLoss
        case .gainStrength:
            return .strength
        case .improveEndurance:
            return .endurance
        case .maintainFitness, .generalHealth:
            return .generalFitness
        case .athleticPerformance:
            return .athleticPerformance
        case .flexibility:
            return .generalFitness
        }
    }
    
    static func convertGymType(_ gymType: GymType) -> TEEquipmentAvailability {
        switch gymType {
        case .commercial, .crossfit, .university:
            return .commercialGym
        case .homeGym:
            return .homeGym
        case .outdoor, .minimalist:
            return .bodyweightOnly
        }
    }
    
    /// Convert IronForge UserProfile to TrainingEngine UserProfile.
    ///
    /// - Parameters:
    ///   - profile: The app-side user profile.
    ///   - stableUserId: A stable user identifier (e.g., Supabase `auth.users.id` or a persisted local UUID).
    ///     If nil, falls back to anonymous but this should be avoided for ML data quality.
    static func convertUserProfile(_ profile: UserProfile, stableUserId: String? = nil) -> TEUserProfile {
        let goals = profile.goals.map { convertGoal($0) }
        
        // Use provided stable ID.
        // CRITICAL: Never generate a new random UUID here - that breaks user-level learning.
        let userId = stableUserId ?? "anonymous"
        
        return TEUserProfile(
            id: userId,
            sex: convertSex(profile.sex),
            experience: convertExperience(profile.workoutExperience),
            goals: goals.isEmpty ? [.generalFitness] : goals,
            weeklyFrequency: profile.weeklyFrequency,
            availableEquipment: convertGymType(profile.gymType),
            preferredUnit: .pounds,
            bodyWeight: profile.bodyWeightLbs.map { TELoad.pounds($0) },
            age: profile.age,
            limitations: [],
            dailyProteinGrams: profile.dailyProteinGrams,
            sleepHours: profile.sleepHours
        )
    }
    
    /// Get a stable user ID for engine calls.
    /// Uses a persisted local UUID (does NOT change across auth transitions).
    static func getStableUserId() -> String {
        // Persisted local UUID for offline/anonymous users.
        // CRITICAL: Never swap this to an auth ID later; otherwise one human splits into two IDs.
        let localUserIdKey = "ironforge.engine.localUserId"
        if let existingId = UserDefaults.standard.string(forKey: localUserIdKey) {
            return existingId
        }
        
        // Generate and persist a new local UUID (only once)
        let newId = UUID().uuidString
        UserDefaults.standard.set(newId, forKey: localUserIdKey)
        return newId
    }
    
    // MARK: - Template Conversion
    
    private static func convertTempo(_ tempo: TempoSpec) -> TrainingEngine.Tempo {
        TrainingEngine.Tempo(
            eccentric: tempo.eccentric,
            pauseBottom: tempo.pauseBottom,
            concentric: tempo.concentric,
            pauseTop: tempo.pauseTop
        )
    }
    
    private static func convertTempoBack(_ tempo: TrainingEngine.Tempo) -> TempoSpec {
        TempoSpec(
            eccentric: tempo.eccentric,
            pauseBottom: tempo.pauseBottom,
            concentric: tempo.concentric,
            pauseTop: tempo.pauseTop
        )
    }
    
    private static func derivedRIR(from set: WorkoutSet) -> Int? {
        if let rir = set.rirObserved { return max(0, min(10, rir)) }
        guard let rpe = set.rpeObserved else { return nil }
        // Common coaching convention: RPE 10 ≈ 0 RIR, 9 ≈ 1 RIR, 8 ≈ 2 RIR, etc.
        let rir = Int((10.0 - rpe).rounded())
        return max(0, min(10, rir))
    }
    
    // MARK: - Load Strategy Selection Policy
    
    /// Determines the appropriate load strategy based on exercise, user experience, and rep targets.
    /// 
    /// Policy:
    /// - `.percentageE1RM` (with nil targetPercentage → engine derives from reps+RIR) for:
    ///   - Compound lifts when lifter is intermediate+ AND rep target is "heavy" (≤5 reps), OR
    ///   - Compound lifts in DUP-style programs (detected by varying rep targets across templates)
    /// - `.absolute` for:
    ///   - All accessories
    ///   - All beginner work (simpler mental model)
    ///   - Compound lifts with higher rep ranges for beginners
    ///
    /// This leverages TrainingEngine's existing `%e1RM derived from reps + targetRIR` logic
    /// when `targetPercentage` is nil.
    static func determineLoadStrategy(
        exercise: ExerciseRef,
        experience: TEExperienceLevel,
        repRangeMin: Int,
        repRangeMax: Int,
        programName: String? = nil
    ) -> TrainingEngine.LoadStrategy {
        let movementPattern = inferMovementPattern(
            from: exercise.name,
            equipment: exercise.equipment,
            target: exercise.target
        )
        
        // Accessories always use absolute loading (simpler, less critical)
        guard movementPattern.isCompound else {
            return .absolute
        }
        
        // Beginners use absolute loading for simpler mental model
        // (They're still building motor patterns and don't need %1RM complexity)
        guard experience != .beginner else {
            return .absolute
        }
        
        // For intermediate+:
        // Use %e1RM for heavy work (≤5 reps) on compounds
        // This allows the engine to derive appropriate intensity from reps + RIR
        let isHeavyWork = repRangeMax <= 5
        
        // Detect DUP-style programs by name (common naming conventions)
        let isDUP = programName?.lowercased().contains("dup") ?? false
        
        // Use %e1RM for:
        // 1. Heavy compound work (strength focus)
        // 2. DUP programs (which vary rep targets and need consistent %e1RM basis)
        if isHeavyWork || isDUP {
            return .percentageE1RM
        }
        
        // Default to absolute for moderate rep ranges on compounds
        // (Still provides good results with simpler model)
        return .absolute
    }
    
    static func convertSetPrescription(
        from te: WorkoutTemplateExercise,
        experience: TEExperienceLevel = .intermediate,
        programName: String? = nil
    ) -> TESetPrescription {
        let loadStrategy = determineLoadStrategy(
            exercise: te.exercise,
            experience: experience,
            repRangeMin: te.repRangeMin,
            repRangeMax: te.repRangeMax,
            programName: programName
        )
        
        return TESetPrescription(
            setCount: te.setsTarget,
            targetRepsRange: te.repRangeMin...te.repRangeMax,
            targetRIR: max(0, min(5, te.targetRIR)),
            tempo: convertTempo(te.tempo),
            restSeconds: max(0, te.restSeconds),
            loadStrategy: loadStrategy,
            targetPercentage: nil, // Let engine derive from reps+RIR when using %e1RM
            increment: TELoad.pounds(te.increment)
        )
    }
    
    static func convertTemplateExercise(
        _ te: WorkoutTemplateExercise,
        order: Int,
        experience: TEExperienceLevel = .intermediate,
        programName: String? = nil
    ) -> TETemplateExercise {
        let exercise = convertExerciseRef(te.exercise)
        let prescription = convertSetPrescription(from: te, experience: experience, programName: programName)
        
        return TETemplateExercise(
            id: te.id,
            exercise: exercise,
            prescription: prescription,
            order: order,
            supersetGroup: nil,
            notes: nil
        )
    }
    
    static func convertWorkoutTemplate(
        _ template: WorkoutTemplate,
        experience: TEExperienceLevel = .intermediate,
        programName: String? = nil
    ) -> TEWorkoutTemplate {
        let exercises = template.exercises.enumerated().map { idx, te in
            convertTemplateExercise(te, order: idx, experience: experience, programName: programName)
        }
        
        let targetMuscles = exercises.flatMap { $0.exercise.primaryMuscles }
        
        return TEWorkoutTemplate(
            id: template.id,
            name: template.name,
            exercises: exercises,
            estimatedDurationMinutes: nil,
            targetMuscleGroups: targetMuscles,
            description: nil,
            createdAt: template.createdAt,
            updatedAt: template.updatedAt
        )
    }
    
    // MARK: - Progression Policy Conversion
    
    static func convertProgressionPolicy(from te: WorkoutTemplateExercise) -> TEProgressionPolicyType {
        let deloadPercentage = 1.0 - te.deloadFactor
        let config = TEDoubleProgressionConfig(
            sessionsAtTopBeforeIncrease: 1,
            loadIncrement: TELoad.pounds(te.increment),
            deloadPercentage: deloadPercentage,
            failuresBeforeDeload: te.failureThreshold
        )
        return .doubleProgression(config: config)
    }
    
    // MARK: - Training Plan Construction
    
    static func buildTrainingPlan(
        from templates: [WorkoutTemplate],
        substitutionPool: [Exercise] = [],
        experience: TEExperienceLevel = .intermediate,
        programName: String? = nil
    ) -> TETrainingPlan {
        var teTemplates: [UUID: TEWorkoutTemplate] = [:]
        var progressionPolicies: [String: TEProgressionPolicyType] = [:]
        
        for template in templates {
            let converted = convertWorkoutTemplate(template, experience: experience, programName: programName)
            teTemplates[template.id] = converted
            
            // Register progression policies for each exercise
            for te in template.exercises {
                progressionPolicies[te.exercise.id] = convertProgressionPolicy(from: te)
            }
        }
        
        let schedule: TEScheduleType = templates.count > 1
            ? .rotation(order: templates.map(\.id))
            : .manual
        
        let substitutionExercises = substitutionPool.map { convertExercise($0) }
        
        return TETrainingPlan(
            id: UUID(),
            name: programName ?? "IronForge Plan",
            templates: teTemplates,
            schedule: schedule,
            progressionPolicies: progressionPolicies,
            inSessionPolicies: [:],
            substitutionPool: substitutionExercises,
            deloadConfig: .default,
            loadRoundingPolicy: .standardPounds,
            createdAt: Date()
        )
    }
    
    // MARK: - Lift State Conversion
    
    static func convertLiftState(from state: ExerciseState) -> TELiftState {
        let trend: TrainingEngine.PerformanceTrend = {
            switch state.e1rmTrend {
            case .improving: return .improving
            case .stable: return .stable
            case .declining: return .declining
            case .insufficient: return .insufficient
            }
        }()
        
        let history: [TrainingEngine.E1RMSample] = state.e1rmHistory.map {
            TrainingEngine.E1RMSample(date: $0.date, value: $0.value)
        }
        
        return TELiftState(
            exerciseId: state.exerciseId,
            lastWorkingWeight: TELoad.pounds(state.currentWorkingWeight),
            rollingE1RM: state.rollingE1RM ?? (state.currentWorkingWeight * 1.1), // Rough fallback
            failureCount: state.failuresCount,
            lastDeloadDate: state.lastDeloadAt,
            trend: trend,
            e1rmHistory: history,
            lastSessionDate: state.updatedAt,
            successfulSessionsCount: state.successfulSessionsCount
        )
    }
    
    static func convertLiftStateBack(_ liftState: TELiftState) -> ExerciseState {
        let trend: ExerciseState.E1RMTrend = {
            switch liftState.trend {
            case .improving: return .improving
            case .stable: return .stable
            case .declining: return .declining
            case .insufficient: return .insufficient
            }
        }()
        
        let rollingLb: Double? = {
            guard liftState.rollingE1RM > 0 else { return nil }
            return TELoad(value: liftState.rollingE1RM, unit: liftState.lastWorkingWeight.unit)
                .converted(to: .pounds).value
        }()
        
        let history: [ExerciseState.E1RMSampleLite] = liftState.e1rmHistory.map { s in
            let v = TELoad(value: s.value, unit: liftState.lastWorkingWeight.unit)
                .converted(to: .pounds).value
            return ExerciseState.E1RMSampleLite(date: s.date, value: v)
        }
        
        return ExerciseState(
            exerciseId: liftState.exerciseId,
            currentWorkingWeight: liftState.lastWorkingWeight.converted(to: .pounds).value,
            failuresCount: liftState.failureCount,
            rollingE1RM: rollingLb,
            e1rmTrend: trend,
            e1rmHistory: history,
            lastDeloadAt: liftState.lastDeloadDate,
            successfulSessionsCount: liftState.successfulSessionsCount,
            updatedAt: liftState.lastSessionDate ?? Date()
        )
    }
    
    // MARK: - Workout History Construction
    
    static func buildWorkoutHistory(
        sessions: [WorkoutSession],
        liftStates: [String: ExerciseState],
        dailyBiometrics: [DailyBiometrics] = [],
        referenceDate: Date = Date(),
        calendar: Calendar = .current,
        experience: TEExperienceLevel = .intermediate,
        programName: String? = nil
    ) -> TEWorkoutHistory {
        let completedSessions = sessions.compactMap { session -> TECompletedSession? in
            guard let endedAt = session.endedAt else { return nil }
            
            var exerciseResults: [TEExerciseSessionResult] = []
            
            for (idx, perf) in session.exercises.enumerated() {
                let sets = perf.sets.map { set -> TESetResult in
                    TESetResult(
                        id: set.id,
                        reps: set.reps,
                        load: TELoad.pounds(set.weight),
                        rirObserved: derivedRIR(from: set),
                        tempoObserved: nil,
                        completed: set.isCompleted,
                        isWarmup: set.isWarmup,
                        completedAt: nil,
                        notes: set.notes
                    )
                }
                
                // Determine load strategy based on exercise and experience
                let loadStrategy = determineLoadStrategy(
                    exercise: perf.exercise,
                    experience: experience,
                    repRangeMin: perf.repRangeMin,
                    repRangeMax: perf.repRangeMax,
                    programName: programName
                )
                
                let prescription = TESetPrescription(
                    setCount: perf.setsTarget,
                    targetRepsRange: perf.repRangeMin...perf.repRangeMax,
                    targetRIR: max(0, min(5, perf.targetRIR)),
                    tempo: convertTempo(perf.tempo),
                    restSeconds: max(0, perf.restSeconds),
                    loadStrategy: loadStrategy,
                    targetPercentage: nil,
                    increment: TELoad.pounds(perf.increment)
                )
                
                let result = TEExerciseSessionResult(
                    id: perf.id,
                    exerciseId: perf.exercise.id,
                    prescription: prescription,
                    sets: sets,
                    order: idx,
                    notes: nil
                )
                exerciseResults.append(result)
            }
            
            // Build previous lift states for this session
            var previousLiftStates: [String: TELiftState] = [:]
            for perf in session.exercises {
                if let state = liftStates[perf.exercise.id] {
                    previousLiftStates[perf.exercise.id] = convertLiftState(from: state)
                }
            }
            
            return TECompletedSession(
                id: session.id,
                date: session.startedAt,
                templateId: session.templateId,
                name: session.name,
                exerciseResults: exerciseResults,
                startedAt: session.startedAt,
                endedAt: endedAt,
                wasDeload: session.wasDeload,
                previousLiftStates: previousLiftStates,
                readinessScore: session.computedReadinessScore,
                notes: nil
            )
        }
        
        let teLiftStates = liftStates.mapValues { convertLiftState(from: $0) }
        
        // Readiness history from cached biometrics (0–100).
        let readiness: [TEReadinessRecord] = ReadinessScoreCalculator
            .readinessHistory(from: dailyBiometrics, referenceDate: referenceDate, calendar: calendar, maxDays: 60)
            .map { TEReadinessRecord(date: $0.day, score: $0.score) }
        
        // Recent training volume (kg*reps) keyed by day (includes rest-day zeros for baseline coverage).
        let volumeByDay: [Date: Double] = buildRecentVolumeByDate(
            from: sessions,
            referenceDate: referenceDate,
            calendar: calendar,
            windowDays: 60,
            ensureCoverageDays: 28
        )
        
        return TEWorkoutHistory(
            sessions: completedSessions,
            liftStates: teLiftStates,
            readinessHistory: readiness,
            recentVolumeByDate: volumeByDay
        )
    }

    // MARK: - Volume history (for fatigue-aware deload)
    
    private static func buildRecentVolumeByDate(
        from sessions: [WorkoutSession],
        referenceDate: Date,
        calendar: Calendar,
        windowDays: Int,
        ensureCoverageDays: Int
    ) -> [Date: Double] {
        let endDay = calendar.startOfDay(for: referenceDate)
        let startDay = calendar.date(byAdding: .day, value: -(max(1, windowDays) - 1), to: endDay) ?? endDay
        
        var byDay: [Date: Double] = [:]
        byDay.reserveCapacity(max(ensureCoverageDays, 28))
        
        for session in sessions {
            // Only completed sessions contribute meaningful volume.
            guard session.endedAt != nil else { continue }
            let day = calendar.startOfDay(for: session.startedAt)
            if day < startDay || day > endDay { continue }
            
            var v = 0.0
            for ex in session.exercises {
                for set in ex.sets where set.isCompleted && set.reps > 0 {
                    // Convert lb -> kg and multiply by reps ("kg*reps" volume).
                    v += (set.weight * 0.453592) * Double(set.reps)
                }
            }
            byDay[day] = (byDay[day] ?? 0) + v
        }
        
        // Ensure the baseline window has sufficient coverage by explicitly writing 0 volume
        // for days without logged training sessions.
        //
        // IMPORTANT: Only start filling zeros *after the user has logged at least one session*.
        // This prevents "high fatigue" deloads from triggering immediately on week 1 due to
        // a mostly-empty 28-day baseline.
        if ensureCoverageDays > 0, let earliestTrainingDay = byDay.keys.min() {
            let desiredStart = calendar.date(byAdding: .day, value: -(ensureCoverageDays - 1), to: endDay) ?? endDay
            let coverageStart = max(desiredStart, earliestTrainingDay)
            
            var cursor = endDay
            while cursor >= coverageStart {
                if byDay[cursor] == nil { byDay[cursor] = 0 }
                guard let next = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
                cursor = calendar.startOfDay(for: next)
            }
        }
        
        return byDay
    }
    
    // MARK: - Session Plan to UI Model Conversion
    
    /// Convert a TrainingEngine SessionPlan to UI WorkoutSession.
    ///
    /// CRITICAL: This method now:
    /// 1. Uses `sessionPlan.sessionId` as the session ID (stable join key)
    /// 2. Uses `sessionPlan.date` as the session start time
    /// 3. Populates ML-critical fields on each set (recommendedWeight, recommendedReps, targetRIR, plannedSetId)
    /// 4. Populates ML-critical fields on each exercise (recommendationEventId, plannedTopSet*, stateSnapshot)
    static func convertSessionPlanToUIModel(
        _ sessionPlan: TESessionPlan,
        templateId: UUID?,
        templateName: String,
        computedReadinessScore: Int? = nil,
        exerciseStates: [String: ExerciseState] = [:],
        sessions: [WorkoutSession] = []
    ) -> WorkoutSession {
        let exercises = sessionPlan.exercises.enumerated().map { exIdx, exercisePlan -> ExercisePerformance in
            let exerciseRef = ExerciseRef(
                id: exercisePlan.exercise.id,
                name: exercisePlan.exercise.name,
                bodyPart: exercisePlan.exercise.primaryMuscles.first?.rawValue ?? "unknown",
                equipment: exercisePlan.exercise.equipment.rawValue,
                target: exercisePlan.exercise.primaryMuscles.first?.rawValue ?? "unknown"
            )
            
            // ML CRITICAL: Stable recommendation event ID (deterministic for a given planned session).
            let recommendationEventId = deterministicUUID(
                namespace: sessionPlan.sessionId,
                name: "recommendation_event:\(exercisePlan.exercise.id):\(exIdx)"
            )
            
            // Find the top set (highest target load) for exercise-level planned fields
            let topSetPlan = exercisePlan.sets.filter { !$0.isWarmup }.max { $0.targetLoad.value < $1.targetLoad.value }
            let topSetWeightLbs = topSetPlan?.targetLoad.converted(to: .pounds).value
            let topSetReps = topSetPlan?.targetReps
            let topSetRIR = topSetPlan?.targetRIR
            
            // ML CRITICAL: Stable session exercise ID (deterministic for upserts)
            let sessionExerciseId = deterministicUUID(
                namespace: sessionPlan.sessionId,
                name: "session_exercise:\(exIdx)"
            )
            
            // Create sets with ML-critical fields populated
            let sets: [WorkoutSet] = exercisePlan.sets.enumerated().map { (index, setPlan) -> WorkoutSet in
                let weightLbs = setPlan.targetLoad.converted(to: .pounds).value
                let plannedSetId = deterministicUUID(
                    namespace: recommendationEventId,
                    name: "planned_set:\(setPlan.setIndex)"
                )
                
                // ML CRITICAL: Use plannedSetId as the set ID for stable joins
                return WorkoutSet(
                    id: plannedSetId,
                    reps: setPlan.targetReps,
                    weight: weightLbs,
                    isCompleted: false,
                    targetRIR: setPlan.targetRIR,
                    targetRPE: nil,
                    rirObserved: nil,
                    rpeObserved: nil,
                    completedAt: nil,
                    actualRestSeconds: nil,
                    isWarmup: setPlan.isWarmup,
                    isDropSet: false,
                    isFailure: false,
                    compliance: nil,
                    complianceReason: nil,
                    recommendedWeight: weightLbs,            // ML CRITICAL: Original prescription
                    recommendedReps: setPlan.targetReps,     // ML CRITICAL: Original prescription
                    tempoActual: nil,
                    techniqueLimitations: nil,
                    isUserModified: false,
                    originalPrescribedWeight: weightLbs,     // ML CRITICAL: For modification tracking
                    originalPrescribedReps: setPlan.targetReps,
                    modificationReason: nil,
                    setOutcome: nil,
                    metRepTarget: nil,
                    metEffortTarget: nil,
                    plannedSetId: plannedSetId,              // ML CRITICAL: Stable join key
                    notes: nil
                )
            }
            
            let prescription = exercisePlan.prescription
            
            let (deloadFactor, failureThreshold): (Double, Int) = {
                switch exercisePlan.progressionPolicy {
                case .doubleProgression(let cfg):
                    return (1.0 - cfg.deloadPercentage, cfg.failuresBeforeDeload)
                case .linearProgression(let cfg):
                    return (1.0 - cfg.deloadPercentage, cfg.failuresBeforeDeload)
                default:
                    return (ProgressionDefaults.deloadFactor, ProgressionDefaults.failureThreshold)
                }
            }()
            
            // Build state snapshot for ML (prevents leakage)
            let exerciseId = exercisePlan.exercise.id
            let state = exerciseStates[exerciseId]
            let lastPerf = sessions.lazy.compactMap { session in
                session.exercises.first { $0.exercise.id == exerciseId }
            }.first
            let daysSinceLast: Int? = {
                guard let lastDate = state?.updatedAt else { return nil }
                return Calendar.current.dateComponents([.day], from: lastDate, to: Date()).day
            }()
            
            let stateSnapshot = LiftStateSessionSnapshot.from(
                state: state,
                lastPerformance: lastPerf,
                daysSinceLast: daysSinceLast,
                daysSinceDeload: state?.lastDeloadAt.flatMap { Calendar.current.dateComponents([.day], from: $0, to: Date()).day },
                exposuresLast14Days: 0,  // Could compute from sessions if needed
                volumeLast7Days: nil,
                templateVersion: nil
            )
            
            // Determine exposure role from set structure
            let exposureRole: ExposureRole = {
                let workingSets = exercisePlan.sets.filter { !$0.isWarmup }
                guard workingSets.count > 1 else { return .topSetOnly }
                let weights = workingSets.map { $0.targetLoad.value }
                let allSameWeight = weights.allSatisfy { abs($0 - weights[0]) < 0.01 }
                if allSameWeight {
                    return .straightSets
                }
                // Check if it's backoff sets (first set is heaviest)
                if let first = weights.first, weights.dropFirst().allSatisfy({ $0 < first }) {
                    return .backoffSets
                }
                return .straightSets
            }()
            
            var perf = ExercisePerformance(
                id: sessionExerciseId,  // ML CRITICAL: Deterministic for stable upserts
                exercise: exerciseRef,
                setsTarget: prescription.setCount,
                repRangeMin: prescription.targetRepsRange.lowerBound,
                repRangeMax: prescription.targetRepsRange.upperBound,
                increment: prescription.increment.converted(to: .pounds).value,
                deloadFactor: deloadFactor,
                failureThreshold: failureThreshold,
                targetRIR: prescription.targetRIR,
                tempo: convertTempoBack(prescription.tempo),
                restSeconds: prescription.restSeconds,
                sets: sets,
                nextPrescription: nil,
                isCompleted: false
            )
            
            // Populate ML-critical fields
            perf.recommendationEventId = recommendationEventId
            perf.plannedTopSetWeightLbs = topSetWeightLbs
            perf.plannedTopSetReps = topSetReps
            perf.plannedTargetRIR = topSetRIR
            perf.stateSnapshot = stateSnapshot
            perf.exposureRole = exposureRole
            
            // ML CRITICAL: Capture engine's direction decision for actionType derivation
            perf.progressionDirection = exercisePlan.direction?.rawValue
            perf.progressionDirectionReason = exercisePlan.directionReason?.rawValue
            
            // ML CRITICAL: Populate policy selection snapshot from the store.
            // TrainingEngine logs decisions to TrainingDataLogger which calls our log handler,
            // which stores the policy selection data in PolicySelectionSnapshotStore.
            // We retrieve it here to attach to the UI model for downstream sync to Supabase.
            if let snapshot = PolicySelectionSnapshotStore.shared.snapshot(
                sessionId: sessionPlan.sessionId,
                exerciseId: exercisePlan.exercise.id
            ) {
                perf.policySelectionSnapshot = snapshot
            }
            
            return perf
        }
        
        // CRITICAL: Use sessionPlan.sessionId (stable) instead of generating a new UUID
        return WorkoutSession(
            id: sessionPlan.sessionId,
            templateId: templateId,
            name: templateName,
            startedAt: sessionPlan.date,
            endedAt: nil,
            wasDeload: sessionPlan.isDeload,
            deloadReason: sessionPlan.deloadReason?.rawValue,
            exercises: exercises,
            computedReadinessScore: computedReadinessScore
        )
    }
    
    // MARK: - Convert Completed Session for Engine
    
    static func convertCompletedSession(
        _ session: WorkoutSession,
        previousLiftStates: [String: ExerciseState],
        experience: TEExperienceLevel = .intermediate,
        programName: String? = nil
    ) -> TECompletedSession {
        var exerciseResults: [TEExerciseSessionResult] = []
        
        for (idx, perf) in session.exercises.enumerated() {
            let sets = perf.sets.map { set -> TESetResult in
                TESetResult(
                    id: set.id,
                    reps: set.reps,
                    load: TELoad.pounds(set.weight),
                    rirObserved: derivedRIR(from: set),
                    tempoObserved: nil,
                    completed: set.isCompleted,
                    isWarmup: set.isWarmup,
                    completedAt: nil,
                    notes: set.notes
                )
            }
            
            // Determine load strategy based on exercise and experience
            let loadStrategy = determineLoadStrategy(
                exercise: perf.exercise,
                experience: experience,
                repRangeMin: perf.repRangeMin,
                repRangeMax: perf.repRangeMax,
                programName: programName
            )
            
            let prescription = TESetPrescription(
                setCount: perf.setsTarget,
                targetRepsRange: perf.repRangeMin...perf.repRangeMax,
                targetRIR: max(0, min(5, perf.targetRIR)),
                tempo: convertTempo(perf.tempo),
                restSeconds: max(0, perf.restSeconds),
                loadStrategy: loadStrategy,
                targetPercentage: nil,
                increment: TELoad.pounds(perf.increment)
            )
            
            let result = TEExerciseSessionResult(
                id: perf.id,
                exerciseId: perf.exercise.id,
                prescription: prescription,
                sets: sets,
                order: idx,
                notes: nil
            )
            exerciseResults.append(result)
        }
        
        // Build previous lift states
        var prevStates: [String: TELiftState] = [:]
        for perf in session.exercises {
            if let state = previousLiftStates[perf.exercise.id] {
                prevStates[perf.exercise.id] = convertLiftState(from: state)
            }
        }
        
        return TECompletedSession(
            id: session.id,
            date: session.startedAt,
            templateId: session.templateId,
            name: session.name,
            exerciseResults: exerciseResults,
            startedAt: session.startedAt,
            endedAt: session.endedAt ?? Date(),
            wasDeload: session.wasDeload,
            previousLiftStates: prevStates,
            readinessScore: session.computedReadinessScore,
            notes: nil
        )
    }
    
    // MARK: - Recommend Session
    
    static func recommendSession(
        date: Date = Date(),
        userProfile: UserProfile,
        templates: [WorkoutTemplate],
        sessions: [WorkoutSession],
        liftStates: [String: ExerciseState],
        readiness: Int = 75,
        substitutionPool: [Exercise] = [],
        dailyBiometrics: [DailyBiometrics] = [],
        calendar: Calendar = .current,
        programName: String? = nil,
        policySelector: ProgressionPolicySelector? = nil
    ) -> TESessionPlan {
        // Get stable user ID for ML training data
        let stableUserId = getStableUserId()
        let teUserProfile = convertUserProfile(userProfile, stableUserId: stableUserId)
        let experience = teUserProfile.experience
        let plan = buildTrainingPlan(
            from: templates,
            substitutionPool: substitutionPool,
            experience: experience,
            programName: programName
        )
        let history = buildWorkoutHistory(
            sessions: sessions,
            liftStates: liftStates,
            dailyBiometrics: dailyBiometrics,
            referenceDate: date,
            calendar: calendar,
            experience: experience,
            programName: programName
        )
        
        // Build planning context with stable IDs for ML data logging
        let planningContext = TrainingEngine.SessionPlanningContext(
            sessionId: UUID(),  // New session gets a new stable ID
            userId: stableUserId,
            sessionDate: date,
            isPlannedDeloadWeek: false,
            calendar: calendar
        )
        
        // Build policy selection provider closure
        let policySelectionProvider: TrainingEngine.PolicySelectionProvider? = policySelector.map { selector in
            { @Sendable signals, variationContext in
                selector.selectPolicy(for: signals, variationContext: variationContext, userId: stableUserId)
            }
        }
        
        return TrainingEngine.Engine.recommendSession(
            date: date,
            userProfile: teUserProfile,
            plan: plan,
            history: history,
            readiness: readiness,
            calendar: calendar,
            planningContext: planningContext,
            policySelectionProvider: policySelectionProvider
        )
    }
    
    static func recommendSessionForTemplate(
        date: Date = Date(),
        templateId: UUID,
        userProfile: UserProfile,
        templates: [WorkoutTemplate],
        sessions: [WorkoutSession],
        liftStates: [String: ExerciseState],
        readiness: Int = 75,
        substitutionPool: [Exercise] = [],
        dailyBiometrics: [DailyBiometrics] = [],
        calendar: Calendar = .current,
        programName: String? = nil,
        policySelector: ProgressionPolicySelector? = nil
    ) -> TESessionPlan {
        // Get stable user ID for ML training data
        let stableUserId = getStableUserId()
        let teUserProfile = convertUserProfile(userProfile, stableUserId: stableUserId)
        let experience = teUserProfile.experience
        let plan = buildTrainingPlan(
            from: templates,
            substitutionPool: substitutionPool,
            experience: experience,
            programName: programName
        )
        let history = buildWorkoutHistory(
            sessions: sessions,
            liftStates: liftStates,
            dailyBiometrics: dailyBiometrics,
            referenceDate: date,
            calendar: calendar,
            experience: experience,
            programName: programName
        )
        
        // Build planning context with stable IDs for ML data logging
        let planningContext = TrainingEngine.SessionPlanningContext(
            sessionId: UUID(),  // New session gets a new stable ID
            userId: stableUserId,
            sessionDate: date,
            isPlannedDeloadWeek: false,
            calendar: calendar
        )
        
        // Build policy selection provider closure
        let policySelectionProvider: TrainingEngine.PolicySelectionProvider? = policySelector.map { selector in
            { @Sendable signals, variationContext in
                selector.selectPolicy(for: signals, variationContext: variationContext, userId: stableUserId)
            }
        }
        
        return TrainingEngine.Engine.recommendSessionForTemplate(
            date: date,
            templateId: templateId,
            userProfile: teUserProfile,
            plan: plan,
            history: history,
            readiness: readiness,
            calendar: calendar,
            planningContext: planningContext,
            policySelectionProvider: policySelectionProvider
        )
    }
    
    // MARK: - Update Lift States After Session
    
    static func updateLiftStates(
        afterSession session: WorkoutSession,
        previousLiftStates: [String: ExerciseState],
        experience: TEExperienceLevel = .intermediate,
        programName: String? = nil
    ) -> [String: ExerciseState] {
        let completedSession = convertCompletedSession(
            session,
            previousLiftStates: previousLiftStates,
            experience: experience,
            programName: programName
        )
        let updatedStates = TrainingEngine.Engine.updateLiftState(afterSession: completedSession)
        
        var result: [String: ExerciseState] = previousLiftStates
        for state in updatedStates {
            result[state.exerciseId] = convertLiftStateBack(state)
        }
        return result
    }
}

// MARK: - Readiness scoring (DailyBiometrics → 0–100 score)
//
// This lives in this file so it is guaranteed to be part of the app target (Xcode project),
// even when files are added outside of Xcode.
//
// If HealthKit data is missing, we degrade to a neutral score.
enum ReadinessScoreCalculator {
    struct DayScore: Hashable {
        /// Start-of-day in the provided calendar.
        let day: Date
        let score: Int
    }
    
    struct DayInputs {
        // Core metrics (primary drivers)
        let sleepMinutes: Double?
        let hrvMs: Double?
        let restingHrBpm: Double?
        let activeEnergyKcal: Double?
        let steps: Double?
        
        // Extended sleep quality metrics
        let sleepDeepMinutes: Double?
        let sleepRemMinutes: Double?
        let timeInBedMinutes: Double?
        
        // Recovery stress metrics
        let respiratoryRate: Double?
        let oxygenSaturation: Double?
        let wristTemperatureCelsius: Double?
        
        // Circadian/activity context
        let timeInDaylightMinutes: Double?
        let exerciseTimeMinutes: Double?
    }
    
    /// Compute readiness scores for up to the last `maxDays` of biometrics (inclusive of `referenceDate` day).
    static func readinessHistory(
        from biometrics: [DailyBiometrics],
        referenceDate: Date = Date(),
        calendar: Calendar = .current,
        maxDays: Int = 60,
        baselineWindowDays: Int = 7,
        minBaselineSamplesPerMetric: Int = 3
    ) -> [DayScore] {
        guard maxDays > 0 else { return [] }
        
        let endDay = calendar.startOfDay(for: referenceDate)
        let startDay = calendar.date(byAdding: .day, value: -(maxDays - 1), to: endDay) ?? endDay
        
        // Sort and clamp to the window.
        let relevant: [DailyBiometrics] = biometrics
            .filter { day in
                let d = calendar.startOfDay(for: day.date)
                return d >= startDay && d <= endDay
            }
            .sorted { $0.date < $1.date }
        
        guard !relevant.isEmpty else { return [] }
        
        var results: [DayScore] = []
        results.reserveCapacity(relevant.count)
        
        // O(n^2) over <=60 days; acceptable and keeps the logic clear.
        for i in 0..<relevant.count {
            let current = relevant[i]
            let day = calendar.startOfDay(for: current.date)
            let baselineStart = calendar.date(byAdding: .day, value: -baselineWindowDays, to: day) ?? day
            
            let priorPool = relevant[0..<i].filter { b in
                let d = calendar.startOfDay(for: b.date)
                return d >= baselineStart && d < day
            }
            
            let inputs = DayInputs(
                // Core metrics
                sleepMinutes: current.sleepMinutes,
                hrvMs: current.hrvSDNN,
                restingHrBpm: current.restingHR,
                activeEnergyKcal: current.activeEnergy,
                steps: current.steps,
                // Extended sleep quality
                sleepDeepMinutes: current.sleepDeepMinutes,
                sleepRemMinutes: current.sleepRemMinutes,
                timeInBedMinutes: current.timeInBedMinutes,
                // Recovery stress
                respiratoryRate: current.respiratoryRate,
                oxygenSaturation: current.oxygenSaturation,
                wristTemperatureCelsius: current.wristTemperatureCelsius,
                // Circadian/activity
                timeInDaylightMinutes: current.timeInDaylightMinutes,
                exerciseTimeMinutes: current.exerciseTimeMinutes
            )
            
            let baselines = baselineAverages(from: priorPool, minSamples: minBaselineSamplesPerMetric)
            let score = scoreDay(inputs: inputs, baselines: baselines)
            
            results.append(DayScore(day: day, score: score))
        }
        
        return results
    }
    
    /// Convenience: compute today’s readiness score from cached biometrics.
    static func todayScore(
        from biometrics: [DailyBiometrics],
        referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) -> Int? {
        let day = calendar.startOfDay(for: referenceDate)
        let history = readinessHistory(from: biometrics, referenceDate: referenceDate, calendar: calendar, maxDays: 60)
        // Prefer exact match; fallback to most recent score if we only have older data.
        return history.first(where: { $0.day == day })?.score ?? history.last?.score
    }
    
    // MARK: - Scoring
    
    private struct Baselines {
        // Core metrics
        var sleepMinutes: Double?
        var hrvMs: Double?
        var restingHrBpm: Double?
        var activeEnergyKcal: Double?
        var steps: Double?
        
        // Extended sleep quality
        var sleepDeepMinutes: Double?
        var sleepRemMinutes: Double?
        var timeInBedMinutes: Double?
        
        // Recovery stress
        var respiratoryRate: Double?
        var oxygenSaturation: Double?
        var wristTemperatureCelsius: Double?
        
        // Circadian/activity
        var timeInDaylightMinutes: Double?
        var exerciseTimeMinutes: Double?
    }
    
    private static func baselineAverages(from prior: [DailyBiometrics], minSamples: Int) -> Baselines {
        func avg(_ values: [Double]) -> Double? {
            guard values.count >= minSamples else { return nil }
            return values.reduce(0, +) / Double(values.count)
        }
        
        return Baselines(
            // Core metrics
            sleepMinutes: avg(prior.compactMap { $0.sleepMinutes }),
            hrvMs: avg(prior.compactMap { $0.hrvSDNN }),
            restingHrBpm: avg(prior.compactMap { $0.restingHR }),
            activeEnergyKcal: avg(prior.compactMap { $0.activeEnergy }),
            steps: avg(prior.compactMap { $0.steps }),
            // Extended sleep quality
            sleepDeepMinutes: avg(prior.compactMap { $0.sleepDeepMinutes }),
            sleepRemMinutes: avg(prior.compactMap { $0.sleepRemMinutes }),
            timeInBedMinutes: avg(prior.compactMap { $0.timeInBedMinutes }),
            // Recovery stress
            respiratoryRate: avg(prior.compactMap { $0.respiratoryRate }),
            oxygenSaturation: avg(prior.compactMap { $0.oxygenSaturation }),
            wristTemperatureCelsius: avg(prior.compactMap { $0.wristTemperatureCelsius }),
            // Circadian/activity
            timeInDaylightMinutes: avg(prior.compactMap { $0.timeInDaylightMinutes }),
            exerciseTimeMinutes: avg(prior.compactMap { $0.exerciseTimeMinutes })
        )
    }
    
    private static func scoreDay(inputs: DayInputs, baselines: Baselines) -> Int {
        // Neutral default (good enough to train, not a green light to PR).
        var score = 75
        
        // =======================================================================
        // PRIMARY DRIVERS (core metrics - significant weight)
        // =======================================================================
        
        // Sleep duration (primary driver, max ±15 pts)
        if let today = inputs.sleepMinutes, let base = baselines.sleepMinutes, base > 0 {
            let ratio = today / base
            // Below baseline hurts quickly.
            if ratio < 0.85 {
                score -= 15
            } else if ratio < 1.0 {
                // Linearly scale 0..15 points between 0.85..1.0
                score -= Int(((1.0 - ratio) / 0.15 * 15.0).rounded())
            } else if ratio > 1.10 {
                score += 5
            } else {
                score += Int(((ratio - 1.0) / 0.10 * 5.0).rounded())
            }
        }
        
        // HRV (primary driver, max ±15 pts)
        if let today = inputs.hrvMs, let base = baselines.hrvMs, base > 0 {
            let ratio = today / base
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
        
        // Resting HR (primary driver, max ±10 pts; higher is worse)
        if let today = inputs.restingHrBpm, let base = baselines.restingHrBpm, base > 0 {
            let ratio = today / base
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
        
        // =======================================================================
        // SECONDARY DRIVERS (extended metrics - conservative weights)
        // These only contribute when both today's value AND baseline exist.
        // =======================================================================
        
        // Sleep quality: deep + REM as % of total sleep (max ±5 pts)
        // Better sleep quality = better recovery, correlates with anabolic hormone release.
        if let deepToday = inputs.sleepDeepMinutes,
           let remToday = inputs.sleepRemMinutes,
           let sleepToday = inputs.sleepMinutes,
           let deepBase = baselines.sleepDeepMinutes,
           let remBase = baselines.sleepRemMinutes,
           let sleepBase = baselines.sleepMinutes,
           sleepToday > 0, sleepBase > 0 {
            let qualityToday = (deepToday + remToday) / sleepToday
            let qualityBase = (deepBase + remBase) / sleepBase
            if qualityBase > 0 {
                let ratio = qualityToday / qualityBase
                if ratio < 0.80 {
                    score -= 5
                } else if ratio < 0.95 {
                    score -= Int(((0.95 - ratio) / 0.15 * 5.0).rounded())
                } else if ratio > 1.15 {
                    score += 3
                } else if ratio > 1.0 {
                    score += Int(((ratio - 1.0) / 0.15 * 3.0).rounded())
                }
            }
        }
        
        // Sleep efficiency: actual sleep / time in bed (max ±3 pts)
        if let sleepToday = inputs.sleepMinutes,
           let inBedToday = inputs.timeInBedMinutes,
           let sleepBase = baselines.sleepMinutes,
           let inBedBase = baselines.timeInBedMinutes,
           inBedToday > 0, inBedBase > 0 {
            let effToday = sleepToday / inBedToday
            let effBase = sleepBase / inBedBase
            if effBase > 0 {
                let ratio = effToday / effBase
                // Only penalize significantly poor efficiency
                if ratio < 0.85 {
                    score -= 3
                } else if ratio > 1.05 {
                    score += 2
                }
            }
        }
        
        // Respiratory rate: elevated = possible illness/stress (max ±4 pts)
        // Higher respiratory rate during sleep indicates stress/illness.
        if let today = inputs.respiratoryRate, let base = baselines.respiratoryRate, base > 0 {
            let ratio = today / base
            if ratio > 1.15 {
                score -= 4  // Significantly elevated - possible illness
            } else if ratio > 1.05 {
                score -= Int(((ratio - 1.05) / 0.10 * 4.0).rounded())
            } else if ratio < 0.95 {
                score += 2  // Lower than normal is generally positive
            }
        }
        
        // Blood oxygen saturation SpO2 (max ±3 pts)
        // Low SpO2 indicates respiratory stress or altitude acclimatization issues.
        // Normal is 95-100%, concerning below 94%.
        if let today = inputs.oxygenSaturation, let base = baselines.oxygenSaturation, base > 0 {
            // SpO2 has a narrow normal range, so we use absolute thresholds too
            if today < 94.0 {
                score -= 3  // Concerning low
            } else if today < 95.0 {
                score -= 1
            }
            // If today is significantly below personal baseline, also penalize
            let ratio = today / base
            if ratio < 0.97 && today < 97.0 {
                score -= 2  // Below baseline AND below 97%
            }
        }
        
        // Wrist temperature deviation (max ±3 pts)
        // Elevated temperature can indicate immune response or hormonal shifts.
        // This is reported as deviation from baseline by Apple Watch S8+.
        if let today = inputs.wristTemperatureCelsius, let base = baselines.wristTemperatureCelsius {
            // Deviation > +0.5°C from personal baseline can indicate stress/illness
            let deviation = today - base
            if deviation > 0.7 {
                score -= 3  // Significant elevation - possible illness
            } else if deviation > 0.4 {
                score -= Int((deviation / 0.7 * 3.0).rounded())
            } else if deviation < -0.3 {
                score += 1  // Slightly cooler is fine
            }
        }
        
        // Time in daylight: circadian rhythm support (max ±3 pts)
        // Adequate daylight exposure supports circadian rhythm and recovery.
        if let today = inputs.timeInDaylightMinutes, let base = baselines.timeInDaylightMinutes, base > 0 {
            let ratio = today / base
            // Very low daylight can disrupt sleep/recovery
            if ratio < 0.30 {
                score -= 3
            } else if ratio < 0.50 {
                score -= 1
            } else if ratio > 1.30 {
                score += 2  // Good daylight exposure
            }
        }
        
        // Exercise time previous day: overtraining signal (max -4 pts)
        // Excessive exercise yesterday can reduce today's readiness.
        // Only penalize, don't reward (rest day shouldn't boost readiness).
        if let today = inputs.exerciseTimeMinutes, let base = baselines.exerciseTimeMinutes, base > 0 {
            let ratio = today / base
            if ratio > 2.0 {
                score -= 4  // Very high exercise load
            } else if ratio > 1.5 {
                score -= Int(((ratio - 1.5) / 0.5 * 4.0).rounded())
            }
        }
        
        // =======================================================================
        // ACTIVITY LOAD (minor, max -5 pts)
        // Very high day-to-day activity can reduce readiness.
        // Treat "below baseline" as neutral (it could be intentional rest).
        // =======================================================================
        if let today = inputs.activeEnergyKcal, let base = baselines.activeEnergyKcal, base > 0 {
            let ratio = today / base
            if ratio > 1.40 {
                score -= 5
            } else if ratio > 1.15 {
                score -= 2
            }
        } else if let today = inputs.steps, let base = baselines.steps, base > 0 {
            let ratio = today / base
            if ratio > 1.40 {
                score -= 5
            } else if ratio > 1.15 {
                score -= 2
            }
        }
        
        return max(0, min(100, score))
    }
}
