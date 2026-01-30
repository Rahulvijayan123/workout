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

// MARK: - ML Data Collection Types

/// How the user responded to a recommendation (load, reps, exercise choice)
enum RecommendationCompliance: String, Codable, Hashable, CaseIterable {
    case acceptedAsIs = "accepted_as_is"
    case modifiedUp = "modified_up"        // User increased load/reps beyond recommendation
    case modifiedDown = "modified_down"    // User decreased load/reps from recommendation
    case ignored = "ignored"               // User completely ignored recommendation
    case notApplicable = "not_applicable"  // No recommendation was given (e.g., first session)
    
    var displayText: String {
        switch self {
        case .acceptedAsIs: return "Followed recommendation"
        case .modifiedUp: return "Went heavier/more"
        case .modifiedDown: return "Went lighter/less"
        case .ignored: return "Did own thing"
        case .notApplicable: return "No recommendation"
        }
    }
}

/// Reason code for why user modified or ignored a recommendation
enum ComplianceReasonCode: String, Codable, Hashable, CaseIterable {
    case feltStrong = "felt_strong"
    case feltWeak = "felt_weak"
    case pain = "pain"
    case fatigue = "fatigue"
    case equipmentUnavailable = "equipment_unavailable"
    case timeConstraint = "time_constraint"
    case formConcern = "form_concern"
    case warmupInsufficient = "warmup_insufficient"
    case personalPreference = "personal_preference"
    case testingMax = "testing_max"
    case other = "other"
    case none = "none"
    
    var displayText: String {
        switch self {
        case .feltStrong: return "Felt strong"
        case .feltWeak: return "Felt weak"
        case .pain: return "Pain/discomfort"
        case .fatigue: return "Too fatigued"
        case .equipmentUnavailable: return "Equipment unavailable"
        case .timeConstraint: return "Short on time"
        case .formConcern: return "Form breaking down"
        case .warmupInsufficient: return "Needed more warmup"
        case .personalPreference: return "Personal preference"
        case .testingMax: return "Testing max"
        case .other: return "Other"
        case .none: return "N/A"
        }
    }
}

/// Body region for pain/injury tracking
enum BodyRegion: String, Codable, Hashable, CaseIterable {
    case neck = "neck"
    case shoulder = "shoulder"
    case upperBack = "upper_back"
    case lowerBack = "lower_back"
    case chest = "chest"
    case bicep = "bicep"
    case tricep = "tricep"
    case forearm = "forearm"
    case wrist = "wrist"
    case hand = "hand"
    case hip = "hip"
    case glute = "glute"
    case quad = "quad"
    case hamstring = "hamstring"
    case knee = "knee"
    case calf = "calf"
    case ankle = "ankle"
    case foot = "foot"
    case core = "core"
    case other = "other"
    
    var displayText: String {
        switch self {
        case .neck: return "Neck"
        case .shoulder: return "Shoulder"
        case .upperBack: return "Upper Back"
        case .lowerBack: return "Lower Back"
        case .chest: return "Chest"
        case .bicep: return "Bicep"
        case .tricep: return "Tricep"
        case .forearm: return "Forearm"
        case .wrist: return "Wrist"
        case .hand: return "Hand"
        case .hip: return "Hip"
        case .glute: return "Glute"
        case .quad: return "Quad"
        case .hamstring: return "Hamstring"
        case .knee: return "Knee"
        case .calf: return "Calf"
        case .ankle: return "Ankle"
        case .foot: return "Foot"
        case .core: return "Core/Abs"
        case .other: return "Other"
        }
    }
}

/// Pain/injury entry for tracking discomfort
struct PainEntry: Codable, Hashable, Identifiable {
    var id: UUID = UUID()
    var region: BodyRegion
    var severity: Int  // 0-10 scale
    var notes: String?
    
    init(id: UUID = UUID(), region: BodyRegion, severity: Int, notes: String? = nil) {
        self.id = id
        self.region = region
        self.severity = max(0, min(10, severity))
        self.notes = notes
    }
}

/// Reason for exercise substitution
enum SubstitutionReason: String, Codable, Hashable, CaseIterable {
    case equipmentUnavailable = "equipment_unavailable"
    case pain = "pain"
    case fatigue = "fatigue"
    case variety = "variety"
    case progression = "progression"  // Switched to harder/easier variation
    case timeConstraint = "time_constraint"
    case personalPreference = "personal_preference"
    case other = "other"
    case none = "none"
    
    var displayText: String {
        switch self {
        case .equipmentUnavailable: return "Equipment unavailable"
        case .pain: return "Pain/injury"
        case .fatigue: return "Fatigue"
        case .variety: return "Wanted variety"
        case .progression: return "Progression variant"
        case .timeConstraint: return "Time constraint"
        case .personalPreference: return "Personal preference"
        case .other: return "Other"
        case .none: return "N/A"
        }
    }
}

/// Coarse nutrition bucket (not requiring precise tracking)
enum NutritionBucket: String, Codable, Hashable, CaseIterable {
    case deficit = "deficit"
    case maintenance = "maintenance"
    case surplus = "surplus"
    case unknown = "unknown"
    
    var displayText: String {
        switch self {
        case .deficit: return "Cutting (deficit)"
        case .maintenance: return "Maintenance"
        case .surplus: return "Bulking (surplus)"
        case .unknown: return "Unknown"
        }
    }
}

/// Coarse protein intake bucket
enum ProteinBucket: String, Codable, Hashable, CaseIterable {
    case low = "low"       // < 1.4g/kg
    case adequate = "adequate"  // 1.4-2.0g/kg
    case high = "high"     // > 2.0g/kg
    case unknown = "unknown"
    
    var displayText: String {
        switch self {
        case .low: return "Low protein"
        case .adequate: return "Adequate protein"
        case .high: return "High protein"
        case .unknown: return "Unknown"
        }
    }
}

