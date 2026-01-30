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
        
        print("[HealthKit] Starting comprehensive biometrics fetch for \(lastNDays) days...")
        
        // MARK: - Fetch all metrics in parallel
        async let sleepByDay = fetchSafe { try await self.healthKit.fetchDailySleepMinutes(lastNDays: lastNDays) }
        async let hrvByDay = fetchSafe { try await self.healthKit.fetchDailyAvgHRV(lastNDays: lastNDays) }
        async let restingHRByDay = fetchSafe { try await self.healthKit.fetchDailyAvgRestingHR(lastNDays: lastNDays) }
        async let vo2MaxByDay = fetchSafe { try await self.healthKit.fetchDailyVO2Max(lastNDays: lastNDays) }
        async let respiratoryRateByDay = fetchSafe { try await self.healthKit.fetchDailyAvgRespiratoryRate(lastNDays: lastNDays) }
        async let oxygenSatByDay = fetchSafe { try await self.healthKit.fetchDailyAvgOxygenSaturation(lastNDays: lastNDays) }
        
        async let activeEnergyByDay = fetchSafe { try await self.healthKit.fetchDailyActiveEnergy(lastNDays: lastNDays) }
        async let stepsByDay = fetchSafe { try await self.healthKit.fetchDailySteps(lastNDays: lastNDays) }
        async let exerciseTimeByDay = fetchSafe { try await self.healthKit.fetchDailyExerciseTime(lastNDays: lastNDays) }
        async let standHoursByDay = fetchSafeInt { try await self.healthKit.fetchDailyStandHours(lastNDays: lastNDays) }
        
        async let walkingHRByDay = fetchSafe { try await self.healthKit.fetchDailyWalkingHeartRateAverage(lastNDays: lastNDays) }
        async let walkingAsymmetryByDay = fetchSafe { try await self.healthKit.fetchDailyWalkingAsymmetry(lastNDays: lastNDays) }
        async let walkingSpeedByDay = fetchSafe { try await self.healthKit.fetchDailyWalkingSpeed(lastNDays: lastNDays) }
        async let walkingStepLengthByDay = fetchSafe { try await self.healthKit.fetchDailyWalkingStepLength(lastNDays: lastNDays) }
        async let walkingDoubleSupportByDay = fetchSafe { try await self.healthKit.fetchDailyWalkingDoubleSupport(lastNDays: lastNDays) }
        async let stairAscentByDay = fetchSafe { try await self.healthKit.fetchDailyStairAscentSpeed(lastNDays: lastNDays) }
        async let stairDescentByDay = fetchSafe { try await self.healthKit.fetchDailyStairDescentSpeed(lastNDays: lastNDays) }
        async let sixMinWalkByDay = fetchSafe { try await self.healthKit.fetchDailySixMinuteWalkDistance(lastNDays: lastNDays) }
        
        async let leanBodyMassByDay = fetchSafe { try await self.healthKit.fetchDailyLeanBodyMass(lastNDays: lastNDays) }
        
        async let dietaryEnergyByDay = fetchSafe { try await self.healthKit.fetchDailyDietaryEnergy(lastNDays: lastNDays) }
        async let dietaryProteinByDay = fetchSafe { try await self.healthKit.fetchDailyDietaryProtein(lastNDays: lastNDays) }
        async let dietaryCarbsByDay = fetchSafe { try await self.healthKit.fetchDailyDietaryCarbs(lastNDays: lastNDays) }
        async let dietaryFatByDay = fetchSafe { try await self.healthKit.fetchDailyDietaryFat(lastNDays: lastNDays) }
        async let waterIntakeByDay = fetchSafe { try await self.healthKit.fetchDailyWaterIntake(lastNDays: lastNDays) }
        async let caffeineByDay = fetchSafe { try await self.healthKit.fetchDailyCaffeine(lastNDays: lastNDays) }
        
        async let menstrualFlowByDay = fetchSafeInt { try await self.healthKit.fetchDailyMenstrualFlow(lastNDays: lastNDays) }
        async let cervicalMucusByDay = fetchSafeInt { try await self.healthKit.fetchDailyCervicalMucusQuality(lastNDays: lastNDays) }
        async let basalTempByDay = fetchSafe { try await self.healthKit.fetchDailyBasalBodyTemperature(lastNDays: lastNDays) }
        
        async let mindfulMinutesByDay = fetchSafe { try await self.healthKit.fetchDailyMindfulMinutes(lastNDays: lastNDays) }
        
        // Await all results
        let sleep = await sleepByDay
        let hrv = await hrvByDay
        let restingHR = await restingHRByDay
        let vo2Max = await vo2MaxByDay
        let respiratoryRate = await respiratoryRateByDay
        let oxygenSat = await oxygenSatByDay
        let activeEnergy = await activeEnergyByDay
        let steps = await stepsByDay
        let exerciseTime = await exerciseTimeByDay
        let standHours = await standHoursByDay
        let walkingHR = await walkingHRByDay
        let walkingAsymmetry = await walkingAsymmetryByDay
        let walkingSpeed = await walkingSpeedByDay
        let walkingStepLength = await walkingStepLengthByDay
        let walkingDoubleSupport = await walkingDoubleSupportByDay
        let stairAscent = await stairAscentByDay
        let stairDescent = await stairDescentByDay
        let sixMinWalk = await sixMinWalkByDay
        let leanBodyMass = await leanBodyMassByDay
        let dietaryEnergy = await dietaryEnergyByDay
        let dietaryProtein = await dietaryProteinByDay
        let dietaryCarbs = await dietaryCarbsByDay
        let dietaryFat = await dietaryFatByDay
        let waterIntake = await waterIntakeByDay
        let caffeine = await caffeineByDay
        let menstrualFlow = await menstrualFlowByDay
        let cervicalMucus = await cervicalMucusByDay
        let basalTemp = await basalTempByDay
        let mindfulMinutes = await mindfulMinutesByDay
        
        // Fetch sleep stages and time in daylight (iOS version dependent)
        var sleepStagesByDay: [Date: SleepStagesBreakdown] = [:]
        var timeInDaylightByDay: [Date: Double] = [:]
        var wristTempByDay: [Date: Double] = [:]
        
        if #available(iOS 16.0, *) {
            sleepStagesByDay = (try? await healthKit.fetchDailySleepStages(lastNDays: lastNDays)) ?? [:]
            wristTempByDay = (try? await healthKit.fetchDailyWristTemperature(lastNDays: lastNDays)) ?? [:]
        }
        
        if #available(iOS 17.0, *) {
            timeInDaylightByDay = (try? await healthKit.fetchDailyTimeInDaylight(lastNDays: lastNDays)) ?? [:]
        }
        
        // Collect all days with any data
        var allDays = Set<Date>()
        allDays.formUnion(sleep.keys)
        allDays.formUnion(hrv.keys)
        allDays.formUnion(restingHR.keys)
        allDays.formUnion(vo2Max.keys)
        allDays.formUnion(respiratoryRate.keys)
        allDays.formUnion(oxygenSat.keys)
        allDays.formUnion(activeEnergy.keys)
        allDays.formUnion(steps.keys)
        allDays.formUnion(exerciseTime.keys)
        allDays.formUnion(standHours.keys)
        allDays.formUnion(walkingHR.keys)
        allDays.formUnion(walkingAsymmetry.keys)
        allDays.formUnion(walkingSpeed.keys)
        allDays.formUnion(walkingStepLength.keys)
        allDays.formUnion(walkingDoubleSupport.keys)
        allDays.formUnion(stairAscent.keys)
        allDays.formUnion(stairDescent.keys)
        allDays.formUnion(sixMinWalk.keys)
        allDays.formUnion(leanBodyMass.keys)
        allDays.formUnion(dietaryEnergy.keys)
        allDays.formUnion(dietaryProtein.keys)
        allDays.formUnion(dietaryCarbs.keys)
        allDays.formUnion(dietaryFat.keys)
        allDays.formUnion(waterIntake.keys)
        allDays.formUnion(caffeine.keys)
        allDays.formUnion(menstrualFlow.keys)
        allDays.formUnion(cervicalMucus.keys)
        allDays.formUnion(basalTemp.keys)
        allDays.formUnion(mindfulMinutes.keys)
        allDays.formUnion(sleepStagesByDay.keys)
        allDays.formUnion(timeInDaylightByDay.keys)
        allDays.formUnion(wristTempByDay.keys)
        
        print("[HealthKit] Found data for \(allDays.count) days")
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
            
            // Core Recovery
            if let v = sleep[dayStart] { record.sleepMinutes = v }
            if let v = hrv[dayStart] { record.hrvSDNN = v }
            if let v = restingHR[dayStart] { record.restingHR = v }
            if let v = vo2Max[dayStart] { record.vo2Max = v }
            if let v = respiratoryRate[dayStart] { record.respiratoryRate = v }
            if let v = oxygenSat[dayStart] { record.oxygenSaturation = v }
            
            // Activity
            if let v = activeEnergy[dayStart] { record.activeEnergy = v }
            if let v = steps[dayStart] { record.steps = v }
            if let v = exerciseTime[dayStart] { record.exerciseTimeMinutes = v }
            if let v = standHours[dayStart] { record.standHours = v }
            
            // Walking
            if let v = walkingHR[dayStart] { record.walkingHeartRateAvg = v }
            if let v = walkingAsymmetry[dayStart] { record.walkingAsymmetry = v }
            if let v = walkingSpeed[dayStart] { record.walkingSpeed = v }
            if let v = walkingStepLength[dayStart] { record.walkingStepLength = v }
            if let v = walkingDoubleSupport[dayStart] { record.walkingDoubleSupport = v }
            if let v = stairAscent[dayStart] { record.stairAscentSpeed = v }
            if let v = stairDescent[dayStart] { record.stairDescentSpeed = v }
            if let v = sixMinWalk[dayStart] { record.sixMinuteWalkDistance = v }
            
            // Sleep Stages
            if let stages = sleepStagesByDay[dayStart] {
                record.timeInBedMinutes = stages.inBedMinutes
                record.sleepAwakeMinutes = stages.awakeMinutes
                record.sleepCoreMinutes = stages.coreMinutes
                record.sleepDeepMinutes = stages.deepMinutes
                record.sleepRemMinutes = stages.remMinutes
            }
            if let v = timeInDaylightByDay[dayStart] { record.timeInDaylightMinutes = v }
            if let v = wristTempByDay[dayStart] { record.wristTemperatureCelsius = v }
            
            // Body
            if let v = leanBodyMass[dayStart] { record.leanBodyMassKg = v }
            
            // Nutrition
            if let v = dietaryEnergy[dayStart] { record.dietaryEnergyKcal = v }
            if let v = dietaryProtein[dayStart] { record.dietaryProteinGrams = v }
            if let v = dietaryCarbs[dayStart] { record.dietaryCarbsGrams = v }
            if let v = dietaryFat[dayStart] { record.dietaryFatGrams = v }
            if let v = waterIntake[dayStart] { record.waterIntakeLiters = v }
            if let v = caffeine[dayStart] { record.caffeineMg = v }
            
            // Female Health
            if let v = menstrualFlow[dayStart] { record.menstrualFlowRaw = v }
            if let v = cervicalMucus[dayStart] { record.cervicalMucusQualityRaw = v }
            if let v = basalTemp[dayStart] { record.basalBodyTemperatureCelsius = v }
            
            // Mindfulness
            if let v = mindfulMinutes[dayStart] { record.mindfulMinutes = v }
            
            record.fromHealthKit = true
            record.updatedAt = now
        }
        
        do {
            try modelContext.save()
            print("[HealthKit] Saved biometrics for \(allDays.count) days")
        } catch {
            print("[HealthKit] Failed to save biometrics: \(error)")
        }
    }
    
    // MARK: - Helper Functions
    
    /// Safely fetch a Double dictionary, returning empty on error
    private func fetchSafe(_ fetch: @escaping () async throws -> [Date: Double]) async -> [Date: Double] {
        do {
            return try await fetch()
        } catch {
            return [:]
        }
    }
    
    /// Safely fetch an Int dictionary, returning empty on error
    private func fetchSafeInt(_ fetch: @escaping () async throws -> [Date: Int]) async -> [Date: Int] {
        do {
            return try await fetch()
        } catch {
            return [:]
        }
    }
}

