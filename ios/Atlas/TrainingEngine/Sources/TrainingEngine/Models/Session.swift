// Session.swift
// Completed workout session with results.

import Foundation

/// Result of an exercise within a session.
public struct ExerciseSessionResult: Codable, Sendable, Hashable, Identifiable {
    public let id: UUID
    
    /// The exercise that was performed.
    public let exerciseId: String
    
    /// The prescription that was used.
    public let prescription: SetPrescription
    
    /// All sets performed (including warmups).
    public let sets: [SetResult]
    
    /// Order within the session.
    public let order: Int
    
    /// Notes for this exercise.
    public let notes: String?
    
    public init(
        id: UUID = UUID(),
        exerciseId: String,
        prescription: SetPrescription,
        sets: [SetResult],
        order: Int = 0,
        notes: String? = nil
    ) {
        self.id = id
        self.exerciseId = exerciseId
        self.prescription = prescription
        self.sets = sets
        self.order = order
        self.notes = notes
    }
    
    /// Working sets only (non-warmup, completed).
    public var workingSets: [SetResult] {
        // Treat a set as "working" only if it has actual reps > 0 and was marked completed.
        // This avoids corrupting progression/state with placeholder sets (e.g., completed=true, reps=0).
        sets.filter { $0.completed && !$0.isWarmup && $0.reps > 0 }
    }
    
    /// Total volume (sum of load × reps for working sets).
    public var totalVolume: Double {
        workingSets.reduce(0) { $0 + $1.volume }
    }
    
    /// Best estimated 1RM from any set.
    public var bestE1RM: Double {
        workingSets.map(\.estimatedE1RM).max() ?? 0
    }
    
    /// Average reps across working sets.
    public var averageReps: Double {
        let working = workingSets
        guard !working.isEmpty else { return 0 }
        return Double(working.map(\.reps).reduce(0, +)) / Double(working.count)
    }
}

/// A completed workout session.
public struct CompletedSession: Codable, Sendable, Hashable, Identifiable {
    public let id: UUID
    
    /// Date of the session.
    public let date: Date
    
    /// The template this session was based on (if any).
    public let templateId: WorkoutTemplateId?
    
    /// Name of the workout.
    public let name: String
    
    /// Results for each exercise.
    public let exerciseResults: [ExerciseSessionResult]
    
    /// When the session started.
    public let startedAt: Date
    
    /// When the session ended.
    public let endedAt: Date?
    
    /// Whether this was a deload session.
    public let wasDeload: Bool
    
    /// Lift states at the start of this session (for computing updates).
    public let previousLiftStates: [String: LiftState]
    
    /// User's readiness score at session start.
    public let readinessScore: Int?
    
    /// Session notes.
    public let notes: String?
    
    public init(
        id: UUID = UUID(),
        date: Date,
        templateId: WorkoutTemplateId? = nil,
        name: String,
        exerciseResults: [ExerciseSessionResult],
        startedAt: Date,
        endedAt: Date? = nil,
        wasDeload: Bool = false,
        previousLiftStates: [String: LiftState] = [:],
        readinessScore: Int? = nil,
        notes: String? = nil
    ) {
        self.id = id
        self.date = date
        self.templateId = templateId
        self.name = name
        self.exerciseResults = exerciseResults
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.wasDeload = wasDeload
        self.previousLiftStates = previousLiftStates
        self.readinessScore = readinessScore
        self.notes = notes
    }
    
    /// Duration in minutes (if ended).
    public var durationMinutes: Int? {
        guard let ended = endedAt else { return nil }
        return Int(ended.timeIntervalSince(startedAt) / 60)
    }
    
    /// Total session volume across all exercises.
    public var totalVolume: Double {
        exerciseResults.reduce(0) { $0 + $1.totalVolume }
    }
    
    /// All exercise IDs performed.
    public var exerciseIds: [String] {
        exerciseResults.map(\.exerciseId)
    }
}
