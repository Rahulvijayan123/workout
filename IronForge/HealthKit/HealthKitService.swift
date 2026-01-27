import Foundation
import HealthKit

final class HealthKitService: @unchecked Sendable {
    private let healthStore: HKHealthStore
    private let calendar: Calendar
    
    init(healthStore: HKHealthStore = HKHealthStore(), calendar: Calendar = .current) {
        self.healthStore = healthStore
        self.calendar = calendar
    }
    
    func isAvailable() -> Bool {
        HKHealthStore.isHealthDataAvailable()
    }
    
    enum PermissionState: String, Sendable {
        case notDetermined
        case authorized
        case denied
    }
    
    static func permissionState(from status: HKAuthorizationStatus) -> PermissionState {
        switch status {
        case .notDetermined:
            return .notDetermined
        case .sharingDenied:
            return .denied
        case .sharingAuthorized:
            return .authorized
        @unknown default:
            return .denied
        }
    }
    
    func permissionState(for type: HKObjectType) -> PermissionState {
        Self.permissionState(from: healthStore.authorizationStatus(for: type))
    }
    
    struct AuthorizationResult: Sendable {
        let requestedMetrics: [HealthKitMetric]
        let stateByMetric: [HealthKitMetric: PermissionState]
        
        var deniedMetrics: [HealthKitMetric] {
            requestedMetrics.filter { stateByMetric[$0] == .denied }
        }
        
        var authorizedMetrics: [HealthKitMetric] {
            requestedMetrics.filter { stateByMetric[$0] == .authorized }
        }
    }
    
    enum HealthKitServiceError: Error, LocalizedError {
        case healthDataNotAvailable
        case missingInfoPlistKey(String)
        case invalidConfiguration(String)
        case queryReturnedNoResults
        
        var errorDescription: String? {
            switch self {
            case .healthDataNotAvailable:
                return "Health data is not available on this device."
            case .missingInfoPlistKey(let key):
                return "Missing required Info.plist key: \(key)."
            case .invalidConfiguration(let message):
                return message
            case .queryReturnedNoResults:
                return "No results were returned."
            }
        }
    }
    
