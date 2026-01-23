// DeloadPolicy.swift
// Deload triggers and application rules.
// Transparent, deterministic deload decisions.

import Foundation

/// Result of deload evaluation.
public struct DeloadDecision: Sendable, Hashable {
    /// Whether a deload should be applied.
    public let shouldDeload: Bool
    
    /// Reason for the deload (if any).
    public let reason: DeloadReason?
    
    /// Detailed explanation.
    public let explanation: String
    
    /// Triggered rules.
    public let triggeredRules: [DeloadTriggerResult]
    
    public init(
        shouldDeload: Bool,
        reason: DeloadReason?,
        explanation: String,
        triggeredRules: [DeloadTriggerResult] = []
    ) {
        self.shouldDeload = shouldDeload
        self.reason = reason
        self.explanation = explanation
        self.triggeredRules = triggeredRules
    }
    
    /// No deload needed.
    public static let noDeload = DeloadDecision(
        shouldDeload: false,
        reason: nil,
        explanation: "No deload triggers met"
    )
}

/// Result of a single deload trigger evaluation.
public struct DeloadTriggerResult: Sendable, Hashable {
    public let trigger: DeloadTrigger
    public let triggered: Bool
    public let details: String
    
    public init(trigger: DeloadTrigger, triggered: Bool, details: String) {
        self.trigger = trigger
        self.triggered = triggered
        self.details = details
    }
}

/// Types of deload triggers.
public enum DeloadTrigger: String, Codable, Sendable, Hashable {
    case performanceDecline = "performance_decline"
    case lowReadiness = "low_readiness"
    case scheduledDeload = "scheduled_deload"
    case highFatigue = "high_fatigue"
}

/// Deload policy implementation.
/// Evaluates multiple triggers and returns a deterministic decision.
public enum DeloadPolicy {
    
    /// Evaluates all deload triggers and returns a decision.
    public static func evaluate(
        userProfile: UserProfile,
        plan: TrainingPlan,
        history: WorkoutHistory,
        readiness: Int,
        date: Date,
        calendar: Calendar = .current
    ) -> DeloadDecision {
        guard let config = plan.deloadConfig else {
            return .noDeload
        }
        
        var triggeredRules: [DeloadTriggerResult] = []
        var shouldDeload = false
        var primaryReason: DeloadReason?
        var explanations: [String] = []
        
        // 1. Check scheduled deload
        let scheduledResult = evaluateScheduledDeload(
            config: config,
            history: history,
            date: date,
            calendar: calendar
        )
        triggeredRules.append(scheduledResult)
        if scheduledResult.triggered {
            shouldDeload = true
            primaryReason = .scheduledDeload
            explanations.append(scheduledResult.details)
        }
        
        // 2. Check performance decline (multi-session trend)
        let performanceResult = evaluatePerformanceDecline(
            userProfile: userProfile,
            plan: plan,
            history: history,
            date: date,
            calendar: calendar
        )
        triggeredRules.append(performanceResult)
        if performanceResult.triggered {
            shouldDeload = true
            if primaryReason == nil { primaryReason = .performanceDecline }
            explanations.append(performanceResult.details)
        }
        
        // 3. Check low readiness
        let readinessResult = evaluateLowReadiness(
            config: config,
            history: history,
            currentReadiness: readiness,
            date: date,
            calendar: calendar
        )
        triggeredRules.append(readinessResult)
        if readinessResult.triggered {
            shouldDeload = true
            if primaryReason == nil { primaryReason = .lowReadiness }
            explanations.append(readinessResult.details)
        }
        
        // 4. Check high fatigue (low readiness + high volume)
        let fatigueResult = evaluateHighFatigue(
            config: config,
            history: history,
            currentReadiness: readiness,
            userProfile: userProfile,
            date: date,
            calendar: calendar
        )
        triggeredRules.append(fatigueResult)
        if fatigueResult.triggered {
            shouldDeload = true
            if primaryReason == nil { primaryReason = .highAccumulatedFatigue }
            explanations.append(fatigueResult.details)
        }
        
        let explanation = explanations.isEmpty
            ? "No deload triggers met"
            : explanations.joined(separator: "; ")
        
        return DeloadDecision(
            shouldDeload: shouldDeload,
            reason: primaryReason,
            explanation: explanation,
            triggeredRules: triggeredRules
        )
    }
    
