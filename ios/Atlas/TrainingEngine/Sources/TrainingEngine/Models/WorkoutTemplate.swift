// WorkoutTemplate.swift
// Template for a workout session.

import Foundation

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
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.exercises = exercises
        self.estimatedDurationMinutes = estimatedDurationMinutes
        self.targetMuscleGroups = targetMuscleGroups
        self.description = description
        self.createdAt = createdAt
        self.updatedAt = updatedAt
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
