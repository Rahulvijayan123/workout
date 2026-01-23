import Foundation

// MARK: - Progression Defaults

enum ProgressionDefaults {
    /// Default number of consecutive failures before triggering a deload.
    static let failureThreshold: Int = 3
    /// Default deload factor as a multiplier (e.g., 0.9 means reduce to 90%).
    static let deloadFactor: Double = 0.9
    /// Default deload percentage (e.g., 0.10 = 10% reduction).
    static let deloadPercentage: Double = 0.10
}

// MARK: - Tempo (UI model)

/// Tempo prescription (eccentric-pause-concentric-pause), expressed in seconds.
///
/// This mirrors `TrainingEngine.Tempo` but lives in the IronForge models so we don't import engine types here.
struct TempoSpec: Codable, Hashable {
    var eccentric: Int
    var pauseBottom: Int
    var concentric: Int
    var pauseTop: Int
    
    init(eccentric: Int = 2, pauseBottom: Int = 0, concentric: Int = 1, pauseTop: Int = 0) {
        self.eccentric = max(0, eccentric)
        self.pauseBottom = max(0, pauseBottom)
        self.concentric = max(0, concentric)
        self.pauseTop = max(0, pauseTop)
    }
    
    static let standard = TempoSpec(eccentric: 2, pauseBottom: 0, concentric: 1, pauseTop: 0)
}

// MARK: - Workout Templates

