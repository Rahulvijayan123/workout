// TrainingEngine.swift
// Pure Swift module for deterministic workout progression, deload, and substitutions.

import Foundation

/// The main entry point for the Training Engine.
/// Provides deterministic session recommendations, in-session adjustments, and state updates.
/// Note: Named `Engine` (not `TrainingEngine`) to avoid shadowing the module name.
public enum Engine {
    
    /// Recommends a session plan for the given date based on user profile, plan, history, and readiness.
    ///
    /// - Parameters:
    ///   - date: The date for which to recommend a session.
    ///   - userProfile: The user's profile (sex, experience, goals, frequency).
    ///   - plan: The training plan (templates, schedule, progression policies).
    ///   - history: Recent workout history.
    ///   - readiness: Today's readiness score (0-100).
    /// - Returns: A `SessionPlan` with exercises, sets, target loads/reps, and substitutions.
    public static func recommendSession(
        date: Date,
        userProfile: UserProfile,
        plan: TrainingPlan,
        history: WorkoutHistory,
        readiness: Int,
        calendar: Calendar = .current
    ) -> SessionPlan {
        let scheduler = TemplateScheduler(plan: plan, history: history, calendar: calendar)
        guard let templateId = scheduler.selectTemplate(for: date) else {
            return SessionPlan(
                date: date,
                templateId: nil,
                exercises: [],
                isDeload: false,
                deloadReason: nil
            )
        }
        
        return recommendSessionForTemplate(
            date: date,
            templateId: templateId,
            userProfile: userProfile,
            plan: plan,
            history: history,
            readiness: readiness,
            excludingExerciseIds: [],
            calendar: calendar
        )
    }
    
