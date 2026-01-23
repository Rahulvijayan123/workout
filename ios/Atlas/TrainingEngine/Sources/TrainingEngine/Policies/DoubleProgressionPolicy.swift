// DoubleProgressionPolicy.swift
// Double progression: add reps until top of range, then add load and reset reps.
// Inspired by Liftosaur's `dp` built-in progression mode.

import Foundation

/// Configuration for double progression.
public struct DoubleProgressionConfig: Codable, Sendable, Hashable {
    /// Number of sessions at top of rep range before increasing load.
    public let sessionsAtTopBeforeIncrease: Int
    
    /// Load increment when progressing.
    public let loadIncrement: Load
    
    /// Percentage to deload on failure.
    public let deloadPercentage: Double
    
    /// Number of consecutive failures before triggering deload.
    public let failuresBeforeDeload: Int
    
    public init(
        sessionsAtTopBeforeIncrease: Int = 1,
        loadIncrement: Load = .pounds(5),
        deloadPercentage: Double = FailureThresholdDefaults.deloadPercentage,
        failuresBeforeDeload: Int = FailureThresholdDefaults.failuresBeforeDeload
    ) {
        self.sessionsAtTopBeforeIncrease = max(1, sessionsAtTopBeforeIncrease)
        self.loadIncrement = loadIncrement
        self.deloadPercentage = FailureThresholdDefaults.clampedDeloadPercentage(deloadPercentage)
        self.failuresBeforeDeload = FailureThresholdDefaults.clampedFailureThreshold(failuresBeforeDeload)
    }
    
    /// Default configuration for general training.
    public static let `default` = DoubleProgressionConfig()
    
    /// Configuration optimized for hypertrophy.
    public static let hypertrophy = DoubleProgressionConfig(
        sessionsAtTopBeforeIncrease: 1,
        loadIncrement: .pounds(5),
        deloadPercentage: FailureThresholdDefaults.deloadPercentage,
        failuresBeforeDeload: FailureThresholdDefaults.failuresBeforeDeload
    )
    
    /// Configuration for smaller increments (isolation exercises).
    public static let smallIncrement = DoubleProgressionConfig(
        sessionsAtTopBeforeIncrease: 1,
        loadIncrement: .pounds(2.5),
        deloadPercentage: FailureThresholdDefaults.deloadPercentage,
        failuresBeforeDeload: 3
    )
}

/// Double progression policy implementation.
/// 
/// Algorithm (inspired by Liftosaur):
/// 1. If all sets hit top of rep range → increase load, reset to lower bound
/// 2. If all sets hit at least lower bound → target +1 rep next session
/// 3. If below lower bound → count as failure, deload after N failures
public enum DoubleProgressionPolicy {
    
