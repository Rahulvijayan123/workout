// WorkoutTemplate.swift
// Template for a workout session.

import Foundation

/// Session intent for DUP (Daily Undulating Periodization) and program-aware progression.
/// This allows different hold/increment behavior based on the day's training focus.
public enum SessionIntent: String, Codable, Sendable, Hashable {
    /// Heavy/strength day: lower reps, higher intensity, slower progression.
    case heavy = "heavy"
    
    /// Volume/hypertrophy day: higher reps, moderate intensity, reps-first progression.
    case volume = "volume"
    
    /// Light/technique day: lower intensity, focus on movement quality.
    case light = "light"
    
    /// General training (no specific periodization intent).
    case general = "general"
    
    /// Infers session intent from a prescription's rep range.
    public static func infer(from prescription: SetPrescription) -> SessionIntent {
        let targetReps = prescription.targetRepsRange.lowerBound
        if targetReps <= 5 {
            return .heavy
        } else if targetReps >= 10 {
            return .volume
        } else {
            return .general
        }
    }
    
    /// Whether this intent prefers smaller, more conservative increments.
    public var prefersSmallIncrements: Bool {
        switch self {
        case .heavy, .light:
            return true
        case .volume, .general:
            return false
        }
    }
    
    /// Whether this intent should hold more often on grinder sessions.
    public var sensitiveToGrinders: Bool {
        switch self {
        case .heavy:
            return true
        case .volume, .light, .general:
            return false
        }
    }
    
    /// Whether this intent prefers reps-first progression (increase reps before load).
    public var prefersRepsFirst: Bool {
        switch self {
        case .volume:
            return true
        case .heavy, .light, .general:
            return false
        }
    }
}

/// An exercise within a workout template, with its prescription.
public struct TemplateExercise: Codable, Sendable, Hashable, Identifiable {
    public let id: UUID
    
    /// The exercise definition.
    public let exercise: Exercise
    
    /// How the exercise should be performed.
    public let prescription: SetPrescription
    
    /// Order within the workout (0-based).
    public let order: Int
    
    /// Optional superset group ID (exercises with same group are supersetted).
    public let supersetGroup: String?
    
    /// Optional notes for this exercise.
    public let notes: String?
    
    public init(
        id: UUID = UUID(),
        exercise: Exercise,
        prescription: SetPrescription,
        order: Int = 0,
        supersetGroup: String? = nil,
        notes: String? = nil
    ) {
        self.id = id
        self.exercise = exercise
        self.prescription = prescription
        self.order = order
        self.supersetGroup = supersetGroup
        self.notes = notes
    }
}

/// A workout template defining a complete workout.
public struct WorkoutTemplate: Codable, Sendable, Hashable, Identifiable {
    public let id: UUID
    
    /// Name of the workout (e.g., "Push Day A").
    public let name: String
    
    /// Ordered list of exercises with prescriptions.
    public let exercises: [TemplateExercise]
    
    /// Estimated duration in minutes.
    public let estimatedDurationMinutes: Int?
    
    /// Target muscle groups for this workout.
    public let targetMuscleGroups: [MuscleGroup]
    
    /// Optional description.
    public let description: String?
    
    /// Session intent for DUP-aware progression (heavy/volume/light/general).
    /// If nil, intent is inferred from exercise prescriptions.
    public let intent: SessionIntent?
    
    /// Creation timestamp.
    public let createdAt: Date
    
    /// Last modification timestamp.
    public let updatedAt: Date
    
    public init(
        id: UUID = UUID(),
        name: String,
        exercises: [TemplateExercise],
        estimatedDurationMinutes: Int? = nil,
        targetMuscleGroups: [MuscleGroup] = [],
        description: String? = nil,
        intent: SessionIntent? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.exercises = exercises
        self.estimatedDurationMinutes = estimatedDurationMinutes
        self.targetMuscleGroups = targetMuscleGroups
        self.description = description
        self.intent = intent
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
    
    /// Effective session intent (explicit or inferred from primary compound).
    public var effectiveIntent: SessionIntent {
        if let explicit = intent { return explicit }
        
        // Infer from first compound exercise's prescription
        if let compound = exercises.first(where: { $0.exercise.movementPattern.isCompound }) {
            return SessionIntent.infer(from: compound.prescription)
        }
        
        // Fallback to first exercise
        if let first = exercises.first {
            return SessionIntent.infer(from: first.prescription)
        }
        
        return .general
    }
    
    /// Total planned sets across all exercises.
    public var totalPlannedSets: Int {
        exercises.reduce(0) { $0 + $1.prescription.setCount }
    }
    
    /// All unique muscles targeted.
    public var allTargetedMuscles: Set<MuscleGroup> {
        exercises.reduce(into: Set<MuscleGroup>()) { result, te in
            result.formUnion(te.exercise.allMuscles)
        }
    }
}

/// Identifier for a workout template.
public typealias WorkoutTemplateId = UUID
