import Foundation
import HealthKit

/// User-facing toggles for requesting read-only HealthKit access during onboarding.
struct HealthKitSelection: Hashable, Sendable {
    // Recovery
    var sleepAnalysis: Bool = true
    var heartRateVariabilitySDNN: Bool = true
    var restingHeartRate: Bool = true
    
    // Activity
    var activeEnergyBurned: Bool = true
    var stepCount: Bool = true
    
    // Optional
    var workouts: Bool = false
    
    // Body (optional; off by default)
    var bodyMass: Bool = false
    var bodyFatPercentage: Bool = false
    
    var selectedMetrics: [HealthKitMetric] {
        var metrics: [HealthKitMetric] = []
        if sleepAnalysis { metrics.append(.sleepAnalysis) }
        if heartRateVariabilitySDNN { metrics.append(.heartRateVariabilitySDNN) }
        if restingHeartRate { metrics.append(.restingHeartRate) }
        if activeEnergyBurned { metrics.append(.activeEnergyBurned) }
        if stepCount { metrics.append(.stepCount) }
        if workouts { metrics.append(.workouts) }
        if bodyMass { metrics.append(.bodyMass) }
        if bodyFatPercentage { metrics.append(.bodyFatPercentage) }
        return metrics
    }
    
    var selectedReadTypes: Set<HKObjectType> {
        Set(selectedMetrics.compactMap { $0.objectType() })
    }
    
    var hasAnySelected: Bool {
        !selectedMetrics.isEmpty
    }
}

