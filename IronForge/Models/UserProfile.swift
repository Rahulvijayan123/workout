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
    var customWeeklySchedule: CustomWeeklySchedule = CustomWeeklySchedule()
    var maxes: LiftMaxes = LiftMaxes()
    var fitnessLevel: FitnessLevel = .intermediate
    var dailyProteinGrams: Int = 150
    var sleepHours: Double = 7.5
    var waterIntakeLiters: Double = 3.0
    var supplements: [String] = []
    
    /// Current training phase (affects progression and recovery expectations)
    /// ML model uses this to adjust predictions for caloric deficit vs surplus
    var trainingPhase: TrainingPhase = .maintenance
}

// MARK: - Training Phase (Critical for ML)
/// Training phase affects expected performance, recovery, and progression rates.
/// During a cut, strength may stall or decrease slightly - this is expected.
/// During a bulk, faster progression is typical.
enum TrainingPhase: String, Codable, CaseIterable {
    case cut = "Cut"
    case maintenance = "Maintenance"
    case bulk = "Bulk"
    case recomp = "Recomp"
    
    var description: String {
        switch self {
        case .cut: return "Caloric deficit • Fat loss focus"
        case .maintenance: return "Caloric balance • Maintain"
        case .bulk: return "Caloric surplus • Muscle gain"
        case .recomp: return "Slight deficit • Body recomposition"
        }
    }
    
    var icon: String {
        switch self {
        case .cut: return "arrow.down.circle"
        case .maintenance: return "equal.circle"
        case .bulk: return "arrow.up.circle"
        case .recomp: return "arrow.triangle.2.circlepath.circle"
        }
    }
    
    /// Expected strength progression rate modifier (1.0 = normal)
    var progressionExpectation: Double {
        switch self {
        case .cut: return 0.7      // Slower progression expected
        case .maintenance: return 1.0
        case .bulk: return 1.2     // Faster progression expected
        case .recomp: return 0.85  // Slightly slower
        }
    }
}

// MARK: - Custom Weekly Schedule
struct CustomWeeklySchedule: Codable {
    var monday: WorkoutDayType = .push
    var tuesday: WorkoutDayType = .pull
    var wednesday: WorkoutDayType = .legs
    var thursday: WorkoutDayType = .rest
    var friday: WorkoutDayType = .push
    var saturday: WorkoutDayType = .pull
    var sunday: WorkoutDayType = .rest
    
    subscript(day: DayOfWeek) -> WorkoutDayType {
        get {
            switch day {
            case .monday: return monday
            case .tuesday: return tuesday
            case .wednesday: return wednesday
            case .thursday: return thursday
            case .friday: return friday
            case .saturday: return saturday
            case .sunday: return sunday
            }
        }
        set {
            switch day {
            case .monday: monday = newValue
            case .tuesday: tuesday = newValue
            case .wednesday: wednesday = newValue
            case .thursday: thursday = newValue
            case .friday: friday = newValue
            case .saturday: saturday = newValue
            case .sunday: sunday = newValue
            }
        }
    }
    
    var workoutDaysCount: Int {
        [monday, tuesday, wednesday, thursday, friday, saturday, sunday]
            .filter { $0 != .rest }
            .count
    }
}

enum DayOfWeek: String, CaseIterable, Codable {
    case monday = "Monday"
    case tuesday = "Tuesday"
    case wednesday = "Wednesday"
    case thursday = "Thursday"
    case friday = "Friday"
    case saturday = "Saturday"
    case sunday = "Sunday"
    
    var shortName: String {
        String(rawValue.prefix(3)).uppercased()
    }
    
    var singleLetter: String {
        String(rawValue.prefix(1))
    }
}

enum WorkoutDayType: String, Codable, CaseIterable {
    case rest = "Rest"
    case push = "Push"
    case pull = "Pull"
    case legs = "Legs"
    case fullBody = "Full Body"
    case upperBody = "Upper Body"
    case lowerBody = "Lower Body"
    case chest = "Chest"
    case back = "Back"
    case shoulders = "Shoulders"
    case arms = "Arms"
    case biceps = "Biceps"
    case triceps = "Triceps"
    case quads = "Quads"
    case hamstrings = "Hamstrings"
    case glutes = "Glutes"
    case abs = "Abs/Core"
    
    var icon: String {
        switch self {
        case .rest: return "bed.double.fill"
        case .push: return "arrow.right"
        case .pull: return "arrow.left"
        case .legs: return "figure.walk"
        case .fullBody: return "figure.stand"
        case .upperBody: return "figure.arms.open"
        case .lowerBody: return "figure.walk"
        case .chest: return "heart.fill"
        case .back: return "arrow.uturn.backward"
        case .shoulders: return "figure.arms.open"
        case .arms: return "figure.strengthtraining.functional"
        case .biceps: return "figure.strengthtraining.functional"
        case .triceps: return "figure.strengthtraining.functional"
        case .quads: return "figure.walk"
        case .hamstrings: return "figure.walk"
        case .glutes: return "figure.walk"
        case .abs: return "figure.core.training"
        }
    }
    
    var color: (red: Double, green: Double, blue: Double) {
        switch self {
        case .rest: return (0.5, 0.5, 0.5)        // Gray
        case .push: return (0.9, 0.3, 0.3)        // Red
        case .pull: return (0.3, 0.6, 0.9)        // Blue
        case .legs: return (0.3, 0.8, 0.4)        // Green
        case .fullBody: return (0.6, 0.3, 1.0)    // Purple
        case .upperBody: return (1.0, 0.6, 0.2)   // Orange
        case .lowerBody: return (0.2, 0.7, 0.6)   // Teal
        case .chest: return (0.9, 0.2, 0.4)       // Pink-red
        case .back: return (0.2, 0.5, 0.8)        // Navy
        case .shoulders: return (0.9, 0.7, 0.2)   // Gold
        case .arms: return (0.7, 0.4, 0.9)        // Light purple
        case .biceps: return (0.8, 0.3, 0.6)      // Magenta
        case .triceps: return (0.5, 0.3, 0.8)     // Indigo
        case .quads: return (0.3, 0.7, 0.3)       // Forest green
        case .hamstrings: return (0.4, 0.6, 0.3)  // Olive
        case .glutes: return (0.8, 0.5, 0.3)      // Bronze
        case .abs: return (0.9, 0.5, 0.1)         // Orange-red
        }
    }
}

// MARK: - Enums
enum Sex: String, Codable, CaseIterable {
    case male = "Male"
    case female = "Female"
    
    var icon: String {
        switch self {
        case .male: return "figure.stand"
        case .female: return "figure.stand.dress"
        }
    }
    
    /// Scientific astronomical symbol (Mars ♂ / Venus ♀)
    var scientificSymbol: String {
        switch self {
        case .male: return "♂"
        case .female: return "♀"
        }
    }
    
    /// Short label for compact UI
    var shortLabel: String {
        switch self {
        case .male: return "M"
        case .female: return "F"
        }
    }
    
    /// Color for the sex indicator
    var accentColor: (red: Double, green: Double, blue: Double) {
        switch self {
        case .male: return (0.3, 0.5, 1.0)    // Blue
        case .female: return (0.95, 0.45, 0.7)  // Hot Pink
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
