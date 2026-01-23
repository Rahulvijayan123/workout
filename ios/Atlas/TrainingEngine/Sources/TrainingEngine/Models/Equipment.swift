// Equipment.swift
// Equipment types and availability tracking.

import Foundation

/// Types of gym equipment.
public enum Equipment: String, Codable, Sendable, Hashable, CaseIterable {
    case barbell = "barbell"
    case dumbbell = "dumbbell"
    case kettlebell = "kettlebell"
    case cable = "cable"
    case machine = "machine"
    case smithMachine = "smith_machine"
    case bodyweight = "bodyweight"
    case resistanceBand = "resistance_band"
    case ezBar = "ez_bar"
    case trapBar = "trap_bar"
    case landmine = "landmine"
    case suspensionTrainer = "suspension_trainer"
    case medicineBall = "medicine_ball"
    case plateLoaded = "plate_loaded"
    case cardioMachine = "cardio_machine"
    case foam_roller = "foam_roller"
    case pullUpBar = "pull_up_bar"
    case dipStation = "dip_station"
    case bench = "bench"
    case inclineBench = "incline_bench"
    case declineBench = "decline_bench"
    case preacherBench = "preacher_bench"
    case romanChair = "roman_chair"
    case legPressMachine = "leg_press_machine"
    case hackSquatMachine = "hack_squat_machine"
    case cableCrossover = "cable_crossover"
    case latPulldownMachine = "lat_pulldown_machine"
    case rowingMachine = "rowing_machine"
    case chestPressMachine = "chest_press_machine"
    case shoulderPressMachine = "shoulder_press_machine"
    case pecDeckMachine = "pec_deck_machine"
    case legExtensionMachine = "leg_extension_machine"
    case legCurlMachine = "leg_curl_machine"
    case calfRaiseMachine = "calf_raise_machine"
    case abdominalMachine = "abdominal_machine"
    case unknown = "unknown"
    
    /// Whether this equipment is typically available in a home gym.
    public var homeGymCommon: Bool {
        switch self {
        case .dumbbell, .kettlebell, .resistanceBand, .bodyweight,
             .pullUpBar, .bench:
            return true
        default:
            return false
        }
    }
    
    /// Whether this equipment is free weights (allows more stabilization work).
    public var isFreeWeight: Bool {
        switch self {
        case .barbell, .dumbbell, .kettlebell, .ezBar, .trapBar:
            return true
        default:
            return false
        }
    }
}

/// Set of available equipment for a user/gym.
public struct EquipmentAvailability: Codable, Sendable, Hashable {
    public let available: Set<Equipment>
    
    public init(available: Set<Equipment>) {
        self.available = available
    }
    
    /// All equipment available (commercial gym).
    public static let commercialGym = EquipmentAvailability(
        available: Set(Equipment.allCases.filter { $0 != .unknown })
    )
    
    /// Basic home gym setup.
    public static let homeGym = EquipmentAvailability(
        available: Equipment.allCases.filter(\.homeGymCommon).reduce(into: Set<Equipment>()) { $0.insert($1) }
    )
    
    /// Bodyweight only.
    public static let bodyweightOnly = EquipmentAvailability(
        available: [.bodyweight, .pullUpBar]
    )
    
    /// Checks if the given equipment is available.
    public func isAvailable(_ equipment: Equipment) -> Bool {
        available.contains(equipment) || equipment == .bodyweight
    }
}