    /// Recommends a session plan for a specific template. Useful for mid-session replanning (equipment changes),
    /// or when the caller wants to bypass schedule selection.
    public static func recommendSessionForTemplate(
        date: Date,
        templateId: WorkoutTemplateId,
        userProfile: UserProfile,
        plan: TrainingPlan,
        history: WorkoutHistory,
        readiness: Int,
        excludingExerciseIds: Set<String> = [],
        calendar: Calendar = .current
    ) -> SessionPlan {
        
        guard let template = plan.templates[templateId] else {
            return SessionPlan(
                date: date,
                templateId: templateId,
                exercises: [],
                isDeload: false,
                deloadReason: nil
            )
        }
        
        // Check deload triggers
        let deloadDecision = DeloadPolicy.evaluate(
            userProfile: userProfile,
            plan: plan,
            history: history,
            readiness: readiness,
            date: date,
            calendar: calendar
        )
        
        var exercisePlans: [ExercisePlan] = []
        var usedExerciseIds: Set<String> = []
        var insights: [CoachingInsight] = []
        
        // Original exercise IDs present in the template; used to avoid collisions where a substitute
        // would duplicate a different planned exercise.
        let reservedOriginalIds = Set(template.exercises.map(\.exercise.id))
        
        // Lookup table for quickly mapping an exerciseId back to its Exercise metadata.
        // Used for "return to original after equipment outage" rebasing.
        let exerciseById: [String: Exercise] = {
            var m: [String: Exercise] = [:]
            m.reserveCapacity(plan.substitutionPool.count + plan.templates.count * 8)
            
            for ex in plan.substitutionPool {
                m[ex.id] = ex
            }
            
            for t in plan.templates.values {
                for te in t.exercises {
                    m[te.exercise.id] = te.exercise
                }
            }
            
            return m
        }()
        
        for templateExercise in template.exercises {
            let originalExercise = templateExercise.exercise
            if excludingExerciseIds.contains(originalExercise.id) {
                continue
            }
            let prescription = templateExercise.prescription
            
            // Determine substitutions for the *original* exercise (used for both suggestions and equipment outages).
            let substitutions = SubstitutionRanker.rank(
                for: originalExercise,
                candidates: plan.substitutionPool,
                availableEquipment: userProfile.availableEquipment,
                maxResults: 8
            )
            
            // Choose the exercise to actually perform (may rewrite due to equipment outages).
            // Also avoid accidental duplicates created by substitutions.
            let exercise: Exercise = {
                let originalAvailable = userProfile.availableEquipment.isAvailable(originalExercise.equipment)
                
                if originalAvailable && !usedExerciseIds.contains(originalExercise.id) {
                    return originalExercise
                }
                
                if let best = substitutions.first(where: {
                    let candidateId = $0.exercise.id
                    return !usedExerciseIds.contains(candidateId)
                    && !reservedOriginalIds.contains(candidateId) // avoid collisions with other template exercises
                }) {
                    return best.exercise
                }
                
                // If we can't find a non-colliding substitute, use the best available substitute.
                if let bestAny = substitutions.first(where: { !usedExerciseIds.contains($0.exercise.id) }) {
                    return bestAny.exercise
                }
                
                // No usable substitute. If the original isn't available, omit this exercise from the plan
                // (better than returning an unexecutable plan).
                return originalExercise
            }()
            
            // Skip unexecutable exercises if we failed to find a usable substitute.
            guard userProfile.availableEquipment.isAvailable(exercise.equipment) else {
                continue
            }
            
            usedExerciseIds.insert(exercise.id)
            
            func heuristicScale(from source: Exercise, to target: Exercise) -> Double {
                if target.equipment == source.equipment { return 1.0 }
                if target.equipment == .bodyweight { return 0.0 }
                if source.equipment == .bodyweight { return 0.0 }
                
                let sourceBarbellLike = (source.equipment == .barbell || source.equipment == .trapBar || source.equipment == .ezBar)
                let targetBarbellLike = (target.equipment == .barbell || target.equipment == .trapBar || target.equipment == .ezBar)
                
                let sourceDumbbellLike = (source.equipment == .dumbbell || source.equipment == .kettlebell)
                let targetDumbbellLike = (target.equipment == .dumbbell || target.equipment == .kettlebell)
                
                let sourceMachineLike = (source.equipment == .machine || source.equipment == .cable || source.equipment == .smithMachine || source.equipment == .plateLoaded)
                let targetMachineLike = (target.equipment == .machine || target.equipment == .cable || target.equipment == .smithMachine || target.equipment == .plateLoaded)
                
                func barbellToDumbbellScale(for pattern: MovementPattern) -> Double {
                    switch pattern {
                    case .squat:
                        return 0.35
                    case .hipHinge:
                        return 0.55
                    case .horizontalPush, .verticalPush:
                        return 0.45
                    default:
                        return 0.50
                    }
                }
                
                // Barbell → dumbbell/machine.
                if sourceBarbellLike && targetDumbbellLike {
                    return barbellToDumbbellScale(for: target.movementPattern)
                }
                if sourceBarbellLike && targetMachineLike {
                    return 0.70
                }
                
                // Dumbbell/machine → barbell (inverse scaling; used when returning to a previously-stale original lift).
                if sourceDumbbellLike && targetBarbellLike {
                    let base = barbellToDumbbellScale(for: target.movementPattern)
                    return base > 0 ? (1.0 / base) : 0.0
                }
                if sourceMachineLike && targetBarbellLike {
                    return (1.0 / 0.70)
                }
                
                // Conservative fallback (clamped).
                if sourceBarbellLike && !targetBarbellLike { return 0.60 }
                if !sourceBarbellLike && targetBarbellLike { return 1.65 }
                return 0.85
            }
            
            func scaledLiftState(
                target: Exercise,
                source: Exercise,
                sourceState: LiftState,
                roundingPolicy: LoadRoundingPolicy
            ) -> LiftState {
                let scale = max(0.0, min(3.0, heuristicScale(from: source, to: target)))
                
                let scaledWorking = (sourceState.lastWorkingWeight.converted(to: roundingPolicy.unit) * scale)
                    .rounded(using: roundingPolicy)
                
                let scaledRollingE1RM: Double = {
                    guard sourceState.rollingE1RM > 0 else { return 0 }
                    let asLoad = Load(value: sourceState.rollingE1RM, unit: sourceState.lastWorkingWeight.unit)
                    return (asLoad.converted(to: roundingPolicy.unit).value * scale)
                }()
                
                return LiftState(
                    exerciseId: target.id,
                    lastWorkingWeight: scaledWorking,
                    rollingE1RM: scaledRollingE1RM,
                    failureCount: 0,
                    lastDeloadDate: nil,
                    trend: .insufficient,
                    e1rmHistory: [],
                    lastSessionDate: sourceState.lastSessionDate,
                    successfulSessionsCount: 0
                )
            }
            
            // Progression is driven by the exercise being performed.
            // If we substituted due to equipment and the substitute has no meaningful state yet,
            // seed from the original lift state (scaled).
            let effectiveExerciseId = exercise.id
            let liftState: LiftState = {
                if let existing = history.liftStates[effectiveExerciseId], existing.lastWorkingWeight.value > 0 {
                    // If we're returning to the *original* lift after a long gap (often due to equipment-driven substitutions),
                    // try to rebase from the most recently-performed comparable substitute to avoid "false detraining".
                    if effectiveExerciseId == originalExercise.id {
                        let daysSinceLast: Int = {
                            guard let last = existing.lastSessionDate else { return Int.max }
                            let lastDay = calendar.startOfDay(for: last)
                            let today = calendar.startOfDay(for: date)
                            return calendar.dateComponents([.day], from: lastDay, to: today).day ?? Int.max
                        }()
                        
                        if daysSinceLast >= 28 {
                            // Find the most recently-performed comparable lift (often a substitute used during an outage)
                            // and scale it back to the original lift to avoid treating the gap as true detraining.
                            var best: (exercise: Exercise, state: LiftState, days: Int, score: Double)?
                            let today = calendar.startOfDay(for: date)
                            
                            for (candidateId, st) in history.liftStates {
                                guard candidateId != originalExercise.id else { continue }
                                guard st.lastWorkingWeight.value > 0 else { continue }
                                guard let last = st.lastSessionDate else { continue }
                                
                                let candidateExercise = exerciseById[candidateId]
                                guard let candidateExercise else { continue }
                                
                                // Only treat very similar lifts as comparable for rebasing.
                                guard candidateExercise.movementPattern == originalExercise.movementPattern else { continue }
                                guard candidateExercise.equipment != .bodyweight else { continue }
                                let overlap = candidateExercise.muscleOverlap(with: originalExercise)
                                guard overlap >= 0.60 else { continue }
                                
                                let subDays = calendar.dateComponents(
                                    [.day],
                                    from: calendar.startOfDay(for: last),
                                    to: today
                                ).day ?? Int.max
                                
                                guard subDays < 28 else { continue }
                                
                                let strengthSignal = (st.rollingE1RM > 0) ? st.rollingE1RM : st.lastWorkingWeight.value
                                // Prefer candidates that are both similar *and* represent meaningful loading.
                                let score = max(0, strengthSignal) * (0.5 + overlap)
                                
                                if best == nil
                                    || score > (best?.score ?? -Double.greatestFiniteMagnitude)
                                    || (abs(score - (best?.score ?? 0)) < 0.0001 && subDays < (best?.days ?? Int.max))
                                {
                                    best = (candidateExercise, st, subDays, score)
                                }
                            }
                            
                            if let best, let recentComparableDate = best.state.lastSessionDate {
                                // Key behavior: avoid "false detraining" when the user trained a comparable lift recently.
                                //
                                // Safety: returning from a substitute (e.g., dumbbell hinge) back to the original barbell lift
                                // is often a bit harder (different stability + loading). We refresh the lastSessionDate so the
                                // detraining reduction does not fire, but apply a small one-time "return-to-original" penalty
                                // to keep the first session conservative.
                                var refreshed = existing
                                refreshed.lastSessionDate = recentComparableDate
                                
                                if best.exercise.equipment != originalExercise.equipment {
                                    let penalty: Double = {
                                        let originalBarbellLike = (originalExercise.equipment == .barbell || originalExercise.equipment == .trapBar || originalExercise.equipment == .ezBar)
                                        let fromDumbbellLike = (best.exercise.equipment == .dumbbell || best.exercise.equipment == .kettlebell)
                                        let fromMachineLike = (best.exercise.equipment == .machine || best.exercise.equipment == .cable || best.exercise.equipment == .smithMachine || best.exercise.equipment == .plateLoaded)
                                        
                                        if originalBarbellLike && fromDumbbellLike {
                                            switch originalExercise.movementPattern {
                                            case .squat:
                                                return 0.85
                                            case .hipHinge:
                                                return 0.90
                                            case .horizontalPush, .verticalPush:
                                                return 0.90
                                            default:
                                                return 0.92
                                            }
                                        }
                                        
                                        if originalBarbellLike && fromMachineLike {
                                            return 0.92
                                        }
                                        
                                        return 0.90
                                    }()
                                    
                                    refreshed.lastWorkingWeight = (refreshed.lastWorkingWeight * penalty)
                                        .rounded(using: plan.loadRoundingPolicy)
                                    
                                    if refreshed.rollingE1RM > 0 {
                                        refreshed.rollingE1RM *= penalty
                                    }
                                }
                                
                                return refreshed
                            }
                        }
                    }
                    
                    return existing
                }
                
                // If we substituted due to equipment and the substitute has no meaningful state yet,
                // seed from the original lift state (scaled).
                if effectiveExerciseId != originalExercise.id,
                   let originalState = history.liftStates[originalExercise.id],
                   originalState.lastWorkingWeight.value > 0
                {
                    return scaledLiftState(
                        target: exercise,
                        source: originalExercise,
                        sourceState: originalState,
                        roundingPolicy: plan.loadRoundingPolicy
                    )
                }
                
                // If we have no state for the (original) lift but we have a recent comparable substitute state,
                // seed from that to avoid starting from 0 after an extended equipment change.
                if effectiveExerciseId == originalExercise.id {
                    var best: (exercise: Exercise, state: LiftState, days: Int, score: Double)?
                    let today = calendar.startOfDay(for: date)
                    
                    for (candidateId, st) in history.liftStates {
                        guard candidateId != originalExercise.id else { continue }
                        guard st.lastWorkingWeight.value > 0 else { continue }
                        guard let last = st.lastSessionDate else { continue }
                        
                        let candidateExercise = exerciseById[candidateId]
                        guard let candidateExercise else { continue }
                        guard candidateExercise.movementPattern == originalExercise.movementPattern else { continue }
                        guard candidateExercise.equipment != .bodyweight else { continue }
                        let overlap = candidateExercise.muscleOverlap(with: originalExercise)
                        guard overlap >= 0.60 else { continue }
                        
                        let subDays = calendar.dateComponents(
                            [.day],
                            from: calendar.startOfDay(for: last),
                            to: today
                        ).day ?? Int.max
                        guard subDays < 28 else { continue }
                        
                        let strengthSignal = (st.rollingE1RM > 0) ? st.rollingE1RM : st.lastWorkingWeight.value
                        let score = max(0, strengthSignal) * (0.5 + overlap)
                        if best == nil
                            || score > (best?.score ?? -Double.greatestFiniteMagnitude)
                            || (abs(score - (best?.score ?? 0)) < 0.0001 && subDays < (best?.days ?? Int.max))
                        {
                            best = (candidateExercise, st, subDays, score)
                        }
                    }
                    
                    if let best {
                        return scaledLiftState(
                            target: exercise,
                            source: best.exercise,
                            sourceState: best.state,
                            roundingPolicy: plan.loadRoundingPolicy
                        )
                    }
                }
                
                return history.liftStates[effectiveExerciseId] ?? LiftState(exerciseId: effectiveExerciseId)
            }()
            
            insights.append(contentsOf: CoachingInsightsPolicy.insightsForExercise(
                exerciseId: effectiveExerciseId,
                exercise: exercise,
                liftState: liftState,
                userProfile: userProfile,
                history: history,
                date: date,
                calendar: calendar,
                currentReadiness: readiness,
                substitutions: substitutions
            ))
            
            let progressionContext = ProgressionContext(
                userProfile: userProfile,
                exercise: exercise,
                date: date,
                calendar: calendar
            )
            
            // Determine between-session progression policy.
            // If a caller used `.rirAutoregulation` in the old `progressionPolicies` map, treat it as an
            // in-session policy and fall back to the default progression policy.
            // Use the original exercise id as the policy key so substitutions keep the intended policy config.
            let rawProgression = plan.progressionPolicies[originalExercise.id]
            let (progressionPolicy, inSessionFromLegacyProgression): (ProgressionPolicyType, InSessionAdjustmentPolicyType?) = {
                guard let rawProgression else {
                    return (ProgressionPolicyType.defaultPolicy(for: exercise.movementPattern, goals: userProfile.goals), nil)
                }
                
                if case .rirAutoregulation(let config) = rawProgression {
                    return (ProgressionPolicyType.defaultPolicy(for: exercise.movementPattern, goals: userProfile.goals),
                            .rirAutoregulation(config: config))
                }
                
                return (rawProgression, nil)
            }()

            // Determine in-session adjustment policy.
            let inSessionPolicy: InSessionAdjustmentPolicyType = {
                if let explicit = plan.inSessionPolicies[originalExercise.id] {
                    return explicit
                }
                if let legacy = inSessionFromLegacyProgression {
                    return legacy
                }
                if case .topSetBackoff(let cfg) = progressionPolicy, cfg.useDailyMax {
                    return .topSetBackoff(config: cfg)
                }
                return InSessionAdjustmentPolicyType.defaultFor(prescription: prescription)
            }()
            
            func isMaterialPrescriptionChange(from prior: SetPrescription, to current: SetPrescription) -> Bool {
                // Treat changes to protocol/technique drivers as "new context":
                // rep range, volume (sets), tempo, rest, effort target, and load strategy.
                //
                // This prevents interpreting a program change (e.g., slower tempo or shorter rest)
                // as a true strength decline and avoids unnecessary deload loops.
                if prior.loadStrategy != current.loadStrategy { return true }
                if prior.setCount != current.setCount { return true }
                if prior.targetRepsRange != current.targetRepsRange { return true }
                if prior.targetRIR != current.targetRIR { return true }
                if prior.tempo != current.tempo { return true }
                if abs(prior.restSeconds - current.restSeconds) > 15 { return true }
                return false
            }
            
            // Compute baseline target load.
            // Global deload adjustments (intensity/volume) are applied below via plan.deloadConfig.
            let baseTargetLoad: Load = {
                // Safety: bodyweight exercises should not inherit external loads from substituted barbell/machine lifts.
                if exercise.equipment == .bodyweight {
                    return .zero
                }
                
                // If the prescription context changed materially since the last non-deload exposure,
                // rebase the absolute load from rolling e1RM so we don't "fail into a deload" just
                // because the protocol got harder (tempo/rest/rep-range changes) or different.
                if let lastResult = history.exerciseResults(forExercise: effectiveExerciseId, limit: 1).first,
                   isMaterialPrescriptionChange(from: lastResult.prescription, to: prescription),
                   liftState.rollingE1RM > 0
                {
                    let unit: LoadUnit = (liftState.lastWorkingWeight.value > 0)
                        ? liftState.lastWorkingWeight.unit
                        : plan.loadRoundingPolicy.unit
                    
                    let e1rm = Load(value: liftState.rollingE1RM, unit: unit)
                    let targetReps = prescription.targetRepsRange.lowerBound
                    let rebased = Load(value: E1RMCalculator.workingWeight(fromE1RM: e1rm.value, targetReps: targetReps), unit: unit)
                    return rebased.rounded(using: plan.loadRoundingPolicy)
                }
                switch prescription.loadStrategy {
                case .percentageE1RM:
                    if let pct = prescription.targetPercentage, liftState.rollingE1RM > 0 {
                        // Prefer preserving the exercise's unit if we have an established working weight.
                        let unit: LoadUnit = (liftState.lastWorkingWeight.value > 0)
                            ? liftState.lastWorkingWeight.unit
                            : plan.loadRoundingPolicy.unit
                        return Load(value: liftState.rollingE1RM * pct, unit: unit)
                    }
                    // Fallback: if we can't compute %e1RM, use the progression baseline.
                    return progressionPolicy.computeNextLoad(
                        prescription: prescription,
                        liftState: liftState,
                        history: history,
                        exerciseId: effectiveExerciseId,
                        context: progressionContext
                    )
                    
                default:
                    return progressionPolicy.computeNextLoad(
                        prescription: prescription,
                        liftState: liftState,
                        history: history,
                        exerciseId: effectiveExerciseId,
                        context: progressionContext
                    )
                }
            }()

            // Long hiatus / detraining handling (conservative):
            // If the user hasn't performed the lift for weeks, ramp intensity down deterministically
            // to avoid suggesting a "resume at peak" load.
            let detrainingReduction: Double = {
                guard let last = liftState.lastSessionDate else { return 0 }
                let lastDay = calendar.startOfDay(for: last)
                let today = calendar.startOfDay(for: date)
                let days = calendar.dateComponents([.day], from: lastDay, to: today).day ?? 0
                
                switch days {
                case 0..<28:
                    return 0
                case 28..<56:
                    return 0.10
                case 56..<84:
                    return 0.20
                default:
                    return 0.30
                }
            }()
            
            let detrainedBase = baseTargetLoad * (1.0 - detrainingReduction)
            
            let targetLoad: Load = {
                guard deloadDecision.shouldDeload, let deloadConfig = plan.deloadConfig else {
                    return detrainedBase
                }
                return detrainedBase * (1.0 - deloadConfig.intensityReduction)
            }()

            // Output loads in the plan's rounding unit (supports unit switches like lb history → kg plan).
            let sessionBaseLoad = targetLoad.converted(to: plan.loadRoundingPolicy.unit)
            
            // Build set plans
            var setPlans: [SetPlan] = []
            let baseTargetReps = progressionPolicy.computeNextTargetReps(
                prescription: prescription,
                history: history,
                exerciseId: effectiveExerciseId
            )
            let targetReps = deloadDecision.shouldDeload ? prescription.targetRepsRange.lowerBound : baseTargetReps

            let setCount = deloadDecision.shouldDeload
                ? max(1, prescription.setCount - (plan.deloadConfig?.volumeReduction ?? 1))
                : prescription.setCount
            
            for setIndex in 0..<setCount {
                let setLoad = progressionPolicy.computeSetLoad(
                    setIndex: setIndex,
                    totalSets: setCount,
                    baseLoad: sessionBaseLoad,
                    prescription: prescription,
                    roundingPolicy: plan.loadRoundingPolicy
                )
                
                setPlans.append(SetPlan(
                    setIndex: setIndex,
                    targetLoad: setLoad,
                    targetReps: targetReps,
                    targetRIR: prescription.targetRIR,
                    restSeconds: prescription.restSeconds,
                    isWarmup: false,
                    backoffPercentage: {
                        if case .topSetBackoff(let cfg) = progressionPolicy, setIndex > 0 {
                            return cfg.backoffPercentage
                        }
                        return nil
                    }(),
                    inSessionPolicy: inSessionPolicy,
                    roundingPolicy: plan.loadRoundingPolicy
                ))
            }
            
            exercisePlans.append(ExercisePlan(
                exercise: exercise,
                prescription: prescription,
                sets: setPlans,
                progressionPolicy: progressionPolicy,
                inSessionPolicy: inSessionPolicy,
                substitutions: substitutions
            ))
        }
        
        return SessionPlan(
            date: date,
            templateId: templateId,
            exercises: exercisePlans,
            isDeload: deloadDecision.shouldDeload,
            deloadReason: deloadDecision.reason,
            insights: insights
        )
    }
    
