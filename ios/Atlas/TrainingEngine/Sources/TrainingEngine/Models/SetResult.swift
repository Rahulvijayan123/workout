// SetResult.swift
// Result of a completed set.

import Foundation

/// Observed tempo during a set.
public struct ObservedTempo: Codable, Sendable, Hashable {
    /// Estimated eccentric duration.
    public let eccentricEstimate: Int?
    /// Whether pause was held.
    public let pauseHeld: Bool?
    /// Notes on tempo execution.
    public let notes: String?
    
    public init(eccentricEstimate: Int? = nil, pauseHeld: Bool? = nil, notes: String? = nil) {
        self.eccentricEstimate = eccentricEstimate
        self.pauseHeld = pauseHeld
        self.notes = notes
    }
}

/// Result of a completed set.
public struct SetResult: Codable, Sendable, Hashable, Identifiable {
    public let id: UUID
    
    /// Number of reps completed.
    public let reps: Int
    
    /// Load used.
    public let load: Load
    
    /// Observed Reps In Reserve (how many more reps could have been done).
    public let rirObserved: Int?
    
    /// Observed tempo information.
    public let tempoObserved: ObservedTempo?
    
    /// Whether this set was completed (vs. skipped or failed).
    public let completed: Bool
    
    /// Whether this was a warmup set.
    public let isWarmup: Bool
    
    /// Timestamp when the set was completed.
    public let completedAt: Date?
    
    /// Optional notes.
    public let notes: String?
    
    public init(
        id: UUID = UUID(),
        reps: Int,
        load: Load,
        rirObserved: Int? = nil,
        tempoObserved: ObservedTempo? = nil,
        completed: Bool = true,
        isWarmup: Bool = false,
        completedAt: Date? = nil,
        notes: String? = nil
    ) {
        self.id = id
        self.reps = max(0, reps)
        self.load = load
        self.rirObserved = rirObserved.map { max(0, min(10, $0)) }
        self.tempoObserved = tempoObserved
        self.completed = completed
        self.isWarmup = isWarmup
        self.completedAt = completedAt
        self.notes = notes
    }
    
    /// Estimated 1RM from this set using Brzycki formula.
    public var estimatedE1RM: Double {
        E1RMCalculator.brzycki(weight: load.value, reps: reps)
    }
    
    /// Volume (load × reps) for this set.
    public var volume: Double {
        load.value * Double(reps)
    }
}

/// Calculator for estimated 1 rep max.
public enum E1RMCalculator {
    /// Brzycki formula: weight × (36 / (37 - reps))
    /// Most accurate for 1-10 rep range.
    public static func brzycki(weight: Double, reps: Int) -> Double {
        guard reps > 0, reps < 37 else { return weight }
        return weight * (36.0 / (37.0 - Double(reps)))
    }
    
    /// Epley formula: weight × (1 + reps/30)
    /// Common alternative formula.
    public static func epley(weight: Double, reps: Int) -> Double {
        guard reps > 0 else { return weight }
        return weight * (1.0 + Double(reps) / 30.0)
    }
    
    /// Computes working weight from e1RM and target reps.
    public static func workingWeight(fromE1RM e1rm: Double, targetReps: Int) -> Double {
        guard targetReps > 0, targetReps < 37 else { return e1rm }
        // Inverse Brzycki
        return e1rm * (37.0 - Double(targetReps)) / 36.0
    }
    
    /// Computes working weight as percentage of e1RM.
    public static func workingWeight(fromE1RM e1rm: Double, percentage: Double) -> Double {
        e1rm * max(0, min(1, percentage))
    }
}