    // MARK: - Individual Trigger Evaluations
    
    /// Evaluates scheduled deload trigger.
    private static func evaluateScheduledDeload(
        config: DeloadConfig,
        history: WorkoutHistory,
        date: Date,
        calendar: Calendar
    ) -> DeloadTriggerResult {
        guard let scheduleWeeks = config.scheduledDeloadWeeks else {
            return DeloadTriggerResult(
                trigger: .scheduledDeload,
                triggered: false,
                details: "No scheduled deload configured"
            )
        }
        
        // Find last deload date across all exercises
        let lastDeloadDate = history.liftStates.values
            .compactMap(\.lastDeloadDate)
            .max()
        
        guard let lastDeload = lastDeloadDate else {
            // Never deloaded - check if enough time has passed since first session
            guard let firstSession = history.sessions.last else {
                return DeloadTriggerResult(
                    trigger: .scheduledDeload,
                    triggered: false,
                    details: "No training history"
                )
            }
            
            let weeksSinceStart = calendar.dateComponents([.weekOfYear], from: firstSession.date, to: date).weekOfYear ?? 0
            let triggered = weeksSinceStart >= scheduleWeeks
            
            return DeloadTriggerResult(
                trigger: .scheduledDeload,
                triggered: triggered,
                details: triggered
                    ? "Scheduled deload: \(weeksSinceStart) weeks since training start (threshold: \(scheduleWeeks))"
                    : "\(weeksSinceStart) weeks since start, deload at \(scheduleWeeks)"
            )
        }
        
        let weeksSinceDeload = calendar.dateComponents([.weekOfYear], from: lastDeload, to: date).weekOfYear ?? 0
        let triggered = weeksSinceDeload >= scheduleWeeks
        
        return DeloadTriggerResult(
            trigger: .scheduledDeload,
            triggered: triggered,
            details: triggered
                ? "Scheduled deload: \(weeksSinceDeload) weeks since last deload (threshold: \(scheduleWeeks))"
                : "\(weeksSinceDeload) weeks since last deload, deload at \(scheduleWeeks)"
        )
    }
    