    // MARK: - Next Prescription (Set-by-Set)
    
    /// Computes the next prescription for a single exercise, returning a full set-by-set plan.
    ///
    /// This is the canonical entry point for computing what weight/reps to use next session.
    /// It factors in:
    /// - Progression policy (double progression, linear, top-set/backoff, etc.)
    /// - Current lift state (last working weight, failure count, e1RM)
    /// - Workout history for trend analysis
    /// - Deload status
    ///
    /// - Parameters:
    ///   - exercise: The exercise to compute prescription for.
    ///   - prescription: The set prescription (sets, reps range, tempo, etc.).
    ///   - progressionPolicy: How to progress between sessions.
    ///   - inSessionPolicy: How to adjust during the session.
    ///   - history: Recent workout history.
    ///   - liftState: Current per-exercise state.
    ///   - isDeload: Whether this should be a deload session.
    ///   - roundingPolicy: How to round loads.
    ///   - date: The date for which to compute (used for detraining calculations).
    /// - Returns: An `ExercisePlan` with set-by-set targets.
    public static func nextPrescription(
        exercise: Exercise,
        prescription: SetPrescription,
        progressionPolicy: ProgressionPolicyType,
        inSessionPolicy: InSessionAdjustmentPolicyType = .none,
        history: WorkoutHistory,
        liftState: LiftState,
        isDeload: Bool = false,
        roundingPolicy: LoadRoundingPolicy = .standardPounds,
        deloadConfig: DeloadConfig? = .default,
        userProfile: UserProfile? = nil,
        date: Date = Date(),
        calendar: Calendar = .current
    ) -> ExercisePlan {
        let exerciseId = exercise.id
        
        // If a caller didn't specify an in-session policy, derive a safe default that matches
        // what the full session planner would choose.
        let effectiveInSessionPolicy: InSessionAdjustmentPolicyType = {
            if inSessionPolicy != .none {
                return inSessionPolicy
            }
            if case .topSetBackoff(let cfg) = progressionPolicy, cfg.useDailyMax {
                return .topSetBackoff(config: cfg)
            }
            return InSessionAdjustmentPolicyType.defaultFor(prescription: prescription)
        }()
        
        // Compute baseline target load using progression policy.
        let baseTargetLoad: Load = {
            // Safety: bodyweight exercises have no external load unless explicitly modeled.
            if exercise.equipment == .bodyweight {
                return .zero
            }
            
            let progressionContext: ProgressionContext? = userProfile.map {
                ProgressionContext(userProfile: $0, exercise: exercise, date: date, calendar: calendar)
            }
            switch prescription.loadStrategy {
            case .percentageE1RM:
                if let pct = prescription.targetPercentage, liftState.rollingE1RM > 0 {
                    let unit: LoadUnit = (liftState.lastWorkingWeight.value > 0)
                        ? liftState.lastWorkingWeight.unit
                        : roundingPolicy.unit
                    return Load(value: liftState.rollingE1RM * pct, unit: unit)
                }
                return progressionPolicy.computeNextLoad(
                    prescription: prescription,
                    liftState: liftState,
                    history: history,
                    exerciseId: exerciseId,
                    context: progressionContext
                )
                
            default:
                return progressionPolicy.computeNextLoad(
                    prescription: prescription,
                    liftState: liftState,
                    history: history,
                    exerciseId: exerciseId,
                    context: progressionContext
                )
            }
        }()
        
        // Detraining reduction for long hiatuses.
        let detrainingReduction: Double = {
            guard let last = liftState.lastSessionDate else { return 0 }
            let lastDay = calendar.startOfDay(for: last)
            let today = calendar.startOfDay(for: date)
            let days = calendar.dateComponents([.day], from: lastDay, to: today).day ?? 0
            
            switch days {
            case 0..<28:
                return 0
            case 28..<56:
                return 0.10
            case 56..<84:
                return 0.20
            default:
                return 0.30
            }
        }()
        
        let detrainedBase = baseTargetLoad * (1.0 - detrainingReduction)
        
        // Apply deload intensity reduction if needed.
        let targetLoad: Load = {
            guard isDeload, let config = deloadConfig else {
                return detrainedBase
            }
            return detrainedBase * (1.0 - config.intensityReduction)
        }()
        
        // Convert to plan's rounding unit.
        let sessionBaseLoad = targetLoad.converted(to: roundingPolicy.unit)
        
        // Compute target reps.
        let baseTargetReps = progressionPolicy.computeNextTargetReps(
            prescription: prescription,
            history: history,
            exerciseId: exerciseId
        )
        let targetReps = isDeload ? prescription.targetRepsRange.lowerBound : baseTargetReps
        
        // Compute set count (reduce on deload).
        let setCount = isDeload
            ? max(1, prescription.setCount - (deloadConfig?.volumeReduction ?? 1))
            : prescription.setCount
        
        // Build set plans.
        var setPlans: [SetPlan] = []
        for setIndex in 0..<setCount {
            let setLoad = progressionPolicy.computeSetLoad(
                setIndex: setIndex,
                totalSets: setCount,
                baseLoad: sessionBaseLoad,
                prescription: prescription,
                roundingPolicy: roundingPolicy
            )
            
            setPlans.append(SetPlan(
                setIndex: setIndex,
                targetLoad: setLoad,
                targetReps: targetReps,
                targetRIR: prescription.targetRIR,
                restSeconds: prescription.restSeconds,
                isWarmup: false,
                backoffPercentage: {
                    if case .topSetBackoff(let cfg) = progressionPolicy, setIndex > 0 {
                        return cfg.backoffPercentage
                    }
                    return nil
                }(),
                inSessionPolicy: effectiveInSessionPolicy,
                roundingPolicy: roundingPolicy
            ))
        }
        
        return ExercisePlan(
            exercise: exercise,
            prescription: prescription,
            sets: setPlans,
            progressionPolicy: progressionPolicy,
            inSessionPolicy: effectiveInSessionPolicy,
            substitutions: []
        )
    }
    