struct WorkoutTemplate: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var name: String
    var exercises: [WorkoutTemplateExercise]
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    
    // Backward-compatible decoding from old format
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decode(String.self, forKey: .name)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
        
        // Try new format first, fallback to old TemplateExercise format
        if let newExercises = try? container.decode([WorkoutTemplateExercise].self, forKey: .exercises) {
            exercises = newExercises
        } else if let oldExercises = try? container.decode([LegacyTemplateExercise].self, forKey: .exercises) {
            exercises = oldExercises.map { WorkoutTemplateExercise(from: $0) }
        } else {
            exercises = []
        }
    }
    
    init(id: UUID = UUID(), name: String, exercises: [WorkoutTemplateExercise], createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.id = id
        self.name = name
        self.exercises = exercises
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// MARK: - Template Exercise (per-template settings)

struct WorkoutTemplateExercise: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var exercise: ExerciseRef
    
    /// Number of sets to perform
    var setsTarget: Int = 3
    
    /// Rep range bounds
    var repRangeMin: Int = 6
    var repRangeMax: Int = 10
    
    /// Target effort in Reps In Reserve (0 = to failure).
    var targetRIR: Int = 2
    
    /// Tempo prescription for the exercise.
    var tempo: TempoSpec = .standard
    
    /// Rest between sets, in seconds.
    var restSeconds: Int = 120
    
    /// Weight increment for progression (lbs by default)
    var increment: Double = 5
    
    /// Deload factor as multiplier (e.g., 0.9 means reduce to 90%)
    var deloadFactor: Double = ProgressionDefaults.deloadFactor
    
    /// Number of consecutive failures before triggering deload
    var failureThreshold: Int = ProgressionDefaults.failureThreshold
    
    /// Computed rep range for convenience
    var repRange: ClosedRange<Int> {
        repRangeMin...repRangeMax
    }
    
    // Backward-compatible decoding
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        exercise = try container.decode(ExerciseRef.self, forKey: .exercise)
        
        // New fields with defaults
        setsTarget = try container.decodeIfPresent(Int.self, forKey: .setsTarget) ?? 3
        repRangeMin = try container.decodeIfPresent(Int.self, forKey: .repRangeMin) ?? 6
        repRangeMax = try container.decodeIfPresent(Int.self, forKey: .repRangeMax) ?? 10
        targetRIR = try container.decodeIfPresent(Int.self, forKey: .targetRIR) ?? 2
        tempo = try container.decodeIfPresent(TempoSpec.self, forKey: .tempo) ?? .standard
        restSeconds = try container.decodeIfPresent(Int.self, forKey: .restSeconds) ?? 120
        increment = try container.decodeIfPresent(Double.self, forKey: .increment) ?? 5
        deloadFactor = try container.decodeIfPresent(Double.self, forKey: .deloadFactor) ?? ProgressionDefaults.deloadFactor
        failureThreshold = try container.decodeIfPresent(Int.self, forKey: .failureThreshold) ?? ProgressionDefaults.failureThreshold
        
        // Legacy field support: "sets" -> setsTarget
        if let legacySets = try? container.decode(Int.self, forKey: .legacySets) {
            setsTarget = legacySets
        }
        
        // Legacy field support: "repRange" -> repRangeMin/Max
        if let legacyRange = try? container.decode(LegacyClosedRange.self, forKey: .legacyRepRange) {
            repRangeMin = legacyRange.lowerBound
            repRangeMax = legacyRange.upperBound
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(exercise, forKey: .exercise)
        try container.encode(setsTarget, forKey: .setsTarget)
        try container.encode(repRangeMin, forKey: .repRangeMin)
        try container.encode(repRangeMax, forKey: .repRangeMax)
        try container.encode(targetRIR, forKey: .targetRIR)
        try container.encode(tempo, forKey: .tempo)
        try container.encode(restSeconds, forKey: .restSeconds)
        try container.encode(increment, forKey: .increment)
        try container.encode(deloadFactor, forKey: .deloadFactor)
        try container.encode(failureThreshold, forKey: .failureThreshold)
    }
    
    private enum CodingKeys: String, CodingKey {
        case id, exercise, setsTarget, repRangeMin, repRangeMax, targetRIR, tempo, restSeconds, increment, deloadFactor, failureThreshold
        case legacySets = "sets"
        case legacyRepRange = "repRange"
    }
    
    init(
        id: UUID = UUID(),
        exercise: ExerciseRef,
        setsTarget: Int = 3,
        repRangeMin: Int = 6,
        repRangeMax: Int = 10,
        targetRIR: Int = 2,
        tempo: TempoSpec = .standard,
        restSeconds: Int = 120,
        increment: Double = 5,
        deloadFactor: Double = ProgressionDefaults.deloadFactor,
        failureThreshold: Int = ProgressionDefaults.failureThreshold
    ) {
        self.id = id
        self.exercise = exercise
        self.setsTarget = setsTarget
        self.repRangeMin = repRangeMin
        self.repRangeMax = repRangeMax
        self.targetRIR = targetRIR
        self.tempo = tempo
        self.restSeconds = restSeconds
        self.increment = increment
        self.deloadFactor = deloadFactor
        self.failureThreshold = failureThreshold
    }
    
    /// Initialize from legacy format
    init(from legacy: LegacyTemplateExercise) {
        self.id = legacy.id
        self.exercise = legacy.exercise
        self.setsTarget = legacy.sets
        self.repRangeMin = legacy.repRange.lowerBound
        self.repRangeMax = legacy.repRange.upperBound
        self.targetRIR = 2
        self.tempo = .standard
        self.restSeconds = 120
        self.increment = legacy.increment
        self.deloadFactor = ProgressionDefaults.deloadFactor
        self.failureThreshold = ProgressionDefaults.failureThreshold
    }
}

// MARK: - Workout Sessions (Logging)