    /// Computes the next session's target load.
    public static func computeNextLoad(
        config: DoubleProgressionConfig,
        prescription: SetPrescription,
        liftState: LiftState,
        history: WorkoutHistory,
        exerciseId: String,
        context: ProgressionContext? = nil
    ) -> Load {
        // Get last session results for this exercise
        guard let lastResult = history.exerciseResults(forExercise: exerciseId, limit: 1).first else {
            // No history, use last working weight or start fresh
            return liftState.lastWorkingWeight.value > 0
                ? liftState.lastWorkingWeight
                : Load(value: 0, unit: prescription.increment.unit)
        }
        
        let workingSets = lastResult.workingSets
        guard !workingSets.isEmpty else {
            return liftState.lastWorkingWeight
        }
        
        let repRange = prescription.targetRepsRange
        let lowerBound = repRange.lowerBound
        let upperBound = repRange.upperBound
        
        // Get reps from each working set
        let reps = workingSets.map(\.reps)
        
        // Current load (average of working sets)
        let avgLoad = workingSets.map(\.load.value).reduce(0, +) / Double(workingSets.count)
        var currentLoad = Load(value: avgLoad, unit: liftState.lastWorkingWeight.unit)
        
        // Guardrail: if the last logged session load is very likely a kg↔lb entry mistake,
        // do NOT let that nuke the next prescription. In those cases, prefer the persistent
        // `liftState.lastWorkingWeight` baseline (which is already protected in updateLiftState).
        if liftState.lastWorkingWeight.value > 0, currentLoad.value > 0 {
            let ratio = currentLoad.value / liftState.lastWorkingWeight.value
            let kgToLb = 2.20462
            let lbToKg = 0.453592
            if abs(ratio - lbToKg) < 0.08 || abs(ratio - kgToLb) < 0.25 {
                currentLoad = liftState.lastWorkingWeight
            }
        }
        
        // Check conditions
        let allAtOrAboveUpper = reps.allSatisfy { $0 >= upperBound }
        let allAtOrAboveLower = reps.allSatisfy { $0 >= lowerBound }
        
        if allAtOrAboveUpper {
            // All sets hit top of range.
            // Optional: require N consecutive "top" sessions before increasing load.
            if config.sessionsAtTopBeforeIncrease <= 1 {
                return currentLoad + adaptiveIncrement(
                    config: config,
                    prescription: prescription,
                    currentLoad: currentLoad,
                    lastResult: lastResult,
                    liftState: liftState,
                    history: history,
                    exerciseId: exerciseId,
                    context: context
                )
            }
            
            let recent = history.exerciseResults(forExercise: exerciseId, limit: config.sessionsAtTopBeforeIncrease)
            let consecutiveTopCount = recent.prefix { result in
                let ws = result.workingSets
                guard !ws.isEmpty else { return false }
                let r = ws.map(\.reps)
                return r.allSatisfy { $0 >= upperBound }
            }.count
            
            if consecutiveTopCount >= config.sessionsAtTopBeforeIncrease {
                return currentLoad + adaptiveIncrement(
                    config: config,
                    prescription: prescription,
                    currentLoad: currentLoad,
                    lastResult: lastResult,
                    liftState: liftState,
                    history: history,
                    exerciseId: exerciseId,
                    context: context
                )
            } else {
                return currentLoad
            }
        }
        
        if allAtOrAboveLower {
            // All sets within range → maintain load (reps will increase)
            return currentLoad
        }
        
        // Below lower bound - check failure count.
        // For advanced/strong lifters, occasional misses are normal; we adapt the "when" and "how much"
        // so we don't spiral into repeated 10% drops.
        let missDepth = max(0, lowerBound - (reps.min() ?? lowerBound))
        let (effectiveFailuresBeforeDeload, effectiveDeloadPct) = adaptiveFailureDeloadPolicy(
            config: config,
            prescription: prescription,
            currentLoad: currentLoad,
            lastResult: lastResult,
            liftState: liftState,
            history: history,
            exerciseId: exerciseId,
            missDepth: missDepth,
            context: context
        )
        
        if liftState.failureCount >= effectiveFailuresBeforeDeload {
            let deloadedValue = currentLoad.value * (1.0 - effectiveDeloadPct)
            return Load(value: max(0, deloadedValue), unit: currentLoad.unit)
        }
        
        // Not enough failures yet, maintain load
        return currentLoad
    }

    // MARK: - Adaptive increments (training age / strength level)
    
