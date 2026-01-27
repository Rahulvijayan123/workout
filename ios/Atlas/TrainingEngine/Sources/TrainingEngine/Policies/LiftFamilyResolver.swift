// LiftFamilyResolver.swift
// Maps exercises to canonical lift families for state continuity across variations/substitutions.

import Foundation

/// A canonical lift family that groups related exercises.
public struct LiftFamily: Codable, Sendable, Hashable {
    /// Unique identifier for this family.
    public let id: String
    
    /// Display name for the family.
    public let name: String
    
    /// Primary movement pattern.
    public let movementPattern: MovementPattern
    
    /// Primary muscle groups.
    public let primaryMuscles: [MuscleGroup]
    
    public init(
        id: String,
        name: String,
        movementPattern: MovementPattern,
        primaryMuscles: [MuscleGroup]
    ) {
        self.id = id
        self.name = name
        self.movementPattern = movementPattern
        self.primaryMuscles = primaryMuscles
    }
    
    // MARK: - Standard lift families
    
    /// Bench press family (flat/incline/decline, barbell/dumbbell).
    public static let benchPress = LiftFamily(
        id: "bench_press",
        name: "Bench Press",
        movementPattern: .horizontalPush,
        primaryMuscles: [.chest, .frontDelts, .triceps]
    )
    
    /// Overhead press family (standing/seated, barbell/dumbbell).
    public static let overheadPress = LiftFamily(
        id: "overhead_press",
        name: "Overhead Press",
        movementPattern: .verticalPush,
        primaryMuscles: [.frontDelts, .triceps]
    )
    
    /// Squat family (back/front/goblet).
    public static let squat = LiftFamily(
        id: "squat",
        name: "Squat",
        movementPattern: .squat,
        primaryMuscles: [.quadriceps, .glutes]
    )
    
    /// Deadlift family (conventional/sumo/trap bar).
    public static let deadlift = LiftFamily(
        id: "deadlift",
        name: "Deadlift",
        movementPattern: .hipHinge,
        primaryMuscles: [.glutes, .hamstrings, .lowerBack]
    )
    
    /// Row family (barbell/dumbbell/cable).
    public static let row = LiftFamily(
        id: "row",
        name: "Row",
        movementPattern: .horizontalPull,
        primaryMuscles: [.lats, .rhomboids, .biceps]
    )
    
    /// Pulldown/pull-up family.
    public static let pulldown = LiftFamily(
        id: "pulldown",
        name: "Pulldown/Pull-up",
        movementPattern: .verticalPull,
        primaryMuscles: [.lats, .biceps]
    )
    
    /// Generic family for exercises that don't fit standard patterns.
    public static func generic(for exercise: Exercise) -> LiftFamily {
        LiftFamily(
            id: exercise.id,
            name: exercise.name,
            movementPattern: exercise.movementPattern,
            primaryMuscles: Array(exercise.primaryMuscles)
        )
    }
}

/// Resolution result containing family, coefficient, and state keys.
public struct LiftFamilyResolution: Sendable {
    /// The canonical lift family.
    public let family: LiftFamily
    
    /// Coefficient to apply when converting load from family baseline (0.0-1.5 typical).
    /// 1.0 = same as family baseline
    /// <1.0 = variation is typically lighter (e.g., incline bench vs flat)
    /// >1.0 = variation is typically heavier (rare)
    public let coefficient: Double
    
    /// Whether this is a direct family member (vs substitution).
    public let isDirectMember: Bool
    
    /// The original exercise ID (for explicit update key).
    public let exerciseId: String
    
    /// The state key to use for READING (estimating) loads.
    /// This is the canonical family baseline that we scale from.
    /// For variations/substitutions, we estimate their load by reading the family's
    /// baseline and applying the coefficient.
    public var referenceStateKey: String {
        family.id
    }
    
    /// The state key to use for WRITING (persisting) state after a session.
    /// - Direct family members (e.g., barbell back squat, bench, squat): write to family.id
    /// - Variations (e.g., close-grip bench, pause bench, front squat): write to their own exercise ID
    /// - Substitutions (e.g., leg press for squat): write to their own exercise ID
    ///
    /// This prevents variations/substitutions from contaminating the base lift's state,
    /// while still allowing them to reference the base lift for initial load estimation.
    ///
    /// Note: Direct members write to family.id even if their ID is a shorthand (e.g., "bench" → "bench_press").
    /// This ensures state continuity when switching between equivalent notations.
    public var updateStateKey: String {
        // Direct family members update the family state (e.g., "bench" → "bench_press", "squat" → "squat")
        // Variations (e.g., close_grip_bench) and substitutions update their own state
        isDirectMember ? family.id : exerciseId
    }
    