/// Menstrual cycle phase (opt-in, for female users)
enum CyclePhase: String, Codable, Hashable, CaseIterable {
    case menstrual = "menstrual"        // Days 1-5 typically
    case follicular = "follicular"      // Days 6-14 typically
    case ovulatory = "ovulatory"        // Days 14-16 typically
    case luteal = "luteal"              // Days 17-28 typically
    case notTracking = "not_tracking"
    case notApplicable = "not_applicable"
    
    var displayText: String {
        switch self {
        case .menstrual: return "Menstrual"
        case .follicular: return "Follicular"
        case .ovulatory: return "Ovulatory"
        case .luteal: return "Luteal"
        case .notTracking: return "Not tracking"
        case .notApplicable: return "N/A"
        }
    }
}

/// Life stress/disruption flags
struct LifeStressFlags: Codable, Hashable {
    var illness: Bool = false
    var travel: Bool = false
    var workStress: Bool = false
    var poorSleep: Bool = false
    var other: Bool = false
    var notes: String?
    
    var hasAnyFlag: Bool {
        illness || travel || workStress || poorSleep || other
    }
    
    init(illness: Bool = false, travel: Bool = false, workStress: Bool = false, 
         poorSleep: Bool = false, other: Bool = false, notes: String? = nil) {
        self.illness = illness
        self.travel = travel
        self.workStress = workStress
        self.poorSleep = poorSleep
        self.other = other
        self.notes = notes
    }
}

/// Equipment variation used (for tracking when user uses different equipment)
enum EquipmentVariation: String, Codable, Hashable, CaseIterable {
    case standard = "standard"           // Used prescribed equipment
    case barbellToDbDumbbell = "bb_to_db"  // Barbell → Dumbbell
    case dumbbellToBarbell = "db_to_bb"
    case freeWeightToMachine = "fw_to_machine"
    case machineToFreeWeight = "machine_to_fw"
    case cableToFreeWeight = "cable_to_fw"
    case freeWeightToCable = "fw_to_cable"
    case bandAssisted = "band_assisted"
    case bandResisted = "band_resisted"
    case other = "other"
    
    var displayText: String {
        switch self {
        case .standard: return "As prescribed"
        case .barbellToDbDumbbell: return "Barbell → Dumbbell"
        case .dumbbellToBarbell: return "Dumbbell → Barbell"
        case .freeWeightToMachine: return "Free weight → Machine"
        case .machineToFreeWeight: return "Machine → Free weight"
        case .cableToFreeWeight: return "Cable → Free weight"
        case .freeWeightToCable: return "Free weight → Cable"
        case .bandAssisted: return "Band assisted"
        case .bandResisted: return "Band resisted"
        case .other: return "Other variation"
        }
    }
}

/// Technique/ROM limitation flags
struct TechniqueLimitations: Codable, Hashable {
    var limitedROM: Bool = false
    var gripIssue: Bool = false
    var stabilityIssue: Bool = false
    var breathingIssue: Bool = false
    var other: Bool = false
    var notes: String?
    
    var hasAnyLimitation: Bool {
        limitedROM || gripIssue || stabilityIssue || breathingIssue || other
    }
    
    init(limitedROM: Bool = false, gripIssue: Bool = false, stabilityIssue: Bool = false,
         breathingIssue: Bool = false, other: Bool = false, notes: String? = nil) {
        self.limitedROM = limitedROM
        self.gripIssue = gripIssue
        self.stabilityIssue = stabilityIssue
        self.breathingIssue = breathingIssue
        self.other = other
        self.notes = notes
    }
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
    
    /// Computed readiness score (0-100) captured at session start.
    /// Used to track readiness history per-lift and inform progression decisions.
    /// This is set once at session creation and should not be modified afterward.
    var computedReadinessScore: Int?
    
    var isActive: Bool { endedAt == nil }
    
    // MARK: - Pre-Session Subjective Signals (Readiness)
    
    /// Pre-workout readiness score (1-5 scale, simple)
    var preWorkoutReadiness: Int? = nil
    
    /// Pre-workout soreness level (0-10 scale)
    var preWorkoutSoreness: Int? = nil
    
    /// Pre-workout energy level (1-5 scale)
    var preWorkoutEnergy: Int? = nil
    
    /// Pre-workout motivation level (1-5 scale)
    var preWorkoutMotivation: Int? = nil
    
    // MARK: - Post-Session Subjective Signals
    
    /// Session RPE (1-10 scale) - validated internal load metric
    var sessionRPE: Int? = nil
    
    /// Post-workout overall feeling (1-5 scale)
    var postWorkoutFeeling: Int? = nil
    
    /// Whether the session felt harder than expected
    var harderThanExpected: Bool? = nil
    
    /// Post-session notes
    var sessionNotes: String? = nil
    
    // MARK: - Session-Level Pain/Injury (Safety Critical)
    
    /// Session-level pain entries
    var sessionPainEntries: [PainEntry]? = nil
    
    /// Maximum pain level experienced during session (0-10)
    var maxPainLevel: Int? = nil
    
    /// Whether any exercise was stopped due to pain
    var anyExerciseStoppedDueToPain: Bool {
        exercises.contains { $0.stoppedDueToPain }
    }
    
    // MARK: - Context Signals
    
    /// Life stress flags (illness, travel, work stress, etc.)
    var lifeStressFlags: LifeStressFlags? = nil
    
    /// Time of day category
    var timeOfDay: TimeOfDay? = nil
    
    /// Whether this was a fasted workout
    var wasFasted: Bool? = nil
    
    /// Hours since last meal (if known)
    var hoursSinceLastMeal: Double? = nil
    
    /// Quality of sleep night before (1-5)
    var sleepQualityLastNight: Int? = nil
    
    /// Hours of sleep night before
    var sleepHoursLastNight: Double? = nil
    
    // MARK: - Computed Properties
    
