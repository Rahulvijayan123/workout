// Session.swift
// Completed workout session with results.

import Foundation

/// Kind of session adjustment applied (for state update logic).
public enum SessionAdjustmentKind: String, Codable, Sendable, Hashable {
    /// No adjustment - normal session.
    case none = "none"
    
    /// True deload session (scheduled or fatigue-triggered).
    case deload = "deload"
    
    /// Acute readiness cut (temporary reduction, not a true deload).
    case readinessCut = "readiness_cut"
    
    /// Post-break reset session (ramping back after extended gap).
    case breakReset = "break_reset"
}

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
    
    /// Adjustment kind for this specific exercise (deload, readiness cut, etc.).
    /// When present, overrides the session-level adjustmentKind for state update decisions.
    public let adjustmentKind: SessionAdjustmentKind?
    
    public init(
        id: UUID = UUID(),
        exerciseId: String,
        prescription: SetPrescription,
        sets: [SetResult],
        order: Int = 0,
        notes: String? = nil,
        adjustmentKind: SessionAdjustmentKind? = nil
    ) {
        self.id = id
        self.exerciseId = exerciseId
        self.prescription = prescription
        self.sets = sets
        self.order = order
        self.notes = notes
        self.adjustmentKind = adjustmentKind
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
    /// Deprecated: use `adjustmentKind == .deload` instead. Kept for backward compatibility.
    public let wasDeload: Bool
    
    /// Kind of session adjustment applied (deload, readiness cut, break reset, or none).
    /// More granular than `wasDeload` for proper state update handling.
    public let adjustmentKind: SessionAdjustmentKind
    
    /// Lift states at the start of this session (for computing updates).
    public let previousLiftStates: [String: LiftState]
    
    /// User's readiness score at session start.
    public let readinessScore: Int?
    
    /// The reason this session was a deload (if `wasDeload` is true).
    /// Used to differentiate scheduled deloads from fatigue-triggered deloads
    /// for proper deload block continuation logic.
    public let deloadReason: DeloadReason?
    
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
        adjustmentKind: SessionAdjustmentKind? = nil,
        previousLiftStates: [String: LiftState] = [:],
        readinessScore: Int? = nil,
        deloadReason: DeloadReason? = nil,
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
        // Derive adjustmentKind from wasDeload if not explicitly provided (backward compat)
        self.adjustmentKind = adjustmentKind ?? (wasDeload ? .deload : .none)
        self.previousLiftStates = previousLiftStates
        self.readinessScore = readinessScore
        self.deloadReason = deloadReason
        self.notes = notes
    }
    
    /// Whether this session should update baseline weights (false for deload/readiness cuts).
    public var shouldUpdateBaseline: Bool {
        switch adjustmentKind {
        case .none:
            return true
        case .deload, .readinessCut:
            return false
        case .breakReset:
            // Break resets do update baseline (they're the new reality)
            return true
        }
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

// MARK: - CompletedSession Codable (backward compatible)

extension CompletedSession {
    enum CodingKeys: String, CodingKey {
        case id
        case date
        case templateId
        case name
        case exerciseResults
        case startedAt
        case endedAt
        case wasDeload
        case adjustmentKind
        case previousLiftStates
        case readinessScore
        case deloadReason
        case notes
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        id = try container.decode(UUID.self, forKey: .id)
        date = try container.decode(Date.self, forKey: .date)
        templateId = try container.decodeIfPresent(UUID.self, forKey: .templateId)
        name = try container.decode(String.self, forKey: .name)
        exerciseResults = try container.decode([ExerciseSessionResult].self, forKey: .exerciseResults)
        startedAt = try container.decode(Date.self, forKey: .startedAt)
        endedAt = try container.decodeIfPresent(Date.self, forKey: .endedAt)
        wasDeload = try container.decodeIfPresent(Bool.self, forKey: .wasDeload) ?? false
        
        // Backward compatibility: derive adjustmentKind from wasDeload if not present
        if let kind = try container.decodeIfPresent(SessionAdjustmentKind.self, forKey: .adjustmentKind) {
            adjustmentKind = kind
        } else {
            adjustmentKind = wasDeload ? .deload : .none
        }
        
        previousLiftStates = try container.decodeIfPresent([String: LiftState].self, forKey: .previousLiftStates) ?? [:]
        readinessScore = try container.decodeIfPresent(Int.self, forKey: .readinessScore)
        deloadReason = try container.decodeIfPresent(DeloadReason.self, forKey: .deloadReason)
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encode(id, forKey: .id)
        try container.encode(date, forKey: .date)
        try container.encodeIfPresent(templateId, forKey: .templateId)
        try container.encode(name, forKey: .name)
        try container.encode(exerciseResults, forKey: .exerciseResults)
        try container.encode(startedAt, forKey: .startedAt)
        try container.encodeIfPresent(endedAt, forKey: .endedAt)
        try container.encode(wasDeload, forKey: .wasDeload)
        try container.encode(adjustmentKind, forKey: .adjustmentKind)
        try container.encode(previousLiftStates, forKey: .previousLiftStates)
        try container.encodeIfPresent(readinessScore, forKey: .readinessScore)
        try container.encodeIfPresent(deloadReason, forKey: .deloadReason)
        try container.encodeIfPresent(notes, forKey: .notes)
    }
}
