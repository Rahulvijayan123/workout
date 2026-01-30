import Foundation
import SwiftData

/// Local cache of daily biometrics (start-of-day keyed) derived from HealthKit aggregates.
@Model
final class DailyBiometrics {
    /// Start of local day.
    @Attribute(.unique) var date: Date
    
    // MARK: - Core Recovery Metrics (HealthKit)
    
    /// Total sleep time in minutes
    var sleepMinutes: Double?
    /// HRV SDNN in milliseconds
    var hrvSDNN: Double?
    /// Resting heart rate in bpm
    var restingHR: Double?
    /// VO2 Max in mL/(kg·min) - best single predictor of recovery capacity
    var vo2Max: Double?
    /// Respiratory rate in breaths per minute (sleep)
    var respiratoryRate: Double?
    /// Blood oxygen saturation percentage (0-100)
    var oxygenSaturation: Double?
    
    // MARK: - Activity Metrics (HealthKit)
    
    /// Active energy in kilocalories
    var activeEnergy: Double?
    /// Steps (count)
    var steps: Double?
    /// Exercise time in minutes
    var exerciseTimeMinutes: Double?
    /// Stand hours (count of hours with standing activity)
    var standHours: Int?
    
    // MARK: - Walking Metrics (HealthKit - Injury Detection)
    
    /// Walking heart rate average in bpm
    var walkingHeartRateAvg: Double?
    /// Walking asymmetry percentage (0-100) - early injury indicator
    var walkingAsymmetry: Double?
    /// Walking speed in m/s
    var walkingSpeed: Double?
    /// Walking step length in meters
    var walkingStepLength: Double?
    /// Double support percentage (0-100)
    var walkingDoubleSupport: Double?
    /// Stair ascent speed in m/s - leg power indicator
    var stairAscentSpeed: Double?
    /// Stair descent speed in m/s
    var stairDescentSpeed: Double?
    /// Six minute walk test distance in meters
    var sixMinuteWalkDistance: Double?
    
    // MARK: - Sleep Details (HealthKit - iOS 16+)
    
    /// Time in bed (minutes)
    var timeInBedMinutes: Double?
    /// Time awake during sleep (minutes)
    var sleepAwakeMinutes: Double?
    /// Core (light) sleep minutes
    var sleepCoreMinutes: Double?
    /// Deep sleep minutes - correlates with anabolic hormone release
    var sleepDeepMinutes: Double?
    /// REM sleep minutes
    var sleepRemMinutes: Double?
    /// Time in daylight in minutes (iOS 17+) - affects circadian rhythm
    var timeInDaylightMinutes: Double?
    /// Wrist temperature deviation in Celsius (iOS 16+, Watch S8+)
    var wristTemperatureCelsius: Double?
    
    /// Sleep efficiency (sleep time / time in bed, 0-1)
    var sleepEfficiency: Double? {
        guard let sleep = sleepMinutes, let inBed = timeInBedMinutes, inBed > 0 else { return nil }
        return sleep / inBed
    }
    
    /// Deep sleep percentage
    var deepSleepPercentage: Double? {
        guard let deep = sleepDeepMinutes, let total = sleepMinutes, total > 0 else { return nil }
        return deep / total * 100
    }
    
    /// REM sleep percentage
    var remSleepPercentage: Double? {
        guard let rem = sleepRemMinutes, let total = sleepMinutes, total > 0 else { return nil }
        return rem / total * 100
    }
    
    // MARK: - Body Composition (HealthKit + Manual)
    
    /// Body weight in kg
    var bodyWeightKg: Double?
    /// Body fat percentage
    var bodyFatPercentage: Double?
    /// Lean body mass in kg
    var leanBodyMassKg: Double?
    /// Whether body weight was from HealthKit
    var bodyWeightFromHealthKit: Bool = false
    
    // MARK: - Nutrition (HealthKit if user logs)
    
    /// Dietary energy consumed in kcal (from HealthKit)
    var dietaryEnergyKcal: Double?
    /// Dietary protein in grams (from HealthKit)
    var dietaryProteinGrams: Double?
    /// Dietary carbohydrates in grams (from HealthKit)
    var dietaryCarbsGrams: Double?
    /// Dietary fat in grams (from HealthKit)
    var dietaryFatGrams: Double?
    /// Water intake in liters (from HealthKit)
    var waterIntakeLiters: Double?
    /// Caffeine intake in mg (from HealthKit)
    var caffeineMg: Double?
    
    // MARK: - Nutrition Buckets (Coarse - Low Friction)
    
    /// Caloric intake bucket (deficit/maintenance/surplus)
    var nutritionBucketRaw: String?
    var nutritionBucket: NutritionBucket? {
        get { nutritionBucketRaw.flatMap { NutritionBucket(rawValue: $0) } }
        set { nutritionBucketRaw = newValue?.rawValue }
    }
    
