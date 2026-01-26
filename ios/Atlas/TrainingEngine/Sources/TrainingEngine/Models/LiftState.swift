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

/// State for tracking post-break ramp-back progression.
public struct PostBreakRampState: Codable, Sendable, Hashable {
    /// The pre-break working weight target to ramp back to.
    public let targetWeight: Load
    
    /// Number of ramp sessions completed since the break.
    public var sessionsCompleted: Int
    
    /// Total sessions planned for the ramp (typically 1-3).
    public let totalSessions: Int
    
    /// Date when the ramp started.
    public let startDate: Date
    
    public init(
        targetWeight: Load,
        sessionsCompleted: Int = 0,
        totalSessions: Int = 2,
        startDate: Date
    ) {
        self.targetWeight = targetWeight
        self.sessionsCompleted = max(0, sessionsCompleted)
        self.totalSessions = max(1, min(3, totalSessions))
        self.startDate = startDate
    }
    
    /// Whether the ramp is complete.
    public var isComplete: Bool {
        sessionsCompleted >= totalSessions
    }
    
    /// Progress fraction (0-1).
    public var progress: Double {
        guard totalSessions > 0 else { return 1.0 }
        return min(1.0, Double(sessionsCompleted) / Double(totalSessions))
    }
}

/// Per-exercise state tracking progression, failures, and trends.
/// Inspired by Liftosaur's per-exercise `state.*` concept.
public struct LiftState: Sendable, Hashable {
    /// The exercise this state belongs to.
    public let exerciseId: String
    
    /// Last working weight successfully used.
    public var lastWorkingWeight: Load
    
    /// Rolling estimated 1RM (exponentially smoothed).
    public var rollingE1RM: Double
    
    /// Consecutive session failure count (reset on success).
    /// Alias: `failStreak`.
    public var failureCount: Int
    
    /// Consecutive sessions with grinder success (RIR below target but reps achieved).
    /// Reset on easy success or failure.
    public var highRpeStreak: Int
    
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
    
    /// Consecutive clean success sessions (no failure, no grinder).
    /// Used for fixed-rep progression gating. Reset on failure, grinder, deload, readiness-cut, or break reset.
    public var successStreak: Int
    
    /// Recent readiness scores at exposure times (most recent first, bounded to 6).
    /// Used for detecting persistent low readiness patterns.
    public var recentReadinessScores: [Int]
    
    /// Post-break ramp state (if currently ramping back after extended break).
    public var postBreakRamp: PostBreakRampState?
    
    /// Post-deload ramp state (if currently ramping back after a deload).
    /// Prevents whiplash (jumping back to full weight too quickly after deload).
    public var postDeloadRamp: PostBreakRampState?
    
    /// Maximum size for the recentReadinessScores buffer.
    public static let maxReadinessHistorySize = 6
    
    // MARK: - Aliases
    
    /// Alias for `failureCount` to match direction policy terminology.
    public var failStreak: Int {
        get { failureCount }
        set { failureCount = newValue }
    }
    