    /// Simplified version of `nextPrescription` that uses default policies based on movement pattern.
    ///
    /// - Parameters:
    ///   - exercise: The exercise to compute prescription for.
    ///   - prescription: The set prescription.
    ///   - history: Recent workout history.
    ///   - liftState: Current per-exercise state.
    ///   - goals: Training goals (used to derive default progression policy).
    ///   - isDeload: Whether this should be a deload session.
    ///   - roundingPolicy: How to round loads.
    /// - Returns: An `ExercisePlan` with set-by-set targets.
    public static func nextPrescription(
        exercise: Exercise,
        prescription: SetPrescription,
        history: WorkoutHistory,
        liftState: LiftState,
        goals: [TrainingGoal] = [.generalFitness],
        isDeload: Bool = false,
        roundingPolicy: LoadRoundingPolicy = .standardPounds
    ) -> ExercisePlan {
        let progressionPolicy = ProgressionPolicyType.defaultPolicy(
            for: exercise.movementPattern,
            goals: goals
        )
        let inSessionPolicy = InSessionAdjustmentPolicyType.defaultFor(prescription: prescription)
        
        return nextPrescription(
            exercise: exercise,
            prescription: prescription,
            progressionPolicy: progressionPolicy,
            inSessionPolicy: inSessionPolicy,
            history: history,
            liftState: liftState,
            isDeload: isDeload,
            roundingPolicy: roundingPolicy
        )
    }
    
