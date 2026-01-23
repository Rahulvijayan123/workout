import Foundation

/// Loads and transforms exercises from the bundled free-exercise-db JSON
enum ExerciseLoader {
    /// Muscle → Body Part mapping for ProgressionEngine compatibility
    static let muscleToBodyPart: [String: String] = [
        // Chest
        "chest": "chest",
        "pectorals": "chest",
        // Back
        "lats": "back",
        "middle back": "back",
        "lower back": "back",
        "traps": "back",
        // Shoulders
        "shoulders": "shoulders",
        "deltoids": "shoulders",
        // Arms
        "biceps": "upper arms",
        "triceps": "upper arms",
        "forearms": "lower arms",
        // Core
        "abdominals": "waist",
        "obliques": "waist",
        // Legs
        "quadriceps": "upper legs",
        "hamstrings": "upper legs",
        "glutes": "upper legs",
        "calves": "lower legs",
        "adductors": "upper legs",
        "abductors": "upper legs",
        // Neck
        "neck": "neck"
    ]
    
    /// Equipment normalization for ProgressionEngine compatibility
    static func normalizeEquipment(_ raw: String?) -> String {
        guard let raw = raw?.lowercased() else { return "body weight" }
        switch raw {
        case "body only", "none", "":
            return "body weight"
        case "e-z curl bar":
            return "barbell"
        case "exercise ball":
            return "stability ball"
        default:
            return raw
        }
    }
    
    /// Derive body part from primary muscle using the mapping table
    static func deriveBodyPart(from primaryMuscle: String) -> String {
        let normalized = primaryMuscle.lowercased()
        return muscleToBodyPart[normalized] ?? "other"
    }
    
    /// Convert a FreeExerciseDBExercise to an Exercise
    static func transform(_ source: FreeExerciseDBExercise) -> Exercise {
        let target = source.primaryMuscles.first ?? "unknown"
        let bodyPart = deriveBodyPart(from: target)
        let equipment = normalizeEquipment(source.equipment)
        
        return Exercise(
            id: source.id,
            name: source.name,
            bodyPart: bodyPart,
            equipment: equipment,
            gifUrl: nil, // Images not used in this integration
            target: target,
            secondaryMuscles: source.secondaryMuscles,
            instructions: source.instructions
        )
    }
    
    /// Load all exercises from the bundled JSON file
    static func loadBundledExercises() -> [Exercise] {
        guard let url = Bundle.main.url(forResource: "exercises", withExtension: "json") else {
            print("⚠️ exercises.json not found in bundle")
            return []
        }
        
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            let sourceExercises = try decoder.decode([FreeExerciseDBExercise].self, from: data)
            return sourceExercises.map(transform)
        } catch {
            print("⚠️ Failed to load exercises.json: \(error)")
            return []
        }
    }
}