    /// Requests read-only authorization for the selected types.
    ///
    /// - Important: If `NSHealthShareUsageDescription` is missing from Info.plist,
    ///   iOS will terminate the app when requesting HealthKit authorization. We defensively
    ///   check for the key and throw instead so onboarding won’t crash.
    func requestAuthorization(selected: HealthKitSelection) async throws -> AuthorizationResult {
        guard isAvailable() else { throw HealthKitServiceError.healthDataNotAvailable }
        guard selected.hasAnySelected else {
            return AuthorizationResult(requestedMetrics: [], stateByMetric: [:])
        }
        
        // Prevent a hard crash if the key is missing.
        if (Bundle.main.object(forInfoDictionaryKey: "NSHealthShareUsageDescription") as? String)?.isEmpty != false {
            throw HealthKitServiceError.missingInfoPlistKey("NSHealthShareUsageDescription")
        }
        
        let requestedMetrics = selected.selectedMetrics
        let readTypes = selected.selectedReadTypes
        
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            healthStore.requestAuthorization(toShare: nil, read: readTypes) { _, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: ())
            }
        }
        
        var states: [HealthKitMetric: PermissionState] = [:]
        for metric in requestedMetrics {
            if let type = metric.objectType() {
                states[metric] = permissionState(for: type)
            } else {
                states[metric] = .denied
            }
        }
        
        return AuthorizationResult(requestedMetrics: requestedMetrics, stateByMetric: states)
    }
    
    // MARK: - Sleep
    
    func fetchDailySleepMinutes(lastNDays: Int) async throws -> [Date: Double] {
        guard lastNDays > 0 else { return [:] }
        guard let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else { return [:] }
        
        let range = HealthKitDateHelpers.lastNDaysDateRange(lastNDays: lastNDays, endingAt: Date(), calendar: calendar)
        // For sleep we want *overlapping* samples too (e.g. a segment that started before midnight but ends after).
        let predicate = HKQuery.predicateForSamples(withStart: range.start, end: range.end, options: [])
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
        
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: sleepType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sort]
            ) { _, samples, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                
                guard let categorySamples = samples as? [HKCategorySample], !categorySamples.isEmpty else {
                    continuation.resume(returning: [:])
                    return
                }
                
                let asleepSegments: [(start: Date, end: Date)] = categorySamples
                    .filter { Self.isAsleepSleepSampleValue($0.value) }
                    .map { (start: $0.startDate, end: $0.endDate) }
                
                guard !asleepSegments.isEmpty else {
                    continuation.resume(returning: [:])
                    return
                }
                
                let bucketed = HealthKitDateHelpers.bucketedMinutesByDay(segments: asleepSegments, calendar: self.calendar)
                continuation.resume(returning: bucketed)
            }
            
            self.healthStore.execute(query)
        }
    }
    
    private static func isAsleepSleepSampleValue(_ rawValue: Int) -> Bool {
        guard let value = HKCategoryValueSleepAnalysis(rawValue: rawValue) else { return false }
        
        if #available(iOS 16.0, *) {
            switch value {
            case .asleep, .asleepUnspecified, .asleepCore, .asleepDeep, .asleepREM:
                return true
            case .inBed, .awake:
                return false
            @unknown default:
                return false
            }
        } else {
            // Prior to sleep stage breakdown, only `.asleep` represents asleep time.
            return value == .asleep
        }
    }
    
    // MARK: - Quantity aggregates
    
    func fetchDailyAvgHRV(lastNDays: Int) async throws -> [Date: Double] {
        try await fetchDailyStatistics(
            quantityIdentifier: .heartRateVariabilitySDNN,
            unit: .secondUnit(with: .milli),
            options: [.discreteAverage],
            lastNDays: lastNDays
        )
    }
    
    func fetchDailyAvgRestingHR(lastNDays: Int) async throws -> [Date: Double] {
        let bpmUnit = HKUnit.count().unitDivided(by: .minute())
        return try await fetchDailyStatistics(
            quantityIdentifier: .restingHeartRate,
            unit: bpmUnit,
            options: [.discreteAverage],
            lastNDays: lastNDays
        )
    }
    
    func fetchDailyActiveEnergy(lastNDays: Int) async throws -> [Date: Double] {
        try await fetchDailyStatistics(
            quantityIdentifier: .activeEnergyBurned,
            unit: .kilocalorie(),
            options: [.cumulativeSum],
            lastNDays: lastNDays
        )
    }
    
    func fetchDailySteps(lastNDays: Int) async throws -> [Date: Double] {
        try await fetchDailyStatistics(
            quantityIdentifier: .stepCount,
            unit: .count(),
            options: [.cumulativeSum],
            lastNDays: lastNDays
        )
    }
    
    private func fetchDailyStatistics(
        quantityIdentifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        options: HKStatisticsOptions,
        lastNDays: Int
    ) async throws -> [Date: Double] {
        guard lastNDays > 0 else { return [:] }
        guard let quantityType = HKQuantityType.quantityType(forIdentifier: quantityIdentifier) else {
            throw HealthKitServiceError.invalidConfiguration("Unsupported HealthKit quantity type: \(quantityIdentifier.rawValue)")
        }
        
        let range = HealthKitDateHelpers.lastNDaysDateRange(lastNDays: lastNDays, endingAt: Date(), calendar: calendar)
        let predicate = HKQuery.predicateForSamples(withStart: range.start, end: range.end, options: .strictStartDate)
        let anchorDate = calendar.startOfDay(for: range.end)
        let interval = DateComponents(day: 1)
        
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsCollectionQuery(
                quantityType: quantityType,
                quantitySamplePredicate: predicate,
                options: options,
                anchorDate: anchorDate,
                intervalComponents: interval
            )
            
            query.initialResultsHandler = { _, results, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                
                guard let results = results else {
                    continuation.resume(returning: [:])
                    return
                }
                
                var output: [Date: Double] = [:]
                
                results.enumerateStatistics(from: range.start, to: range.end) { statistics, _ in
                    let day = self.calendar.startOfDay(for: statistics.startDate)
                    
                    let quantity: HKQuantity?
                    if options.contains(.cumulativeSum) {
                        quantity = statistics.sumQuantity()
                    } else if options.contains(.discreteAverage) {
                        quantity = statistics.averageQuantity()
                    } else {
                        quantity = nil
                    }
                    
                    guard let quantity else { return }
                    output[day] = quantity.doubleValue(for: unit)
                }
                
                continuation.resume(returning: output)
            }
            
            self.healthStore.execute(query)
        }
    }
    
    // MARK: - Body Mass
    
    /// Fetches the most recent body mass measurement from HealthKit.
    /// - Returns: Body mass in pounds (lbs), or `nil` if no measurement is available.
    func fetchMostRecentBodyMassLbs() async throws -> Double? {
        guard let bodyMassType = HKQuantityType.quantityType(forIdentifier: .bodyMass) else {
            return nil
        }
        
        // Query for the single most recent sample, sorted by end date descending
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: bodyMassType,
                predicate: nil,
                limit: 1,
                sortDescriptors: [sortDescriptor]
            ) { _, samples, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                
                guard let sample = samples?.first as? HKQuantitySample else {
                    continuation.resume(returning: nil)
                    return
                }
                
                // Convert to pounds
                let poundsUnit = HKUnit.pound()
                let massInLbs = sample.quantity.doubleValue(for: poundsUnit)
                continuation.resume(returning: massInLbs)
            }
            
            self.healthStore.execute(query)
        }
    }
    
    // MARK: - Workouts (optional)
    
    func fetchWorkouts(lastNDays: Int) async throws -> [HKWorkoutSummary] {
        guard lastNDays > 0 else { return [] }
        
        let workoutType = HKObjectType.workoutType()
        let range = HealthKitDateHelpers.lastNDaysDateRange(lastNDays: lastNDays, endingAt: Date(), calendar: calendar)
        let predicate = HKQuery.predicateForSamples(withStart: range.start, end: range.end, options: .strictStartDate)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
        
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: workoutType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sort]
            ) { _, samples, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                
                guard let workouts = samples as? [HKWorkout], !workouts.isEmpty else {
                    continuation.resume(returning: [])
                    return
                }
                
                continuation.resume(returning: workouts.map(HKWorkoutSummary.init(workout:)))
            }
            
            self.healthStore.execute(query)
        }
    }
}