    /// Computed: Total pain entries across session and exercises
    var allPainEntries: [PainEntry] {
        var entries = sessionPainEntries ?? []
        for exercise in exercises {
            if let exercisePain = exercise.painEntries {
                entries.append(contentsOf: exercisePain)
            }
        }
        return entries
    }
    
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
        
        // Computed readiness score
        computedReadinessScore = try container.decodeIfPresent(Int.self, forKey: .computedReadinessScore)
        
        // Pre-session signals
        preWorkoutReadiness = try container.decodeIfPresent(Int.self, forKey: .preWorkoutReadiness)
        preWorkoutSoreness = try container.decodeIfPresent(Int.self, forKey: .preWorkoutSoreness)
        preWorkoutEnergy = try container.decodeIfPresent(Int.self, forKey: .preWorkoutEnergy)
        preWorkoutMotivation = try container.decodeIfPresent(Int.self, forKey: .preWorkoutMotivation)
        
        // Post-session signals
        sessionRPE = try container.decodeIfPresent(Int.self, forKey: .sessionRPE)
        postWorkoutFeeling = try container.decodeIfPresent(Int.self, forKey: .postWorkoutFeeling)
        harderThanExpected = try container.decodeIfPresent(Bool.self, forKey: .harderThanExpected)
        sessionNotes = try container.decodeIfPresent(String.self, forKey: .sessionNotes)
        
        // Pain/injury
        sessionPainEntries = try container.decodeIfPresent([PainEntry].self, forKey: .sessionPainEntries)
        maxPainLevel = try container.decodeIfPresent(Int.self, forKey: .maxPainLevel)
        
        // Context signals
        lifeStressFlags = try container.decodeIfPresent(LifeStressFlags.self, forKey: .lifeStressFlags)
        timeOfDay = try container.decodeIfPresent(TimeOfDay.self, forKey: .timeOfDay)
        wasFasted = try container.decodeIfPresent(Bool.self, forKey: .wasFasted)
        hoursSinceLastMeal = try container.decodeIfPresent(Double.self, forKey: .hoursSinceLastMeal)
        sleepQualityLastNight = try container.decodeIfPresent(Int.self, forKey: .sleepQualityLastNight)
        sleepHoursLastNight = try container.decodeIfPresent(Double.self, forKey: .sleepHoursLastNight)
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
        
        // Computed readiness score
        try container.encodeIfPresent(computedReadinessScore, forKey: .computedReadinessScore)
        
        // Pre-session signals
        try container.encodeIfPresent(preWorkoutReadiness, forKey: .preWorkoutReadiness)
        try container.encodeIfPresent(preWorkoutSoreness, forKey: .preWorkoutSoreness)
        try container.encodeIfPresent(preWorkoutEnergy, forKey: .preWorkoutEnergy)
        try container.encodeIfPresent(preWorkoutMotivation, forKey: .preWorkoutMotivation)
        
        // Post-session signals
        try container.encodeIfPresent(sessionRPE, forKey: .sessionRPE)
        try container.encodeIfPresent(postWorkoutFeeling, forKey: .postWorkoutFeeling)
        try container.encodeIfPresent(harderThanExpected, forKey: .harderThanExpected)
        try container.encodeIfPresent(sessionNotes, forKey: .sessionNotes)
        
        // Pain/injury
        try container.encodeIfPresent(sessionPainEntries, forKey: .sessionPainEntries)
        try container.encodeIfPresent(maxPainLevel, forKey: .maxPainLevel)
        
        // Context signals
        try container.encodeIfPresent(lifeStressFlags, forKey: .lifeStressFlags)
        try container.encodeIfPresent(timeOfDay, forKey: .timeOfDay)
        try container.encodeIfPresent(wasFasted, forKey: .wasFasted)
        try container.encodeIfPresent(hoursSinceLastMeal, forKey: .hoursSinceLastMeal)
        try container.encodeIfPresent(sleepQualityLastNight, forKey: .sleepQualityLastNight)
        try container.encodeIfPresent(sleepHoursLastNight, forKey: .sleepHoursLastNight)
    }
    
    private enum CodingKeys: String, CodingKey {
        case id, templateId, name, startedAt, endedAt, wasDeload, deloadReason, exercises
        case computedReadinessScore
        case preWorkoutReadiness, preWorkoutSoreness, preWorkoutEnergy, preWorkoutMotivation
        case sessionRPE, postWorkoutFeeling, harderThanExpected, sessionNotes
        case sessionPainEntries, maxPainLevel
        case lifeStressFlags, timeOfDay, wasFasted, hoursSinceLastMeal, sleepQualityLastNight, sleepHoursLastNight
    }
    
    init(
        id: UUID = UUID(),
        templateId: UUID? = nil,
        name: String,
        startedAt: Date = Date(),
        endedAt: Date? = nil,
        wasDeload: Bool = false,
        deloadReason: String? = nil,
        exercises: [ExercisePerformance],
        computedReadinessScore: Int? = nil,
        preWorkoutReadiness: Int? = nil,
        preWorkoutSoreness: Int? = nil,
        preWorkoutEnergy: Int? = nil,
        preWorkoutMotivation: Int? = nil,
        sessionRPE: Int? = nil,
        postWorkoutFeeling: Int? = nil,
        harderThanExpected: Bool? = nil,
        sessionNotes: String? = nil,
        sessionPainEntries: [PainEntry]? = nil,
        maxPainLevel: Int? = nil,
        lifeStressFlags: LifeStressFlags? = nil,
        timeOfDay: TimeOfDay? = nil,
        wasFasted: Bool? = nil,
        hoursSinceLastMeal: Double? = nil,
        sleepQualityLastNight: Int? = nil,
        sleepHoursLastNight: Double? = nil
    ) {
        self.id = id
        self.templateId = templateId
        self.name = name
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.wasDeload = wasDeload
        self.deloadReason = deloadReason
        self.exercises = exercises
        self.computedReadinessScore = computedReadinessScore
        self.preWorkoutReadiness = preWorkoutReadiness
        self.preWorkoutSoreness = preWorkoutSoreness
        self.preWorkoutEnergy = preWorkoutEnergy
        self.preWorkoutMotivation = preWorkoutMotivation
        self.sessionRPE = sessionRPE
        self.postWorkoutFeeling = postWorkoutFeeling
        self.harderThanExpected = harderThanExpected
        self.sessionNotes = sessionNotes
        self.sessionPainEntries = sessionPainEntries
        self.maxPainLevel = maxPainLevel
        self.lifeStressFlags = lifeStressFlags
        self.timeOfDay = timeOfDay
        self.wasFasted = wasFasted
        self.hoursSinceLastMeal = hoursSinceLastMeal
        self.sleepQualityLastNight = sleepQualityLastNight
        self.sleepHoursLastNight = sleepHoursLastNight
    }
}

