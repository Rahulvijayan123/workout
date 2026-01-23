import Foundation

/// Additional context for progression calculations.
///
/// This allows policies to scale progression based on training age, bodyweight, movement pattern,
/// and recent training density (e.g., 135→225 progresses differently than 225→315).
public struct ProgressionContext: Sendable {
    public let userProfile: UserProfile
    public let exercise: Exercise
    public let date: Date
    public let calendar: Calendar
    
    public init(
        userProfile: UserProfile,
        exercise: Exercise,
        date: Date,
        calendar: Calendar = .current
    ) {
        self.userProfile = userProfile
        self.exercise = exercise
        self.date = date
        self.calendar = calendar
    }
}

