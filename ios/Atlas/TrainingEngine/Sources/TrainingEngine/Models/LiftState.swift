// LiftState.swift
// Per-exercise persistent state for progression tracking.

import Foundation

/// A single e1RM measurement sample.
public struct E1RMSample: Codable, Sendable, Hashable {
    public let date: Date
    public let value: Double
    
    public init(date: Date, value: Double) {
        self.date = date
        self.value = max(0, value)
    }
}

/// Trend direction for performance.
public enum PerformanceTrend: String, Codable, Sendable, Hashable {
    case improving = "improving"
    case stable = "stable"
    case declining = "declining"
    case insufficient = "insufficient"
}

/// Per-exercise state tracking progression, failures, and trends.
/// Inspired by Liftosaur's per-exercise `state.*` concept.
public struct LiftState: Codable, Sendable, Hashable {
    /// The exercise this state belongs to.
    public let exerciseId: String
    
    /// Last working weight successfully used.
    public var lastWorkingWeight: Load
    
    /// Rolling estimated 1RM (exponentially smoothed).
    public var rollingE1RM: Double
    
    /// Consecutive session failure count (reset on success).
    public var failureCount: Int
    
    /// Date of last deload for this exercise.
    public var lastDeloadDate: Date?
    
    /// Current performance trend.
    public var trend: PerformanceTrend
    
    /// Recent e1RM history for trend calculation.
    public var e1rmHistory: [E1RMSample]
    
    /// Last session date for this exercise.
    public var lastSessionDate: Date?
    
    /// Cumulative successful sessions count.
    public var successfulSessionsCount: Int
    
    public init(
        exerciseId: String,
        lastWorkingWeight: Load = .zero,
        rollingE1RM: Double = 0,
        failureCount: Int = 0,
        lastDeloadDate: Date? = nil,
        trend: PerformanceTrend = .insufficient,
        e1rmHistory: [E1RMSample] = [],
        lastSessionDate: Date? = nil,
        successfulSessionsCount: Int = 0
    ) {
        self.exerciseId = exerciseId
        self.lastWorkingWeight = lastWorkingWeight
        self.rollingE1RM = max(0, rollingE1RM)
        self.failureCount = max(0, failureCount)
        self.lastDeloadDate = lastDeloadDate
        self.trend = trend
        self.e1rmHistory = e1rmHistory
        self.lastSessionDate = lastSessionDate
        self.successfulSessionsCount = max(0, successfulSessionsCount)
    }
    
    /// Days since last deload (nil if never deloaded).
    public func daysSinceDeload(from date: Date = Date(), calendar: Calendar = .current) -> Int? {
        guard let lastDeload = lastDeloadDate else { return nil }
        return calendar.dateComponents([.day], from: lastDeload, to: date).day
    }
    
    /// Days since last session (nil if never performed).
    public func daysSinceLastSession(from date: Date = Date(), calendar: Calendar = .current) -> Int? {
        guard let lastSession = lastSessionDate else { return nil }
        return calendar.dateComponents([.day], from: lastSession, to: date).day
    }
}

/// Calculator for performance trends.
public enum TrendCalculator {
    /// Minimum samples needed for trend calculation.
    public static let minimumSamples = 3
    
    /// Computes trend from e1RM history samples.
    public static func compute(from samples: [E1RMSample]) -> PerformanceTrend {
        guard samples.count >= minimumSamples else {
            return .insufficient
        }
        
        // Use last N samples for trend
        let recent = samples.suffix(5)
        guard recent.count >= minimumSamples else {
            return .insufficient
        }
        
        // Simple linear regression slope
        let n = Double(recent.count)
        var sumX = 0.0
        var sumY = 0.0
        var sumXY = 0.0
        var sumX2 = 0.0
        
        for (index, sample) in recent.enumerated() {
            let x = Double(index)
            let y = sample.value
            sumX += x
            sumY += y
            sumXY += x * y
            sumX2 += x * x
        }
        
        let denominator = n * sumX2 - sumX * sumX
        guard denominator != 0 else { return .stable }
        
        let slope = (n * sumXY - sumX * sumY) / denominator
        
        // Normalize slope by average value to get percentage change
        let avgValue = sumY / n
        guard avgValue > 0 else { return .stable }
        
        let percentageSlope = slope / avgValue
        
        // Thresholds for trend determination
        if percentageSlope > 0.01 {
            return .improving
        } else if percentageSlope < -0.01 {
            return .declining
        } else {
            return .stable
        }
    }
    
    /// Checks if there's a 2-session decline.
    public static func hasTwoSessionDecline(samples: [E1RMSample]) -> Bool {
        guard samples.count >= 3 else { return false }
        
        let last3 = samples.suffix(3)
        let values = last3.map(\.value)
        
        // Check if last two sessions both declined from the one before
        return values[1] < values[0] && values[2] < values[1]
    }
}

// MARK: - Type Alias for Cross-Package Compatibility

/// Alias for `LiftState` to provide naming consistency with IronForge's `ExerciseState`.
/// This allows external consumers to use either name based on their domain conventions.
public typealias ExerciseState = LiftState
