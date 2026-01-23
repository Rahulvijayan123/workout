// UserProfile.swift
// User profile for training recommendations.

import Foundation

/// Biological sex for strength standards and recommendations.
public enum BiologicalSex: String, Codable, Sendable, Hashable {
    case male = "male"
    case female = "female"
    case other = "other"
}

/// Training experience level.
public enum ExperienceLevel: String, Codable, Sendable, Hashable {
    case beginner = "beginner"       // < 1 year
    case intermediate = "intermediate" // 1-3 years
    case advanced = "advanced"       // 3-5 years
    case elite = "elite"             // 5+ years
    
    /// Expected rate of progression (weekly load increase %).
    public var expectedProgressionRate: Double {
        switch self {
        case .beginner: return 0.025     // 2.5% per week
        case .intermediate: return 0.01  // 1% per week
        case .advanced: return 0.005     // 0.5% per week
        case .elite: return 0.002        // 0.2% per week
        }
    }
    
    /// Recommended deload frequency in weeks.
    public var recommendedDeloadFrequencyWeeks: Int {
        switch self {
        case .beginner: return 6
        case .intermediate: return 5
        case .advanced: return 4
        case .elite: return 3
        }
    }
}

/// Primary training goal.
public enum TrainingGoal: String, Codable, Sendable, Hashable {
    case strength = "strength"
    case hypertrophy = "hypertrophy"
    case powerlifting = "powerlifting"
    case generalFitness = "general_fitness"
    case fatLoss = "fat_loss"
    case endurance = "endurance"
    case athleticPerformance = "athletic_performance"
    
    /// Whether this goal benefits from higher volume.
    public var prefersHigherVolume: Bool {
        switch self {
        case .hypertrophy, .endurance, .fatLoss:
            return true
        default:
            return false
        }
    }
    
    /// Whether this goal benefits from heavier loads.
    public var prefersHeavierLoads: Bool {
        switch self {
        case .strength, .powerlifting:
            return true
        default:
            return false
        }
    }
}

/// User profile for training recommendations.
public struct UserProfile: Codable, Sendable, Hashable {
    /// User identifier.
    public let id: String
    
    /// Biological sex.
    public let sex: BiologicalSex
    
    /// Training experience level.
    public let experience: ExperienceLevel
    
    /// Primary training goals (ordered by priority).
    public let goals: [TrainingGoal]
    
    /// Preferred training frequency (days per week).
    public let weeklyFrequency: Int
    
    /// Available equipment.
    public let availableEquipment: EquipmentAvailability
    
    /// Preferred load unit.
    public let preferredUnit: LoadUnit
    
    /// Body weight in preferred unit (optional, for relative strength).
    public let bodyWeight: Load?
    
    /// Age in years (optional, for recovery considerations).
    public let age: Int?
    
    /// Injuries or limitations to consider.
    public let limitations: [String]
    
    /// Optional nutrition signal (self-reported).
    public let dailyProteinGrams: Int?
    
    /// Optional sleep baseline (self-reported, hours).
    public let sleepHours: Double?
    
    public init(
        id: String = UUID().uuidString,
        sex: BiologicalSex,
        experience: ExperienceLevel,
        goals: [TrainingGoal],
        weeklyFrequency: Int = 4,
        availableEquipment: EquipmentAvailability = .commercialGym,
        preferredUnit: LoadUnit = .pounds,
        bodyWeight: Load? = nil,
        age: Int? = nil,
        limitations: [String] = [],
        dailyProteinGrams: Int? = nil,
        sleepHours: Double? = nil
    ) {
        self.id = id
        self.sex = sex
        self.experience = experience
        self.goals = goals
        self.weeklyFrequency = max(1, min(7, weeklyFrequency))
        self.availableEquipment = availableEquipment
        self.preferredUnit = preferredUnit
        self.bodyWeight = bodyWeight
        self.age = age
        self.limitations = limitations
        self.dailyProteinGrams = dailyProteinGrams
        self.sleepHours = sleepHours
    }
    
    /// Primary goal (first in list or general fitness).
    public var primaryGoal: TrainingGoal {
        goals.first ?? .generalFitness
    }
}
