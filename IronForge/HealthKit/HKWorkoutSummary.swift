import Foundation
import HealthKit

/// Lightweight representation of an `HKWorkout` for onboarding previews and simple lists.
struct HKWorkoutSummary: Identifiable, Hashable, Sendable {
    var id: UUID
    var startDate: Date
    var endDate: Date
    var durationMinutes: Double
    var activityType: HKWorkoutActivityType
    var totalEnergyBurnedKilocalories: Double?
    var totalDistanceMeters: Double?
    
    init(workout: HKWorkout) {
        self.id = workout.uuid
        self.startDate = workout.startDate
        self.endDate = workout.endDate
        self.durationMinutes = workout.duration / 60.0
        self.activityType = workout.workoutActivityType
        self.totalEnergyBurnedKilocalories = workout.totalEnergyBurned?.doubleValue(for: .kilocalorie())
        self.totalDistanceMeters = workout.totalDistance?.doubleValue(for: .meter())
    }
}

