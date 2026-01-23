// Exercise.swift
// Exercise entity with muscle and movement pattern information.

import Foundation

/// A muscle group targeted by an exercise.
public enum MuscleGroup: String, Codable, Sendable, Hashable, CaseIterable {
    case chest = "chest"
    case back = "back"
    case shoulders = "shoulders"
    case biceps = "biceps"
    case triceps = "triceps"
    case forearms = "forearms"
    case quadriceps = "quadriceps"
    case hamstrings = "hamstrings"
    case glutes = "glutes"
    case calves = "calves"
    case abdominals = "abdominals"
    case obliques = "obliques"
    case lowerBack = "lower_back"
    case traps = "traps"
    case lats = "lats"
    case rhomboids = "rhomboids"
    case rearDelts = "rear_delts"
    case frontDelts = "front_delts"
    case sideDelts = "side_delts"
    case hipFlexors = "hip_flexors"
    case adductors = "adductors"
    case abductors = "abductors"
    case rotatorCuff = "rotator_cuff"
    case neck = "neck"
    case unknown = "unknown"
}

/// An exercise definition.
public struct Exercise: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public let name: String
    public let equipment: Equipment
    public let primaryMuscles: [MuscleGroup]
    public let secondaryMuscles: [MuscleGroup]
    public let movementPattern: MovementPattern
    
    /// Optional description/instructions.
    public let instructions: [String]?
    
    /// Optional GIF/video URL for demonstration.
    public let mediaUrl: String?
    
    public init(
        id: String,
        name: String,
        equipment: Equipment,
        primaryMuscles: [MuscleGroup],
        secondaryMuscles: [MuscleGroup] = [],
        movementPattern: MovementPattern,
        instructions: [String]? = nil,
        mediaUrl: String? = nil
    ) {
        self.id = id
        self.name = name
        self.equipment = equipment
        self.primaryMuscles = primaryMuscles
        self.secondaryMuscles = secondaryMuscles
        self.movementPattern = movementPattern
        self.instructions = instructions
        self.mediaUrl = mediaUrl
    }
    
    /// All muscles targeted (primary + secondary).
    public var allMuscles: [MuscleGroup] {
        primaryMuscles + secondaryMuscles
    }
    
    /// Computes muscle overlap score with another exercise.
    /// Primary muscles are weighted 2x compared to secondary.
    public func muscleOverlap(with other: Exercise) -> Double {
        let selfPrimary = Set(primaryMuscles)
        let selfSecondary = Set(secondaryMuscles)
        let otherPrimary = Set(other.primaryMuscles)
        let otherSecondary = Set(other.secondaryMuscles)
        
        // Primary-to-primary overlap (weight: 2.0)
        let p2p = Double(selfPrimary.intersection(otherPrimary).count) * 2.0
        // Primary-to-secondary overlap (weight: 1.0)
        let p2s = Double(selfPrimary.intersection(otherSecondary).count) * 1.0
        // Secondary-to-primary overlap (weight: 1.0)
        let s2p = Double(selfSecondary.intersection(otherPrimary).count) * 1.0
        // Secondary-to-secondary overlap (weight: 0.5)
        let s2s = Double(selfSecondary.intersection(otherSecondary).count) * 0.5
        
        let totalOverlap = p2p + p2s + s2p + s2s
        
        // Normalize by max possible score
        let maxScore = Double(selfPrimary.count) * 2.0 + Double(selfSecondary.count) * 1.5
        guard maxScore > 0 else { return 0 }
        
        return min(1.0, totalOverlap / maxScore)
    }
}

// MARK: - Common Exercises (Seeds)

extension Exercise {
    /// Barbell back squat.
    public static let barbellSquat = Exercise(
        id: "barbell_squat",
        name: "Barbell Back Squat",
        equipment: .barbell,
        primaryMuscles: [.quadriceps, .glutes],
        secondaryMuscles: [.hamstrings, .lowerBack, .abdominals],
        movementPattern: .squat
    )
    
    /// Conventional deadlift.
    public static let conventionalDeadlift = Exercise(
        id: "conventional_deadlift",
        name: "Conventional Deadlift",
        equipment: .barbell,
        primaryMuscles: [.hamstrings, .glutes, .lowerBack],
        secondaryMuscles: [.quadriceps, .traps, .forearms],
        movementPattern: .hipHinge
    )
    
    /// Flat barbell bench press.
    public static let barbellBenchPress = Exercise(
        id: "barbell_bench_press",
        name: "Barbell Bench Press",
        equipment: .barbell,
        primaryMuscles: [.chest],
        secondaryMuscles: [.triceps, .frontDelts],
        movementPattern: .horizontalPush
    )
    
    /// Overhead press.
    public static let overheadPress = Exercise(
        id: "overhead_press",
        name: "Overhead Press",
        equipment: .barbell,
        primaryMuscles: [.shoulders, .frontDelts],
        secondaryMuscles: [.triceps, .traps],
        movementPattern: .verticalPush
    )
    
    /// Barbell row.
    public static let barbellRow = Exercise(
        id: "barbell_row",
        name: "Barbell Row",
        equipment: .barbell,
        primaryMuscles: [.back, .lats],
        secondaryMuscles: [.biceps, .rearDelts, .rhomboids],
        movementPattern: .horizontalPull
    )
    
    /// Pull-up.
    public static let pullUp = Exercise(
        id: "pull_up",
        name: "Pull-Up",
        equipment: .pullUpBar,
        primaryMuscles: [.lats, .back],
        secondaryMuscles: [.biceps, .forearms],
        movementPattern: .verticalPull
    )
}