    private static func adaptiveIncrement(
        config: DoubleProgressionConfig,
        prescription: SetPrescription,
        currentLoad: Load,
        lastResult: ExerciseSessionResult,
        liftState: LiftState,
        history: WorkoutHistory,
        exerciseId: String,
        context: ProgressionContext?
    ) -> Load {
        // Default behavior (source-compatible): fixed increments.
        guard let context else { return config.loadIncrement }
        guard context.exercise.equipment != .bodyweight else { return .zero }
        
        let unit = currentLoad.unit
        let maxIncrement = config.loadIncrement.converted(to: unit).value
        guard maxIncrement > 0 else { return config.loadIncrement }
        
        let step = minimumIncrementStep(for: context.exercise, unit: unit, maxIncrement: maxIncrement)
        
        // Estimate strength for scaling.
        let estimatedE1RM: Double = {
            if liftState.rollingE1RM > 0 {
                return liftState.rollingE1RM
            }
            // Fallback: compute from last working sets (convert to current unit).
            let best = lastResult.workingSets
                .map { set -> Double in
                    let w = set.load.converted(to: unit).value
                    return E1RMCalculator.brzycki(weight: w, reps: set.reps)
                }
                .max() ?? 0
            if best > 0 { return best }
            // Conservative fallback if we truly have nothing.
            return max(1, currentLoad.value * 1.25)
        }()
        
        // Experience-based weekly progression expectation.
        let expectedWeeklyRate = max(0.0001, context.userProfile.experience.expectedProgressionRate)
        
        // Estimate how often this lift is trained (exposures/week) from recent history.
        let exposuresPerWeek = max(0.5, estimatedExposuresPerWeek(
            history: history,
            exerciseId: exerciseId,
            endingAt: context.date,
            calendar: context.calendar
        ))
        
        // Translate weekly expectation to per-exposure expectation.
        var targetPerExposureRate = expectedWeeklyRate / exposuresPerWeek
        
        // Strength-tier adjustment: as relative strength climbs, increments need to get smaller.
        let bodyWeight = context.userProfile.bodyWeight?.converted(to: unit).value
        targetPerExposureRate *= strengthScalingFactor(
            e1rm: estimatedE1RM,
            bodyWeight: bodyWeight,
            movement: context.exercise.movementPattern,
            unit: unit
        )
        
        // "Learning" adjustment: compare observed e1RM growth vs expected.
        targetPerExposureRate *= observedProgressionFactor(
            liftState: liftState,
            expectedWeeklyRate: expectedWeeklyRate,
            calendar: context.calendar
        )
        
        // Small boost for newer lifters so 135→225 doesn't feel glacial.
        switch context.userProfile.experience {
        case .beginner:
            targetPerExposureRate *= 1.8
        case .intermediate:
            targetPerExposureRate *= 1.2
        case .advanced, .elite:
            targetPerExposureRate *= 1.0
        }
        
        // Convert rate into an absolute increment (in the exercise's unit).
        var inc = estimatedE1RM * targetPerExposureRate
        
        // Clamp to realistic, equipment-dependent steps.
        inc = min(maxIncrement, max(step, inc))
        inc = (inc / step).rounded() * step
        
        return Load(value: inc, unit: unit)
    }

    private static func adaptiveFailureDeloadPolicy(
        config: DoubleProgressionConfig,
        prescription: SetPrescription,
        currentLoad: Load,
        lastResult: ExerciseSessionResult,
        liftState: LiftState,
        history: WorkoutHistory,
        exerciseId: String,
        missDepth: Int,
        context: ProgressionContext?
    ) -> (failuresBeforeDeload: Int, deloadPercentage: Double) {
        var failuresBeforeDeload = max(1, config.failuresBeforeDeload)
        var deloadPct = FailureThresholdDefaults.clampedDeloadPercentage(config.deloadPercentage)
        
        guard let context else {
            return (failuresBeforeDeload, deloadPct)
        }
        
        // Only scale for compound, externally-loaded lifts (where repeated failures are common and recovery takes longer).
        let isCompound = context.exercise.movementPattern.isCompound
        let isExternalLoad = context.exercise.equipment != .bodyweight
        guard isCompound, isExternalLoad else {
            return (failuresBeforeDeload, deloadPct)
        }
        
        switch context.userProfile.experience {
        case .beginner:
            // Keep defaults (fast linear-ish adaptation).
            break
        case .intermediate:
            // Slightly more forgiving: 2 misses might just be a bad day.
            failuresBeforeDeload = max(failuresBeforeDeload, 2)
            deloadPct = min(deloadPct, 0.10)
        case .advanced, .elite:
            // More forgiving and smaller deloads (micro-adjust, don’t cliff-drop).
            failuresBeforeDeload = max(failuresBeforeDeload, 3)
            deloadPct = min(deloadPct, 0.07)
        }
        
        // Miss severity: a 1-rep miss shouldn't trigger a huge reset.
        if missDepth <= 1 {
            deloadPct = min(deloadPct, 0.05)
        } else if missDepth == 2 {
            deloadPct = min(deloadPct, 0.075)
        }
        
        // Floor/cap for safety.
        deloadPct = max(0.02, min(0.20, deloadPct))
        
        return (failuresBeforeDeload, deloadPct)
    }
    