    /// Legacy stateKey - now aliases to referenceStateKey for backward compatibility
    @available(*, deprecated, message: "Use referenceStateKey or updateStateKey explicitly")
    public var stateKey: String {
        referenceStateKey
    }
    
    public init(family: LiftFamily, coefficient: Double, isDirectMember: Bool, exerciseId: String? = nil) {
        self.family = family
        self.coefficient = max(0.1, min(2.0, coefficient))
        self.isDirectMember = isDirectMember
        self.exerciseId = exerciseId ?? family.id
    }
}

/// Resolver for mapping exercises to lift families.
public enum LiftFamilyResolver {
    
    // MARK: - Unified Coefficient Calculation
    
    /// Internal structure to hold coefficient calculation inputs.
    private struct CoefficientInputs {
        let idLower: String
        let nameLower: String
        let equipment: Equipment?
        let family: LiftFamily
    }
    
    /// Unified coefficient calculation based on ID, name, and equipment.
    /// This is the single source of truth for coefficient values.
    private static func computeCoefficient(
        idLower: String,
        nameLower: String,
        equipment: Equipment?,
        family: LiftFamily
    ) -> Double {
        switch family.id {
        case LiftFamily.benchPress.id:
            return benchPressCoefficient(idLower, nameLower, equipment: equipment)
            
        case LiftFamily.overheadPress.id:
            return overheadPressCoefficient(idLower, nameLower, equipment: equipment)
            
        case LiftFamily.squat.id:
            // Special case for leg press
            if idLower.contains("leg_press") || idLower.contains("legpress") {
                return 1.5
            }
            return squatCoefficient(idLower, nameLower, equipment: equipment)
            
        case LiftFamily.deadlift.id:
            return deadliftCoefficient(idLower, nameLower, equipment: equipment)
            
        case LiftFamily.row.id:
            return rowCoefficient(idLower, nameLower, equipment: equipment)
            
        case LiftFamily.pulldown.id:
            return pulldownCoefficient(idLower, nameLower, equipment: equipment)
            
        default:
            return 1.0
        }
    }
    
    /// Infers equipment type from exercise ID string.
    private static func inferEquipment(fromId idLower: String) -> Equipment? {
        if idLower.contains("dumbbell") || idLower.contains("db_") || idLower.hasPrefix("db") {
            return .dumbbell
        }
        if idLower.contains("kettlebell") || idLower.contains("kb_") {
            return .kettlebell
        }
        if idLower.contains("cable") {
            return .cable
        }
        if idLower.contains("machine") {
            return .machine
        }
        if idLower.contains("smith") {
            return .smithMachine
        }
        if idLower.contains("trap_bar") || idLower.contains("trapbar") {
            return .trapBar
        }
        if idLower.contains("ez_bar") || idLower.contains("ezbar") {
            return .ezBar
        }
        // Default assumption for standard lifts without prefix
        return .barbell
    }
    
