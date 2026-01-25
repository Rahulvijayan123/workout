import Foundation

// MARK: - ExerciseDB-compatible Exercise model
//
// This is shaped to match the ExerciseDB API payload:
// { id, name, bodyPart, equipment, gifUrl, target, secondaryMuscles, instructions }
//
// Reference: https://github.com/ExerciseDB/exercisedb-api
struct Exercise: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let bodyPart: String
    let equipment: String
    let gifUrl: String?
    let target: String
    let secondaryMuscles: [String]
    let instructions: [String]
    
    var displayName: String { name.capitalized }
    
    var displayBodyPart: String { bodyPart.capitalized }
    var displayEquipment: String { equipment.capitalized }
    var displayTarget: String { target.capitalized }
    
    var allMuscles: [String] { [target] + secondaryMuscles }
}

// MARK: - Lightweight reference for templates/sessions
struct ExerciseRef: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let bodyPart: String
    let equipment: String
    let target: String
    
    init(from exercise: Exercise) {
        self.id = exercise.id
        self.name = exercise.name
        self.bodyPart = exercise.bodyPart
        self.equipment = exercise.equipment
        self.target = exercise.target
    }
    
    /// Direct initializer for creating ExerciseRef from individual values (e.g., from database)
    init(id: String, name: String, bodyPart: String, equipment: String, target: String) {
        self.id = id
        self.name = name
        self.bodyPart = bodyPart
        self.equipment = equipment
        self.target = target
    }
    
    var displayName: String { name.capitalized }
}

