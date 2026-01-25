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
    /// - Note: For read-only HealthKit permissions, we cannot check authorization status reliably.
    ///   iOS does not reveal whether the user granted read access. We just attempt to fetch data
    ///   and handle empty results gracefully.
    func refreshDailyBiometrics(lastNDays: Int) async {
        guard lastNDays > 0 else { return }
        guard healthKit.isAvailable() else { return }
        
        // Note: We don't check authorization status for read permissions because
        // iOS never tells us whether read access was granted. We just try to fetch
        // the data and it will return empty if access was denied.
        
        print("[HealthKit] Fetching sleep data...")
        let sleepByDay: [Date: Double] = (try? await healthKit.fetchDailySleepMinutes(lastNDays: lastNDays)) ?? [:]
        print("[HealthKit] Sleep data: \(sleepByDay.count) days")
        
        print("[HealthKit] Fetching HRV data...")
        let hrvByDay: [Date: Double] = (try? await healthKit.fetchDailyAvgHRV(lastNDays: lastNDays)) ?? [:]
        print("[HealthKit] HRV data: \(hrvByDay.count) days")
        
        print("[HealthKit] Fetching resting HR data...")
        let restingHRByDay: [Date: Double] = (try? await healthKit.fetchDailyAvgRestingHR(lastNDays: lastNDays)) ?? [:]
        print("[HealthKit] Resting HR data: \(restingHRByDay.count) days")
        
        print("[HealthKit] Fetching active energy data...")
        let activeEnergyByDay: [Date: Double] = (try? await healthKit.fetchDailyActiveEnergy(lastNDays: lastNDays)) ?? [:]
        print("[HealthKit] Active energy data: \(activeEnergyByDay.count) days")
        
        print("[HealthKit] Fetching steps data...")
        let stepsByDay: [Date: Double] = (try? await healthKit.fetchDailySteps(lastNDays: lastNDays)) ?? [:]
        print("[HealthKit] Steps data: \(stepsByDay.count) days")
        
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