    /// Evaluates performance decline trigger (multi-session trend).
    private static func evaluatePerformanceDecline(
        userProfile: UserProfile,
        plan: TrainingPlan,
        history: WorkoutHistory,
        date: Date,
        calendar: Calendar
    ) -> DeloadTriggerResult {
        // IMPORTANT: Use session history (not LiftState.e1rmHistory) and ignore deload sessions.
        //
        // Why:
        // - Deload sessions intentionally reduce load and can reduce e1RM; counting them can create
        //   a deload feedback loop (deload → lower e1RM → "decline" → deload again).
        // - Session history allows unit-normalized comparisons (kg) even across lb↔kg user switches.
        //
        // Additionally, require a meaningful decline (not just tiny day-to-day noise).
        let minRelativeDropPerSession = 0.01   // 1%
        let minAbsoluteDropKg = 1.0            // avoid triggering on tiny swings at low loads
        
        // Advanced lifters often see 1–2 week "flat" periods and small day-to-day noise.
        // Require a longer decline chain before recommending a deload for advanced/elite users.
        let requiredSamples: Int = {
            switch userProfile.experience {
            case .advanced, .elite:
                return 4 // 3 consecutive declines
            case .beginner, .intermediate:
                return 3 // 2 consecutive declines
            }
        }()
        
        func prescriptionsComparable(_ a: SetPrescription, _ b: SetPrescription) -> Bool {
            // Treat technique/protocol changes as non-comparable signals:
            // changes in rep range, set count, tempo, rest, or load strategy can shift performance
            // without reflecting true strength changes.
            if a.loadStrategy != b.loadStrategy { return false }
            if a.setCount != b.setCount { return false }
            if a.targetRepsRange != b.targetRepsRange { return false }
            if a.targetRIR != b.targetRIR { return false }
            if a.tempo != b.tempo { return false }
            if abs(a.restSeconds - b.restSeconds) > 15 { return false }
            return true
        }
        
        // Only evaluate decline on compound, externally-loaded lifts that are part of the current plan.
        var exerciseById: [String: Exercise] = [:]
        exerciseById.reserveCapacity(plan.templates.count * 6)
        for template in plan.templates.values {
            for te in template.exercises {
                exerciseById[te.exercise.id] = te.exercise
            }
        }
        for ex in plan.substitutionPool {
            exerciseById[ex.id] = ex
        }
        
        let candidateExercises: [Exercise] = exerciseById.values.filter { ex in
            ex.movementPattern.isCompound && ex.equipment != .bodyweight
        }
        
        if candidateExercises.isEmpty {
            return DeloadTriggerResult(
                trigger: .performanceDecline,
                triggered: false,
                details: "No compound loaded lifts in plan to evaluate performance decline"
            )
        }
        
        let candidatePatternCount = Set(candidateExercises.map(\.movementPattern)).count
        
        // If we've deloaded recently, do not keep triggering "performance decline" off pre-deload data.
        // Only evaluate decline on sessions *after* the most recent deload session (and before `date`).
        let evaluationDay = calendar.startOfDay(for: date)
        let mostRecentDeloadDate: Date? = history.sessions
            .filter { $0.wasDeload }
            .map(\.date)
            .filter { calendar.startOfDay(for: $0) <= evaluationDay }
            .max()
        
        var decliningExercises: [String] = []
        decliningExercises.reserveCapacity(min(6, candidateExercises.count))
        var decliningPatterns: Set<MovementPattern> = []
        decliningPatterns.reserveCapacity(min(4, candidatePatternCount))
        
        for ex in candidateExercises {
            let exerciseId = ex.id
            
            // Get last N non-deload e1RM samples from sessions (most recent first),
            // but only when prescriptions are comparable (same rep range / tempo / rest / etc.).
            var recentKg: [Double] = []
            recentKg.reserveCapacity(requiredSamples)
            var baselinePrescription: SetPrescription?
            
            for session in history.sessions {
                // Ignore future sessions (dirty history) and ignore anything on/before the most recent deload.
                let sessionDay = calendar.startOfDay(for: session.date)
                if sessionDay > evaluationDay { continue }
                if let cutoff = mostRecentDeloadDate, sessionDay <= calendar.startOfDay(for: cutoff) { continue }
                
                guard session.wasDeload == false else { continue }
                guard let exResult = session.exerciseResults.first(where: { $0.exerciseId == exerciseId }) else { continue }
                
                if let baseline = baselinePrescription {
                    guard prescriptionsComparable(exResult.prescription, baseline) else { continue }
                } else {
                    baselinePrescription = exResult.prescription
                }
                
                let bestKg = exResult.workingSets
                    .map { set in
                        E1RMCalculator.brzycki(weight: set.load.inKilograms, reps: set.reps)
                    }
                    .max() ?? 0
                
                if bestKg > 0 {
                    recentKg.append(bestKg)
                    if recentKg.count == requiredSamples { break }
                }
            }
            
            guard recentKg.count == requiredSamples else { continue }
            
            // recentKg is most-recent-first.
            // For 3 samples: [newest, middle, oldest] -> require oldest > middle > newest
            // For 4 samples: [newest, s2, s3, oldest] -> require oldest > s3 > s2 > newest
            let newest = recentKg[0]
            let second = recentKg[1]
            let third = recentKg[2]
            
            let triggeredForThisExercise: Bool = {
                if requiredSamples == 3 {
                    let oldest = third
                    let middle = second
                    
                    let drop1 = oldest - middle
                    let drop2 = middle - newest
                    
                    let requiredDrop1 = max(oldest * minRelativeDropPerSession, minAbsoluteDropKg)
                    let requiredDrop2 = max(middle * minRelativeDropPerSession, minAbsoluteDropKg)
                    
                    return drop1 >= requiredDrop1 && drop2 >= requiredDrop2
                } else {
                    let oldest = recentKg[3]
                    
                    let drop1 = oldest - third
                    let drop2 = third - second
                    let drop3 = second - newest
                    
                    let requiredDrop1 = max(oldest * minRelativeDropPerSession, minAbsoluteDropKg)
                    let requiredDrop2 = max(third * minRelativeDropPerSession, minAbsoluteDropKg)
                    let requiredDrop3 = max(second * minRelativeDropPerSession, minAbsoluteDropKg)
                    
                    return drop1 >= requiredDrop1 && drop2 >= requiredDrop2 && drop3 >= requiredDrop3
                }
            }()
            
            if triggeredForThisExercise {
                decliningExercises.append(exerciseId)
                decliningPatterns.insert(ex.movementPattern)
            }
        }
        
        let triggered: Bool = {
            // Deloads are systemic: require decline across multiple compound patterns when possible.
            //
            // If the plan only contains a single compound pattern (e.g., a squat-only test plan),
            // fall back to "any decline" so we can still validate behavior in narrow test fixtures.
            if candidatePatternCount >= 2 {
                return decliningPatterns.count >= 2
            }
            
            // Single-pattern plans: any meaningful decline can trigger.
            return !decliningPatterns.isEmpty
        }()
        let details: String
        if triggered {
            let patterns = decliningPatterns
                .map(\.rawValue)
                .sorted()
                .joined(separator: ", ")
            details = "Performance decline in \(decliningExercises.count) compound lift(s): \(requiredSamples - 1)-session e1RM decline (comparable prescriptions). Patterns: [\(patterns)]"
        } else {
            details = mostRecentDeloadDate == nil
                ? "No performance decline detected"
                : "No performance decline detected (evaluating post-deload only)"
        }
        
        return DeloadTriggerResult(
            trigger: .performanceDecline,
            triggered: triggered,
            details: details
        )
    }
    
