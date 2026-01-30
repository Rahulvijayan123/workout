import Foundation
import HealthKit

/// A small, app-scoped vocabulary for the HealthKit signals we support (read-only).
enum HealthKitMetric: String, CaseIterable, Identifiable, Sendable {
    // MARK: - Recovery (Core)
    case sleepAnalysis
    case heartRateVariabilitySDNN
    case restingHeartRate
    case respiratoryRate
    case oxygenSaturation
    case vo2Max
    
    // MARK: - Activity (Core)
    case activeEnergyBurned
    case stepCount
    case appleExerciseTime
    case appleStandHour
    
    // MARK: - Walking Metrics
    case walkingHeartRateAverage
    case walkingAsymmetryPercentage
    case walkingSpeed
    case walkingStepLength
    case walkingDoubleSupportPercentage
    case stairAscentSpeed
    case stairDescentSpeed
    case sixMinuteWalkTestDistance
    
    // MARK: - Sleep Details (iOS 16+)
    case timeInDaylight
    case appleSleepingWristTemperature
    
    // MARK: - Body Composition
    case bodyMass
    case bodyFatPercentage
    case leanBodyMass
    
    // MARK: - Nutrition (if user tracks)
    case dietaryEnergyConsumed
    case dietaryProtein
    case dietaryCarbohydrates
    case dietaryFatTotal
    case dietaryWater
    case dietaryCaffeine
    
    // MARK: - Female Health (Opt-in)
    case menstrualFlow
    case basalBodyTemperature
    case cervicalMucusQuality
    
    // MARK: - Mindfulness
    case mindfulSession
    
    // MARK: - Other
    case workouts
    
    var id: String { rawValue }
    
    enum Category: String, Sendable {
        case recovery
        case activity
        case walking
        case sleep
        case body
        case nutrition
        case femaleHealth
        case mindfulness
        case optional
    }
    
    var category: Category {
        switch self {
        case .sleepAnalysis, .heartRateVariabilitySDNN, .restingHeartRate, .respiratoryRate, .oxygenSaturation, .vo2Max:
            return .recovery
        case .activeEnergyBurned, .stepCount, .appleExerciseTime, .appleStandHour:
            return .activity
        case .walkingHeartRateAverage, .walkingAsymmetryPercentage, .walkingSpeed, .walkingStepLength, 
             .walkingDoubleSupportPercentage, .stairAscentSpeed, .stairDescentSpeed, .sixMinuteWalkTestDistance:
            return .walking
        case .timeInDaylight, .appleSleepingWristTemperature:
            return .sleep
        case .bodyMass, .bodyFatPercentage, .leanBodyMass:
            return .body
        case .dietaryEnergyConsumed, .dietaryProtein, .dietaryCarbohydrates, .dietaryFatTotal, .dietaryWater, .dietaryCaffeine:
            return .nutrition
        case .menstrualFlow, .basalBodyTemperature, .cervicalMucusQuality:
            return .femaleHealth
        case .mindfulSession:
            return .mindfulness
        case .workouts:
            return .optional
        }
    }
    