/// Time of day category for session
enum TimeOfDay: String, Codable, Hashable, CaseIterable {
    case earlyMorning = "early_morning"  // 5-8am
    case morning = "morning"              // 8-11am
    case midday = "midday"                // 11am-2pm
    case afternoon = "afternoon"          // 2-5pm
    case evening = "evening"              // 5-8pm
    case night = "night"                  // 8pm+
    
    var displayText: String {
        switch self {
        case .earlyMorning: return "Early Morning (5-8am)"
        case .morning: return "Morning (8-11am)"
        case .midday: return "Midday (11am-2pm)"
        case .afternoon: return "Afternoon (2-5pm)"
        case .evening: return "Evening (5-8pm)"
        case .night: return "Night (8pm+)"
        }
    }
    
    /// Derive time of day from a date
    static func from(date: Date) -> TimeOfDay {
        let hour = Calendar.current.component(.hour, from: date)
        switch hour {
        case 5..<8: return .earlyMorning
        case 8..<11: return .morning
        case 11..<14: return .midday
        case 14..<17: return .afternoon
        case 17..<20: return .evening
        default: return .night
        }
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
    
    // MARK: - Pain/Injury Tracking (Safety Critical)
    
    /// Pain entries for this exercise (0-10 scale per body region)
    var painEntries: [PainEntry]? = nil
    
    /// Overall pain level during this exercise (0-10, quick entry)
    var overallPainLevel: Int? = nil
    
    /// Whether exercise was stopped due to pain
    var stoppedDueToPain: Bool = false
    
    // MARK: - Substitution Tracking
    
    /// Original exercise that was prescribed (if this is a substitution)
    var originalExerciseId: String? = nil
    
    /// Original exercise name (for display)
    var originalExerciseName: String? = nil
    
    /// Reason for substitution
    var substitutionReason: SubstitutionReason? = nil
    
    /// Whether this was a substitution
    var isSubstitution: Bool {
        originalExerciseId != nil
    }
    
    // MARK: - Equipment Variation
    
    /// Equipment variation used (if different from prescribed)
    var equipmentVariation: EquipmentVariation? = nil
    
    // MARK: - Exercise-Level Compliance
    
    /// Overall compliance for the exercise (aggregated from sets or exercise-level decision)
    var exerciseCompliance: RecommendationCompliance? = nil
    
    /// Reason for exercise-level modification
    var exerciseComplianceReason: ComplianceReasonCode? = nil
    
    // MARK: - Technique Notes
    
    /// Exercise-level technique limitations
    var techniqueLimitations: TechniqueLimitations? = nil
    
    // MARK: - State Snapshot (CRITICAL for ML - prevents leakage)
    
    /// Lift state snapshot at session start - DO NOT update after session starts
    var stateSnapshot: LiftStateSessionSnapshot? = nil
    
    // MARK: - Exposure Definition (For consistent modeling)
    
    /// The role/structure of this exposure
    var exposureRole: ExposureRole? = nil
    
    /// ID of the primary/anchor set (typically the heaviest working set)
    var primarySetId: UUID? = nil
    
    /// Planned top set weight (from prescription)
    var plannedTopSetWeightLbs: Double? = nil
    
    /// Planned top set reps (from prescription)
    var plannedTopSetReps: Int? = nil
    
    /// Planned target RIR for top set
    var plannedTargetRIR: Int? = nil
    
    /// Performed top set weight (what was actually done)
    var performedTopSetWeightLbs: Double? = nil
    
    /// Performed top set reps
    var performedTopSetReps: Int? = nil
    
    /// Performed top set RIR (if logged)
    var performedTopSetRIR: Int? = nil
    
    // MARK: - Outcome Labels (Computed after session)
    
    /// Exposure outcome (success/partial/failure/pain_stop/unknown_difficulty)
    var exposureOutcome: ExposureOutcome? = nil
    
    /// Number of sets with clean success labels
    var setsSuccessful: Int? = nil
    
    /// Number of sets with clean failure labels
    var setsFailed: Int? = nil
    
    /// Number of sets with unknown difficulty (RIR missing)
    var setsUnknownDifficulty: Int? = nil
    
    /// Best e1RM achieved this session (Brzycki, reps <= 12, working sets only)
    var sessionE1rmLbs: Double? = nil
    
    /// Raw e1RM from top set (unsmoothed)
    var rawTopSetE1rmLbs: Double? = nil
    
    /// Delta from state snapshot rolling e1RM
    var e1rmDeltaLbs: Double? = nil
    
    // MARK: - Near-Failure Signals (Auxiliary label for early training)
    
    /// Near-failure signals for this exposure
    var nearFailureSignals: NearFailureSignals? = nil
    
    // MARK: - Modification Tracking (Numeric)
    
    /// Numeric modification details (delta weight, delta reps, direction)
    var modificationDetails: ModificationDetails? = nil
    
    // MARK: - Recommendation Event Link
    
    /// ID of the recommendation event that prescribed this exercise
    var recommendationEventId: UUID? = nil
    
    /// Computed rep range for convenience
    var repRange: ClosedRange<Int> {
        repRangeMin...repRangeMax
    }
    
    /// Compute outcome labels from set results
    /// Uses 3-state labels: SUCCESS, FAIL, UNKNOWN_DIFFICULTY
    mutating func computeOutcomes() {
        let workingSets = sets.filter { !$0.isWarmup && $0.isCompleted }
        
        var successCount = 0
        var failCount = 0
        var unknownCount = 0
        var setOutcomes: [SetOutcome] = []
        var topSet: WorkoutSet? = nil
        var topSetE1rm: Double? = nil
        var bestE1rm: Double? = nil
        
        for set in workingSets {
            // Compute set outcome using 3-state labels
            let outcome = SetOutcome.compute(
                repsAchieved: set.reps,
                targetReps: set.recommendedReps ?? repRangeMin,
                rirObserved: set.rirObserved,
                targetRIR: set.targetRIR ?? targetRIR,
                isFailure: set.isFailure,
                painStop: false
            )
            setOutcomes.append(outcome)
            
            // Count by outcome type
            switch outcome {
            case .success:
                successCount += 1
            case .failure, .grinder:
                failCount += 1
            case .unknownDifficulty:
                unknownCount += 1
            case .painStop, .skipped:
                break  // Don't count
            }
            
            // Track top set (heaviest weight)
            if topSet == nil || set.weight > topSet!.weight {
                topSet = set
            }
            
            // Compute e1RM with guards
            if let e1rm = E1RMComputationConfig.computeE1RM(
                weightLbs: set.weight,
                reps: set.reps,
                currentE1rmLbs: stateSnapshot?.rollingE1rmLbs,
                isFailure: set.isFailure,
                isWarmup: set.isWarmup
            ) {
                if bestE1rm == nil || e1rm > bestE1rm! {
                    bestE1rm = e1rm
                }
                // Track top set e1RM separately
                if set.id == topSet?.id {
                    topSetE1rm = e1rm
                }
            }
        }
        
        // Store counts
        setsSuccessful = successCount
        setsFailed = failCount
        setsUnknownDifficulty = unknownCount
        
        // Store e1RM values
        sessionE1rmLbs = bestE1rm
        rawTopSetE1rmLbs = topSetE1rm
        
        // Store top set info
        if let top = topSet {
            primarySetId = top.id
            performedTopSetWeightLbs = top.weight
            performedTopSetReps = top.reps
            performedTopSetRIR = top.rirObserved
        }
        
        // Compute e1RM delta
        if let snapshot = stateSnapshot, let sessionE1rm = bestE1rm, let snapshotE1rm = snapshot.rollingE1rmLbs {
            e1rmDeltaLbs = sessionE1rm - snapshotE1rm
        }
        
        // Compute exposure outcome using 3-state logic
        exposureOutcome = ExposureOutcome.compute(
            setOutcomes: setOutcomes,
            stoppedDueToPain: stoppedDueToPain
        )
        
        // Compute near-failure signals
        var nearFailure = NearFailureSignals()
        nearFailure.missedReps = setOutcomes.contains(.failure)
        nearFailure.lastRepGrind = setOutcomes.contains(.grinder)
        
        // Check for unusually long rest (would need actual rest times)
        if let lastSet = workingSets.last, let actualRest = lastSet.actualRestSeconds {
            let prescribedRest = restSeconds
            if actualRest > Int(Double(prescribedRest) * 1.5) {
                nearFailure.unusuallyLongRest = true
            }
        }
        
        // Session ended early check (would need more context)
        // nearFailure.sessionEndedEarly = ...
        
        nearFailureSignals = nearFailure
        
        // Compute modification details if user modified
        if let plannedWeight = plannedTopSetWeightLbs,
           let plannedReps = plannedTopSetReps,
           let performedWeight = performedTopSetWeightLbs,
           let performedReps = performedTopSetReps {
            modificationDetails = ModificationDetails.compute(
                recommendedWeightLbs: plannedWeight,
                recommendedReps: plannedReps,
                actualWeightLbs: performedWeight,
                actualReps: performedReps,
                reasonCode: exerciseComplianceReason
            )
        }
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
        
        // Pain/injury fields
        painEntries = try container.decodeIfPresent([PainEntry].self, forKey: .painEntries)
        overallPainLevel = try container.decodeIfPresent(Int.self, forKey: .overallPainLevel)
        stoppedDueToPain = try container.decodeIfPresent(Bool.self, forKey: .stoppedDueToPain) ?? false
        
        // Substitution fields
        originalExerciseId = try container.decodeIfPresent(String.self, forKey: .originalExerciseId)
        originalExerciseName = try container.decodeIfPresent(String.self, forKey: .originalExerciseName)
        substitutionReason = try container.decodeIfPresent(SubstitutionReason.self, forKey: .substitutionReason)
        
        // Equipment/compliance fields
        equipmentVariation = try container.decodeIfPresent(EquipmentVariation.self, forKey: .equipmentVariation)
        exerciseCompliance = try container.decodeIfPresent(RecommendationCompliance.self, forKey: .exerciseCompliance)
        exerciseComplianceReason = try container.decodeIfPresent(ComplianceReasonCode.self, forKey: .exerciseComplianceReason)
        techniqueLimitations = try container.decodeIfPresent(TechniqueLimitations.self, forKey: .techniqueLimitations)
        
        // State snapshot (ML critical - prevents leakage)
        stateSnapshot = try container.decodeIfPresent(LiftStateSessionSnapshot.self, forKey: .stateSnapshot)
        
        // Exposure definition
        exposureRole = try container.decodeIfPresent(ExposureRole.self, forKey: .exposureRole)
        primarySetId = try container.decodeIfPresent(UUID.self, forKey: .primarySetId)
        plannedTopSetWeightLbs = try container.decodeIfPresent(Double.self, forKey: .plannedTopSetWeightLbs)
        plannedTopSetReps = try container.decodeIfPresent(Int.self, forKey: .plannedTopSetReps)
        plannedTargetRIR = try container.decodeIfPresent(Int.self, forKey: .plannedTargetRIR)
        performedTopSetWeightLbs = try container.decodeIfPresent(Double.self, forKey: .performedTopSetWeightLbs)
        performedTopSetReps = try container.decodeIfPresent(Int.self, forKey: .performedTopSetReps)
        performedTopSetRIR = try container.decodeIfPresent(Int.self, forKey: .performedTopSetRIR)
        
        // Outcome labels
        exposureOutcome = try container.decodeIfPresent(ExposureOutcome.self, forKey: .exposureOutcome)
        setsSuccessful = try container.decodeIfPresent(Int.self, forKey: .setsSuccessful)
        setsFailed = try container.decodeIfPresent(Int.self, forKey: .setsFailed)
        setsUnknownDifficulty = try container.decodeIfPresent(Int.self, forKey: .setsUnknownDifficulty)
        sessionE1rmLbs = try container.decodeIfPresent(Double.self, forKey: .sessionE1rmLbs)
        rawTopSetE1rmLbs = try container.decodeIfPresent(Double.self, forKey: .rawTopSetE1rmLbs)
        e1rmDeltaLbs = try container.decodeIfPresent(Double.self, forKey: .e1rmDeltaLbs)
        
        // Near-failure and modification
        nearFailureSignals = try container.decodeIfPresent(NearFailureSignals.self, forKey: .nearFailureSignals)
        modificationDetails = try container.decodeIfPresent(ModificationDetails.self, forKey: .modificationDetails)
        recommendationEventId = try container.decodeIfPresent(UUID.self, forKey: .recommendationEventId)
        
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
        
        // Pain/injury fields
        try container.encodeIfPresent(painEntries, forKey: .painEntries)
        try container.encodeIfPresent(overallPainLevel, forKey: .overallPainLevel)
        try container.encode(stoppedDueToPain, forKey: .stoppedDueToPain)
        
        // Substitution fields
        try container.encodeIfPresent(originalExerciseId, forKey: .originalExerciseId)
        try container.encodeIfPresent(originalExerciseName, forKey: .originalExerciseName)
        try container.encodeIfPresent(substitutionReason, forKey: .substitutionReason)
        
        // Equipment/compliance fields
        try container.encodeIfPresent(equipmentVariation, forKey: .equipmentVariation)
        try container.encodeIfPresent(exerciseCompliance, forKey: .exerciseCompliance)
        try container.encodeIfPresent(exerciseComplianceReason, forKey: .exerciseComplianceReason)
        try container.encodeIfPresent(techniqueLimitations, forKey: .techniqueLimitations)
        
        // State snapshot (ML critical - prevents leakage)
        try container.encodeIfPresent(stateSnapshot, forKey: .stateSnapshot)
        
        // Exposure definition
        try container.encodeIfPresent(exposureRole, forKey: .exposureRole)
        try container.encodeIfPresent(primarySetId, forKey: .primarySetId)
        try container.encodeIfPresent(plannedTopSetWeightLbs, forKey: .plannedTopSetWeightLbs)
        try container.encodeIfPresent(plannedTopSetReps, forKey: .plannedTopSetReps)
        try container.encodeIfPresent(plannedTargetRIR, forKey: .plannedTargetRIR)
        try container.encodeIfPresent(performedTopSetWeightLbs, forKey: .performedTopSetWeightLbs)
        try container.encodeIfPresent(performedTopSetReps, forKey: .performedTopSetReps)
        try container.encodeIfPresent(performedTopSetRIR, forKey: .performedTopSetRIR)
        
        // Outcome labels
        try container.encodeIfPresent(exposureOutcome, forKey: .exposureOutcome)
        try container.encodeIfPresent(setsSuccessful, forKey: .setsSuccessful)
        try container.encodeIfPresent(setsFailed, forKey: .setsFailed)
        try container.encodeIfPresent(setsUnknownDifficulty, forKey: .setsUnknownDifficulty)
        try container.encodeIfPresent(sessionE1rmLbs, forKey: .sessionE1rmLbs)
        try container.encodeIfPresent(rawTopSetE1rmLbs, forKey: .rawTopSetE1rmLbs)
        try container.encodeIfPresent(e1rmDeltaLbs, forKey: .e1rmDeltaLbs)
        
        // Near-failure and modification
        try container.encodeIfPresent(nearFailureSignals, forKey: .nearFailureSignals)
        try container.encodeIfPresent(modificationDetails, forKey: .modificationDetails)
        try container.encodeIfPresent(recommendationEventId, forKey: .recommendationEventId)
    }
    
    private enum CodingKeys: String, CodingKey {
        case id, exercise, setsTarget, repRangeMin, repRangeMax, increment, deloadFactor, failureThreshold, targetRIR, tempo, restSeconds, sets, nextPrescription, isCompleted
        case painEntries, overallPainLevel, stoppedDueToPain
        case originalExerciseId, originalExerciseName, substitutionReason
        case equipmentVariation, exerciseCompliance, exerciseComplianceReason, techniqueLimitations
        case stateSnapshot
        // Exposure definition
        case exposureRole, primarySetId
        case plannedTopSetWeightLbs, plannedTopSetReps, plannedTargetRIR
        case performedTopSetWeightLbs, performedTopSetReps, performedTopSetRIR
        // Outcome labels
        case exposureOutcome, setsSuccessful, setsFailed, setsUnknownDifficulty
        case sessionE1rmLbs, rawTopSetE1rmLbs, e1rmDeltaLbs
        // Near-failure and modification
        case nearFailureSignals, modificationDetails
        case recommendationEventId
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
        isCompleted: Bool = false,
        painEntries: [PainEntry]? = nil,
        overallPainLevel: Int? = nil,
        stoppedDueToPain: Bool = false,
        originalExerciseId: String? = nil,
        originalExerciseName: String? = nil,
        substitutionReason: SubstitutionReason? = nil,
        equipmentVariation: EquipmentVariation? = nil,
        exerciseCompliance: RecommendationCompliance? = nil,
        exerciseComplianceReason: ComplianceReasonCode? = nil,
        techniqueLimitations: TechniqueLimitations? = nil
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
        self.painEntries = painEntries
        self.overallPainLevel = overallPainLevel
        self.stoppedDueToPain = stoppedDueToPain
        self.originalExerciseId = originalExerciseId
        self.originalExerciseName = originalExerciseName
        self.substitutionReason = substitutionReason
        self.equipmentVariation = equipmentVariation
        self.exerciseCompliance = exerciseCompliance
        self.exerciseComplianceReason = exerciseComplianceReason
        self.techniqueLimitations = techniqueLimitations
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
    
    // MARK: - Target Effort (Prescription)
    
    /// Target RIR for this set (from prescription). Critical for ML - comparing target vs observed.
    var targetRIR: Int? = nil
    
    /// Target RPE for this set (1-10, from prescription). Alternative to RIR.
    var targetRPE: Double? = nil
    
    // MARK: - Observed Effort (Actual)
    
    /// Optional observed RIR (reps in reserve).
    var rirObserved: Int? = nil
    
    /// Optional observed RPE (1-10). If present and `rirObserved` is nil, the bridge may derive RIR.
    var rpeObserved: Double? = nil
    
    // MARK: - Timing
    
    /// Timestamp when set was completed (for calculating actual rest periods)
    var completedAt: Date? = nil
    
    /// Actual rest time in seconds since previous set (calculated or manually entered)
    var actualRestSeconds: Int? = nil
    
    // MARK: - Set Classification
    
    /// Whether this was a warmup set.
    var isWarmup: Bool = false
    
    /// Whether this was a drop set.
    var isDropSet: Bool = false
    
    /// Whether this set was taken to failure.
    var isFailure: Bool = false
    
    // MARK: - Recommendation Compliance (ML Critical)
    
    /// How the user responded to the recommendation for this set
    var compliance: RecommendationCompliance? = nil
    
    /// Reason for modifying/ignoring recommendation
    var complianceReason: ComplianceReasonCode? = nil
    
    /// Weight that was recommended (to compare with actual)
    var recommendedWeight: Double? = nil
    
    /// Reps that were recommended (to compare with actual)
    var recommendedReps: Int? = nil
    
    // MARK: - Technique
    
    /// Tempo actually used (if different from prescription)
    var tempoActual: TempoSpec? = nil
    
    /// Technique limitations observed during this set
    var techniqueLimitations: TechniqueLimitations? = nil
    
    // MARK: - User Modifications (Critical for ML)
    
    /// Whether user modified this set from the prescription
    var isUserModified: Bool = false
    
    /// Original prescribed weight before user modification
    var originalPrescribedWeight: Double? = nil
    
    /// Original prescribed reps before user modification
    var originalPrescribedReps: Int? = nil
    
    /// Reason for modification (if modified)
    var modificationReason: ComplianceReasonCode? = nil
    
    // MARK: - Outcome Labels (Computed)
    
    /// Set outcome computed from performance vs targets
    var setOutcome: SetOutcome? = nil
    
    /// Whether rep target was met
    var metRepTarget: Bool? = nil
    
    /// Whether effort target was met (RIR within tolerance)
    var metEffortTarget: Bool? = nil
    
    // MARK: - Planned Set Link
    
    /// ID of the planned set this corresponds to
    var plannedSetId: UUID? = nil
    
    // MARK: - Notes
    
    /// Optional notes for the set.
    var notes: String? = nil
    
    // MARK: - Outcome Computation
    
    /// Compute outcome based on targets
    mutating func computeOutcome(targetReps: Int, targetRIR: Int) {
        metRepTarget = reps >= targetReps
        metEffortTarget = rirObserved == nil || rirObserved! >= (targetRIR - 1)
        
        setOutcome = SetOutcome.compute(
            repsAchieved: reps,
            targetReps: targetReps,
            rirObserved: rirObserved,
            targetRIR: targetRIR,
            isFailure: isFailure,
            painStop: false
        )
    }
    
    // MARK: - Initialization
    
    init(
        id: UUID = UUID(),
        reps: Int,
        weight: Double,
        isCompleted: Bool = false,
        targetRIR: Int? = nil,
        targetRPE: Double? = nil,
        rirObserved: Int? = nil,
        rpeObserved: Double? = nil,
        completedAt: Date? = nil,
        actualRestSeconds: Int? = nil,
        isWarmup: Bool = false,
        isDropSet: Bool = false,
        isFailure: Bool = false,
        compliance: RecommendationCompliance? = nil,
        complianceReason: ComplianceReasonCode? = nil,
        recommendedWeight: Double? = nil,
        recommendedReps: Int? = nil,
        tempoActual: TempoSpec? = nil,
        techniqueLimitations: TechniqueLimitations? = nil,
        isUserModified: Bool = false,
        originalPrescribedWeight: Double? = nil,
        originalPrescribedReps: Int? = nil,
        modificationReason: ComplianceReasonCode? = nil,
        setOutcome: SetOutcome? = nil,
        metRepTarget: Bool? = nil,
        metEffortTarget: Bool? = nil,
        plannedSetId: UUID? = nil,
        notes: String? = nil
    ) {
        self.id = id
        self.reps = reps
        self.weight = weight
        self.isCompleted = isCompleted
        self.targetRIR = targetRIR
        self.targetRPE = targetRPE
        self.rirObserved = rirObserved
        self.rpeObserved = rpeObserved
        self.completedAt = completedAt
        self.actualRestSeconds = actualRestSeconds
        self.isWarmup = isWarmup
        self.isDropSet = isDropSet
        self.isFailure = isFailure
        self.compliance = compliance
        self.complianceReason = complianceReason
        self.recommendedWeight = recommendedWeight
        self.recommendedReps = recommendedReps
        self.tempoActual = tempoActual
        self.techniqueLimitations = techniqueLimitations
        self.isUserModified = isUserModified
        self.originalPrescribedWeight = originalPrescribedWeight
        self.originalPrescribedReps = originalPrescribedReps
        self.modificationReason = modificationReason
        self.setOutcome = setOutcome
        self.metRepTarget = metRepTarget
        self.metEffortTarget = metEffortTarget
        self.plannedSetId = plannedSetId
        self.notes = notes
    }
    
    // Backward-compatible decoding
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        reps = try container.decode(Int.self, forKey: .reps)
        weight = try container.decode(Double.self, forKey: .weight)
        isCompleted = try container.decodeIfPresent(Bool.self, forKey: .isCompleted) ?? false
        
        // New fields with defaults
        targetRIR = try container.decodeIfPresent(Int.self, forKey: .targetRIR)
        targetRPE = try container.decodeIfPresent(Double.self, forKey: .targetRPE)
        rirObserved = try container.decodeIfPresent(Int.self, forKey: .rirObserved)
        rpeObserved = try container.decodeIfPresent(Double.self, forKey: .rpeObserved)
        completedAt = try container.decodeIfPresent(Date.self, forKey: .completedAt)
        actualRestSeconds = try container.decodeIfPresent(Int.self, forKey: .actualRestSeconds)
        isWarmup = try container.decodeIfPresent(Bool.self, forKey: .isWarmup) ?? false
        isDropSet = try container.decodeIfPresent(Bool.self, forKey: .isDropSet) ?? false
        isFailure = try container.decodeIfPresent(Bool.self, forKey: .isFailure) ?? false
        compliance = try container.decodeIfPresent(RecommendationCompliance.self, forKey: .compliance)
        complianceReason = try container.decodeIfPresent(ComplianceReasonCode.self, forKey: .complianceReason)
        recommendedWeight = try container.decodeIfPresent(Double.self, forKey: .recommendedWeight)
        recommendedReps = try container.decodeIfPresent(Int.self, forKey: .recommendedReps)
        tempoActual = try container.decodeIfPresent(TempoSpec.self, forKey: .tempoActual)
        techniqueLimitations = try container.decodeIfPresent(TechniqueLimitations.self, forKey: .techniqueLimitations)
        isUserModified = try container.decodeIfPresent(Bool.self, forKey: .isUserModified) ?? false
        originalPrescribedWeight = try container.decodeIfPresent(Double.self, forKey: .originalPrescribedWeight)
        originalPrescribedReps = try container.decodeIfPresent(Int.self, forKey: .originalPrescribedReps)
        modificationReason = try container.decodeIfPresent(ComplianceReasonCode.self, forKey: .modificationReason)
        setOutcome = try container.decodeIfPresent(SetOutcome.self, forKey: .setOutcome)
        metRepTarget = try container.decodeIfPresent(Bool.self, forKey: .metRepTarget)
        metEffortTarget = try container.decodeIfPresent(Bool.self, forKey: .metEffortTarget)
        plannedSetId = try container.decodeIfPresent(UUID.self, forKey: .plannedSetId)
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(reps, forKey: .reps)
        try container.encode(weight, forKey: .weight)
        try container.encode(isCompleted, forKey: .isCompleted)
        try container.encodeIfPresent(targetRIR, forKey: .targetRIR)
        try container.encodeIfPresent(targetRPE, forKey: .targetRPE)
        try container.encodeIfPresent(rirObserved, forKey: .rirObserved)
        try container.encodeIfPresent(rpeObserved, forKey: .rpeObserved)
        try container.encodeIfPresent(completedAt, forKey: .completedAt)
        try container.encodeIfPresent(actualRestSeconds, forKey: .actualRestSeconds)
        try container.encode(isWarmup, forKey: .isWarmup)
        try container.encode(isDropSet, forKey: .isDropSet)
        try container.encode(isFailure, forKey: .isFailure)
        try container.encodeIfPresent(compliance, forKey: .compliance)
        try container.encodeIfPresent(complianceReason, forKey: .complianceReason)
        try container.encodeIfPresent(recommendedWeight, forKey: .recommendedWeight)
        try container.encodeIfPresent(recommendedReps, forKey: .recommendedReps)
        try container.encodeIfPresent(tempoActual, forKey: .tempoActual)
        try container.encodeIfPresent(techniqueLimitations, forKey: .techniqueLimitations)
        try container.encode(isUserModified, forKey: .isUserModified)
        try container.encodeIfPresent(originalPrescribedWeight, forKey: .originalPrescribedWeight)
        try container.encodeIfPresent(originalPrescribedReps, forKey: .originalPrescribedReps)
        try container.encodeIfPresent(modificationReason, forKey: .modificationReason)
        try container.encodeIfPresent(setOutcome, forKey: .setOutcome)
        try container.encodeIfPresent(metRepTarget, forKey: .metRepTarget)
        try container.encodeIfPresent(metEffortTarget, forKey: .metEffortTarget)
        try container.encodeIfPresent(plannedSetId, forKey: .plannedSetId)
        try container.encodeIfPresent(notes, forKey: .notes)
    }
    
    private enum CodingKeys: String, CodingKey {
        case id, reps, weight, isCompleted
        case targetRIR, targetRPE, rirObserved, rpeObserved
        case completedAt, actualRestSeconds
        case isWarmup, isDropSet, isFailure
        case compliance, complianceReason, recommendedWeight, recommendedReps
        case tempoActual, techniqueLimitations
        case isUserModified, originalPrescribedWeight, originalPrescribedReps, modificationReason
        case setOutcome, metRepTarget, metEffortTarget, plannedSetId, notes
    }
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
    
    var icon: String {
        switch self {
        case .increaseWeight: return "arrow.up.circle.fill"
        case .increaseReps: return "plus.circle.fill"
        case .hold: return "equal.circle.fill"
        case .deload: return "arrow.down.circle.fill"
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
