// SessionPlan.swift
// Output types for session recommendations.

import Foundation

/// A planned set within an exercise.
public struct SetPlan: Codable, Sendable, Hashable {
    /// Set index (0-based).
    public let setIndex: Int
    
    /// Target load for this set.
    public var targetLoad: Load
    
    /// Target reps for this set.
    public var targetReps: Int
    
    /// Target RIR for this set.
    public var targetRIR: Int
    
    /// Rest seconds after this set.
    public let restSeconds: Int
    
    /// Whether this is a warmup set.
    public let isWarmup: Bool
    
    /// For backoff sets, the percentage of top set.
    public let backoffPercentage: Double?

    /// In-session adjustment policy used for this set.
    public let inSessionPolicy: InSessionAdjustmentPolicyType

    /// Rounding policy for in-session load adjustments.
    public let roundingPolicy: LoadRoundingPolicy
    
    public init(
        setIndex: Int,
        targetLoad: Load,
        targetReps: Int,
        targetRIR: Int,
        restSeconds: Int,
        isWarmup: Bool = false,
        backoffPercentage: Double? = nil,
        inSessionPolicy: InSessionAdjustmentPolicyType = .none,
        roundingPolicy: LoadRoundingPolicy = .standardPounds
    ) {
        self.setIndex = setIndex
        self.targetLoad = targetLoad
        self.targetReps = max(1, targetReps)
        self.targetRIR = max(0, min(5, targetRIR))
        self.restSeconds = max(0, restSeconds)
        self.isWarmup = isWarmup
        self.backoffPercentage = backoffPercentage
        self.inSessionPolicy = inSessionPolicy
        self.roundingPolicy = roundingPolicy
    }
}

/// A substitution recommendation with scoring.
public struct Substitution: Codable, Sendable, Hashable {
    /// The substitute exercise.
    public let exercise: Exercise
    
    /// Overall similarity score (0-1).
    public let score: Double
    
    /// Reason components for the substitution.
    public let reasons: [SubstitutionReason]
    
    public init(exercise: Exercise, score: Double, reasons: [SubstitutionReason]) {
        self.exercise = exercise
        self.score = max(0, min(1, score))
        self.reasons = reasons
    }
}

/// Reason why an exercise is a good substitution.
public struct SubstitutionReason: Codable, Sendable, Hashable {
    public let category: ReasonCategory
    public let description: String
    public let score: Double
    
    public enum ReasonCategory: String, Codable, Sendable, Hashable {
        case muscleOverlap = "muscle_overlap"
        case movementPattern = "movement_pattern"
        case equipmentMatch = "equipment_match"
        case equipmentAvailable = "equipment_available"
    }
    
    public init(category: ReasonCategory, description: String, score: Double) {
        self.category = category
        self.description = description
        self.score = score
    }
}

/// Planned exercise within a session.
public struct ExercisePlan: Codable, Sendable, Hashable {
    /// The exercise to perform.
    public let exercise: Exercise
    
    /// The prescription being used.
    public let prescription: SetPrescription
    
    /// Planned sets.
    public let sets: [SetPlan]
    
    /// Progression policy being used.
    public let progressionPolicy: ProgressionPolicyType

    /// In-session adjustment policy being used.
    public let inSessionPolicy: InSessionAdjustmentPolicyType
    
    /// Available substitutions (ranked by score).
    public let substitutions: [Substitution]
    
    public init(
        exercise: Exercise,
        prescription: SetPrescription,
        sets: [SetPlan],
        progressionPolicy: ProgressionPolicyType,
        inSessionPolicy: InSessionAdjustmentPolicyType = .none,
        substitutions: [Substitution] = []
    ) {
        self.exercise = exercise
        self.prescription = prescription
        self.sets = sets
        self.progressionPolicy = progressionPolicy
        self.inSessionPolicy = inSessionPolicy
        self.substitutions = substitutions
    }
    
    /// Total planned volume.
    public var totalPlannedVolume: Double {
        sets.filter { !$0.isWarmup }.reduce(0) {
            $0 + $1.targetLoad.value * Double($1.targetReps)
        }
    }
}

/// Reason for a deload recommendation.
public enum DeloadReason: String, Codable, Sendable, Hashable {
    case scheduledDeload = "scheduled_deload"
    case performanceDecline = "performance_decline"
    case lowReadiness = "low_readiness"
    case highAccumulatedFatigue = "high_accumulated_fatigue"
    case userRequested = "user_requested"
}

/// Complete session plan output.
public struct SessionPlan: Codable, Sendable, Hashable {
    /// Date this plan is for.
    public let date: Date
    
    /// Template ID this plan is based on.
    public let templateId: WorkoutTemplateId?
    
    /// Planned exercises with sets.
    public let exercises: [ExercisePlan]
    
    /// Whether this is a deload session.
    public let isDeload: Bool
    
    /// Reason for deload (if applicable).
    public let deloadReason: DeloadReason?
    
    /// Optional coaching insights (plateau flags, recovery flags, etc).
    public let insights: [CoachingInsight]
    
    public init(
        date: Date,
        templateId: WorkoutTemplateId?,
        exercises: [ExercisePlan],
        isDeload: Bool,
        deloadReason: DeloadReason?,
        insights: [CoachingInsight] = []
    ) {
        self.date = date
        self.templateId = templateId
        self.exercises = exercises
        self.isDeload = isDeload
        self.deloadReason = deloadReason
        self.insights = insights
    }
    
    /// Total planned sets.
    public var totalSets: Int {
        exercises.reduce(0) { $0 + $1.sets.filter { !$0.isWarmup }.count }
    }
    
    /// Estimated duration in minutes.
    public var estimatedDurationMinutes: Int {
        let totalRestSeconds = exercises.reduce(0) { total, ep in
            total + ep.sets.reduce(0) { $0 + $1.restSeconds }
        }
        let totalWorkSeconds = exercises.reduce(0) { total, ep in
            total + ep.sets.count * 60 // ~1 min per set
        }
        return (totalRestSeconds + totalWorkSeconds) / 60
    }
}