    private static func minimumIncrementStep(for exercise: Exercise, unit: LoadUnit, maxIncrement: Double) -> Double {
        // If the template/config already uses a smaller increment, respect it.
        if maxIncrement <= 0 { return unit.standardIncrements.first ?? 1.0 }
        
        switch (unit, exercise.equipment) {
        case (.pounds, .barbell), (.pounds, .ezBar), (.pounds, .trapBar):
            return min(2.5, maxIncrement)
        case (.kilograms, .barbell), (.kilograms, .ezBar), (.kilograms, .trapBar):
            return min(1.25, maxIncrement)
        case (.pounds, .dumbbell), (.pounds, .kettlebell), (.pounds, .machine), (.pounds, .cable), (.pounds, .smithMachine), (.pounds, .plateLoaded):
            return min(5.0, maxIncrement)
        case (.kilograms, .dumbbell), (.kilograms, .kettlebell), (.kilograms, .machine), (.kilograms, .cable), (.kilograms, .smithMachine), (.kilograms, .plateLoaded):
            return min(2.5, maxIncrement)
        default:
            return min(unit.standardIncrements.first ?? 1.0, maxIncrement)
        }
    }
    
    private static func estimatedExposuresPerWeek(
        history: WorkoutHistory,
        exerciseId: String,
        endingAt date: Date,
        calendar: Calendar
    ) -> Double {
        let endDay = calendar.startOfDay(for: date)
        let startDay = calendar.date(byAdding: .day, value: -27, to: endDay) ?? endDay
        
        let exposures28 = history.sessions.filter { session in
            let d = calendar.startOfDay(for: session.date)
            guard d >= startDay && d <= endDay else { return false }
            guard session.wasDeload == false else { return false }
            return session.exerciseResults.contains(where: { $0.exerciseId == exerciseId })
        }.count
        
        // 28 days ≈ 4 weeks
        return Double(exposures28) / 4.0
    }
    
    private static func strengthScalingFactor(
        e1rm: Double,
        bodyWeight: Double?,
        movement: MovementPattern,
        unit: LoadUnit
    ) -> Double {
        // If we have bodyweight, use relative strength; otherwise fallback to absolute e1RM thresholds.
        if let bodyWeight, bodyWeight > 0 {
            let ratio = e1rm / bodyWeight
            switch movement {
            case .horizontalPush, .verticalPush:
                // Bench/press: ~1.0 BW is intermediate, ~1.5 BW is advanced.
                if ratio >= 1.75 { return 0.60 }
                if ratio >= 1.25 { return 0.80 }
                return 1.00
            case .squat:
                if ratio >= 2.50 { return 0.60 }
                if ratio >= 2.00 { return 0.80 }
                return 1.00
            case .hipHinge:
                if ratio >= 2.75 { return 0.60 }
                if ratio >= 2.25 { return 0.80 }
                return 1.00
            default:
                // Accessories: keep stable
                if ratio >= 1.75 { return 0.80 }
                return 1.00
            }
        }
        
        // Absolute fallback (lb or kg). Conservative thresholds.
        let e1rmLb = (unit == .pounds) ? e1rm : Load(value: e1rm, unit: .kilograms).converted(to: .pounds).value
        
        switch movement {
        case .horizontalPush, .verticalPush:
            if e1rmLb >= 315 { return 0.55 }
            if e1rmLb >= 225 { return 0.75 }
            return 1.00
        case .squat:
            if e1rmLb >= 405 { return 0.55 }
            if e1rmLb >= 315 { return 0.75 }
            return 1.00
        case .hipHinge:
            if e1rmLb >= 495 { return 0.55 }
            if e1rmLb >= 405 { return 0.75 }
            return 1.00
        default:
            return 1.00
        }
    }
    