    // MARK: - In-Session Adjustments
    
    /// Adjusts the next set during a session based on the current set result.
    ///
    /// - Parameters:
    ///   - currentSetResult: The result of the just-completed set.
    ///   - plannedNextSet: The originally planned next set.
    /// - Returns: An updated plan for the next set.
    public static func adjustDuringSession(
        currentSetResult: SetResult,
        plannedNextSet: SetPlan
    ) -> SetPlan {
        plannedNextSet.inSessionPolicy.adjustInSession(
            currentResult: currentSetResult,
            plannedNext: plannedNextSet,
            roundingPolicy: plannedNextSet.roundingPolicy
        )
    }

    /// Adjusts the next set during a session based on the current set result.
    /// This overload is kept for callers that pass policy/rounding explicitly.
    ///   - policy: The progression policy for this exercise.
    ///   - roundingPolicy: How to round loads.
    /// - Returns: An updated plan for the next set.
    public static func adjustDuringSession(
        currentSetResult: SetResult,
        plannedNextSet: SetPlan,
        policy: ProgressionPolicyType,
        roundingPolicy: LoadRoundingPolicy
    ) -> SetPlan {
        let derivedInSession: InSessionAdjustmentPolicyType = {
            if case .rirAutoregulation(let config) = policy {
                return .rirAutoregulation(config: config)
            }
            if case .topSetBackoff(let config) = policy, config.useDailyMax {
                return .topSetBackoff(config: config)
            }
            return .none
        }()

        let enrichedNext = SetPlan(
            setIndex: plannedNextSet.setIndex,
            targetLoad: plannedNextSet.targetLoad,
            targetReps: plannedNextSet.targetReps,
            targetRIR: plannedNextSet.targetRIR,
            restSeconds: plannedNextSet.restSeconds,
            isWarmup: plannedNextSet.isWarmup,
            backoffPercentage: plannedNextSet.backoffPercentage,
            inSessionPolicy: derivedInSession,
            roundingPolicy: roundingPolicy
        )

        return derivedInSession.adjustInSession(
            currentResult: currentSetResult,
            plannedNext: enrichedNext,
            roundingPolicy: roundingPolicy
        )
    }
    
