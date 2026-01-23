import Foundation
import HealthKit

/// A small, app-scoped vocabulary for the HealthKit signals we support in v1 (read-only).
enum HealthKitMetric: String, CaseIterable, Identifiable, Sendable {
    case sleepAnalysis
    case heartRateVariabilitySDNN
    case restingHeartRate
    case activeEnergyBurned
    case stepCount
    
    // Optional toggles
    case workouts
    case bodyMass
    case bodyFatPercentage
    
    var id: String { rawValue }
    
    enum Category: String, Sendable {
        case recovery
        case activity
        case optional
        case body
    }
    
    var category: Category {
        switch self {
        case .sleepAnalysis, .heartRateVariabilitySDNN, .restingHeartRate:
            return .recovery
        case .activeEnergyBurned, .stepCount:
            return .activity
        case .workouts:
            return .optional
        case .bodyMass, .bodyFatPercentage:
            return .body
        }
    }
    
    var displayName: String {
        switch self {
        case .sleepAnalysis: return "Sleep"
        case .heartRateVariabilitySDNN: return "HRV (SDNN)"
        case .restingHeartRate: return "Resting HR"
        case .activeEnergyBurned: return "Active Energy"
        case .stepCount: return "Steps"
        case .workouts: return "Workouts"
        case .bodyMass: return "Body Mass"
        case .bodyFatPercentage: return "Body Fat %"
        }
    }
    
    var systemImage: String {
        switch self {
        case .sleepAnalysis: return "bed.double.fill"
        case .heartRateVariabilitySDNN: return "waveform.path.ecg"
        case .restingHeartRate: return "heart.fill"
        case .activeEnergyBurned: return "flame.fill"
        case .stepCount: return "figure.walk"
        case .workouts: return "figure.strengthtraining.traditional"
        case .bodyMass: return "scalemass.fill"
        case .bodyFatPercentage: return "figure"
        }
    }
    
    /// The HealthKit object type used to request *read* authorization for this metric.
    func objectType() -> HKObjectType? {
        switch self {
        case .sleepAnalysis:
            return HKObjectType.categoryType(forIdentifier: .sleepAnalysis)
        case .heartRateVariabilitySDNN:
            return HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN)
        case .restingHeartRate:
            return HKObjectType.quantityType(forIdentifier: .restingHeartRate)
        case .activeEnergyBurned:
            return HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)
        case .stepCount:
            return HKObjectType.quantityType(forIdentifier: .stepCount)
        case .workouts:
            return HKObjectType.workoutType()
        case .bodyMass:
            return HKObjectType.quantityType(forIdentifier: .bodyMass)
        case .bodyFatPercentage:
            return HKObjectType.quantityType(forIdentifier: .bodyFatPercentage)
        }
    }
}

