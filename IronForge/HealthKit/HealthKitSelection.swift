import Foundation
import HealthKit

/// User-facing toggles for requesting read-only HealthKit access during onboarding.
struct HealthKitSelection: Hashable, Sendable {
    // MARK: - Recovery (Core - enabled by default)
    var sleepAnalysis: Bool = true
    var heartRateVariabilitySDNN: Bool = true
    var restingHeartRate: Bool = true
    var vo2Max: Bool = true
    var respiratoryRate: Bool = false
    var oxygenSaturation: Bool = false
    
    // MARK: - Activity (Core - enabled by default)
    var activeEnergyBurned: Bool = true
    var stepCount: Bool = true
    var appleExerciseTime: Bool = true
    var appleStandHour: Bool = false
    
    // MARK: - Walking Metrics (off by default)
    var walkingHeartRateAverage: Bool = false
    var walkingAsymmetryPercentage: Bool = false
    var walkingSpeed: Bool = false
    var walkingStepLength: Bool = false
    var walkingDoubleSupportPercentage: Bool = false
    var stairAscentSpeed: Bool = false
    var stairDescentSpeed: Bool = false
    var sixMinuteWalkTestDistance: Bool = false
    
    // MARK: - Sleep Details (off by default)
    var timeInDaylight: Bool = false
    var appleSleepingWristTemperature: Bool = false
    
    // MARK: - Body Composition (off by default)
    var bodyMass: Bool = false
    var bodyFatPercentage: Bool = false
    var leanBodyMass: Bool = false
    
    // MARK: - Nutrition (off by default)
    var dietaryEnergyConsumed: Bool = false
    var dietaryProtein: Bool = false
    var dietaryCarbohydrates: Bool = false
    var dietaryFatTotal: Bool = false
    var dietaryWater: Bool = false
    var dietaryCaffeine: Bool = false
    
    // MARK: - Female Health (opt-in, off by default)
    var menstrualFlow: Bool = false
    var basalBodyTemperature: Bool = false
    var cervicalMucusQuality: Bool = false
    
    // MARK: - Mindfulness (off by default)
    var mindfulSession: Bool = false
    
    // MARK: - Other
    var workouts: Bool = false
    
    // MARK: - Computed Properties
    
    var selectedMetrics: [HealthKitMetric] {
        var metrics: [HealthKitMetric] = []
        
        // Recovery
        if sleepAnalysis { metrics.append(.sleepAnalysis) }
        if heartRateVariabilitySDNN { metrics.append(.heartRateVariabilitySDNN) }
        if restingHeartRate { metrics.append(.restingHeartRate) }
        if vo2Max { metrics.append(.vo2Max) }
        if respiratoryRate { metrics.append(.respiratoryRate) }
        if oxygenSaturation { metrics.append(.oxygenSaturation) }
        
        // Activity
        if activeEnergyBurned { metrics.append(.activeEnergyBurned) }
        if stepCount { metrics.append(.stepCount) }
        if appleExerciseTime { metrics.append(.appleExerciseTime) }
        if appleStandHour { metrics.append(.appleStandHour) }
        
        // Walking
        if walkingHeartRateAverage { metrics.append(.walkingHeartRateAverage) }
        if walkingAsymmetryPercentage { metrics.append(.walkingAsymmetryPercentage) }
        if walkingSpeed { metrics.append(.walkingSpeed) }
        if walkingStepLength { metrics.append(.walkingStepLength) }
        if walkingDoubleSupportPercentage { metrics.append(.walkingDoubleSupportPercentage) }
        if stairAscentSpeed { metrics.append(.stairAscentSpeed) }
        if stairDescentSpeed { metrics.append(.stairDescentSpeed) }
        if sixMinuteWalkTestDistance { metrics.append(.sixMinuteWalkTestDistance) }
        
        // Sleep Details
        if timeInDaylight { metrics.append(.timeInDaylight) }
        if appleSleepingWristTemperature { metrics.append(.appleSleepingWristTemperature) }
        
        // Body
        if bodyMass { metrics.append(.bodyMass) }
        if bodyFatPercentage { metrics.append(.bodyFatPercentage) }
        if leanBodyMass { metrics.append(.leanBodyMass) }
        
        // Nutrition
        if dietaryEnergyConsumed { metrics.append(.dietaryEnergyConsumed) }
        if dietaryProtein { metrics.append(.dietaryProtein) }
        if dietaryCarbohydrates { metrics.append(.dietaryCarbohydrates) }
        if dietaryFatTotal { metrics.append(.dietaryFatTotal) }
        if dietaryWater { metrics.append(.dietaryWater) }
        if dietaryCaffeine { metrics.append(.dietaryCaffeine) }
        
        // Female Health
        if menstrualFlow { metrics.append(.menstrualFlow) }
        if basalBodyTemperature { metrics.append(.basalBodyTemperature) }
        if cervicalMucusQuality { metrics.append(.cervicalMucusQuality) }
        
        // Mindfulness
        if mindfulSession { metrics.append(.mindfulSession) }
        
        // Other
        if workouts { metrics.append(.workouts) }
        
        return metrics
    }
    
    var selectedReadTypes: Set<HKObjectType> {
        Set(selectedMetrics.compactMap { $0.objectType() })
    }
    
    var hasAnySelected: Bool {
        !selectedMetrics.isEmpty
    }
    
    /// Returns a selection with all available metrics enabled (for requesting comprehensive permissions)
    static var allEnabled: HealthKitSelection {
        var selection = HealthKitSelection()
        // Recovery
        selection.sleepAnalysis = true
        selection.heartRateVariabilitySDNN = true
        selection.restingHeartRate = true
        selection.vo2Max = true
        selection.respiratoryRate = true
        selection.oxygenSaturation = true
        // Activity
        selection.activeEnergyBurned = true
        selection.stepCount = true
        selection.appleExerciseTime = true
        selection.appleStandHour = true
        // Walking
        selection.walkingHeartRateAverage = true
        selection.walkingAsymmetryPercentage = true
        selection.walkingSpeed = true
        selection.walkingStepLength = true
        selection.walkingDoubleSupportPercentage = true
        selection.stairAscentSpeed = true
        selection.stairDescentSpeed = true
        selection.sixMinuteWalkTestDistance = true
        // Sleep
        selection.timeInDaylight = true
        selection.appleSleepingWristTemperature = true
        // Body
        selection.bodyMass = true
        selection.bodyFatPercentage = true
        selection.leanBodyMass = true
        // Nutrition
        selection.dietaryEnergyConsumed = true
        selection.dietaryProtein = true
        selection.dietaryCarbohydrates = true
        selection.dietaryFatTotal = true
        selection.dietaryWater = true
        selection.dietaryCaffeine = true
        // Note: Female health metrics NOT auto-enabled - requires explicit opt-in
        // Mindfulness
        selection.mindfulSession = true
        // Other
        selection.workouts = true
        return selection
    }
}