    /// Resolves an exercise to its lift family with coefficient.
    public static func resolve(_ exercise: Exercise) -> LiftFamilyResolution {
        let lower = exercise.id.lowercased()
        let name = exercise.name.lowercased()
        
        // Try to match to standard families based on ID/name patterns
        
        // Bench press family
        if matchesBenchPress(lower, name) {
            let coefficient = computeCoefficient(idLower: lower, nameLower: name, equipment: exercise.equipment, family: .benchPress)
            let isDirectMember = isDirectBenchPressMember(lower)
            return LiftFamilyResolution(family: .benchPress, coefficient: coefficient, isDirectMember: isDirectMember, exerciseId: exercise.id)
        }
        
        // Overhead press family
        if matchesOverheadPress(lower, name) {
            let coefficient = computeCoefficient(idLower: lower, nameLower: name, equipment: exercise.equipment, family: .overheadPress)
            let isDirectMember = isDirectOverheadPressMember(lower)
            return LiftFamilyResolution(family: .overheadPress, coefficient: coefficient, isDirectMember: isDirectMember, exerciseId: exercise.id)
        }
        
        // Squat family
        if matchesSquat(lower, name) {
            let coefficient = computeCoefficient(idLower: lower, nameLower: name, equipment: exercise.equipment, family: .squat)
            let isDirectMember = isDirectSquatMember(lower)
            return LiftFamilyResolution(family: .squat, coefficient: coefficient, isDirectMember: isDirectMember, exerciseId: exercise.id)
        }
        
        // Deadlift family
        if matchesDeadlift(lower, name) {
            let coefficient = computeCoefficient(idLower: lower, nameLower: name, equipment: exercise.equipment, family: .deadlift)
            let isDirectMember = isDirectDeadliftMember(lower)
            return LiftFamilyResolution(family: .deadlift, coefficient: coefficient, isDirectMember: isDirectMember, exerciseId: exercise.id)
        }
        
        // Row family
        if matchesRow(lower, name) {
            let coefficient = computeCoefficient(idLower: lower, nameLower: name, equipment: exercise.equipment, family: .row)
            let isDirectMember = isDirectRowMember(lower)
            return LiftFamilyResolution(family: .row, coefficient: coefficient, isDirectMember: isDirectMember, exerciseId: exercise.id)
        }
        
        // Pulldown/pull-up family
        if matchesPulldown(lower, name) {
            let coefficient = computeCoefficient(idLower: lower, nameLower: name, equipment: exercise.equipment, family: .pulldown)
            let isDirectMember = isDirectPulldownMember(lower)
            return LiftFamilyResolution(family: .pulldown, coefficient: coefficient, isDirectMember: isDirectMember, exerciseId: exercise.id)
        }
        
        // Check for substitutions based on movement pattern
        if let substitutionFamily = resolveSubstitution(exercise) {
            return substitutionFamily
        }
        
        // Default: generic family using the exercise's own ID
        return LiftFamilyResolution(
            family: .generic(for: exercise),
            coefficient: 1.0,
            isDirectMember: true,
            exerciseId: exercise.id
        )
    }
    
    // MARK: - Direct Member Checks
    // These determine whether an exercise ID represents a canonical/primary form of the lift
    // (writes to family baseline) vs a variation/modification (writes to its own ID).
    
    /// Returns true if the ID represents the canonical bench press (not a variation).
    private static func isDirectBenchPressMember(_ id: String) -> Bool {
        // Direct members: standard flat bench press in any notation
        // NOT direct: incline, decline, close-grip, wide-grip, pause, spoto, floor press, etc.
        let directIds: Set<String> = [
            "bench", "bench_press", "benchpress", "bench press",
            "barbell_bench", "barbell_bench_press", "barbell_benchpress",
            "flat_bench", "flat_bench_press", "flat_benchpress"
        ]
        if directIds.contains(id) { return true }
        
        // Exclude common variations
        if id.contains("incline") || id.contains("decline") ||
           id.contains("close") || id.contains("wide") ||
           id.contains("pause") || id.contains("spoto") ||
           id.contains("floor") || id.contains("tempo") ||
           id.contains("touch") || id.contains("pin") ||
           id.contains("dumbbell") || id.contains("db_") ||
           id.contains("machine") || id.contains("smith") {
            return false
        }
        
        return false
    }
    
    /// Returns true if the ID represents the canonical overhead press (not a variation).
    private static func isDirectOverheadPressMember(_ id: String) -> Bool {
        let directIds: Set<String> = [
            "ohp", "overhead_press", "overheadpress", "overhead press",
            "press", "military_press", "militarypress", "military press",
            "barbell_ohp", "barbell_overhead_press", "standing_press"
        ]
        if directIds.contains(id) { return true }
        
        // Exclude variations
        if id.contains("seated") || id.contains("push_press") ||
           id.contains("behind") || id.contains("arnold") ||
           id.contains("dumbbell") || id.contains("db_") ||
           id.contains("machine") || id.contains("smith") {
            return false
        }
        
        return false
    }
    
