import Foundation

enum HealthKitDateHelpers {
    /// Returns a closed-open interval [start, end) spanning the last N local days, ending "now".
    /// - Note: `lastNDays` is inclusive of today.
    static func lastNDaysDateRange(
        lastNDays: Int,
        endingAt endDate: Date = Date(),
        calendar: Calendar = .current
    ) -> (start: Date, end: Date) {
        guard lastNDays > 0 else { return (endDate, endDate) }
        let end = endDate
        let endDayStart = calendar.startOfDay(for: end)
        let startDay = calendar.date(byAdding: .day, value: -(lastNDays - 1), to: endDayStart) ?? endDayStart
        return (startDay, end)
    }
    
    /// Buckets a list of time segments into local-day keys (start-of-day), splitting segments that span midnight.
    /// Returns minutes per day.
    static func bucketedMinutesByDay(
        segments: [(start: Date, end: Date)],
        calendar: Calendar = .current
    ) -> [Date: Double] {
        guard !segments.isEmpty else { return [:] }
        
        var totals: [Date: Double] = [:]
        
        for segment in segments {
            var cursor = segment.start
            let end = segment.end
            guard cursor < end else { continue }
            
            while cursor < end {
                let dayStart = calendar.startOfDay(for: cursor)
                let nextDayStart = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart.addingTimeInterval(24 * 60 * 60)
                let chunkEnd = min(end, nextDayStart)
                
                let minutes = chunkEnd.timeIntervalSince(cursor) / 60.0
                if minutes > 0 {
                    totals[dayStart, default: 0] += minutes
                }
                
                cursor = chunkEnd
            }
        }
        
        return totals
    }
}