    /// Updates lift states after completing a session.
    ///
    /// - Parameter session: The completed session with results.
    /// - Returns: Updated lift states for each exercise performed.
    public static func updateLiftState(afterSession session: CompletedSession) -> [LiftState] {
        var updatedStates: [LiftState] = []
        
        for exerciseResult in session.exerciseResults {
            let exerciseId = exerciseResult.exerciseId
            var state = session.previousLiftStates[exerciseId] ?? LiftState(exerciseId: exerciseId)
            
            // Compute working sets (exclude warmups; require actual reps > 0).
            let workingSets = exerciseResult.sets.filter { $0.completed && !$0.isWarmup && $0.reps > 0 }
            
            guard !workingSets.isEmpty else {
                updatedStates.append(state)
                continue
            }
            
            // Update last working weight (highest completed load).
            // Note: sets can theoretically contain mixed units; we normalize using the unit of the heaviest set.
            let maxLoad = workingSets.map(\.load).max() ?? state.lastWorkingWeight
            let sessionUnit = maxLoad.unit
            
            // If the user switched units (lb ↔ kg) since the previous state, convert prior e1RM values
            // before smoothing or trend calculation. We assume prior e1RM values were recorded in the
            // same unit as `state.lastWorkingWeight.unit` at that time.
            let priorUnit = state.lastWorkingWeight.unit
            if priorUnit != sessionUnit {
                state.lastWorkingWeight = state.lastWorkingWeight.converted(to: sessionUnit)
                
                if state.rollingE1RM > 0 {
                    state.rollingE1RM = Load(value: state.rollingE1RM, unit: priorUnit)
                        .converted(to: sessionUnit)
                        .value
                }
                
                if !state.e1rmHistory.isEmpty {
                    state.e1rmHistory = state.e1rmHistory.map { sample in
                        let converted = Load(value: sample.value, unit: priorUnit)
                            .converted(to: sessionUnit)
                            .value
                        return E1RMSample(date: sample.date, value: converted)
                    }
                }
            }
            var proposedLastWorkingWeight = maxLoad.converted(to: sessionUnit)

            // Compute session e1RM (best estimated 1RM from any set)
            var sessionE1RM = workingSets
                .map { set -> Double in
                    let w = set.load.converted(to: sessionUnit).value
                    return E1RMCalculator.brzycki(weight: w, reps: set.reps)
                }
                .max() ?? 0
            
            // Check if session was a failure (any set below lower bound of rep range)
            let prescription = exerciseResult.prescription
            let anyFailure = workingSets.contains { $0.reps < prescription.targetRepsRange.lowerBound }

            // IMPORTANT: Deload sessions should not overwrite the lift's working-weight baseline or e1RM history.
            //
            // Why:
            // - Deload sessions intentionally reduce load and/or volume.
            // - If we treat deload performance as a normal datapoint, the baseline (lastWorkingWeight / rollingE1RM)
            //   will drift down and can create a "deload into the ground" spiral over long horizons.
            //
            // We still update:
            // - lastSessionDate (so detraining logic stays correct)
            // - lastDeloadDate
            // - failureCount (reset on a successful deload; increment if the user still failed)
            if session.wasDeload {
                // Special case: if this deload session is the *first exposure after a long gap* for this lift,
                // we should update the working baseline. Otherwise, we can get a huge (unsafe/unrealistic)
                // "bounce-back" next session because:
                // - deload sessions don't update lastWorkingWeight / rollingE1RM
                // - but they *do* update lastSessionDate (removing detraining reduction)
                //
                // Treat long-gap deloads as "return-to-training" exposures.
                let daysSinceLast: Int = {
                    var cal = Calendar(identifier: .gregorian)
                    cal.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
                    guard let last = state.lastSessionDate else { return Int.max }
                    let lastDay = cal.startOfDay(for: last)
                    let today = cal.startOfDay(for: session.date)
                    return cal.dateComponents([.day], from: lastDay, to: today).day ?? 0
                }()
                
                state.lastSessionDate = session.date
                state.lastDeloadDate = session.date
                state.failureCount = anyFailure ? (state.failureCount + 1) : 0
                
                let priorW = state.lastWorkingWeight.value
                let currentW = proposedLastWorkingWeight.value
                let ratio = (priorW > 0 && currentW > 0) ? (currentW / priorW) : 1.0
                let isLargeBaselineShift = ratio < 0.75 || ratio > 1.35
                
                if daysSinceLast >= 28 || isLargeBaselineShift {
                    // Update baseline load + performance signals to reflect the new (post-hiatus) reality.
                    state.lastWorkingWeight = proposedLastWorkingWeight
                    
                    // Update rolling e1RM with exponential smoothing.
                    let alpha = 0.3
                    if state.rollingE1RM > 0 {
                        state.rollingE1RM = alpha * sessionE1RM + (1 - alpha) * state.rollingE1RM
                    } else {
                        state.rollingE1RM = sessionE1RM
                    }
                    
                    // Update trend based on e1RM history.
                    state.e1rmHistory.append(E1RMSample(date: session.date, value: sessionE1RM))
                    if state.e1rmHistory.count > 10 {
                        state.e1rmHistory.removeFirst(state.e1rmHistory.count - 10)
                    }
                    state.trend = TrendCalculator.compute(from: state.e1rmHistory)
                }
                
                updatedStates.append(state)
                continue
            }

            // Guardrail: detect likely kg↔lb entry mistakes and prevent "state nukes".
            //
            // In the real app, unit switches should be explicit, but users can still type a number
            // in the wrong unit (e.g., enter 85 thinking "kg" when the app expects "lb").
            // If we blindly accept that value, the baseline can collapse and the engine will keep
            // recommending absurdly low loads.
            //
            // Heuristic:
            // - Only consider correction when the last known working weight is > 0
            // - Only consider when the new weight is a large jump/drop vs prior
            // - Only consider when the ratio is close to kg↔lb conversion factors
            // - Only consider when the last session was recent (avoid overriding real detraining/injury resets)
            if state.lastWorkingWeight.value > 0, proposedLastWorkingWeight.value > 0 {
                let daysSinceLast: Int = {
                    var cal = Calendar(identifier: .gregorian)
                    cal.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
                    guard let last = state.lastSessionDate else { return 0 }
                    let lastDay = cal.startOfDay(for: last)
                    let today = cal.startOfDay(for: session.date)
                    return cal.dateComponents([.day], from: lastDay, to: today).day ?? 0
                }()
                
                let prior = state.lastWorkingWeight.value
                let current = proposedLastWorkingWeight.value
                let ratio = current / prior
                
                // Only bother if it's a big discontinuity.
                if ratio < 0.60 || ratio > 1.67 {
                    let kgToLb = 2.20462
                    let lbToKg = 0.453592
                    
                    func within(_ x: Double, _ lo: Double, _ hi: Double) -> Bool { x >= lo && x <= hi }
                    
                    // If the ratio is extremely close to conversion factors, it's very likely a unit entry mistake,
                    // even if the lift hasn't been performed recently.
                    let strongSignal = abs(ratio - lbToKg) < 0.03 || abs(ratio - kgToLb) < 0.12
                    let allowCorrection = strongSignal || (daysSinceLast < 56)
                    if allowCorrection {
                        // If the ratio is close to lbToKg (~0.454), user likely entered kg number in a lb field.
                        if abs(ratio - lbToKg) < 0.08 {
                            let corrected = current * kgToLb
                            // Only accept if it lands reasonably close to the prior baseline.
                            if within(corrected / prior, 0.75, 1.35) {
                                proposedLastWorkingWeight = Load(value: corrected, unit: sessionUnit)
                                sessionE1RM *= kgToLb
                            }
                        }
                        
                        // If the ratio is close to kgToLb (~2.205), user likely entered lb number in a kg field.
                        else if abs(ratio - kgToLb) < 0.25 {
                            let corrected = current * lbToKg
                            if within(corrected / prior, 0.75, 1.35) {
                                proposedLastWorkingWeight = Load(value: corrected, unit: sessionUnit)
                                sessionE1RM *= lbToKg
                            }
                        }
                    }
                }
            }
            
            // Non-deload: update working baseline and performance signals.
            state.lastWorkingWeight = proposedLastWorkingWeight
            
            // Update rolling e1RM with exponential smoothing
            let alpha = 0.3
            if state.rollingE1RM > 0 {
                state.rollingE1RM = alpha * sessionE1RM + (1 - alpha) * state.rollingE1RM
            } else {
                state.rollingE1RM = sessionE1RM
            }
            
            if anyFailure {
                state.failureCount += 1
            } else {
                state.failureCount = 0
            }
            
            // Update trend based on e1RM history
            state.e1rmHistory.append(E1RMSample(date: session.date, value: sessionE1RM))
            // Keep only last 10 samples
            if state.e1rmHistory.count > 10 {
                state.e1rmHistory.removeFirst(state.e1rmHistory.count - 10)
            }
            
            state.trend = TrendCalculator.compute(from: state.e1rmHistory)
            state.lastSessionDate = session.date
            if !anyFailure {
                state.successfulSessionsCount += 1
            }
            
            updatedStates.append(state)
        }
        
        return updatedStates
    }
}
