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
    
    // MARK: - Quantity aggregates (Recovery)
    
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
    
    /// Respiratory rate in breaths per minute
    func fetchDailyAvgRespiratoryRate(lastNDays: Int) async throws -> [Date: Double] {
        let breathsPerMinute = HKUnit.count().unitDivided(by: .minute())
        return try await fetchDailyStatistics(
            quantityIdentifier: .respiratoryRate,
            unit: breathsPerMinute,
            options: [.discreteAverage],
            lastNDays: lastNDays
        )
    }
    
    /// Blood oxygen saturation (SpO2) as percentage (0-100)
    func fetchDailyAvgOxygenSaturation(lastNDays: Int) async throws -> [Date: Double] {
        let results = try await fetchDailyStatistics(
            quantityIdentifier: .oxygenSaturation,
            unit: .percent(),
            options: [.discreteAverage],
            lastNDays: lastNDays
        )
        // Convert from 0-1 to 0-100
        return results.mapValues { $0 * 100 }
    }
    
    /// VO2 Max in mL/(kg·min)
    func fetchDailyVO2Max(lastNDays: Int) async throws -> [Date: Double] {
        let vo2Unit = HKUnit.literUnit(with: .milli).unitDivided(by: HKUnit.gramUnit(with: .kilo).unitMultiplied(by: .minute()))
        return try await fetchDailyStatistics(
            quantityIdentifier: .vo2Max,
            unit: vo2Unit,
            options: [.discreteAverage],
            lastNDays: lastNDays
        )
    }
    
    // MARK: - Quantity aggregates (Activity)
    
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
    
    /// Exercise time in minutes
    func fetchDailyExerciseTime(lastNDays: Int) async throws -> [Date: Double] {
        try await fetchDailyStatistics(
            quantityIdentifier: .appleExerciseTime,
            unit: .minute(),
            options: [.cumulativeSum],
            lastNDays: lastNDays
        )
    }
    
    // MARK: - Walking Metrics
    
    /// Walking heart rate average in BPM
    func fetchDailyWalkingHeartRateAverage(lastNDays: Int) async throws -> [Date: Double] {
        let bpmUnit = HKUnit.count().unitDivided(by: .minute())
        return try await fetchDailyStatistics(
            quantityIdentifier: .walkingHeartRateAverage,
            unit: bpmUnit,
            options: [.discreteAverage],
            lastNDays: lastNDays
        )
    }
    
    /// Walking asymmetry as percentage (0-100)
    func fetchDailyWalkingAsymmetry(lastNDays: Int) async throws -> [Date: Double] {
        let results = try await fetchDailyStatistics(
            quantityIdentifier: .walkingAsymmetryPercentage,
            unit: .percent(),
            options: [.discreteAverage],
            lastNDays: lastNDays
        )
        return results.mapValues { $0 * 100 }
    }
    
    /// Walking speed in m/s
    func fetchDailyWalkingSpeed(lastNDays: Int) async throws -> [Date: Double] {
        try await fetchDailyStatistics(
            quantityIdentifier: .walkingSpeed,
            unit: HKUnit.meter().unitDivided(by: .second()),
            options: [.discreteAverage],
            lastNDays: lastNDays
        )
    }
    
    /// Walking step length in meters
    func fetchDailyWalkingStepLength(lastNDays: Int) async throws -> [Date: Double] {
        try await fetchDailyStatistics(
            quantityIdentifier: .walkingStepLength,
            unit: .meter(),
            options: [.discreteAverage],
            lastNDays: lastNDays
        )
    }
    
    /// Walking double support percentage (0-100)
    func fetchDailyWalkingDoubleSupport(lastNDays: Int) async throws -> [Date: Double] {
        let results = try await fetchDailyStatistics(
            quantityIdentifier: .walkingDoubleSupportPercentage,
            unit: .percent(),
            options: [.discreteAverage],
            lastNDays: lastNDays
        )
        return results.mapValues { $0 * 100 }
    }
    
    /// Stair ascent speed in m/s
    func fetchDailyStairAscentSpeed(lastNDays: Int) async throws -> [Date: Double] {
        try await fetchDailyStatistics(
            quantityIdentifier: .stairAscentSpeed,
            unit: HKUnit.meter().unitDivided(by: .second()),
            options: [.discreteAverage],
            lastNDays: lastNDays
        )
    }
    
    /// Stair descent speed in m/s
    func fetchDailyStairDescentSpeed(lastNDays: Int) async throws -> [Date: Double] {
        try await fetchDailyStatistics(
            quantityIdentifier: .stairDescentSpeed,
            unit: HKUnit.meter().unitDivided(by: .second()),
            options: [.discreteAverage],
            lastNDays: lastNDays
        )
    }
    
    /// Six minute walk test distance in meters
    func fetchDailySixMinuteWalkDistance(lastNDays: Int) async throws -> [Date: Double] {
        try await fetchDailyStatistics(
            quantityIdentifier: .sixMinuteWalkTestDistance,
            unit: .meter(),
            options: [.discreteAverage],
            lastNDays: lastNDays
        )
    }
    
    // MARK: - Sleep & Environment
    
    /// Time in daylight in minutes (iOS 17+)
    @available(iOS 17.0, *)
    func fetchDailyTimeInDaylight(lastNDays: Int) async throws -> [Date: Double] {
        try await fetchDailyStatistics(
            quantityIdentifier: .timeInDaylight,
            unit: .minute(),
            options: [.cumulativeSum],
            lastNDays: lastNDays
        )
    }
    
    /// Wrist temperature deviation in Celsius (iOS 16+)
    @available(iOS 16.0, *)
    func fetchDailyWristTemperature(lastNDays: Int) async throws -> [Date: Double] {
        try await fetchDailyStatistics(
            quantityIdentifier: .appleSleepingWristTemperature,
            unit: .degreeCelsius(),
            options: [.discreteAverage],
            lastNDays: lastNDays
        )
    }
    
    // MARK: - Body Composition
    
    /// Lean body mass in kg
    func fetchDailyLeanBodyMass(lastNDays: Int) async throws -> [Date: Double] {
        try await fetchDailyStatistics(
            quantityIdentifier: .leanBodyMass,
            unit: .gramUnit(with: .kilo),
            options: [.discreteAverage],
            lastNDays: lastNDays
        )
    }
    
    // MARK: - Nutrition
    
    /// Dietary energy consumed in kcal
    func fetchDailyDietaryEnergy(lastNDays: Int) async throws -> [Date: Double] {
        try await fetchDailyStatistics(
            quantityIdentifier: .dietaryEnergyConsumed,
            unit: .kilocalorie(),
            options: [.cumulativeSum],
            lastNDays: lastNDays
        )
    }
    
    /// Dietary protein in grams
    func fetchDailyDietaryProtein(lastNDays: Int) async throws -> [Date: Double] {
        try await fetchDailyStatistics(
            quantityIdentifier: .dietaryProtein,
            unit: .gram(),
            options: [.cumulativeSum],
            lastNDays: lastNDays
        )
    }
    
    /// Dietary carbohydrates in grams
    func fetchDailyDietaryCarbs(lastNDays: Int) async throws -> [Date: Double] {
        try await fetchDailyStatistics(
            quantityIdentifier: .dietaryCarbohydrates,
            unit: .gram(),
            options: [.cumulativeSum],
            lastNDays: lastNDays
        )
    }
    
    /// Dietary fat in grams
    func fetchDailyDietaryFat(lastNDays: Int) async throws -> [Date: Double] {
        try await fetchDailyStatistics(
            quantityIdentifier: .dietaryFatTotal,
            unit: .gram(),
            options: [.cumulativeSum],
            lastNDays: lastNDays
        )
    }
    
    /// Water intake in liters
    func fetchDailyWaterIntake(lastNDays: Int) async throws -> [Date: Double] {
        try await fetchDailyStatistics(
            quantityIdentifier: .dietaryWater,
            unit: .liter(),
            options: [.cumulativeSum],
            lastNDays: lastNDays
        )
    }
    
    /// Caffeine intake in mg
    func fetchDailyCaffeine(lastNDays: Int) async throws -> [Date: Double] {
        try await fetchDailyStatistics(
            quantityIdentifier: .dietaryCaffeine,
            unit: .gramUnit(with: .milli),
            options: [.cumulativeSum],
            lastNDays: lastNDays
        )
    }
    
    // MARK: - Female Health
    
    /// Basal body temperature in Celsius
    func fetchDailyBasalBodyTemperature(lastNDays: Int) async throws -> [Date: Double] {
        try await fetchDailyStatistics(
            quantityIdentifier: .basalBodyTemperature,
            unit: .degreeCelsius(),
            options: [.discreteAverage],
            lastNDays: lastNDays
        )
    }
    
    /// Fetches menstrual flow data
    func fetchDailyMenstrualFlow(lastNDays: Int) async throws -> [Date: Int] {
        guard lastNDays > 0 else { return [:] }
        guard let flowType = HKObjectType.categoryType(forIdentifier: .menstrualFlow) else { return [:] }
        
        let range = HealthKitDateHelpers.lastNDaysDateRange(lastNDays: lastNDays, endingAt: Date(), calendar: calendar)
        let predicate = HKQuery.predicateForSamples(withStart: range.start, end: range.end, options: .strictStartDate)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
        
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: flowType,
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
                
                var flowByDay: [Date: Int] = [:]
                for sample in categorySamples {
                    let day = self.calendar.startOfDay(for: sample.startDate)
                    // Take the max flow value for the day if multiple samples
                    if let existing = flowByDay[day] {
                        flowByDay[day] = max(existing, sample.value)
                    } else {
                        flowByDay[day] = sample.value
                    }
                }
                
                continuation.resume(returning: flowByDay)
            }
            
            self.healthStore.execute(query)
        }
    }
    
    /// Fetches cervical mucus quality data
    func fetchDailyCervicalMucusQuality(lastNDays: Int) async throws -> [Date: Int] {
        guard lastNDays > 0 else { return [:] }
        guard let mucusType = HKObjectType.categoryType(forIdentifier: .cervicalMucusQuality) else { return [:] }
        
        let range = HealthKitDateHelpers.lastNDaysDateRange(lastNDays: lastNDays, endingAt: Date(), calendar: calendar)
        let predicate = HKQuery.predicateForSamples(withStart: range.start, end: range.end, options: .strictStartDate)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
        
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: mucusType,
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
                
                var mucusByDay: [Date: Int] = [:]
                for sample in categorySamples {
                    let day = self.calendar.startOfDay(for: sample.startDate)
                    mucusByDay[day] = sample.value
                }
                
                continuation.resume(returning: mucusByDay)
            }
            
            self.healthStore.execute(query)
        }
    }
    
    // MARK: - Mindfulness
    
    /// Fetches mindful minutes per day
    func fetchDailyMindfulMinutes(lastNDays: Int) async throws -> [Date: Double] {
        guard lastNDays > 0 else { return [:] }
        guard let mindfulType = HKObjectType.categoryType(forIdentifier: .mindfulSession) else { return [:] }
        
        let range = HealthKitDateHelpers.lastNDaysDateRange(lastNDays: lastNDays, endingAt: Date(), calendar: calendar)
        let predicate = HKQuery.predicateForSamples(withStart: range.start, end: range.end, options: .strictStartDate)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
        
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: mindfulType,
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
                
                var minutesByDay: [Date: Double] = [:]
                for sample in categorySamples {
                    let day = self.calendar.startOfDay(for: sample.startDate)
                    let duration = sample.endDate.timeIntervalSince(sample.startDate) / 60.0
                    minutesByDay[day, default: 0] += duration
                }
                
                continuation.resume(returning: minutesByDay)
            }
            
            self.healthStore.execute(query)
        }
    }
    
    // MARK: - Stand Hours
    
    /// Fetches stand hours per day (count of hours with standing activity)
    func fetchDailyStandHours(lastNDays: Int) async throws -> [Date: Int] {
        guard lastNDays > 0 else { return [:] }
        guard let standType = HKObjectType.categoryType(forIdentifier: .appleStandHour) else { return [:] }
        
        let range = HealthKitDateHelpers.lastNDaysDateRange(lastNDays: lastNDays, endingAt: Date(), calendar: calendar)
        let predicate = HKQuery.predicateForSamples(withStart: range.start, end: range.end, options: .strictStartDate)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
        
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: standType,
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
                
                var standByDay: [Date: Int] = [:]
                for sample in categorySamples {
                    let day = self.calendar.startOfDay(for: sample.startDate)
                    // Value of 0 = stood, 1 = idle
                    if sample.value == HKCategoryValueAppleStandHour.stood.rawValue {
                        standByDay[day, default: 0] += 1
                    }
                }
                
                continuation.resume(returning: standByDay)
            }
            
            self.healthStore.execute(query)
        }
    }
    
    // MARK: - Sleep Stages (iOS 16+)
    
    /// Fetches detailed sleep stages breakdown
    @available(iOS 16.0, *)
    func fetchDailySleepStages(lastNDays: Int) async throws -> [Date: SleepStagesBreakdown] {
        guard lastNDays > 0 else { return [:] }
        guard let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else { return [:] }
        
        let range = HealthKitDateHelpers.lastNDaysDateRange(lastNDays: lastNDays, endingAt: Date(), calendar: calendar)
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
                
                var stagesByDay: [Date: SleepStagesBreakdown] = [:]
                
                for sample in categorySamples {
                    // Attribute sleep to the day it ended (wake up day)
                    let day = self.calendar.startOfDay(for: sample.endDate)
                    let durationMinutes = sample.endDate.timeIntervalSince(sample.startDate) / 60.0
                    
                    var breakdown = stagesByDay[day] ?? SleepStagesBreakdown()
                    
                    if let value = HKCategoryValueSleepAnalysis(rawValue: sample.value) {
                        switch value {
                        case .inBed:
                            breakdown.inBedMinutes += durationMinutes
                        case .awake:
                            breakdown.awakeMinutes += durationMinutes
                        case .asleepCore:
                            breakdown.coreMinutes += durationMinutes
                        case .asleepDeep:
                            breakdown.deepMinutes += durationMinutes
                        case .asleepREM:
                            breakdown.remMinutes += durationMinutes
                        case .asleepUnspecified, .asleep:
                            breakdown.unspecifiedMinutes += durationMinutes
                        @unknown default:
                            breakdown.unspecifiedMinutes += durationMinutes
                        }
                    }
                    
                    stagesByDay[day] = breakdown
                }
                
                continuation.resume(returning: stagesByDay)
            }
            
            self.healthStore.execute(query)
        }
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

// MARK: - Supporting Types

/// Breakdown of sleep stages for a single night
struct SleepStagesBreakdown: Sendable {
    var inBedMinutes: Double = 0
    var awakeMinutes: Double = 0
    var coreMinutes: Double = 0      // Light sleep
    var deepMinutes: Double = 0
    var remMinutes: Double = 0
    var unspecifiedMinutes: Double = 0
    
    /// Total asleep time (excluding in-bed and awake)
    var totalAsleepMinutes: Double {
        coreMinutes + deepMinutes + remMinutes + unspecifiedMinutes
    }
    
    /// Sleep efficiency = asleep / in-bed
    var efficiency: Double? {
        guard inBedMinutes > 0 else { return nil }
        return totalAsleepMinutes / inBedMinutes
    }
    
    /// Percentage of sleep that was deep
    var deepPercentage: Double? {
        guard totalAsleepMinutes > 0 else { return nil }
        return deepMinutes / totalAsleepMinutes * 100
    }
    
    /// Percentage of sleep that was REM
    var remPercentage: Double? {
        guard totalAsleepMinutes > 0 else { return nil }
        return remMinutes / totalAsleepMinutes * 100
    }
}
