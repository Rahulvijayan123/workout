// FailureThresholdConfig.swift
// Centralized defaults for failure thresholds and deload configuration.

import Foundation

/// Centralized configuration for failure thresholds and deload behavior.
/// This provides a single source of truth for default values used across progression policies.
public enum FailureThresholdDefaults {
    /// Default number of consecutive failures before triggering a deload.
    /// Used by both DoubleProgressionConfig and LinearProgressionConfig.
    public static let failuresBeforeDeload: Int = 2
    
    /// Default percentage to reduce load during deload (e.g., 0.10 = 10% reduction).
    /// This is subtracted from 1.0 to get the remaining load factor.
    public static let deloadPercentage: Double = 0.10
    
    /// Default deload factor as a multiplier (e.g., 0.9 means reduce to 90% of current load).
    /// This is the complement of `deloadPercentage`: 1.0 - deloadPercentage.
    public static var deloadFactor: Double {
        1.0 - deloadPercentage
    }
    
    /// Minimum allowed deload percentage (5%).
    public static let minimumDeloadPercentage: Double = 0.05
    
    /// Maximum allowed deload percentage (20%).
    public static let maximumDeloadPercentage: Double = 0.20
    
    /// Minimum failures before deload (must be at least 1).
    public static let minimumFailuresBeforeDeload: Int = 1
    
    // MARK: - Conversion Helpers
    
    /// Converts a deload factor (e.g., 0.9) to a deload percentage (e.g., 0.10).
    /// - Parameter factor: The multiplier applied to load during deload (0.8 to 0.95).
    /// - Returns: The percentage reduction (0.05 to 0.20).
    public static func deloadPercentage(fromFactor factor: Double) -> Double {
        let percentage = 1.0 - factor
        return max(minimumDeloadPercentage, min(maximumDeloadPercentage, percentage))
    }
    
    /// Converts a deload percentage (e.g., 0.10) to a deload factor (e.g., 0.9).
    /// - Parameter percentage: The percentage reduction (0.05 to 0.20).
    /// - Returns: The multiplier applied to load during deload (0.8 to 0.95).
    public static func deloadFactor(fromPercentage percentage: Double) -> Double {
        let clampedPercentage = max(minimumDeloadPercentage, min(maximumDeloadPercentage, percentage))
        return 1.0 - clampedPercentage
    }
    
    /// Validates and clamps a failure threshold to valid range.
    /// - Parameter value: The proposed failure threshold.
    /// - Returns: A valid failure threshold (at least 1).
    public static func clampedFailureThreshold(_ value: Int) -> Int {
        max(minimumFailuresBeforeDeload, value)
    }
    
    /// Validates and clamps a deload percentage to valid range.
    /// - Parameter value: The proposed deload percentage.
    /// - Returns: A valid deload percentage (0.05 to 0.20).
    public static func clampedDeloadPercentage(_ value: Double) -> Double {
        max(minimumDeloadPercentage, min(maximumDeloadPercentage, value))
    }
}
