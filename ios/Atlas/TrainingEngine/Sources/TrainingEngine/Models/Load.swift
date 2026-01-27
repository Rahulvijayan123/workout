// Load.swift
// Value type representing a weight load with unit and rounding support.

import Foundation

/// Unit of measurement for load/weight.
public enum LoadUnit: String, Codable, Sendable, Hashable {
    case pounds = "lb"
    case kilograms = "kg"
    
    /// Conversion factor to kilograms.
    public var toKgMultiplier: Double {
        switch self {
        case .pounds: return 0.453592
        case .kilograms: return 1.0
        }
    }
    
    /// Standard increments for this unit.
    public var standardIncrements: [Double] {
        switch self {
        case .pounds: return [2.5, 5.0, 10.0]
        case .kilograms: return [1.25, 2.5, 5.0]
        }
    }
}

/// A weight/load value with its unit.
public struct Load: Codable, Sendable, Hashable, Comparable {
    public let value: Double
    public let unit: LoadUnit
    
    public init(value: Double, unit: LoadUnit) {
        self.value = max(0, value)
        self.unit = unit
    }
    
    /// Creates a load in pounds.
    public static func pounds(_ value: Double) -> Load {
        Load(value: value, unit: .pounds)
    }
    
    /// Creates a load in kilograms.
    public static func kilograms(_ value: Double) -> Load {
        Load(value: value, unit: .kilograms)
    }
    
    /// Zero load.
    public static let zero = Load(value: 0, unit: .pounds)
    
    /// Converts this load to kilograms.
    public var inKilograms: Double {
        value * unit.toKgMultiplier
    }
    
    /// Converts this load to the specified unit.
    public func converted(to targetUnit: LoadUnit) -> Load {
        guard unit != targetUnit else { return self }
        
        let inKg = inKilograms
        let converted: Double
        switch targetUnit {
        case .kilograms:
            converted = inKg
        case .pounds:
            converted = inKg / LoadUnit.pounds.toKgMultiplier
        }
        return Load(value: converted, unit: targetUnit)
    }
    
    /// Rounds this load according to the given policy.
    public func rounded(using policy: LoadRoundingPolicy) -> Load {
        policy.round(self)
    }
    
    // MARK: - Comparable
    
    public static func < (lhs: Load, rhs: Load) -> Bool {
        lhs.inKilograms < rhs.inKilograms
    }
    
    // MARK: - Arithmetic
    
    public static func + (lhs: Load, rhs: Load) -> Load {
        let rhsConverted = rhs.converted(to: lhs.unit)
        return Load(value: lhs.value + rhsConverted.value, unit: lhs.unit)
    }
    
    public static func - (lhs: Load, rhs: Load) -> Load {
        let rhsConverted = rhs.converted(to: lhs.unit)
        return Load(value: max(0, lhs.value - rhsConverted.value), unit: lhs.unit)
    }
    
    public static func * (lhs: Load, rhs: Double) -> Load {
        Load(value: lhs.value * rhs, unit: lhs.unit)
    }
    
    public static func / (lhs: Load, rhs: Double) -> Load {
        guard rhs != 0 else { return lhs }
        return Load(value: lhs.value / rhs, unit: lhs.unit)
    }
}

/// Policy for rounding loads to available increments.
public struct LoadRoundingPolicy: Codable, Sendable, Hashable {
    /// The smallest increment to round to.
    public let increment: Double
    /// The unit for the increment.
    public let unit: LoadUnit
    /// Whether to round up, down, or to nearest.
    public let mode: RoundingMode
    
    public enum RoundingMode: String, Codable, Sendable, Hashable {
        case nearest
        case up
        case down
    }
    
    public init(increment: Double, unit: LoadUnit, mode: RoundingMode = .nearest) {
        self.increment = max(0.1, increment)
        self.unit = unit
        self.mode = mode
    }
    
    /// Standard rounding for pounds (2.5 lb increments).
    public static let standardPounds = LoadRoundingPolicy(increment: 2.5, unit: .pounds)
    
    /// Standard rounding for kilograms (1.25 kg increments).
    public static let standardKilograms = LoadRoundingPolicy(increment: 1.25, unit: .kilograms)
    
    /// Microloading for pounds (1.25 lb increments, useful for upper body presses).
    public static let microPounds = LoadRoundingPolicy(increment: 1.25, unit: .pounds)
    
    /// Microloading for kilograms (0.5 kg increments).
    public static let microKilograms = LoadRoundingPolicy(increment: 0.5, unit: .kilograms)
    
    /// Large increment rounding for pounds (5 lb increments, useful for lower body).
    public static let largePounds = LoadRoundingPolicy(increment: 5.0, unit: .pounds)
    
    /// Large increment rounding for kilograms (2.5 kg increments).
    public static let largeKilograms = LoadRoundingPolicy(increment: 2.5, unit: .kilograms)
    
    /// Rounds the given load according to this policy.
    public func round(_ load: Load) -> Load {
        let converted = load.converted(to: unit)
        let roundedValue: Double
        
        switch mode {
        case .nearest:
            roundedValue = (converted.value / increment).rounded() * increment
        case .up:
            roundedValue = (converted.value / increment).rounded(.up) * increment
        case .down:
            roundedValue = (converted.value / increment).rounded(.down) * increment
        }
        
        // Return the rounded value in the policy's unit.
        // The rounding policy represents the gym/plan's execution unit, and downstream code
        // expects `targetLoad.unit == policy.unit` for consistency (especially when plans switch units).
        return Load(value: max(0, roundedValue), unit: unit)
    }
}

extension Load: CustomStringConvertible {
    public var description: String {
        let formatted = value.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f", value)
            : String(format: "%.1f", value)
        return "\(formatted) \(unit.rawValue)"
    }
}