struct WorkoutSession: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var templateId: UUID?
    var name: String
    var startedAt: Date = Date()
    var endedAt: Date?
    
    /// Whether this session was performed as a deload (as recommended by TrainingEngine).
    /// Used to prevent deload feedback loops in long-horizon planning.
    var wasDeload: Bool = false
    
    /// Optional deload reason (stringly-typed to avoid importing TrainingEngine types into UI models).
    var deloadReason: String?
    var exercises: [ExercisePerformance]
    
    var isActive: Bool { endedAt == nil }
    
    // Backward-compatible decoding
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        templateId = try container.decodeIfPresent(UUID.self, forKey: .templateId)
        name = try container.decode(String.self, forKey: .name)
        startedAt = try container.decodeIfPresent(Date.self, forKey: .startedAt) ?? Date()
        endedAt = try container.decodeIfPresent(Date.self, forKey: .endedAt)
        wasDeload = try container.decodeIfPresent(Bool.self, forKey: .wasDeload) ?? false
        deloadReason = try container.decodeIfPresent(String.self, forKey: .deloadReason)
        
        // Try new format first, fallback to old SessionExercise format
        if let newExercises = try? container.decode([ExercisePerformance].self, forKey: .exercises) {
            exercises = newExercises
        } else if let oldExercises = try? container.decode([LegacySessionExercise].self, forKey: .exercises) {
            exercises = oldExercises.map { ExercisePerformance(from: $0) }
        } else {
            exercises = []
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encodeIfPresent(templateId, forKey: .templateId)
        try container.encode(name, forKey: .name)
        try container.encode(startedAt, forKey: .startedAt)
        try container.encodeIfPresent(endedAt, forKey: .endedAt)
        try container.encode(wasDeload, forKey: .wasDeload)
        try container.encodeIfPresent(deloadReason, forKey: .deloadReason)
        try container.encode(exercises, forKey: .exercises)
    }
    
    private enum CodingKeys: String, CodingKey {
        case id, templateId, name, startedAt, endedAt, wasDeload, deloadReason, exercises
    }
    
    init(
        id: UUID = UUID(),
        templateId: UUID? = nil,
        name: String,
        startedAt: Date = Date(),
        endedAt: Date? = nil,
        wasDeload: Bool = false,
        deloadReason: String? = nil,
        exercises: [ExercisePerformance]
    ) {
        self.id = id
        self.templateId = templateId
        self.name = name
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.wasDeload = wasDeload
        self.deloadReason = deloadReason
        self.exercises = exercises
    }
}

// MARK: - Exercise Performance (per-session logged data)