    /// Returns true if the ID represents the canonical back squat (not a variation).
    private static func isDirectSquatMember(_ id: String) -> Bool {
        let directIds: Set<String> = [
            "squat", "back_squat", "backsquat", "back squat",
            "barbell_squat", "barbell_back_squat", "bb_squat",
            "high_bar_squat", "low_bar_squat"
        ]
        if directIds.contains(id) { return true }
        
        // Exclude variations
        if id.contains("front") || id.contains("goblet") ||
           id.contains("safety") || id.contains("ssb") ||
           id.contains("zercher") || id.contains("overhead") ||
           id.contains("pause") || id.contains("tempo") ||
           id.contains("box") || id.contains("pin") ||
           id.contains("dumbbell") || id.contains("db_") ||
           id.contains("machine") || id.contains("smith") ||
           id.contains("hack") || id.contains("leg_press") {
            return false
        }
        
        return false
    }
    
    /// Returns true if the ID represents the canonical deadlift (not a variation).
    private static func isDirectDeadliftMember(_ id: String) -> Bool {
        let directIds: Set<String> = [
            "deadlift", "dl", "conventional_deadlift", "conventional",
            "barbell_deadlift", "bb_deadlift"
        ]
        if directIds.contains(id) { return true }
        
        // Exclude variations (sumo is often treated as primary but we'll keep it separate for state tracking)
        if id.contains("sumo") || id.contains("romanian") ||
           id.contains("rdl") || id.contains("stiff") ||
           id.contains("trap_bar") || id.contains("trapbar") ||
           id.contains("deficit") || id.contains("block") ||
           id.contains("pause") || id.contains("snatch") ||
           id.contains("dumbbell") || id.contains("db_") {
            return false
        }
        
        return false
    }
    
    /// Returns true if the ID represents the canonical barbell row (not a variation).
    private static func isDirectRowMember(_ id: String) -> Bool {
        let directIds: Set<String> = [
            "row", "barbell_row", "bb_row", "bent_over_row",
            "bent_row", "pendlay_row"
        ]
        if directIds.contains(id) { return true }
        
        // Exclude variations
        if id.contains("dumbbell") || id.contains("db_") ||
           id.contains("cable") || id.contains("machine") ||
           id.contains("seated") || id.contains("t_bar") || id.contains("tbar") ||
           id.contains("meadows") || id.contains("seal") ||
           id.contains("chest_supported") {
            return false
        }
        
        return false
    }
    
    /// Returns true if the ID represents the canonical pulldown/pull-up (not a variation).
    private static func isDirectPulldownMember(_ id: String) -> Bool {
        let directIds: Set<String> = [
            "pulldown", "lat_pulldown", "latpulldown", "lat pulldown",
            "pull_up", "pullup", "pull-up", "chin_up", "chinup", "chin-up"
        ]
        if directIds.contains(id) { return true }
        
        // Exclude variations
        if id.contains("close") || id.contains("wide") ||
           id.contains("neutral") || id.contains("underhand") ||
           id.contains("behind") || id.contains("assisted") ||
           id.contains("weighted") || id.contains("machine") {
            return false
        }
        
        return false
    }
    
    /// Resolution result containing reference and update keys from just an exercise ID.
    public struct StateKeyResolution: Sendable {
        /// The state key to READ from (family baseline for load estimation).
        public let referenceStateKey: String
        
        /// The state key to WRITE to (exercise-specific for variations/subs, family for direct members).
        public let updateStateKey: String
        
        /// Coefficient from reference to performed exercise.
        public let coefficient: Double
        
        /// Whether this is a direct family member.
        public let isDirectMember: Bool
    }
    
