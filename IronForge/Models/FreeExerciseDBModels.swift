import Foundation

/// Raw model matching free-exercise-db JSON schema
/// Source: https://github.com/yuhonas/free-exercise-db
struct FreeExerciseDBExercise: Codable {
    let id: String
    let name: String
    let force: String?
    let level: String?
    let mechanic: String?
    let equipment: String?
    let primaryMuscles: [String]
    let secondaryMuscles: [String]
    let instructions: [String]
    let category: String?
    let images: [String]?
}