struct ExercisePerformance: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var exercise: ExerciseRef
    
    /// Snapshot of template settings at time of session (for stable history)
    var setsTarget: Int
    var repRangeMin: Int
    var repRangeMax: Int
    var increment: Double
    var deloadFactor: Double
    var failureThreshold: Int
    
    /// Target effort in Reps In Reserve (snapshot).
    var targetRIR: Int
    
    /// Tempo prescription (snapshot).
    var tempo: TempoSpec
    
    /// Rest between sets, seconds (snapshot).
    var restSeconds: Int
    
    /// Actual logged sets
    var sets: [WorkoutSet]
    
    /// Progression snapshot computed after exercise completion
    var nextPrescription: NextPrescriptionSnapshot?
    
    /// Whether user has marked this exercise as complete for the session
    var isCompleted: Bool = false
    
    /// Computed rep range for convenience
    var repRange: ClosedRange<Int> {
        repRangeMin...repRangeMax
    }
    
    /// Alias for setsTarget for backward compatibility with views.
    var plannedSets: Int {
        setsTarget
    }
    
    // Backward-compatible decoding
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        exercise = try container.decode(ExerciseRef.self, forKey: .exercise)
        sets = try container.decode([WorkoutSet].self, forKey: .sets)
        nextPrescription = try container.decodeIfPresent(NextPrescriptionSnapshot.self, forKey: .nextPrescription)
        isCompleted = try container.decodeIfPresent(Bool.self, forKey: .isCompleted) ?? false
        
        // New fields with defaults
        setsTarget = try container.decodeIfPresent(Int.self, forKey: .setsTarget) ?? 3
        repRangeMin = try container.decodeIfPresent(Int.self, forKey: .repRangeMin) ?? 6
        repRangeMax = try container.decodeIfPresent(Int.self, forKey: .repRangeMax) ?? 10
        increment = try container.decodeIfPresent(Double.self, forKey: .increment) ?? 5
        deloadFactor = try container.decodeIfPresent(Double.self, forKey: .deloadFactor) ?? ProgressionDefaults.deloadFactor
        failureThreshold = try container.decodeIfPresent(Int.self, forKey: .failureThreshold) ?? ProgressionDefaults.failureThreshold
        targetRIR = try container.decodeIfPresent(Int.self, forKey: .targetRIR) ?? 2
        tempo = try container.decodeIfPresent(TempoSpec.self, forKey: .tempo) ?? .standard
        restSeconds = try container.decodeIfPresent(Int.self, forKey: .restSeconds) ?? 120
        
        // Legacy field support
        if let legacyPlannedSets = try? container.decode(Int.self, forKey: .legacyPlannedSets) {
            setsTarget = legacyPlannedSets
        }
        if let legacyRange = try? container.decode(LegacyClosedRange.self, forKey: .legacyRepRange) {
            repRangeMin = legacyRange.lowerBound
            repRangeMax = legacyRange.upperBound
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(exercise, forKey: .exercise)
        try container.encode(setsTarget, forKey: .setsTarget)
        try container.encode(repRangeMin, forKey: .repRangeMin)
        try container.encode(repRangeMax, forKey: .repRangeMax)
        try container.encode(increment, forKey: .increment)
        try container.encode(deloadFactor, forKey: .deloadFactor)
        try container.encode(failureThreshold, forKey: .failureThreshold)
        try container.encode(targetRIR, forKey: .targetRIR)
        try container.encode(tempo, forKey: .tempo)
        try container.encode(restSeconds, forKey: .restSeconds)
        try container.encode(sets, forKey: .sets)
        try container.encodeIfPresent(nextPrescription, forKey: .nextPrescription)
        try container.encode(isCompleted, forKey: .isCompleted)
    }
    
    private enum CodingKeys: String, CodingKey {
        case id, exercise, setsTarget, repRangeMin, repRangeMax, increment, deloadFactor, failureThreshold, targetRIR, tempo, restSeconds, sets, nextPrescription, isCompleted
        case legacyPlannedSets = "plannedSets"
        case legacyRepRange = "repRange"
    }
    
    init(
        id: UUID = UUID(),
        exercise: ExerciseRef,
        setsTarget: Int,
        repRangeMin: Int,
        repRangeMax: Int,
        increment: Double,
        deloadFactor: Double,
        failureThreshold: Int,
        targetRIR: Int = 2,
        tempo: TempoSpec = .standard,
        restSeconds: Int = 120,
        sets: [WorkoutSet],
        nextPrescription: NextPrescriptionSnapshot? = nil,
        isCompleted: Bool = false
    ) {
        self.id = id
        self.exercise = exercise
        self.setsTarget = setsTarget
        self.repRangeMin = repRangeMin
        self.repRangeMax = repRangeMax
        self.increment = increment
        self.deloadFactor = deloadFactor
        self.failureThreshold = failureThreshold
        self.targetRIR = targetRIR
        self.tempo = tempo
        self.restSeconds = restSeconds
        self.sets = sets
        self.nextPrescription = nextPrescription
        self.isCompleted = isCompleted
    }
    
    /// Initialize from template exercise settings
    init(from templateExercise: WorkoutTemplateExercise, sets: [WorkoutSet]) {
        self.id = UUID()
        self.exercise = templateExercise.exercise
        self.setsTarget = templateExercise.setsTarget
        self.repRangeMin = templateExercise.repRangeMin
        self.repRangeMax = templateExercise.repRangeMax
        self.increment = templateExercise.increment
        self.deloadFactor = templateExercise.deloadFactor
        self.failureThreshold = templateExercise.failureThreshold
        self.targetRIR = templateExercise.targetRIR
        self.tempo = templateExercise.tempo
        self.restSeconds = templateExercise.restSeconds
        self.sets = sets
        self.nextPrescription = nil
        self.isCompleted = false
    }
    
    /// Initialize from legacy format
    init(from legacy: LegacySessionExercise) {
        self.id = legacy.id
        self.exercise = legacy.exercise
        self.setsTarget = legacy.plannedSets
        self.repRangeMin = legacy.repRange.lowerBound
        self.repRangeMax = legacy.repRange.upperBound
        self.increment = legacy.increment
        self.deloadFactor = ProgressionDefaults.deloadFactor
        self.failureThreshold = ProgressionDefaults.failureThreshold
        self.targetRIR = 2
        self.tempo = .standard
        self.restSeconds = 120
        self.sets = legacy.sets
        self.nextPrescription = nil
        self.isCompleted = false
    }
}

// MARK: - Workout Set

struct WorkoutSet: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var reps: Int
    var weight: Double
    var isCompleted: Bool = false
    
    /// Optional observed RIR (reps in reserve).
    var rirObserved: Int? = nil
    
    /// Optional observed RPE (1-10). If present and `rirObserved` is nil, the bridge may derive RIR.
    var rpeObserved: Double? = nil
    
    /// Whether this was a warmup set.
    var isWarmup: Bool = false
    
    /// Optional notes for the set.
    var notes: String? = nil
}