    var displayName: String {
        switch self {
        // Recovery
        case .sleepAnalysis: return "Sleep"
        case .heartRateVariabilitySDNN: return "HRV (SDNN)"
        case .restingHeartRate: return "Resting HR"
        case .respiratoryRate: return "Respiratory Rate"
        case .oxygenSaturation: return "Blood Oxygen"
        case .vo2Max: return "VO2 Max"
        // Activity
        case .activeEnergyBurned: return "Active Energy"
        case .stepCount: return "Steps"
        case .appleExerciseTime: return "Exercise Time"
        case .appleStandHour: return "Stand Hours"
        // Walking
        case .walkingHeartRateAverage: return "Walking HR"
        case .walkingAsymmetryPercentage: return "Walking Asymmetry"
        case .walkingSpeed: return "Walking Speed"
        case .walkingStepLength: return "Step Length"
        case .walkingDoubleSupportPercentage: return "Double Support %"
        case .stairAscentSpeed: return "Stair Climb Speed"
        case .stairDescentSpeed: return "Stair Descent Speed"
        case .sixMinuteWalkTestDistance: return "6 Min Walk Distance"
        // Sleep
        case .timeInDaylight: return "Time in Daylight"
        case .appleSleepingWristTemperature: return "Wrist Temperature"
        // Body
        case .bodyMass: return "Body Mass"
        case .bodyFatPercentage: return "Body Fat %"
        case .leanBodyMass: return "Lean Body Mass"
        // Nutrition
        case .dietaryEnergyConsumed: return "Calories"
        case .dietaryProtein: return "Protein"
        case .dietaryCarbohydrates: return "Carbs"
        case .dietaryFatTotal: return "Fat"
        case .dietaryWater: return "Water"
        case .dietaryCaffeine: return "Caffeine"
        // Female Health
        case .menstrualFlow: return "Menstrual Flow"
        case .basalBodyTemperature: return "Basal Temperature"
        case .cervicalMucusQuality: return "Cervical Mucus"
        // Mindfulness
        case .mindfulSession: return "Mindful Minutes"
        // Other
        case .workouts: return "Workouts"
        }
    }
    
    var systemImage: String {
        switch self {
        // Recovery
        case .sleepAnalysis: return "bed.double.fill"
        case .heartRateVariabilitySDNN: return "waveform.path.ecg"
        case .restingHeartRate: return "heart.fill"
        case .respiratoryRate: return "lungs.fill"
        case .oxygenSaturation: return "drop.fill"
        case .vo2Max: return "bolt.heart.fill"
        // Activity
        case .activeEnergyBurned: return "flame.fill"
        case .stepCount: return "figure.walk"
        case .appleExerciseTime: return "figure.run"
        case .appleStandHour: return "figure.stand"
        // Walking
        case .walkingHeartRateAverage: return "heart.text.square.fill"
        case .walkingAsymmetryPercentage: return "figure.walk.motion"
        case .walkingSpeed: return "speedometer"
        case .walkingStepLength: return "ruler.fill"
        case .walkingDoubleSupportPercentage: return "figure.walk.diamond.fill"
        case .stairAscentSpeed: return "stairs"
        case .stairDescentSpeed: return "stairs"
        case .sixMinuteWalkTestDistance: return "figure.walk.circle.fill"
        // Sleep
        case .timeInDaylight: return "sun.max.fill"
        case .appleSleepingWristTemperature: return "thermometer.medium"
        // Body
        case .bodyMass: return "scalemass.fill"
        case .bodyFatPercentage: return "figure"
        case .leanBodyMass: return "figure.arms.open"
        // Nutrition
        case .dietaryEnergyConsumed: return "fork.knife"
        case .dietaryProtein: return "fish.fill"
        case .dietaryCarbohydrates: return "leaf.fill"
        case .dietaryFatTotal: return "drop.triangle.fill"
        case .dietaryWater: return "drop.fill"
        case .dietaryCaffeine: return "cup.and.saucer.fill"
        // Female Health
        case .menstrualFlow: return "drop.circle.fill"
        case .basalBodyTemperature: return "thermometer.low"
        case .cervicalMucusQuality: return "circle.dotted"
        // Mindfulness
        case .mindfulSession: return "brain.head.profile"
        // Other
        case .workouts: return "figure.strengthtraining.traditional"
        }
    }
    
    /// Whether this metric is enabled by default during onboarding
    var defaultEnabled: Bool {
        switch self {
        // Core metrics - enabled by default
        case .sleepAnalysis, .heartRateVariabilitySDNN, .restingHeartRate, .vo2Max,
             .activeEnergyBurned, .stepCount, .appleExerciseTime:
            return true
        // Everything else is opt-in
        default:
            return false
        }
    }
    
    /// Whether this metric requires explicit user opt-in (sensitive data)
    var requiresExplicitOptIn: Bool {
        switch self {
        case .menstrualFlow, .basalBodyTemperature, .cervicalMucusQuality:
            return true
        default:
            return false
        }
    }
    
