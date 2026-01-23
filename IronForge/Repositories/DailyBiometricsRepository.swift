import Foundation
import HealthKit
import SwiftData

@MainActor
final class DailyBiometricsRepository {
    private let modelContext: ModelContext
    private let healthKit: HealthKitService
    private let calendar: Calendar
    
    init(modelContext: ModelContext, healthKit: HealthKitService, calendar: Calendar = .current) {
        self.modelContext = modelContext
        self.healthKit = healthKit
        self.calendar = calendar
    }
    
    /// Pulls the last N days of daily aggregates for whichever metrics are currently authorized and stores them locally.
    ///
    /// - Important: This function is intentionally best-effort. It never throws and never blocks onboarding.
    func refreshDailyBiometrics(lastNDays: Int) async {
        guard lastNDays > 0 else { return }
        guard healthKit.isAvailable() else { return }
        
        func isAuthorized(_ metric: HealthKitMetric) -> Bool {
            guard let type = metric.objectType() else { return false }
            return healthKit.permissionState(for: type) == .authorized
        }
        
        let sleepByDay: [Date: Double] = isAuthorized(.sleepAnalysis)
            ? (try? await healthKit.fetchDailySleepMinutes(lastNDays: lastNDays)) ?? [:]
            : [:]
        
        let hrvByDay: [Date: Double] = isAuthorized(.heartRateVariabilitySDNN)
            ? (try? await healthKit.fetchDailyAvgHRV(lastNDays: lastNDays)) ?? [:]
            : [:]
        
        let restingHRByDay: [Date: Double] = isAuthorized(.restingHeartRate)
            ? (try? await healthKit.fetchDailyAvgRestingHR(lastNDays: lastNDays)) ?? [:]
            : [:]
        
        let activeEnergyByDay: [Date: Double] = isAuthorized(.activeEnergyBurned)
            ? (try? await healthKit.fetchDailyActiveEnergy(lastNDays: lastNDays)) ?? [:]
            : [:]
        
        let stepsByDay: [Date: Double] = isAuthorized(.stepCount)
            ? (try? await healthKit.fetchDailySteps(lastNDays: lastNDays)) ?? [:]
            : [:]
        
        let allDays = Set(sleepByDay.keys)
            .union(hrvByDay.keys)
            .union(restingHRByDay.keys)
            .union(activeEnergyByDay.keys)
            .union(stepsByDay.keys)
        
        guard !allDays.isEmpty else { return }
        
        let range = HealthKitDateHelpers.lastNDaysDateRange(lastNDays: lastNDays, endingAt: Date(), calendar: calendar)
        let startDay = calendar.startOfDay(for: range.start)
        let endDay = calendar.startOfDay(for: range.end)
        
        let existing: [DailyBiometrics]
        do {
            let descriptor = FetchDescriptor<DailyBiometrics>(
                predicate: #Predicate { $0.date >= startDay && $0.date <= endDay }
            )
            existing = try modelContext.fetch(descriptor)
        } catch {
            existing = []
        }
        
        var existingByDay: [Date: DailyBiometrics] = Dictionary(uniqueKeysWithValues: existing.map { ($0.date, $0) })
        let now = Date()
        
        for day in allDays {
            let dayStart = calendar.startOfDay(for: day)
            let record: DailyBiometrics
            if let existing = existingByDay[dayStart] {
                record = existing
            } else {
                record = DailyBiometrics(date: dayStart)
                modelContext.insert(record)
                existingByDay[dayStart] = record
            }
            
            if let sleep = sleepByDay[dayStart] { record.sleepMinutes = sleep }
            if let hrv = hrvByDay[dayStart] { record.hrvSDNN = hrv }
            if let rhr = restingHRByDay[dayStart] { record.restingHR = rhr }
            if let energy = activeEnergyByDay[dayStart] { record.activeEnergy = energy }
            if let steps = stepsByDay[dayStart] { record.steps = steps }
            
            record.updatedAt = now
        }
        
        do {
            try modelContext.save()
        } catch {
            // Best-effort cache; ignore save failures during onboarding.
        }
    }
}