// MARK: - Exercise State (persisted per exercise per user)

struct ExerciseState: Codable, Identifiable, Hashable {
    var id: String { exerciseId }
    var exerciseId: String
    var currentWorkingWeight: Double
    var failuresCount: Int
    
    /// Rolling estimated 1RM (lbs). Used for strength-aware progression scaling.
    var rollingE1RM: Double?
    
    enum E1RMTrend: String, Codable, Hashable {
        case improving
        case stable
        case declining
        case insufficient
    }
    
    var e1rmTrend: E1RMTrend
    
    struct E1RMSampleLite: Codable, Hashable {
        var date: Date
        var value: Double // lbs
        
        init(date: Date, value: Double) {
            self.date = date
            self.value = value
        }
    }
    
    /// Recent e1RM samples (bounded). Used for plateau detection + "learning" progression speed.
    var e1rmHistory: [E1RMSampleLite]
    
    /// Date of last deload affecting this lift (if known).
    var lastDeloadAt: Date?
    
    /// Cumulative successful sessions count (non-failure sessions).
    var successfulSessionsCount: Int
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case exerciseId
        case currentWorkingWeight
        case failuresCount
        case rollingE1RM
        case e1rmTrend
        case e1rmHistory
        case lastDeloadAt
        case successfulSessionsCount
        case updatedAt
    }
    
    init(
        exerciseId: String,
        currentWorkingWeight: Double,
        failuresCount: Int = 0,
        rollingE1RM: Double? = nil,
        e1rmTrend: E1RMTrend = .insufficient,
        e1rmHistory: [E1RMSampleLite] = [],
        lastDeloadAt: Date? = nil,
        successfulSessionsCount: Int = 0,
        updatedAt: Date = Date()
    ) {
        self.exerciseId = exerciseId
        self.currentWorkingWeight = currentWorkingWeight
        self.failuresCount = failuresCount
        self.rollingE1RM = rollingE1RM
        self.e1rmTrend = e1rmTrend
        self.e1rmHistory = e1rmHistory
        self.lastDeloadAt = lastDeloadAt
        self.successfulSessionsCount = successfulSessionsCount
        self.updatedAt = updatedAt
    }
    
    // Backward-compatible decoding (older saves only had weight + failures + updatedAt).
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        exerciseId = try container.decode(String.self, forKey: .exerciseId)
        currentWorkingWeight = try container.decode(Double.self, forKey: .currentWorkingWeight)
        failuresCount = try container.decodeIfPresent(Int.self, forKey: .failuresCount) ?? 0
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
        
        rollingE1RM = try container.decodeIfPresent(Double.self, forKey: .rollingE1RM)
        e1rmTrend = try container.decodeIfPresent(E1RMTrend.self, forKey: .e1rmTrend) ?? .insufficient
        e1rmHistory = try container.decodeIfPresent([E1RMSampleLite].self, forKey: .e1rmHistory) ?? []
        lastDeloadAt = try container.decodeIfPresent(Date.self, forKey: .lastDeloadAt)
        successfulSessionsCount = try container.decodeIfPresent(Int.self, forKey: .successfulSessionsCount) ?? 0
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(exerciseId, forKey: .exerciseId)
        try container.encode(currentWorkingWeight, forKey: .currentWorkingWeight)
        try container.encode(failuresCount, forKey: .failuresCount)
        try container.encode(updatedAt, forKey: .updatedAt)
        
        try container.encodeIfPresent(rollingE1RM, forKey: .rollingE1RM)
        try container.encode(e1rmTrend, forKey: .e1rmTrend)
        try container.encode(e1rmHistory, forKey: .e1rmHistory)
        try container.encodeIfPresent(lastDeloadAt, forKey: .lastDeloadAt)
        try container.encode(successfulSessionsCount, forKey: .successfulSessionsCount)
    }
}

// MARK: - Next Prescription Snapshot (stored on session for history)

struct NextPrescriptionSnapshot: Codable, Hashable {
    var exerciseId: String
    var nextWorkingWeight: Double
    var targetReps: Int
    var setsTarget: Int
    var repRangeMin: Int
    var repRangeMax: Int
    var increment: Double
    var deloadFactor: Double
    var failureThreshold: Int
    var reason: ProgressionReason
    var createdAt: Date

