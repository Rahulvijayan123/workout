import Foundation
import TrainingEngine

/// Versioned config for deriving `TrainingEngine.ExecutionContext` from UI/session data.
///
/// Centralizing thresholds prevents silent drift when the pain scale or business rules change.
struct ExecutionContextConfig: Sendable, Hashable {
    /// Overall pain (0–10) at/above this threshold triggers `injuryDiscomfort`.
    var overallPainThreshold: Int
    
    /// Per-entry pain (0–10) at/above this threshold counts toward triggering `injuryDiscomfort`.
    var perEntryPainThreshold: Int
    
    /// A single per-entry pain at/above this threshold triggers `injuryDiscomfort` (even if only one entry).
    var severeEntryThreshold: Int
    
    /// Minimum number of pain entries at/above `perEntryPainThreshold` required to trigger `injuryDiscomfort`.
    var minEntriesAtOrAboveThreshold: Int
    
    static let v1 = ExecutionContextConfig(
        overallPainThreshold: 5,
        perEntryPainThreshold: 5,
        severeEntryThreshold: 7,
        minEntriesAtOrAboveThreshold: 2
    )
}

enum ExecutionContextEvaluator {
    static func compute(
        for performance: ExercisePerformance,
        config: ExecutionContextConfig = .v1
    ) -> TrainingEngine.ExecutionContext {
        // Explicit stop due to pain is the strongest signal.
        if performance.stoppedDueToPain {
            return .injuryDiscomfort
        }
        
        // Overall pain rating (quick entry).
        if let overall = performance.overallPainLevel, overall >= config.overallPainThreshold {
            return .injuryDiscomfort
        }
        
        // Per-region pain entries (more granular; can be noisy/sparse).
        let severities = (performance.painEntries ?? []).map(\.severity)
        if let maxSeverity = severities.max(), maxSeverity >= config.severeEntryThreshold {
            return .injuryDiscomfort
        }
        let atOrAbove = severities.filter { $0 >= config.perEntryPainThreshold }
        if atOrAbove.count >= max(1, config.minEntriesAtOrAboveThreshold) {
            return .injuryDiscomfort
        }
        
        return .normal
    }
}