    /// Resolves state keys from just an exercise ID.
    /// This is used when the full Exercise object is not available (e.g., in updateLiftState).
    /// Returns both referenceStateKey and updateStateKey with coefficient.
    /// Uses the same coefficient logic as resolve(_:) for consistency.
    public static func resolveStateKeys(fromId exerciseId: String) -> StateKeyResolution {
        let lower = exerciseId.lowercased()
        let inferredEquipment = inferEquipment(fromId: lower)
        
        // Bench press family
        if lower.contains("bench") {
            let coefficient = computeCoefficient(idLower: lower, nameLower: lower, equipment: inferredEquipment, family: .benchPress)
            // Direct members: canonical bench press IDs (not variations like pause_bench, close_grip_bench, incline_bench)
            let isDirectMember = (
                lower == "bench" ||
                lower == "bench_press" || 
                lower == "bench press" || 
                lower == "benchpress" ||
                lower == "barbell_bench" ||
                lower == "barbell_bench_press" ||
                lower == "flat_bench" ||
                lower == "flat_bench_press"
            )
            return StateKeyResolution(
                referenceStateKey: LiftFamily.benchPress.id,
                updateStateKey: isDirectMember ? LiftFamily.benchPress.id : exerciseId,
                coefficient: coefficient,
                isDirectMember: isDirectMember
            )
        }
        
        // Overhead press family
        if lower.contains("ohp") || lower.contains("overhead") || lower.contains("shoulder_press") || lower.contains("military") {
            let coefficient = computeCoefficient(idLower: lower, nameLower: lower, equipment: inferredEquipment, family: .overheadPress)
            let isDirectMember = (lower == "overhead_press" || lower == "ohp")
            return StateKeyResolution(
                referenceStateKey: LiftFamily.overheadPress.id,
                updateStateKey: isDirectMember ? LiftFamily.overheadPress.id : exerciseId,
                coefficient: coefficient,
                isDirectMember: isDirectMember
            )
        }
        
        // Squat family
        if lower.contains("squat") && !lower.contains("split") {
            let coefficient = computeCoefficient(idLower: lower, nameLower: lower, equipment: inferredEquipment, family: .squat)
            let isDirectMember = (lower == "squat" || lower == "back_squat" || lower == "backsquat")
            return StateKeyResolution(
                referenceStateKey: LiftFamily.squat.id,
                updateStateKey: isDirectMember ? LiftFamily.squat.id : exerciseId,
                coefficient: coefficient,
                isDirectMember: isDirectMember
            )
        }
        
        // Leg press (squat substitute - always updates its own state)
        if lower.contains("leg_press") || lower.contains("legpress") {
            return StateKeyResolution(
                referenceStateKey: LiftFamily.squat.id,
                updateStateKey: exerciseId,
                coefficient: 1.5,
                isDirectMember: false
            )
        }
        
        // Deadlift family
        if lower.contains("deadlift") || lower == "dl" {
            let coefficient = computeCoefficient(idLower: lower, nameLower: lower, equipment: inferredEquipment, family: .deadlift)
            let isDirectMember = (lower == "deadlift" || lower == "conventional_deadlift")
            return StateKeyResolution(
                referenceStateKey: LiftFamily.deadlift.id,
                updateStateKey: isDirectMember ? LiftFamily.deadlift.id : exerciseId,
                coefficient: coefficient,
                isDirectMember: isDirectMember
            )
        }
        
        // Row family
        if lower.contains("row") && !lower.contains("narrow") {
            let coefficient = computeCoefficient(idLower: lower, nameLower: lower, equipment: inferredEquipment, family: .row)
            let isDirectMember = (lower == "row" || lower == "barbell_row" || lower == "bent_over_row")
            return StateKeyResolution(
                referenceStateKey: LiftFamily.row.id,
                updateStateKey: isDirectMember ? LiftFamily.row.id : exerciseId,
                coefficient: coefficient,
                isDirectMember: isDirectMember
            )
        }
        
        // Pulldown/pull-up family
        if lower.contains("pulldown") || lower.contains("lat_pull") || lower.contains("pull_up") || lower.contains("pullup") || lower.contains("chin") {
            let coefficient = computeCoefficient(idLower: lower, nameLower: lower, equipment: inferredEquipment, family: .pulldown)
            let isDirectMember = (lower == "pulldown" || lower == "lat_pulldown")
            return StateKeyResolution(
                referenceStateKey: LiftFamily.pulldown.id,
                updateStateKey: isDirectMember ? LiftFamily.pulldown.id : exerciseId,
                coefficient: coefficient,
                isDirectMember: isDirectMember
            )
        }
        
        // Default: use the exercise ID itself for both keys
        return StateKeyResolution(
            referenceStateKey: exerciseId,
            updateStateKey: exerciseId,
            coefficient: 1.0,
            isDirectMember: true
        )
    }
    
    /// Resolves a canonical state key from just an exercise ID (legacy method).
    /// Returns a tuple of (stateKey, coefficient estimate).
    /// Uses the same coefficient logic as resolve(_:) for consistency.
    @available(*, deprecated, message: "Use resolveStateKeys(fromId:) for separate reference/update keys")
    public static func resolveStateKey(fromId exerciseId: String) -> (stateKey: String, coefficient: Double) {
        let resolution = resolveStateKeys(fromId: exerciseId)
        return (resolution.referenceStateKey, resolution.coefficient)
    }
    