    init(exerciseId: String, nextWorkingWeight: Double, targetReps: Int, setsTarget: Int, repRangeMin: Int, repRangeMax: Int, increment: Double, deloadFactor: Double, failureThreshold: Int, reason: ProgressionReason, createdAt: Date = Date()) {
        self.exerciseId = exerciseId
        self.nextWorkingWeight = nextWorkingWeight
        self.targetReps = targetReps
        self.setsTarget = setsTarget
        self.repRangeMin = repRangeMin
        self.repRangeMax = repRangeMax
        self.increment = increment
        self.deloadFactor = deloadFactor
        self.failureThreshold = failureThreshold
        self.reason = reason
        self.createdAt = createdAt
    }
    
    // Backward-compatible decoding
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        exerciseId = try container.decode(String.self, forKey: .exerciseId)
        nextWorkingWeight = try container.decode(Double.self, forKey: .nextWorkingWeight)
        targetReps = try container.decode(Int.self, forKey: .targetReps)
        setsTarget = try container.decode(Int.self, forKey: .setsTarget)
        repRangeMin = try container.decode(Int.self, forKey: .repRangeMin)
        repRangeMax = try container.decode(Int.self, forKey: .repRangeMax)
        increment = try container.decode(Double.self, forKey: .increment)
        deloadFactor = try container.decode(Double.self, forKey: .deloadFactor)
        failureThreshold = try container.decode(Int.self, forKey: .failureThreshold)
        reason = try container.decode(ProgressionReason.self, forKey: .reason)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
    }
}

enum ProgressionReason: String, Codable, Hashable {
    case increaseWeight
    case increaseReps
    case hold
    case deload
    
    var displayText: String {
        switch self {
        case .increaseWeight: return "Increase weight"
        case .increaseReps: return "Add reps"
        case .hold: return "Hold steady"
        case .deload: return "Deload"
        }
    }
    
    var detailText: String {
        switch self {
        case .increaseWeight:
            return "You hit the top of your rep range across sets. Increase load and reset reps to rebuild."
        case .increaseReps:
            return "You're inside your rep range. Keep the same load and add a rep next session."
        case .hold:
            return "Keep load and reps consistent until you can progress cleanly."
        case .deload:
            return "You've hit the failure threshold. Reduce load and rebuild with clean reps."
        }
    }
}

// MARK: - Legacy Types (for backward compatibility)

/// Legacy TemplateExercise format for decoding old data
struct LegacyTemplateExercise: Codable {
    var id: UUID = UUID()
    var exercise: ExerciseRef
    var sets: Int = 3
    var repRange: ClosedRange<Int> = 6...10
    var increment: Double = 5
}

/// Legacy SessionExercise format for decoding old data
struct LegacySessionExercise: Codable {
    var id: UUID = UUID()
    var exercise: ExerciseRef
    var plannedSets: Int
    var repRange: ClosedRange<Int>
    var increment: Double
    var sets: [WorkoutSet]
}

/// Helper for decoding ClosedRange from JSON
struct LegacyClosedRange: Codable {
    var lowerBound: Int
    var upperBound: Int

    init(lowerBound: Int, upperBound: Int) {
        self.lowerBound = lowerBound
        self.upperBound = upperBound
    }

    init(from decoder: Decoder) throws {
        // Swift's standard library currently encodes ClosedRange as an unkeyed array: [lower, upper].
        // We also support a keyed shape for robustness/backward compatibility.
        if var unkeyed = try? decoder.unkeyedContainer() {
            lowerBound = try unkeyed.decode(Int.self)
            upperBound = try unkeyed.decode(Int.self)
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        lowerBound = try container.decode(Int.self, forKey: .lowerBound)
        upperBound = try container.decode(Int.self, forKey: .upperBound)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(lowerBound)
        try container.encode(upperBound)
    }

    private enum CodingKeys: String, CodingKey {
        case lowerBound, upperBound
    }
}

// MARK: - Type Aliases for Backward Compatibility

/// Alias for backward compatibility with existing code
typealias TemplateExercise = WorkoutTemplateExercise

/// Alias for backward compatibility with existing code
typealias SessionExercise = ExercisePerformance
