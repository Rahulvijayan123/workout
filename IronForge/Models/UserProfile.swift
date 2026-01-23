import Foundation

// MARK: - User Profile Model
struct UserProfile: Codable {
    var name: String = ""
    var age: Int = 25
    /// Optional body weight (lbs). Used to scale progression + recovery heuristics.
    var bodyWeightLbs: Double? = nil
    var sex: Sex = .male
    var workoutExperience: WorkoutExperience = .beginner
    var goals: [FitnessGoal] = []
    var weeklyFrequency: Int = 4
    var gymType: GymType = .commercial
    var workoutSplit: WorkoutSplit = .pushPullLegs
    var maxes: LiftMaxes = LiftMaxes()
    var fitnessLevel: FitnessLevel = .intermediate
    var dailyProteinGrams: Int = 150
    var sleepHours: Double = 7.5
    var waterIntakeLiters: Double = 3.0
    var supplements: [String] = []
}

// MARK: - Enums
enum Sex: String, Codable, CaseIterable {
    case male = "Male"
    case female = "Female"
    case other = "Other"
    
    var icon: String {
        switch self {
        case .male: return "figure.stand"
        case .female: return "figure.stand.dress"
        case .other: return "person.fill"
        }
    }
    
    /// Scientific astronomical symbol (Mars ♂ / Venus ♀)
    var scientificSymbol: String {
        switch self {
        case .male: return "♂"
        case .female: return "♀"
        case .other: return "⚥"
        }
    }
    
    /// Short label for compact UI
    var shortLabel: String {
        switch self {
        case .male: return "M"
        case .female: return "F"
        case .other: return "X"
        }
    }
}

enum WorkoutExperience: String, Codable, CaseIterable {
    case newbie = "Just Starting"
    case beginner = "Less than 1 year"
    case intermediate = "1-3 years"
    case advanced = "3-5 years"
    case expert = "5+ years"
    
    var description: String {
        switch self {
        case .newbie: return "Ready to begin your journey"
        case .beginner: return "Building the foundation"
        case .intermediate: return "Developing consistency"
        case .advanced: return "Refining technique"
        case .expert: return "Optimizing performance"
        }
    }
    
    var icon: String {
        switch self {
        case .newbie: return "leaf.fill"
        case .beginner: return "figure.walk"
        case .intermediate: return "figure.run"
        case .advanced: return "figure.strengthtraining.traditional"
        case .expert: return "trophy.fill"
        }
    }
}

enum FitnessGoal: String, Codable, CaseIterable {
    case buildMuscle = "Build Muscle"
    case loseFat = "Lose Fat"
    case gainStrength = "Gain Strength"
    case improveEndurance = "Improve Endurance"
    case maintainFitness = "Maintain Fitness"
    case athleticPerformance = "Athletic Performance"
    case flexibility = "Flexibility"
    case generalHealth = "General Health"
    
    /// Abstract/geometric wireframe icons for tech aesthetic (uniform weight)
    var icon: String {
        switch self {
        case .buildMuscle: return "circle.hexagongrid"         // Hexagon grid (uniform)
        case .loseFat: return "drop"                           // Sweat droplet (outline)
        case .gainStrength: return "bolt"                      // Lightning (outline)
        case .improveEndurance: return "heart"                 // Heart outline
        case .maintainFitness: return "arrow.triangle.2.circlepath" // Cycle arrows
        case .athleticPerformance: return "timer"              // Timer (cleaner than stopwatch)
        case .flexibility: return "angle"                      // Protractor angle (mathematical)
        case .generalHealth: return "waveform.path"            // ECG pulse line
        }
    }
}

enum GymType: String, Codable, CaseIterable {
    case commercial = "Commercial Gym"
    case homeGym = "Home Gym"
    case crossfit = "CrossFit Box"
    case university = "University Gym"
    case outdoor = "Outdoor / Park"
    case minimalist = "Minimalist Setup"
    
    var description: String {
        switch self {
        case .commercial: return "Full equipment access"
        case .homeGym: return "Custom setup at home"
        case .crossfit: return "Functional fitness focus"
        case .university: return "Campus facilities"
        case .outdoor: return "Bodyweight & nature"
        case .minimalist: return "Basics only"
        }
    }
    
    var icon: String {
        switch self {
        case .commercial: return "dumbbell"                    // Dumbbell (gym equipment)
        case .homeGym: return "house"                          // House outline
        case .crossfit: return "figure.highintensity.intervaltraining" // HIIT figure
        case .university: return "building.columns"            // Campus columns
        case .outdoor: return "sun.max"                        // Sun (outdoors)
        case .minimalist: return "square.stack.3d.up"          // Minimal stack
        }
    }
}

enum WorkoutSplit: String, Codable, CaseIterable {
    case pushPullLegs = "Push Pull Legs"
    case fullBody = "Full Body"
    case upperLower = "Upper Lower"
    case pushPullLegsArms = "PPL + Arms"
    case broSplit = "Bro Split"
    case arnoldSplit = "Arnold Split"
    case powerBuilding = "Powerbuilding"
    case custom = "Custom"
    
    var description: String {
        switch self {
        case .pushPullLegs: return "3-6 days • Push, Pull, Legs"
        case .fullBody: return "2-4 days • Total body each session"
        case .upperLower: return "4 days • Upper & Lower alternating"
        case .pushPullLegsArms: return "6 days • PPL with dedicated arm day"
        case .broSplit: return "5-6 days • One muscle group per day"
        case .arnoldSplit: return "6 days • Chest/Back, Shoulders/Arms, Legs"
        case .powerBuilding: return "4-5 days • Strength + Hypertrophy"
        case .custom: return "Design your own split"
        }
    }
    
    var icon: String {
        switch self {
        case .pushPullLegs: return "arrow.left.arrow.right"
        case .fullBody: return "figure.stand"
        case .upperLower: return "arrow.up.arrow.down"
        case .pushPullLegsArms: return "figure.arms.open"
        case .broSplit: return "figure.strengthtraining.functional" // Muscle isolation
        case .arnoldSplit: return "trophy"                     // Classic/Golden era
        case .powerBuilding: return "bolt"                     // Power (outline)
        case .custom: return "slider.horizontal.3"
        }
    }
}

enum FitnessLevel: String, Codable, CaseIterable {
    case beginner = "Beginner"
    case novice = "Novice"
    case intermediate = "Intermediate"
    case advanced = "Advanced"
    case elite = "Elite"
    
    var description: String {
        switch self {
        case .beginner: return "Learning the basics"
        case .novice: return "Building consistency"
        case .intermediate: return "Solid foundation"
        case .advanced: return "High performance"
        case .elite: return "Peak condition"
        }
    }
}

// MARK: - Lift Maxes
struct LiftMaxes: Codable {
    var benchPress: Int?
    var squat: Int?
    var deadlift: Int?
    var overheadPress: Int?
    var barbellRow: Int?
    var pullUps: Int?
    
    var isPopulated: Bool {
        benchPress != nil || squat != nil || deadlift != nil
    }
    
    var totalBigThree: Int? {
        guard let bench = benchPress, let sq = squat, let dl = deadlift else {
            return nil
        }
        return bench + sq + dl
    }
}
