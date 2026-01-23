// MovementPattern.swift
// Classification of exercises by movement type.

import Foundation

/// Classification of exercises by their primary movement pattern.
/// Used for progression policy defaults and substitution matching.
public enum MovementPattern: String, Codable, Sendable, Hashable, CaseIterable {
    // Compound movements
    case horizontalPush = "horizontal_push"     // Bench press, push-ups
    case horizontalPull = "horizontal_pull"     // Rows
    case verticalPush = "vertical_push"         // Overhead press
    case verticalPull = "vertical_pull"         // Pull-ups, lat pulldowns
    case squat = "squat"                        // Squats, leg press
    case hipHinge = "hip_hinge"                 // Deadlifts, RDL
    case lunge = "lunge"                        // Lunges, step-ups
    
    // Isolation movements
    case elbowFlexion = "elbow_flexion"         // Bicep curls
    case elbowExtension = "elbow_extension"     // Tricep extensions
    case shoulderFlexion = "shoulder_flexion"   // Front raises
    case shoulderAbduction = "shoulder_abduction" // Lateral raises
    case kneeExtension = "knee_extension"       // Leg extensions
    case kneeFlexion = "knee_flexion"           // Leg curls
    case hipAbduction = "hip_abduction"         // Hip abductor machines
    case hipAdduction = "hip_adduction"         // Hip adductor machines
    case coreFlexion = "core_flexion"           // Crunches, leg raises
    case coreRotation = "core_rotation"         // Russian twists
    case coreStability = "core_stability"       // Planks
    
    // Carries and others
    case carry = "carry"                        // Farmer's walks
    case unknown = "unknown"
    
    /// Whether this is a compound (multi-joint) movement.
    public var isCompound: Bool {
        switch self {
        case .horizontalPush, .horizontalPull, .verticalPush, .verticalPull,
             .squat, .hipHinge, .lunge:
            return true
        default:
            return false
        }
    }
    
    /// Similarity score to another movement pattern (0-1).
    /// Used for substitution ranking.
    public func similarity(to other: MovementPattern) -> Double {
        if self == other { return 1.0 }
        
        // Group similar patterns
        let pushPatterns: Set<MovementPattern> = [.horizontalPush, .verticalPush]
        let pullPatterns: Set<MovementPattern> = [.horizontalPull, .verticalPull]
        let legPatterns: Set<MovementPattern> = [.squat, .hipHinge, .lunge]
        let armFlexPatterns: Set<MovementPattern> = [.elbowFlexion, .elbowExtension]
        let shoulderIsoPatterns: Set<MovementPattern> = [.shoulderFlexion, .shoulderAbduction]
        let corePatterns: Set<MovementPattern> = [.coreFlexion, .coreRotation, .coreStability]
        
        let groups: [Set<MovementPattern>] = [
            pushPatterns, pullPatterns, legPatterns,
            armFlexPatterns, shoulderIsoPatterns, corePatterns
        ]
        
        for group in groups {
            if group.contains(self) && group.contains(other) {
                return 0.7
            }
        }
        
        // Compound to compound gets partial credit
        if self.isCompound && other.isCompound {
            return 0.3
        }
        
        return 0.0
    }
}
