import Foundation
import SwiftData

/// Local cache of daily biometrics (start-of-day keyed) derived from HealthKit aggregates.
@Model
final class DailyBiometrics {
    /// Start of local day.
    @Attribute(.unique) var date: Date
    
    var sleepMinutes: Double?
    /// HRV SDNN in milliseconds.
    var hrvSDNN: Double?
    /// Resting heart rate in bpm.
    var restingHR: Double?
    /// Active energy in kilocalories.
    var activeEnergy: Double?
    /// Steps (count).
    var steps: Double?
    
    var updatedAt: Date
    
    init(
        date: Date,
        sleepMinutes: Double? = nil,
        hrvSDNN: Double? = nil,
        restingHR: Double? = nil,
        activeEnergy: Double? = nil,
        steps: Double? = nil,
        updatedAt: Date = .now
    ) {
        self.date = date
        self.sleepMinutes = sleepMinutes
        self.hrvSDNN = hrvSDNN
        self.restingHR = restingHR
        self.activeEnergy = activeEnergy
        self.steps = steps
        self.updatedAt = updatedAt
    }
}