    /// Protein intake bucket (low/adequate/high)
    var proteinBucketRaw: String?
    var proteinBucket: ProteinBucket? {
        get { proteinBucketRaw.flatMap { ProteinBucket(rawValue: $0) } }
        set { proteinBucketRaw = newValue?.rawValue }
    }
    
    /// Estimated protein in grams (manual entry)
    var proteinGrams: Int?
    
    /// Estimated total calories (manual entry)
    var totalCalories: Int?
    
    /// Hydration level (1-5 scale, subjective)
    var hydrationLevel: Int?
    
    /// Alcohol consumption (0 = none, 1 = light, 2 = moderate, 3 = heavy)
    var alcoholLevel: Int?
    
    // MARK: - Female Health (HealthKit - Opt-in)
    
    /// Menstrual flow (raw HK value)
    var menstrualFlowRaw: Int?
    /// Cervical mucus quality (raw HK value)
    var cervicalMucusQualityRaw: Int?
    /// Basal body temperature in Celsius
    var basalBodyTemperatureCelsius: Double?
    
    /// Menstrual cycle phase (opt-in)
    var cyclePhaseRaw: String?
    var cyclePhase: CyclePhase? {
        get { cyclePhaseRaw.flatMap { CyclePhase(rawValue: $0) } }
        set { cyclePhaseRaw = newValue?.rawValue }
    }
    
    /// Day of cycle (1-based, if tracking)
    var cycleDayNumber: Int?
    
    /// Whether user is on hormonal birth control (affects interpretation)
    var onHormonalBirthControl: Bool?
    
    // MARK: - Mindfulness (HealthKit)
    
    /// Mindful session minutes
    var mindfulMinutes: Double?
    
    // MARK: - Subjective Daily Metrics (Manual Entry)
    
    /// Sleep quality score (1-5 scale, subjective)
    var sleepQuality: Int?
    
    /// Number of sleep disruptions
    var sleepDisruptions: Int?
    
    /// Overall energy level (1-5)
    var energyLevel: Int?
    
    /// Stress level (1-5)
    var stressLevel: Int?
    
    /// Mood score (1-5)
    var moodScore: Int?
    
    /// Overall soreness level (0-10)
    var overallSoreness: Int?
    
    /// Computed readiness score (0-100, derived from other metrics)
    var readinessScore: Int?
    
    // MARK: - Life Stress Flags
    
    /// Illness flag
    var hasIllness: Bool = false
    
    /// Travel flag
    var hasTravel: Bool = false
    
    /// Work stress flag
    var hasWorkStress: Bool = false
    
    /// Poor sleep flag (for quick entry without details)
    var hadPoorSleep: Bool = false
    
    /// Other stress flag
    var hasOtherStress: Bool = false
    
    /// Stress notes
    var stressNotes: String?
    
    /// Convenience: has any stress flag
    var hasAnyStressFlag: Bool {
        hasIllness || hasTravel || hasWorkStress || hadPoorSleep || hasOtherStress
    }
    
    // MARK: - Data Source Flags
    
    /// Whether data came from HealthKit
    var fromHealthKit: Bool = false
    
    /// Whether data came from manual entry
    var fromManualEntry: Bool = false
    
    var updatedAt: Date
    
    // MARK: - Initialization
    
