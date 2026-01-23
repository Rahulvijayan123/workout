// TemplateScheduler.swift
// Deterministic template selection based on schedule type.

import Foundation

/// Scheduler for selecting workout templates.
public struct TemplateScheduler {
    public let plan: TrainingPlan
    public let history: WorkoutHistory
    public let calendar: Calendar
    
    public init(
        plan: TrainingPlan,
        history: WorkoutHistory,
        calendar: Calendar = .current
    ) {
        self.plan = plan
        self.history = history
        self.calendar = calendar
    }
    
    /// Selects the appropriate template for a given date.
    public func selectTemplate(for date: Date) -> WorkoutTemplateId? {
        switch plan.schedule {
        case .fixedWeekday(let mapping):
            return selectFixedWeekday(mapping: mapping, date: date)
            
        case .rotation(let order):
            return selectRotation(order: order)
            
        case .manual:
            return nil
        }
    }
    
    /// Selects template based on fixed weekday mapping.
    private func selectFixedWeekday(
        mapping: [Int: WorkoutTemplateId],
        date: Date
    ) -> WorkoutTemplateId? {
        let weekday = calendar.component(.weekday, from: date)
        return mapping[weekday]
    }
    
    /// Selects next template in rotation order.
    private func selectRotation(order: [WorkoutTemplateId]) -> WorkoutTemplateId? {
        guard !order.isEmpty else { return nil }
        return history.nextTemplateInRotation(order: order)
    }
    
    /// Determines if a given date is a training day.
    public func isTrainingDay(_ date: Date) -> Bool {
        selectTemplate(for: date) != nil
    }
    
    /// Gets all training days in a week starting from date.
    public func trainingDaysInWeek(startingFrom date: Date) -> [Date] {
        var trainingDays: [Date] = []
        
        for dayOffset in 0..<7 {
            guard let checkDate = calendar.date(byAdding: .day, value: dayOffset, to: date) else {
                continue
            }
            
            if isTrainingDay(checkDate) {
                trainingDays.append(checkDate)
            }
        }
        
        return trainingDays
    }
    
    /// Gets the next training day from a given date.
    public func nextTrainingDay(from date: Date, maxDaysToSearch: Int = 7) -> Date? {
        for dayOffset in 1...maxDaysToSearch {
            guard let checkDate = calendar.date(byAdding: .day, value: dayOffset, to: date) else {
                continue
            }
            
            if isTrainingDay(checkDate) {
                return checkDate
            }
        }
        
        return nil
    }
    
    /// Gets the schedule preview for the next N days.
    public func schedulePreview(days: Int, from startDate: Date = Date()) -> [SchedulePreviewItem] {
        var preview: [SchedulePreviewItem] = []
        
        for dayOffset in 0..<days {
            guard let date = calendar.date(byAdding: .day, value: dayOffset, to: startDate) else {
                continue
            }
            
            let templateId = selectTemplate(for: date)
            let template = templateId.flatMap { plan.templates[$0] }
            
            preview.append(SchedulePreviewItem(
                date: date,
                templateId: templateId,
                templateName: template?.name,
                isRestDay: templateId == nil
            ))
        }
        
        return preview
    }
}

/// A preview item for the schedule.
public struct SchedulePreviewItem: Sendable, Hashable {
    public let date: Date
    public let templateId: WorkoutTemplateId?
    public let templateName: String?
    public let isRestDay: Bool
    
    public init(
        date: Date,
        templateId: WorkoutTemplateId?,
        templateName: String?,
        isRestDay: Bool
    ) {
        self.date = date
        self.templateId = templateId
        self.templateName = templateName
        self.isRestDay = isRestDay
    }
}

// MARK: - Schedule Builders

extension TemplateScheduler {
    /// Creates a Push/Pull/Legs rotation schedule.
    public static func pplRotation(
        push: WorkoutTemplateId,
        pull: WorkoutTemplateId,
        legs: WorkoutTemplateId
    ) -> ScheduleType {
        .rotation(order: [push, pull, legs])
    }
    
    /// Creates an Upper/Lower rotation schedule.
    public static func upperLowerRotation(
        upper: WorkoutTemplateId,
        lower: WorkoutTemplateId
    ) -> ScheduleType {
        .rotation(order: [upper, lower])
    }
    
    /// Creates a fixed weekday schedule for a 3-day split.
    public static func threeDayFixed(
        monday: WorkoutTemplateId,
        wednesday: WorkoutTemplateId,
        friday: WorkoutTemplateId
    ) -> ScheduleType {
        .fixedWeekday(mapping: [
            2: monday,      // Monday
            4: wednesday,   // Wednesday
            6: friday       // Friday
        ])
    }
    
    /// Creates a fixed weekday schedule for a 4-day split.
    public static func fourDayFixed(
        monday: WorkoutTemplateId,
        tuesday: WorkoutTemplateId,
        thursday: WorkoutTemplateId,
        friday: WorkoutTemplateId
    ) -> ScheduleType {
        .fixedWeekday(mapping: [
            2: monday,      // Monday
            3: tuesday,     // Tuesday
            5: thursday,    // Thursday
            6: friday       // Friday
        ])
    }
}
