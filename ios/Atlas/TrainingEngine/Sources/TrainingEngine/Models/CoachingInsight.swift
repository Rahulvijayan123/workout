import Foundation

/// High-level coaching signals surfaced alongside a `SessionPlan`.
///
/// These are intentionally "suggestions" (not prescriptions) so the app can present them as guidance
/// without silently rewriting a user's program.
public struct CoachingInsight: Codable, Sendable, Hashable, Identifiable {
    public enum Topic: String, Codable, Sendable, Hashable {
        case progression = "progression"
        case plateau = "plateau"
        case recovery = "recovery"
        case nutrition = "nutrition"
        case effort = "effort"
        case technique = "technique"
        case variation = "variation"
    }
    
    /// Deterministic identifier (so `SessionPlan` remains deterministic and comparable in tests).
    public let id: String
    public let topic: Topic
    public let title: String
    public let detail: String
    public let relatedExerciseId: String?
    
    public init(
        topic: Topic,
        title: String,
        detail: String,
        relatedExerciseId: String? = nil
    ) {
        self.id = CoachingInsight.makeId(topic: topic, title: title, relatedExerciseId: relatedExerciseId)
        self.topic = topic
        self.title = title
        self.detail = detail
        self.relatedExerciseId = relatedExerciseId
    }

    private static func makeId(topic: Topic, title: String, relatedExerciseId: String?) -> String {
        let ex = relatedExerciseId ?? ""
        // Stable, human-readable id (not cryptographic).
        return "\(topic.rawValue)|\(ex)|\(title)"
    }
}