    private static func observedProgressionFactor(
        liftState: LiftState,
        expectedWeeklyRate: Double,
        calendar: Calendar
    ) -> Double {
        // Use recent e1RM history to detect "faster than expected" vs "stalling" lifters.
        let samples = liftState.e1rmHistory
        guard samples.count >= 4 else { return 1.0 }
        
        let recent = Array(samples.suffix(6))
        guard let oldest = recent.first, let newest = recent.last else { return 1.0 }
        
        let old = oldest.value
        let new = newest.value
        guard old > 0, new > 0 else { return 1.0 }
        
        let days = max(1, calendar.dateComponents([.day], from: oldest.date, to: newest.date).day ?? 1)
        let weeks = Double(days) / 7.0
        guard weeks > 0 else { return 1.0 }
        
        let observedWeeklyRate = ((new - old) / old) / weeks
        guard expectedWeeklyRate > 0 else { return 1.0 }
        
        let ratio = observedWeeklyRate / expectedWeeklyRate
        // Clamp to avoid runaway.
        return max(0.6, min(1.4, ratio.isFinite ? ratio : 1.0))
    }
    
    /// Determines target reps for the next session.
    public static func computeTargetReps(
        config: DoubleProgressionConfig,
        prescription: SetPrescription,
        history: WorkoutHistory,
        exerciseId: String
    ) -> Int {
        guard let lastResult = history.exerciseResults(forExercise: exerciseId, limit: 1).first else {
            // No history, start at lower bound
            return prescription.targetRepsRange.lowerBound
        }
        
        let workingSets = lastResult.workingSets
        guard !workingSets.isEmpty else {
            return prescription.targetRepsRange.lowerBound
        }
        
        let repRange = prescription.targetRepsRange
        let reps = workingSets.map(\.reps)
        let minReps = reps.min() ?? repRange.lowerBound
        
        let allAtOrAboveUpper = reps.allSatisfy { $0 >= repRange.upperBound }
        let allAtOrAboveLower = reps.allSatisfy { $0 >= repRange.lowerBound }
        
        if allAtOrAboveUpper {
            // If we are going to increase load now, reset to lower bound.
            // Otherwise, stay at the upper bound until the required "top" streak is met.
            if config.sessionsAtTopBeforeIncrease <= 1 {
                return repRange.lowerBound
            }
            
            let recent = history.exerciseResults(forExercise: exerciseId, limit: config.sessionsAtTopBeforeIncrease)
            let consecutiveTopCount = recent.prefix { result in
                let ws = result.workingSets
                guard !ws.isEmpty else { return false }
                let r = ws.map(\.reps)
                return r.allSatisfy { $0 >= repRange.upperBound }
            }.count
            
            if consecutiveTopCount >= config.sessionsAtTopBeforeIncrease {
                return repRange.lowerBound
            } else {
                return repRange.upperBound
            }
        }
        
        if allAtOrAboveLower {
            // Progress reps by 1, capped at upper bound
            return min(repRange.upperBound, minReps + 1)
        }
        
        // Failed - target lower bound
        return repRange.lowerBound
    }
    
    /// Evaluates whether progression criteria are met.
    public static func evaluateProgression(
        config: DoubleProgressionConfig,
        prescription: SetPrescription,
        lastResult: ExerciseSessionResult
    ) -> ProgressionDecision {
        let workingSets = lastResult.workingSets
        guard !workingSets.isEmpty else {
            return .hold(reason: "No working sets completed")
        }
        
        let repRange = prescription.targetRepsRange
        let reps = workingSets.map(\.reps)
        
        let allAtOrAboveUpper = reps.allSatisfy { $0 >= repRange.upperBound }
        let allAtOrAboveLower = reps.allSatisfy { $0 >= repRange.lowerBound }
        
        if allAtOrAboveUpper {
            return .increaseLoad(
                amount: config.loadIncrement,
                reason: "All sets at or above \(repRange.upperBound) reps"
            )
        }
        
        if allAtOrAboveLower {
            let minReps = reps.min() ?? repRange.lowerBound
            let nextReps = min(repRange.upperBound, minReps + 1)
            return .increaseReps(
                target: nextReps,
                reason: "All sets within range, targeting \(nextReps) reps"
            )
        }
        
        return .failure(reason: "Below \(repRange.lowerBound) rep minimum")
    }
}

/// Result of progression evaluation.
public enum ProgressionDecision: Sendable, Hashable {
    case increaseLoad(amount: Load, reason: String)
    case increaseReps(target: Int, reason: String)
    case hold(reason: String)
    case failure(reason: String)
    case deload(amount: Load, reason: String)
}