    /// Evaluates low readiness trigger.
    private static func evaluateLowReadiness(
        config: DeloadConfig,
        history: WorkoutHistory,
        currentReadiness: Int,
        date: Date,
        calendar: Calendar
    ) -> DeloadTriggerResult {
        let threshold = config.readinessThreshold
        let requiredDays = config.lowReadinessDaysRequired
        
        // We treat `currentReadiness` as "today's" readiness and count prior consecutive low days
        // from readinessHistory. This avoids requiring readinessHistory to contain today's record.
        let today = calendar.startOfDay(for: date)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)
        let priorConsecutiveLowDays: Int = {
            guard let yesterday else { return 0 }
            return history.consecutiveLowReadinessDays(threshold: threshold, from: yesterday, calendar: calendar)
        }()
        
        let currentlyLow = currentReadiness < threshold
        let totalLowDays = (currentlyLow ? 1 : 0) + priorConsecutiveLowDays
        
        let triggered = totalLowDays >= requiredDays
        
        return DeloadTriggerResult(
            trigger: .lowReadiness,
            triggered: triggered,
            details: triggered
                ? "Low readiness for \(totalLowDays) consecutive days (threshold: \(requiredDays) days below \(threshold))"
                : "Readiness OK: \(totalLowDays) low days (need \(requiredDays) for trigger)"
        )
    }
    
    /// Evaluates high fatigue trigger (low readiness + high accumulated volume).
    private static func evaluateHighFatigue(
        config: DeloadConfig,
        history: WorkoutHistory,
        currentReadiness: Int,
        userProfile: UserProfile,
        date: Date,
        calendar: Calendar
    ) -> DeloadTriggerResult {
        let threshold = config.readinessThreshold
        
        // Must have low readiness
        guard currentReadiness < threshold else {
            return DeloadTriggerResult(
                trigger: .highFatigue,
                triggered: false,
                details: "Readiness (\(currentReadiness)) above fatigue threshold (\(threshold))"
            )
        }
        
        // Compare recent volume to baseline.
        // If baseline data coverage is too sparse, treat as insufficient baseline and do not trigger.
        let minBaselineCoverageDays = 14
        let baselineWindowDays = 28
        let endDay = calendar.startOfDay(for: date)
        let startDay = calendar.date(byAdding: .day, value: -(baselineWindowDays - 1), to: endDay) ?? endDay
        
        var baselineDayKeys: Set<Date> = []
        baselineDayKeys.reserveCapacity(min(baselineWindowDays, history.recentVolumeByDate.count))
        for key in history.recentVolumeByDate.keys {
            let d = calendar.startOfDay(for: key)
            if d >= startDay && d <= endDay {
                baselineDayKeys.insert(d)
            }
        }
        
        if baselineDayKeys.count < minBaselineCoverageDays {
            return DeloadTriggerResult(
                trigger: .highFatigue,
                triggered: false,
                details: "Fatigue check: insufficient baseline coverage (\(baselineDayKeys.count)/\(baselineWindowDays) days)"
            )
        }
        
        let recentVolume = history.totalVolume(lastDays: 7, from: date, calendar: calendar)
        let baselineVolume = history.averageDailyVolume(lastDays: 28, from: date, calendar: calendar) * 7
        
        // Trigger if recent volume is >120% of baseline
        // If baseline is missing/zero, we treat this as "insufficient baseline" and do not trigger.
        let volumeRatio = baselineVolume > 0 ? recentVolume / baselineVolume : 0.0
        let highVolume = volumeRatio > 1.20
        
        let triggered = highVolume // Already know readiness is low
        
        return DeloadTriggerResult(
            trigger: .highFatigue,
            triggered: triggered,
            details: triggered
                ? "High fatigue: readiness \(currentReadiness) with volume at \(Int(volumeRatio * 100))% of baseline"
                : (baselineVolume > 0
                    ? "Fatigue check: volume at \(Int(volumeRatio * 100))% of baseline"
                    : "Fatigue check: insufficient baseline volume")
        )
    }
    
    // MARK: - Deload Application
    
    /// Applies deload modifications to a session plan.
    public static func applyDeload(
        config: DeloadConfig,
        exercisePlan: ExercisePlan
    ) -> ExercisePlan {
        // Reduce load by intensity reduction percentage
        let loadFactor = 1.0 - config.intensityReduction
        
        // Reduce set count by volume reduction
        let originalSetCount = exercisePlan.sets.count
        let newSetCount = max(1, originalSetCount - config.volumeReduction)
        
        // Create modified sets
        let modifiedSets: [SetPlan] = exercisePlan.sets
            .prefix(newSetCount)
            .map { originalSet in
                var modified = originalSet
                modified.targetLoad = originalSet.targetLoad * loadFactor
                return modified
            }
        
        return ExercisePlan(
            exercise: exercisePlan.exercise,
            prescription: exercisePlan.prescription,
            sets: modifiedSets,
            progressionPolicy: exercisePlan.progressionPolicy,
            inSessionPolicy: exercisePlan.inSessionPolicy,
            substitutions: exercisePlan.substitutions
        )
    }
    
    /// Computes recommended deload duration based on triggers.
    public static func recommendedDeloadDuration(
        decision: DeloadDecision,
        userProfile: UserProfile
    ) -> Int {
        // Base duration on experience and trigger type
        let baseDays: Int
        
        switch decision.reason {
        case .performanceDecline:
            baseDays = 5
        case .highAccumulatedFatigue:
            baseDays = 7
        case .lowReadiness:
            baseDays = 5
        case .scheduledDeload:
            baseDays = 7
        case .userRequested, .none:
            baseDays = 5
        }
        
        // Adjust for experience level
        switch userProfile.experience {
        case .beginner:
            return baseDays - 2
        case .intermediate:
            return baseDays
        case .advanced, .elite:
            return baseDays + 2
        }
    }
}