    /// Resolves based on movement pattern for substitutions.
    private static func resolveSubstitution(_ exercise: Exercise) -> LiftFamilyResolution? {
        let lower = exercise.id.lowercased()
        
        switch exercise.movementPattern {
        case .horizontalPush:
            // Machine chest press, push-ups, etc.
            if lower.contains("chest") || lower.contains("push") {
                let coefficient: Double = exercise.equipment == .machine ? 0.80 : 0.70
                return LiftFamilyResolution(family: .benchPress, coefficient: coefficient, isDirectMember: false, exerciseId: exercise.id)
            }
            
        case .verticalPush:
            // Machine shoulder press, etc.
            if lower.contains("shoulder") || lower.contains("military") {
                let coefficient: Double = exercise.equipment == .machine ? 0.85 : 0.80
                return LiftFamilyResolution(family: .overheadPress, coefficient: coefficient, isDirectMember: false, exerciseId: exercise.id)
            }
            
        case .squat:
            // Leg press, hack squat, etc.
            if lower.contains("leg_press") || lower.contains("hack") {
                return LiftFamilyResolution(family: .squat, coefficient: 1.5, isDirectMember: false, exerciseId: exercise.id)
            }
            
        case .hipHinge:
            // Romanian deadlift, hip thrust, etc.
            if lower.contains("rdl") || lower.contains("romanian") {
                return LiftFamilyResolution(family: .deadlift, coefficient: 0.70, isDirectMember: false, exerciseId: exercise.id)
            }
            if lower.contains("hip_thrust") || lower.contains("glute_bridge") {
                return LiftFamilyResolution(family: .deadlift, coefficient: 0.75, isDirectMember: false, exerciseId: exercise.id)
            }
            
        case .horizontalPull:
            // Cable row, seated row, etc.
            if exercise.equipment == .cable || exercise.equipment == .machine {
                return LiftFamilyResolution(family: .row, coefficient: 0.85, isDirectMember: false, exerciseId: exercise.id)
            }
            
        case .verticalPull:
            // Lat pulldown variations
            if exercise.equipment == .cable || exercise.equipment == .machine {
                return LiftFamilyResolution(family: .pulldown, coefficient: 0.90, isDirectMember: false, exerciseId: exercise.id)
            }
            
        default:
            break
        }
        
        return nil
    }
    
    // MARK: - Pattern matching
    
    private static func matchesBenchPress(_ id: String, _ name: String) -> Bool {
        id.contains("bench") || name.contains("bench press")
    }
    
    private static func matchesOverheadPress(_ id: String, _ name: String) -> Bool {
        id.contains("ohp") || id.contains("overhead") || id.contains("shoulder_press") ||
        name.contains("overhead press") || name.contains("ohp") || name.contains("military press")
    }
    
    private static func matchesSquat(_ id: String, _ name: String) -> Bool {
        (id.contains("squat") && !id.contains("split")) || name.contains("squat")
    }
    
    private static func matchesDeadlift(_ id: String, _ name: String) -> Bool {
        id.contains("deadlift") || id == "dl" || name.contains("deadlift")
    }
    
    private static func matchesRow(_ id: String, _ name: String) -> Bool {
        id.contains("row") && !id.contains("upright") || name.contains("row")
    }
    
    private static func matchesPulldown(_ id: String, _ name: String) -> Bool {
        id.contains("pulldown") || id.contains("pullup") || id.contains("pull_up") ||
        name.contains("pulldown") || name.contains("pull-up") || name.contains("chin")
    }
    
    // MARK: - Coefficients
    
    private static func benchPressCoefficient(_ id: String, _ name: String, equipment: Equipment?) -> Double {
        var coefficient = 1.0
        
        // Angle adjustments
        if id.contains("incline") || name.contains("incline") {
            coefficient *= 0.85
        } else if id.contains("decline") || name.contains("decline") {
            coefficient *= 1.05
        }
        
        // Grip adjustments
        if id.contains("close_grip") || id.contains("close") || name.contains("close grip") {
            coefficient *= 0.90
        } else if id.contains("wide") || name.contains("wide") {
            coefficient *= 0.95
        }
        
        // Equipment adjustments
        if let equipment = equipment {
            switch equipment {
            case .dumbbell:
                coefficient *= 0.45 // Per-hand weight is roughly 45% of barbell
            case .machine, .smithMachine:
                coefficient *= 0.85
            case .cable:
                coefficient *= 0.50
            default:
                break
            }
        }
        
        return coefficient
    }
    
