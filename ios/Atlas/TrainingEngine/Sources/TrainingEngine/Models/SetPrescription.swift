// SetPrescription.swift
// Prescription for how sets should be performed.

import Foundation

/// Tempo prescription for an exercise (eccentric-pause-concentric-pause).
public struct Tempo: Codable, Sendable, Hashable {
    /// Eccentric (lowering) phase duration in seconds.
    public let eccentric: Int
    /// Pause at the bottom position in seconds.
    public let pauseBottom: Int
    /// Concentric (lifting) phase duration in seconds.
    public let concentric: Int
    /// Pause at the top position in seconds.
    public let pauseTop: Int
    
    public init(eccentric: Int = 2, pauseBottom: Int = 0, concentric: Int = 1, pauseTop: Int = 0) {
        self.eccentric = max(0, eccentric)
        self.pauseBottom = max(0, pauseBottom)
        self.concentric = max(0, concentric)
        self.pauseTop = max(0, pauseTop)
    }
    
    /// Standard controlled tempo (2-0-1-0).
    public static let standard = Tempo(eccentric: 2, pauseBottom: 0, concentric: 1, pauseTop: 0)
    
    /// Slow eccentric for hypertrophy (3-1-1-0).
    public static let slowEccentric = Tempo(eccentric: 3, pauseBottom: 1, concentric: 1, pauseTop: 0)
    
    /// Pause reps (2-2-1-0).
    public static let pause = Tempo(eccentric: 2, pauseBottom: 2, concentric: 1, pauseTop: 0)
    
    /// Total time under tension per rep.
    public var totalSeconds: Int {
        eccentric + pauseBottom + concentric + pauseTop
    }
    
    /// String representation (e.g., "2-0-1-0").
    public var notation: String {
        "\(eccentric)-\(pauseBottom)-\(concentric)-\(pauseTop)"
    }
}

/// Strategy for how load should be determined.
public enum LoadStrategy: String, Codable, Sendable, Hashable {
    /// Use absolute weight from lift state.
    case absolute = "absolute"
    /// Use percentage of estimated 1RM.
    case percentageE1RM = "percentage_e1rm"
    /// Use RPE/RIR-based autoregulation.
    case rpeAutoregulated = "rpe_autoregulated"
    /// Top set + backoff sets at percentage.
    case topSetBackoff = "top_set_backoff"
}

/// Prescription for how an exercise should be performed.
public struct SetPrescription: Codable, Sendable, Hashable {
    /// Number of working sets.
    public let setCount: Int
    
    /// Target rep range (e.g., 6...10).
    public let targetRepsRange: ClosedRange<Int>
    
    /// Target Reps In Reserve (0 = to failure, 2 = stop 2 reps before failure).
    public let targetRIR: Int
    
    /// Tempo prescription.
    public let tempo: Tempo
    
    /// Rest between sets in seconds.
    public let restSeconds: Int
    
    /// Strategy for determining load.
    public let loadStrategy: LoadStrategy
    
    /// For percentage-based strategies, the target percentage (0.0-1.0).
    public let targetPercentage: Double?
    
    /// Weight increment for progression.
    public let increment: Load
    
    public init(
        setCount: Int = 3,
        targetRepsRange: ClosedRange<Int> = 6...10,
        targetRIR: Int = 2,
        tempo: Tempo = .standard,
        restSeconds: Int = 120,
        loadStrategy: LoadStrategy = .absolute,
        targetPercentage: Double? = nil,
        increment: Load = .pounds(5)
    ) {
        self.setCount = max(1, setCount)
        self.targetRepsRange = targetRepsRange
        self.targetRIR = max(0, min(5, targetRIR))
        self.tempo = tempo
        self.restSeconds = max(0, restSeconds)
        self.loadStrategy = loadStrategy
        self.targetPercentage = targetPercentage.map { max(0, min(1, $0)) }
        self.increment = increment
    }
    
    /// Standard hypertrophy prescription (3x8-12, RIR 2).
    public static let hypertrophy = SetPrescription(
        setCount: 3,
        targetRepsRange: 8...12,
        targetRIR: 2,
        tempo: .standard,
        restSeconds: 90,
        loadStrategy: .absolute
    )
    
    /// Standard strength prescription (5x5, RIR 1).
    public static let strength = SetPrescription(
        setCount: 5,
        targetRepsRange: 5...5,
        targetRIR: 1,
        tempo: .standard,
        restSeconds: 180,
        loadStrategy: .absolute
    )
    
    /// Power/explosive prescription (5x3, RIR 2-3).
    public static let power = SetPrescription(
        setCount: 5,
        targetRepsRange: 3...3,
        targetRIR: 3,
        tempo: Tempo(eccentric: 1, pauseBottom: 0, concentric: 0, pauseTop: 0),
        restSeconds: 240,
        loadStrategy: .percentageE1RM,
        targetPercentage: 0.85
    )
}

// Note: ClosedRange is Codable in Swift 5.9+ when Bound is Codable