    init(
        date: Date,
        // Core Recovery
        sleepMinutes: Double? = nil,
        hrvSDNN: Double? = nil,
        restingHR: Double? = nil,
        vo2Max: Double? = nil,
        respiratoryRate: Double? = nil,
        oxygenSaturation: Double? = nil,
        // Activity
        activeEnergy: Double? = nil,
        steps: Double? = nil,
        exerciseTimeMinutes: Double? = nil,
        standHours: Int? = nil,
        // Walking
        walkingHeartRateAvg: Double? = nil,
        walkingAsymmetry: Double? = nil,
        walkingSpeed: Double? = nil,
        walkingStepLength: Double? = nil,
        walkingDoubleSupport: Double? = nil,
        stairAscentSpeed: Double? = nil,
        stairDescentSpeed: Double? = nil,
        sixMinuteWalkDistance: Double? = nil,
        // Sleep Details
        timeInBedMinutes: Double? = nil,
        sleepAwakeMinutes: Double? = nil,
        sleepCoreMinutes: Double? = nil,
        sleepDeepMinutes: Double? = nil,
        sleepRemMinutes: Double? = nil,
        timeInDaylightMinutes: Double? = nil,
        wristTemperatureCelsius: Double? = nil,
        // Body
        bodyWeightKg: Double? = nil,
        bodyFatPercentage: Double? = nil,
        leanBodyMassKg: Double? = nil,
        bodyWeightFromHealthKit: Bool = false,
        // Nutrition (HealthKit)
        dietaryEnergyKcal: Double? = nil,
        dietaryProteinGrams: Double? = nil,
        dietaryCarbsGrams: Double? = nil,
        dietaryFatGrams: Double? = nil,
        waterIntakeLiters: Double? = nil,
        caffeineMg: Double? = nil,
        // Nutrition Buckets
        nutritionBucket: NutritionBucket? = nil,
        proteinBucket: ProteinBucket? = nil,
        proteinGrams: Int? = nil,
        totalCalories: Int? = nil,
        hydrationLevel: Int? = nil,
        alcoholLevel: Int? = nil,
        // Female Health
        menstrualFlowRaw: Int? = nil,
        cervicalMucusQualityRaw: Int? = nil,
        basalBodyTemperatureCelsius: Double? = nil,
        cyclePhase: CyclePhase? = nil,
        cycleDayNumber: Int? = nil,
        onHormonalBirthControl: Bool? = nil,
        // Mindfulness
        mindfulMinutes: Double? = nil,
        // Subjective
        sleepQuality: Int? = nil,
        sleepDisruptions: Int? = nil,
        energyLevel: Int? = nil,
        stressLevel: Int? = nil,
        moodScore: Int? = nil,
        overallSoreness: Int? = nil,
        readinessScore: Int? = nil,
        // Stress Flags
        hasIllness: Bool = false,
        hasTravel: Bool = false,
        hasWorkStress: Bool = false,
        hadPoorSleep: Bool = false,
        hasOtherStress: Bool = false,
        stressNotes: String? = nil,
        // Data Source
        fromHealthKit: Bool = false,
        fromManualEntry: Bool = false,
        updatedAt: Date = .now
    ) {
        self.date = date
        // Core Recovery
        self.sleepMinutes = sleepMinutes
        self.hrvSDNN = hrvSDNN
        self.restingHR = restingHR
        self.vo2Max = vo2Max
        self.respiratoryRate = respiratoryRate
        self.oxygenSaturation = oxygenSaturation
        // Activity
        self.activeEnergy = activeEnergy
        self.steps = steps
        self.exerciseTimeMinutes = exerciseTimeMinutes
        self.standHours = standHours
        // Walking
        self.walkingHeartRateAvg = walkingHeartRateAvg
        self.walkingAsymmetry = walkingAsymmetry
        self.walkingSpeed = walkingSpeed
        self.walkingStepLength = walkingStepLength
        self.walkingDoubleSupport = walkingDoubleSupport
        self.stairAscentSpeed = stairAscentSpeed
        self.stairDescentSpeed = stairDescentSpeed
        self.sixMinuteWalkDistance = sixMinuteWalkDistance
        // Sleep Details
        self.timeInBedMinutes = timeInBedMinutes
        self.sleepAwakeMinutes = sleepAwakeMinutes
        self.sleepCoreMinutes = sleepCoreMinutes
        self.sleepDeepMinutes = sleepDeepMinutes
        self.sleepRemMinutes = sleepRemMinutes
        self.timeInDaylightMinutes = timeInDaylightMinutes
        self.wristTemperatureCelsius = wristTemperatureCelsius
        // Body
        self.bodyWeightKg = bodyWeightKg
        self.bodyFatPercentage = bodyFatPercentage
        self.leanBodyMassKg = leanBodyMassKg
        self.bodyWeightFromHealthKit = bodyWeightFromHealthKit
        // Nutrition (HealthKit)
        self.dietaryEnergyKcal = dietaryEnergyKcal
        self.dietaryProteinGrams = dietaryProteinGrams
        self.dietaryCarbsGrams = dietaryCarbsGrams
        self.dietaryFatGrams = dietaryFatGrams
        self.waterIntakeLiters = waterIntakeLiters
        self.caffeineMg = caffeineMg
        // Nutrition Buckets
        self.nutritionBucketRaw = nutritionBucket?.rawValue
        self.proteinBucketRaw = proteinBucket?.rawValue
        self.proteinGrams = proteinGrams
        self.totalCalories = totalCalories
        self.hydrationLevel = hydrationLevel
        self.alcoholLevel = alcoholLevel
        // Female Health
        self.menstrualFlowRaw = menstrualFlowRaw
        self.cervicalMucusQualityRaw = cervicalMucusQualityRaw
        self.basalBodyTemperatureCelsius = basalBodyTemperatureCelsius
        self.cyclePhaseRaw = cyclePhase?.rawValue
        self.cycleDayNumber = cycleDayNumber
        self.onHormonalBirthControl = onHormonalBirthControl
        // Mindfulness
        self.mindfulMinutes = mindfulMinutes
        // Subjective
        self.sleepQuality = sleepQuality
        self.sleepDisruptions = sleepDisruptions
        self.energyLevel = energyLevel
        self.stressLevel = stressLevel
        self.moodScore = moodScore
        self.overallSoreness = overallSoreness
        self.readinessScore = readinessScore
        // Stress Flags
        self.hasIllness = hasIllness
        self.hasTravel = hasTravel
        self.hasWorkStress = hasWorkStress
        self.hadPoorSleep = hadPoorSleep
        self.hasOtherStress = hasOtherStress
        self.stressNotes = stressNotes
        // Data Source
        self.fromHealthKit = fromHealthKit
        self.fromManualEntry = fromManualEntry
        self.updatedAt = updatedAt
    }
}