    private static func overheadPressCoefficient(_ id: String, _ name: String, equipment: Equipment?) -> Double {
        var coefficient = 1.0
        
        // Seated vs standing
        if id.contains("seated") || name.contains("seated") {
            coefficient *= 1.05 // Seated is typically slightly stronger
        }
        
        // Equipment adjustments
        if let equipment = equipment {
            switch equipment {
            case .dumbbell:
                coefficient *= 0.45
            case .machine:
                coefficient *= 0.85
            default:
                break
            }
        }
        
        return coefficient
    }
    
    private static func squatCoefficient(_ id: String, _ name: String, equipment: Equipment?) -> Double {
        var coefficient = 1.0
        
        // Squat variations
        if id.contains("front") || name.contains("front") {
            coefficient *= 0.80
        } else if id.contains("goblet") || name.contains("goblet") {
            coefficient *= 0.35
        } else if id.contains("safety_bar") || id.contains("ssb") || name.contains("safety bar") {
            coefficient *= 0.90
        }
        
        // Equipment adjustments
        if let equipment = equipment {
            switch equipment {
            case .dumbbell, .kettlebell:
                coefficient *= 0.35
            case .smithMachine:
                coefficient *= 0.90
            default:
                break
            }
        }
        
        return coefficient
    }
    
    private static func deadliftCoefficient(_ id: String, _ name: String, equipment: Equipment?) -> Double {
        var coefficient = 1.0
        
        // Deadlift variations
        if id.contains("sumo") || name.contains("sumo") {
            coefficient *= 1.0 // Roughly same
        } else if id.contains("romanian") || id.contains("rdl") || name.contains("romanian") {
            coefficient *= 0.70
        } else if id.contains("stiff") || name.contains("stiff") {
            coefficient *= 0.75
        }
        
        // Equipment adjustments
        if let equipment = equipment {
            switch equipment {
            case .trapBar:
                coefficient *= 1.05 // Trap bar typically allows slightly more weight
            case .dumbbell:
                coefficient *= 0.55
            default:
                break
            }
        }
        
        return coefficient
    }
    
    private static func rowCoefficient(_ id: String, _ name: String, equipment: Equipment?) -> Double {
        var coefficient = 1.0
        
        // Row variations
        if id.contains("pendlay") || name.contains("pendlay") {
            coefficient *= 0.90
        } else if id.contains("t-bar") || id.contains("tbar") || name.contains("t-bar") {
            coefficient *= 1.10
        }
        
        // Equipment adjustments
        if let equipment = equipment {
            switch equipment {
            case .dumbbell:
                coefficient *= 0.55 // Per-hand
            case .cable, .machine:
                coefficient *= 0.85
            default:
                break
            }
        }
        
        return coefficient
    }
    
    private static func pulldownCoefficient(_ id: String, _ name: String, equipment: Equipment?) -> Double {
        var coefficient = 1.0
        
        // Grip adjustments
        if id.contains("close") || name.contains("close") {
            coefficient *= 0.95
        } else if id.contains("wide") || name.contains("wide") {
            coefficient *= 1.0
        }
        
        // Pull-up vs pulldown (body weight factor)
        if id.contains("pullup") || id.contains("pull_up") || name.contains("pull-up") {
            coefficient *= 0.75 // Approximate relative to bodyweight-loaded pulldown
        } else if id.contains("chin") || name.contains("chin") {
            coefficient *= 0.80
        }
        
        return coefficient
    }
}

// MARK: - Extension for convenient access

public extension Exercise {
    /// Resolves this exercise to its lift family.
    var liftFamily: LiftFamilyResolution {
        LiftFamilyResolver.resolve(self)
    }
    
    /// The state key to use for READING progression baseline (family reference).
    var progressionReferenceKey: String {
        liftFamily.referenceStateKey
    }
    
    /// The state key to use for WRITING progression state (exercise-specific for variations).
    var progressionUpdateKey: String {
        liftFamily.updateStateKey
    }
    
    /// Legacy state key (deprecated - use progressionReferenceKey or progressionUpdateKey).
    @available(*, deprecated, message: "Use progressionReferenceKey or progressionUpdateKey")
    var progressionStateKey: String {
        liftFamily.referenceStateKey
    }
}