    public init(
        exerciseId: String,
        lastWorkingWeight: Load = .zero,
        rollingE1RM: Double = 0,
        failureCount: Int = 0,
        highRpeStreak: Int = 0,
        lastDeloadDate: Date? = nil,
        trend: PerformanceTrend = .insufficient,
        e1rmHistory: [E1RMSample] = [],
        lastSessionDate: Date? = nil,
        successfulSessionsCount: Int = 0,
        successStreak: Int = 0,
        recentReadinessScores: [Int] = [],
        postBreakRamp: PostBreakRampState? = nil,
        postDeloadRamp: PostBreakRampState? = nil
    ) {
        self.exerciseId = exerciseId
        self.lastWorkingWeight = lastWorkingWeight
        self.rollingE1RM = max(0, rollingE1RM)
        self.failureCount = max(0, failureCount)
        self.highRpeStreak = max(0, highRpeStreak)
        self.lastDeloadDate = lastDeloadDate
        self.trend = trend
        self.e1rmHistory = e1rmHistory
        self.lastSessionDate = lastSessionDate
        self.successfulSessionsCount = max(0, successfulSessionsCount)
        self.successStreak = max(0, successStreak)
        self.recentReadinessScores = Array(recentReadinessScores.prefix(Self.maxReadinessHistorySize))
        self.postBreakRamp = postBreakRamp
        self.postDeloadRamp = postDeloadRamp
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
    
    // MARK: - Mutation helpers
    
    /// Appends a readiness score to the recent history (maintains bounded size).
    public mutating func appendReadinessScore(_ score: Int) {
        recentReadinessScores.insert(max(0, min(100, score)), at: 0)
        if recentReadinessScores.count > Self.maxReadinessHistorySize {
            recentReadinessScores.removeLast()
        }
    }
    
    /// Resets streak counters (typically after a deload).
    public mutating func resetStreaks() {
        failureCount = 0
        highRpeStreak = 0
        successStreak = 0
    }
    
    /// Clears the post-break ramp state.
    public mutating func clearPostBreakRamp() {
        postBreakRamp = nil
    }
    
    /// Increments the post-break ramp progress.
    public mutating func incrementRampProgress() {
        guard var ramp = postBreakRamp else { return }
        ramp.sessionsCompleted += 1
        if ramp.isComplete {
            postBreakRamp = nil
        } else {
            postBreakRamp = ramp
        }
    }
    
    /// Starts a new post-break ramp if not already ramping.
    /// - Parameters:
    ///   - targetWeight: The pre-break baseline weight to ramp back to.
    ///   - sessions: Number of sessions for the ramp (typically 2-3).
    ///   - date: The start date of the ramp.
    public mutating func startPostBreakRamp(
        targetWeight: Load,
        sessions: Int = 2,
        date: Date
    ) {
        // Don't overwrite an existing ramp
        guard postBreakRamp == nil else { return }
        
        postBreakRamp = PostBreakRampState(
            targetWeight: targetWeight,
            sessionsCompleted: 0,
            totalSessions: sessions,
            startDate: date
        )
    }
    
    /// Whether currently in a post-break ramp.
    public var isRampingBack: Bool {
        postBreakRamp != nil && !(postBreakRamp?.isComplete ?? true)
    }
    
    /// Whether currently in a post-deload ramp.
    public var isRampingAfterDeload: Bool {
        postDeloadRamp != nil && !(postDeloadRamp?.isComplete ?? true)
    }
    
    /// Whether in any ramp state (break or deload).
    public var isInAnyRamp: Bool {
        isRampingBack || isRampingAfterDeload
    }
    
    /// Starts a new post-deload ramp if not already ramping.
    /// - Parameters:
    ///   - targetWeight: The pre-deload baseline weight to ramp back to.
    ///   - sessions: Number of sessions for the ramp (typically 2-3).
    ///   - date: The start date of the ramp.
    public mutating func startPostDeloadRamp(
        targetWeight: Load,
        sessions: Int = 2,
        date: Date
    ) {
        // Don't overwrite an existing ramp
        guard postDeloadRamp == nil else { return }
        
        postDeloadRamp = PostBreakRampState(
            targetWeight: targetWeight,
            sessionsCompleted: 0,
            totalSessions: sessions,
            startDate: date
        )
    }
    
    /// Increments the post-deload ramp progress.
    public mutating func incrementDeloadRampProgress() {
        guard var ramp = postDeloadRamp else { return }
        ramp.sessionsCompleted += 1
        if ramp.isComplete {
            postDeloadRamp = nil
        } else {
            postDeloadRamp = ramp
        }
    }
    
    /// Clears the post-deload ramp state.
    public mutating func clearPostDeloadRamp() {
        postDeloadRamp = nil
    }
}

// MARK: - Codable (backward compatible)

extension LiftState: Codable {
    enum CodingKeys: String, CodingKey {
        case exerciseId
        case lastWorkingWeight
        case rollingE1RM
        case failureCount
        case highRpeStreak
        case lastDeloadDate
        case trend
        case e1rmHistory
        case lastSessionDate
        case successfulSessionsCount
        case successStreak
        case recentReadinessScores
        case postBreakRamp
        case postDeloadRamp
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        exerciseId = try container.decode(String.self, forKey: .exerciseId)
        lastWorkingWeight = try container.decodeIfPresent(Load.self, forKey: .lastWorkingWeight) ?? .zero
        rollingE1RM = try container.decodeIfPresent(Double.self, forKey: .rollingE1RM) ?? 0
        failureCount = try container.decodeIfPresent(Int.self, forKey: .failureCount) ?? 0
        highRpeStreak = try container.decodeIfPresent(Int.self, forKey: .highRpeStreak) ?? 0
        lastDeloadDate = try container.decodeIfPresent(Date.self, forKey: .lastDeloadDate)
        trend = try container.decodeIfPresent(PerformanceTrend.self, forKey: .trend) ?? .insufficient
        e1rmHistory = try container.decodeIfPresent([E1RMSample].self, forKey: .e1rmHistory) ?? []
        lastSessionDate = try container.decodeIfPresent(Date.self, forKey: .lastSessionDate)
        successfulSessionsCount = try container.decodeIfPresent(Int.self, forKey: .successfulSessionsCount) ?? 0
        successStreak = try container.decodeIfPresent(Int.self, forKey: .successStreak) ?? 0
        recentReadinessScores = try container.decodeIfPresent([Int].self, forKey: .recentReadinessScores) ?? []
        postBreakRamp = try container.decodeIfPresent(PostBreakRampState.self, forKey: .postBreakRamp)
        postDeloadRamp = try container.decodeIfPresent(PostBreakRampState.self, forKey: .postDeloadRamp)
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encode(exerciseId, forKey: .exerciseId)
        try container.encode(lastWorkingWeight, forKey: .lastWorkingWeight)
        try container.encode(rollingE1RM, forKey: .rollingE1RM)
        try container.encode(failureCount, forKey: .failureCount)
        try container.encode(highRpeStreak, forKey: .highRpeStreak)
        try container.encodeIfPresent(lastDeloadDate, forKey: .lastDeloadDate)
        try container.encode(trend, forKey: .trend)
        try container.encode(e1rmHistory, forKey: .e1rmHistory)
        try container.encodeIfPresent(lastSessionDate, forKey: .lastSessionDate)
        try container.encode(successfulSessionsCount, forKey: .successfulSessionsCount)
        try container.encode(successStreak, forKey: .successStreak)
        try container.encode(recentReadinessScores, forKey: .recentReadinessScores)
        try container.encodeIfPresent(postBreakRamp, forKey: .postBreakRamp)
        try container.encodeIfPresent(postDeloadRamp, forKey: .postDeloadRamp)
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
