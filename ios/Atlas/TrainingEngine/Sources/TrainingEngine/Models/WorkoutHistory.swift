// WorkoutHistory.swift
// Workout history for progression and deload decisions.

import Foundation

/// Daily readiness record.
public struct ReadinessRecord: Codable, Sendable, Hashable {
    public let date: Date
    public let score: Int // 0-100
    
    public init(date: Date, score: Int) {
        self.date = date
        self.score = max(0, min(100, score))
    }
}

/// Workout history containing recent sessions and lift states.
public struct WorkoutHistory: Codable, Sendable, Hashable {
    /// Recent completed sessions (most recent first).
    public let sessions: [CompletedSession]
    
    /// Current lift states for all exercises.
    public let liftStates: [String: LiftState]
    
    /// Recent readiness records.
    public let readinessHistory: [ReadinessRecord]
    
    /// Last N days of total volume (for fatigue tracking).
    public let recentVolumeByDate: [Date: Double]
    
    public init(
        sessions: [CompletedSession] = [],
        liftStates: [String: LiftState] = [:],
        readinessHistory: [ReadinessRecord] = [],
        recentVolumeByDate: [Date: Double] = [:]
    ) {
        // Normalize session ordering to be deterministic and robust to unsorted inputs.
        self.sessions = sessions.sorted { a, b in
            if a.date != b.date { return a.date > b.date }
            if a.startedAt != b.startedAt { return a.startedAt > b.startedAt }
            return a.id.uuidString > b.id.uuidString
        }
        self.liftStates = liftStates
        self.readinessHistory = readinessHistory
        self.recentVolumeByDate = recentVolumeByDate
    }
    
    /// Gets the last N sessions.
    public func lastSessions(_ n: Int) -> [CompletedSession] {
        Array(sessions.prefix(n))
    }
    
    /// Gets sessions containing a specific exercise.
    public func sessions(forExercise exerciseId: String) -> [CompletedSession] {
        sessions.filter { session in
            session.exerciseIds.contains(exerciseId)
        }
    }
    
    /// Gets the last session for a specific exercise.
    public func lastSession(forExercise exerciseId: String) -> CompletedSession? {
        sessions(forExercise: exerciseId).first
    }
    
    /// Gets exercise results for a specific exercise from recent sessions.
    public func exerciseResults(forExercise exerciseId: String, limit: Int = 10) -> [ExerciseSessionResult] {
        guard limit > 0 else { return [] }
        
        // Sessions are stored most-recent-first. We want the most recent *N occurrences* of this exercise,
        // not simply the first N sessions overall.
        var results: [ExerciseSessionResult] = []
        results.reserveCapacity(min(limit, 10))
        
        for session in sessions {
            // Deload sessions intentionally reduce load/volume and should not drive progression baselines.
            // (They are still present in `sessions` for auditing and fatigue calculations.)
            guard session.wasDeload == false else { continue }
            if let match = session.exerciseResults.first(where: { $0.exerciseId == exerciseId }) {
                results.append(match)
                if results.count >= limit {
                    break
                }
            }
        }
        
        return results
    }
    
    /// Computes total volume over the last N days.
    public func totalVolume(lastDays: Int, from date: Date = Date(), calendar: Calendar = .current) -> Double {
        guard lastDays > 0 else { return 0 }
        
        // Treat volume as day-bucketed data. Keys may include timestamps, so normalize via startOfDay.
        let endDay = calendar.startOfDay(for: date)
        let startDay = calendar.date(byAdding: .day, value: -(lastDays - 1), to: endDay) ?? endDay
        
        var total = 0.0
        for (key, value) in recentVolumeByDate {
            let dayKey = calendar.startOfDay(for: key)
            if dayKey >= startDay && dayKey <= endDay {
                total += value
            }
        }
        return total
    }
    
    /// Computes average daily volume over a window.
    public func averageDailyVolume(lastDays: Int, from date: Date = Date(), calendar: Calendar = .current) -> Double {
        guard lastDays > 0 else { return 0 }
        let total = totalVolume(lastDays: lastDays, from: date, calendar: calendar)
        return total / Double(lastDays)
    }
    
    /// Gets consecutive low-readiness days.
    public func consecutiveLowReadinessDays(threshold: Int, from date: Date = Date(), calendar: Calendar = .current) -> Int {
        // Real-world readiness can have missing days (device not worn, data not synced).
        // We only count *consecutive calendar days* with records below threshold.
        let startDay = calendar.startOfDay(for: date)
        
        // Collapse multiple records per day deterministically by taking the minimum score for the day.
        var byDay: [Date: Int] = [:]
        byDay.reserveCapacity(min(readinessHistory.count, 64))
        for record in readinessHistory {
            let d = calendar.startOfDay(for: record.date)
            byDay[d] = min(byDay[d] ?? 100, record.score)
        }
        
        var count = 0
        var offset = 0
        
        while true {
            guard let checkDay = calendar.date(byAdding: .day, value: -offset, to: startDay) else {
                break
            }
            guard let score = byDay[checkDay] else {
                // Gap in data breaks consecutiveness.
                break
            }
            if score < threshold {
                count += 1
                offset += 1
            } else {
                break
            }
        }
        
        return count
    }
    
    /// Determines the next template in rotation based on history.
    public func nextTemplateInRotation(order: [WorkoutTemplateId]) -> WorkoutTemplateId? {
        guard !order.isEmpty else { return nil }
        
        // Find last used template
        guard let lastSession = sessions.first,
              let lastTemplateId = lastSession.templateId,
              let lastIndex = order.firstIndex(of: lastTemplateId) else {
            // No history, start with first
            return order.first
        }
        
        // Return next in rotation (wrapping around)
        let nextIndex = (lastIndex + 1) % order.count
        return order[nextIndex]
    }
}

// MARK: - Codable (ensure normalization on decode)

extension WorkoutHistory {
    enum CodingKeys: String, CodingKey {
        case sessions
        case liftStates
        case readinessHistory
        case recentVolumeByDate
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        let sessions = try container.decodeIfPresent([CompletedSession].self, forKey: .sessions) ?? []
        let liftStates = try container.decodeIfPresent([String: LiftState].self, forKey: .liftStates) ?? [:]
        let readinessHistory = try container.decodeIfPresent([ReadinessRecord].self, forKey: .readinessHistory) ?? []
        let recentVolumeByDate = try container.decodeIfPresent([Date: Double].self, forKey: .recentVolumeByDate) ?? [:]
        
        self.init(
            sessions: sessions,
            liftStates: liftStates,
            readinessHistory: readinessHistory,
            recentVolumeByDate: recentVolumeByDate
        )
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(sessions, forKey: .sessions)
        try container.encode(liftStates, forKey: .liftStates)
        try container.encode(readinessHistory, forKey: .readinessHistory)
        try container.encode(recentVolumeByDate, forKey: .recentVolumeByDate)
    }
}