    /// The HealthKit object type used to request *read* authorization for this metric.
    func objectType() -> HKObjectType? {
        switch self {
        // Category types
        case .sleepAnalysis:
            return HKObjectType.categoryType(forIdentifier: .sleepAnalysis)
        case .mindfulSession:
            return HKObjectType.categoryType(forIdentifier: .mindfulSession)
        case .menstrualFlow:
            return HKObjectType.categoryType(forIdentifier: .menstrualFlow)
        case .cervicalMucusQuality:
            return HKObjectType.categoryType(forIdentifier: .cervicalMucusQuality)
        case .appleStandHour:
            return HKObjectType.categoryType(forIdentifier: .appleStandHour)
            
        // Quantity types
        case .heartRateVariabilitySDNN:
            return HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN)
        case .restingHeartRate:
            return HKObjectType.quantityType(forIdentifier: .restingHeartRate)
        case .respiratoryRate:
            return HKObjectType.quantityType(forIdentifier: .respiratoryRate)
        case .oxygenSaturation:
            return HKObjectType.quantityType(forIdentifier: .oxygenSaturation)
        case .vo2Max:
            return HKObjectType.quantityType(forIdentifier: .vo2Max)
        case .activeEnergyBurned:
            return HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)
        case .stepCount:
            return HKObjectType.quantityType(forIdentifier: .stepCount)
        case .appleExerciseTime:
            return HKObjectType.quantityType(forIdentifier: .appleExerciseTime)
        case .walkingHeartRateAverage:
            return HKObjectType.quantityType(forIdentifier: .walkingHeartRateAverage)
        case .walkingAsymmetryPercentage:
            return HKObjectType.quantityType(forIdentifier: .walkingAsymmetryPercentage)
        case .walkingSpeed:
            return HKObjectType.quantityType(forIdentifier: .walkingSpeed)
        case .walkingStepLength:
            return HKObjectType.quantityType(forIdentifier: .walkingStepLength)
        case .walkingDoubleSupportPercentage:
            return HKObjectType.quantityType(forIdentifier: .walkingDoubleSupportPercentage)
        case .stairAscentSpeed:
            return HKObjectType.quantityType(forIdentifier: .stairAscentSpeed)
        case .stairDescentSpeed:
            return HKObjectType.quantityType(forIdentifier: .stairDescentSpeed)
        case .sixMinuteWalkTestDistance:
            return HKObjectType.quantityType(forIdentifier: .sixMinuteWalkTestDistance)
        case .timeInDaylight:
            if #available(iOS 17.0, *) {
                return HKObjectType.quantityType(forIdentifier: .timeInDaylight)
            } else {
                return nil
            }
        case .appleSleepingWristTemperature:
            if #available(iOS 16.0, *) {
                return HKObjectType.quantityType(forIdentifier: .appleSleepingWristTemperature)
            } else {
                return nil
            }
        case .bodyMass:
            return HKObjectType.quantityType(forIdentifier: .bodyMass)
        case .bodyFatPercentage:
            return HKObjectType.quantityType(forIdentifier: .bodyFatPercentage)
        case .leanBodyMass:
            return HKObjectType.quantityType(forIdentifier: .leanBodyMass)
        case .dietaryEnergyConsumed:
            return HKObjectType.quantityType(forIdentifier: .dietaryEnergyConsumed)
        case .dietaryProtein:
            return HKObjectType.quantityType(forIdentifier: .dietaryProtein)
        case .dietaryCarbohydrates:
            return HKObjectType.quantityType(forIdentifier: .dietaryCarbohydrates)
        case .dietaryFatTotal:
            return HKObjectType.quantityType(forIdentifier: .dietaryFatTotal)
        case .dietaryWater:
            return HKObjectType.quantityType(forIdentifier: .dietaryWater)
        case .dietaryCaffeine:
            return HKObjectType.quantityType(forIdentifier: .dietaryCaffeine)
        case .basalBodyTemperature:
            return HKObjectType.quantityType(forIdentifier: .basalBodyTemperature)
            
        // Workout type
        case .workouts:
            return HKObjectType.workoutType()
        }
    }
}

