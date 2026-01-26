import Foundation

/// Additional context for progression calculations.
///
/// This allows policies to scale progression based on training age, bodyweight, movement pattern,
/// session intent (DUP), and recent training density (e.g., 135→225 progresses differently than 225→315).
public struct ProgressionContext: Sendable {
    public let userProfile: UserProfile
    public let exercise: Exercise
    public let date: Date
    public let calendar: Calendar
    
    /// Session intent for DUP-aware progression (heavy/volume/light/general).
    public let sessionIntent: SessionIntent
    
    /// Template ID this context is associated with (if any).
    public let templateId: WorkoutTemplateId?
    
    public init(
        userProfile: UserProfile,
        exercise: Exercise,
        date: Date,
        calendar: Calendar = .current,
        sessionIntent: SessionIntent = .general,
        templateId: WorkoutTemplateId? = nil
    ) {
        self.userProfile = userProfile
        self.exercise = exercise
        self.date = date
        self.calendar = calendar
        self.sessionIntent = sessionIntent
        self.templateId = templateId
    }
    
    /// Whether this context prefers smaller, more conservative increments.
    public var prefersSmallIncrements: Bool {
        sessionIntent.prefersSmallIncrements
    }
    
    /// Whether this context should be more sensitive to grinder sessions.
    public var sensitiveToGrinders: Bool {
        sessionIntent.sensitiveToGrinders
    }
    
    /// Whether this context prefers reps-first progression.
    public var prefersRepsFirst: Bool {
        sessionIntent.prefersRepsFirst
    }
}

