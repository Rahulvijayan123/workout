// TrainingEngine.swift
// Pure Swift module for deterministic workout progression, deload, and substitutions.

import Foundation

// MARK: - Session Planning Context (for logging)

/// Context collected during session planning, used for ML training data logging.
public struct SessionPlanningContext {
    public let sessionId: UUID
    public let userId: String
    public let sessionDate: Date
    public let isPlannedDeloadWeek: Bool
    public let calendar: Calendar
    
    public init(
        sessionId: UUID = UUID(),
        userId: String = "anonymous",
        sessionDate: Date,
        isPlannedDeloadWeek: Bool = false,
        calendar: Calendar = .current
    ) {
        self.sessionId = sessionId
        self.userId = userId
        self.sessionDate = sessionDate
        self.isPlannedDeloadWeek = isPlannedDeloadWeek
        self.calendar = calendar
    }
}

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
    ///   - plannedDeloadWeek: If true, forces a scheduled deload regardless of other triggers.
    /// - Returns: A `SessionPlan` with exercises, sets, target loads/reps, and substitutions.
    public static func recommendSession(
        date: Date,
        userProfile: UserProfile,
        plan: TrainingPlan,
        history: WorkoutHistory,
        readiness: Int,
        plannedDeloadWeek: Bool = false,
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
            plannedDeloadWeek: plannedDeloadWeek,
            excludingExerciseIds: [],
            calendar: calendar
        )
    }
    
    /// Recommends a session plan for a specific template. Useful for mid-session replanning (equipment changes),
    /// or when the caller wants to bypass schedule selection.
    ///
    /// - Parameters:
    ///   - plannedDeloadWeek: If true, forces a scheduled deload regardless of other triggers.
    public static func recommendSessionForTemplate(
        date: Date,
        templateId: WorkoutTemplateId,
        userProfile: UserProfile,
        plan: TrainingPlan,
        history: WorkoutHistory,
        readiness: Int,
        plannedDeloadWeek: Bool = false,
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
        
        // Check deload triggers (or use explicit planned deload override)
        let deloadDecision: DeloadDecision = {
            if plannedDeloadWeek {
                return DeloadDecision(
                    shouldDeload: true,
                    reason: .scheduledDeload,
                    explanation: "Planned deload week (explicit override)",
                    triggeredRules: []
                )
            }
            return DeloadPolicy.evaluate(
                userProfile: userProfile,
                plan: plan,
                history: history,
                readiness: readiness,
                date: date,
                calendar: calendar
            )
        }()
        
        var exercisePlans: [ExercisePlan] = []
        var usedExerciseIds: Set<String> = []
        var insights: [CoachingInsight] = []
        
        // Original exercise IDs present in the template; used to avoid collisions where a substitute
        // would duplicate a different planned exercise.
        let reservedOriginalIds = Set(template.exercises.map(\.exercise.id))
        
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
            
            // =====================================================================
            // LIFT FAMILY STATE: Separate reference (read) and update (write) keys
            // =====================================================================
            // 
            // Resolve the exercise to its lift family. This provides:
            // - referenceStateKey: canonical key for READING baseline (family.id)
            // - updateStateKey: key for WRITING state (exercise-specific for variations)
            // - coefficient: scaling factor for load conversion (reference → performed)
            //
            // For reading (load estimation):
            // - First try the exercise's own state (if it exists from a previous session)
            // - Then fall back to family baseline and apply coefficient
            //
            // For writing: state goes to updateStateKey (handled in updateLiftState)
            
            let familyResolution = LiftFamilyResolver.resolve(exercise)
            let referenceStateKey = familyResolution.referenceStateKey
            let updateStateKey = familyResolution.updateStateKey
            let familyCoefficient = familyResolution.coefficient
            
            // Also resolve the original exercise for policy lookups
            let originalFamilyResolution = LiftFamilyResolver.resolve(originalExercise)
            
            // Look up state for load estimation:
            // 1. First try exercise's own state (updateStateKey) - variations/subs build their own history
            // 2. Then try family baseline (referenceStateKey) - for first-time variations
            // 3. Finally, try original exercise state (for substitution migration)
            let liftState: LiftState = {
                // Try exercise's own update state first (variations maintain their own state)
                if let existing = history.liftStates[updateStateKey], existing.lastWorkingWeight.value > 0 {
                    return existing
                }
                
                // Try canonical family reference key (for first-time variations)
                // No coefficient scaling here - that's applied later to familyBaselineLoad
                if updateStateKey != referenceStateKey,
                   let existing = history.liftStates[referenceStateKey],
                   existing.lastWorkingWeight.value > 0 {
                    return existing
                }
                
                // Fallback: try the performed exercise ID directly (backward compatibility)
                if let existing = history.liftStates[exercise.id], existing.lastWorkingWeight.value > 0 {
                    return existing
                }
                
                // Fallback: try the original exercise ID (for substitution cases)
                // This handles migration from old per-exercise states to canonical family states.
                if exercise.id != originalExercise.id,
                   let originalState = history.liftStates[originalExercise.id],
                   originalState.lastWorkingWeight.value > 0
                {
                    // The old state was stored in exercise-specific terms.
                    // Use it as-is; coefficient will be applied later if needed.
                    return originalState
                }
                
                // No state found - return empty state
                return LiftState(exerciseId: referenceStateKey)
            }()
            
            // effectiveExerciseId is used for history lookups (which still use exercise IDs)
            let effectiveExerciseId = exercise.id
            
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
            
            // =====================================================================
            // DIRECTION/MAGNITUDE SYSTEM: Compute load and volume using new pipeline
            // =====================================================================
            
            // Safety: bodyweight exercises should not inherit external loads.
            guard exercise.equipment != .bodyweight else {
                let setPlans = (0..<prescription.setCount).map { setIndex in
                    SetPlan(
                        setIndex: setIndex,
                        targetLoad: .zero,
                        targetReps: prescription.targetRepsRange.lowerBound,
                        targetRIR: prescription.targetRIR,
                        restSeconds: prescription.restSeconds,
                        isWarmup: false,
                        backoffPercentage: nil,
                        inSessionPolicy: inSessionPolicy,
                        roundingPolicy: plan.loadRoundingPolicy
                    )
                }
                exercisePlans.append(ExercisePlan(
                    exercise: exercise,
                    prescription: prescription,
                    sets: setPlans,
                    progressionPolicy: progressionPolicy,
                    inSessionPolicy: inSessionPolicy,
                    substitutions: substitutions,
                    recommendedAdjustmentKind: nil,
                    direction: nil,
                    directionReason: nil,
                    directionExplanation: nil,
                    policyChecks: nil
                ))
                continue
            }
            
            // Compute baseline load (the "anchor" before direction/magnitude adjustments).
            //
            // State resolution:
            // - If we found the exercise's own state (updateStateKey), it's already in exercise-specific terms
            // - If we found the family baseline (referenceStateKey), apply coefficient to convert
            //
            // This ensures variations/substitutions that have their own history use their own loads,
            // while new variations properly inherit from the family baseline.
            let stateIsExerciseSpecific = (liftState.exerciseId == updateStateKey && updateStateKey != referenceStateKey)
            
            // DATA SANITY: If liftState.lastSessionDate is in the future relative to `date`,
            // the state data is suspect (possibly from test data or clock issues).
            // Treat such state as unreliable for baseline purposes.
            let hasValidStateDate: Bool = {
                guard let lastDate = liftState.lastSessionDate else { return true } // No date = OK
                var cal = Calendar(identifier: .gregorian)
                cal.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
                let daysDiff = cal.dateComponents([.day], from: date, to: lastDate).day ?? 0
                return daysDiff <= 1 // Allow 1 day tolerance for timezone issues
            }()
            
            let familyBaselineLoad: Load = {
                // Helper: derive %e1RM from targetReps + targetRIR using inverse Brzycki
                // This approximates what weight to use for a given rep/RIR target
                func derivedPercentageFromRepsRIR(reps: Int, rir: Int) -> Double {
                    // Effective reps = targetReps + targetRIR (assuming you could do RIR more)
                    let effectiveReps = max(1, reps + rir)
                    // Brzycki inverse: % = 1.0278 - 0.0278 * reps (roughly)
                    // More conservative formula for higher rep ranges
                    return E1RMCalculator.workingWeight(fromE1RM: 1.0, targetReps: effectiveReps)
                }
                
                let unit = plan.loadRoundingPolicy.unit
                
                // 1) For explicit %e1RM strategies with percentage, ALWAYS compute from e1RM.
                if case .percentageE1RM = prescription.loadStrategy,
                   let pct = prescription.targetPercentage,
                   liftState.rollingE1RM > 0,
                   hasValidStateDate {
                    return Load(value: liftState.rollingE1RM * pct, unit: unit)
                        .rounded(using: plan.loadRoundingPolicy)
                }
                
                // 2) For %e1RM with nil percentage OR rpeAutoregulated:
                // CRITICAL FIX (V10): Anchor to lastWorkingWeight when available to prevent
                // baseline drift from %e1RM math. Only use derivedPercentageFromRepsRIR for
                // cold starts or material prescription changes.
                //
                // Prior bug: For advanced bench (235 lb working, ~266 e1RM, 4 reps @ RIR 2),
                // the derived percent computed ~229 instead of anchoring at 235.
                if (prescription.loadStrategy == .percentageE1RM && prescription.targetPercentage == nil) ||
                   prescription.loadStrategy == .rpeAutoregulated {
                    
                    // Prefer anchoring to lastWorkingWeight (prevents baseline drift)
                    if liftState.lastWorkingWeight.value > 0 && hasValidStateDate {
                        // Check if prescription context changed materially - if so, rebase from e1RM
                        let lastResult = history.exerciseResults(forExercise: effectiveExerciseId, limit: 1).first
                        let prescriptionChanged = lastResult.map { isMaterialPrescriptionChange(from: $0.prescription, to: prescription) } ?? false
                        
                        if !prescriptionChanged {
                            // Anchor baseline to last working weight
                            return liftState.lastWorkingWeight
                        }
                    }
                    
                    // Cold start or material prescription change: derive from e1RM
                    if liftState.rollingE1RM > 0 && hasValidStateDate {
                        let targetReps = prescription.targetRepsRange.lowerBound
                        let derivedPct = derivedPercentageFromRepsRIR(reps: targetReps, rir: prescription.targetRIR)
                        return Load(value: liftState.rollingE1RM * derivedPct, unit: unit)
                            .rounded(using: plan.loadRoundingPolicy)
                    }
                }
                
                // 3) If prescription context changed materially, rebase from e1RM.
                if let lastResult = history.exerciseResults(forExercise: effectiveExerciseId, limit: 1).first,
                   isMaterialPrescriptionChange(from: lastResult.prescription, to: prescription),
                   liftState.rollingE1RM > 0,
                   hasValidStateDate
                {
                    let e1rmUnit: LoadUnit = liftState.lastWorkingWeight.value > 0 ? liftState.lastWorkingWeight.unit : unit
                    let e1rm = Load(value: liftState.rollingE1RM, unit: e1rmUnit)
                    let targetReps = prescription.targetRepsRange.lowerBound
                    let rebased = Load(value: E1RMCalculator.workingWeight(fromE1RM: e1rm.value, targetReps: targetReps), unit: e1rm.unit)
                    return rebased.rounded(using: plan.loadRoundingPolicy)
                }
                
                // 4) Prefer last working weight as baseline if available (for absolute strategies).
                if liftState.lastWorkingWeight.value > 0 && hasValidStateDate {
                    return liftState.lastWorkingWeight
                }
                
                // 5) Cold start: estimate if no baseline.
                // Note: cold start estimate is already exercise-specific, so don't apply coefficient.
                if liftState.lastWorkingWeight.value <= 0.0001 || !hasValidStateDate,
                   history.exerciseResults(forExercise: effectiveExerciseId, limit: 1).isEmpty,
                   let estimated = initialWorkingLoadEstimate(
                    for: exercise,
                    prescription: prescription,
                    userProfile: userProfile,
                    roundingPolicy: plan.loadRoundingPolicy
                   )
                {
                    // Cold start is already exercise-specific; return directly
                    return estimated
                }
                
                // Fallback to zero (will be handled by magnitude).
                return liftState.lastWorkingWeight
            }()
            
            // Apply family coefficient to convert from family baseline to exercise-specific load.
            // ONLY apply coefficient if:
            // 1. We read from family baseline (not exercise-specific state)
            // 2. Not a cold-start estimate (already exercise-specific)
            let baselineLoad: Load = {
                // If we used cold-start estimation, the load is already exercise-specific
                let isColdStart = liftState.lastWorkingWeight.value <= 0.0001 &&
                    history.exerciseResults(forExercise: effectiveExerciseId, limit: 1).isEmpty
                
                if isColdStart {
                    return familyBaselineLoad
                }
                
                // If state is already exercise-specific, don't apply coefficient
                if stateIsExerciseSpecific {
                    return familyBaselineLoad
                }
                
                // Apply coefficient for variations/substitutes reading from family baseline
                return (familyBaselineLoad * familyCoefficient)
                    .rounded(using: plan.loadRoundingPolicy)
            }()
            
            // Build lift signals for direction/magnitude decision.
            let signals = buildLiftSignals(
                exerciseId: effectiveExerciseId,
                exercise: exercise,
                liftState: liftState,
                prescription: prescription,
                history: history,
                userProfile: userProfile,
                todayReadiness: readiness,
                sessionDeloadTriggered: deloadDecision.shouldDeload,
                sessionDeloadReason: deloadDecision.reason,
                date: date,
                calendar: calendar
            )
            
            // Compute direction and magnitude.
            let (finalLoad, directionDecision, magnitudeParams, volumeAdjustment, policyChecks) = computeTargetLoadWithDirectionMagnitude(
                signals: signals,
                baseTargetLoad: baselineLoad,
                liftState: liftState,
                plan: plan
            )
            
            // Output loads in the plan's rounding unit.
            let sessionBaseLoad = finalLoad.converted(to: plan.loadRoundingPolicy.unit)
                .rounded(using: magnitudeParams.roundingPolicy)
            
            // Build set plans with direction-aware volume.
            var setPlans: [SetPlan] = []
            let baseTargetReps = progressionPolicy.computeNextTargetReps(
                prescription: prescription,
                history: history,
                exerciseId: effectiveExerciseId
            )
            
            // Use lower rep bound for deloads/resets, otherwise policy-computed reps.
            let targetReps: Int = {
                switch directionDecision.direction {
                case .deload, .resetAfterBreak:
                    return prescription.targetRepsRange.lowerBound
                default:
                    return baseTargetReps
                }
            }()

            // Apply volume adjustment based on direction.
            //
            // IMPORTANT:
            // - Deload volume reduction must respect `DeloadConfig.volumeReduction` (sets to remove),
            //   which is threaded through the magnitude layer as `volumeAdjustment`.
            let setCount: Int = {
                let base = prescription.setCount
                
                switch directionDecision.direction {
                case .deload:
                    return max(1, base + volumeAdjustment)
                case .decreaseSlightly:
                    // Small reduction for acute readiness: -1 set (from magnitude policy)
                    return max(1, base + volumeAdjustment)
                case .resetAfterBreak:
                    // Break resets may have modest volume reduction
                    return max(1, base + volumeAdjustment)
                default:
                    // Normal sessions: no volume adjustment
                    return max(1, base + volumeAdjustment)
                }
            }()
            
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
            
            // Map direction to adjustment kind for persistence
            let recommendedAdjustmentKind: SessionAdjustmentKind? = {
                switch directionDecision.direction {
                case .deload:
                    return .deload
                case .decreaseSlightly:
                    return .readinessCut
                case .resetAfterBreak:
                    return .breakReset
                case .increase:
                    return SessionAdjustmentKind.none
                case .hold:
                    // V10: Allow "hold load + readiness cut (volume reduction)" as a first-class outcome.
                    // If we held specifically due to acute low readiness AND magnitude applied a volume reduction,
                    // persist as a readinessCut even though the load direction is HOLD.
                    if directionDecision.primaryReason == .acuteLowReadinessSingleDay && volumeAdjustment < 0 {
                        return .readinessCut
                    }
                    return SessionAdjustmentKind.none
                }
            }()
            
            exercisePlans.append(ExercisePlan(
                exercise: exercise,
                prescription: prescription,
                sets: setPlans,
                progressionPolicy: progressionPolicy,
                inSessionPolicy: inSessionPolicy,
                substitutions: substitutions,
                recommendedAdjustmentKind: recommendedAdjustmentKind,
                direction: directionDecision.direction,
                directionReason: directionDecision.primaryReason,
                directionExplanation: directionDecision.explanation,
                policyChecks: policyChecks
            ))
            
            // Log decision for ML training data collection
            logDecisionIfEnabled(
                sessionId: UUID(), // Caller can override via context
                userId: "anonymous",
                sessionDate: date,
                exerciseId: effectiveExerciseId,
                history: history,
                liftState: liftState,
                signals: signals,
                direction: directionDecision,
                magnitude: magnitudeParams,
                baselineLoad: baselineLoad,
                finalLoad: sessionBaseLoad,
                targetReps: targetReps,
                targetRIR: prescription.targetRIR,
                setCount: setCount,
                volumeAdjustment: volumeAdjustment,
                isSessionDeload: deloadDecision.shouldDeload,
                adjustmentKind: recommendedAdjustmentKind ?? .none,
                policyChecks: policyChecks,
                plan: plan,
                userProfile: userProfile,
                exercise: exercise,
                originalExercise: originalExercise,
                familyResolution: familyResolution,
                stateIsExerciseSpecific: stateIsExerciseSpecific,
                isPlannedDeloadWeek: plannedDeloadWeek,
                calendar: calendar
            )
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
    
    // MARK: - Direction/Magnitude System
    
    /// Builds lift signals for direction/magnitude decision.
    private static func buildLiftSignals(
        exerciseId: String,
        exercise: Exercise,
        liftState: LiftState,
        prescription: SetPrescription,
        history: WorkoutHistory,
        userProfile: UserProfile,
        todayReadiness: Int,
        sessionDeloadTriggered: Bool,
        sessionDeloadReason: DeloadReason?,
        date: Date,
        calendar: Calendar
    ) -> LiftSignals {
        // Get last session results for this exercise (non-deload)
        let lastResult = history.exerciseResults(forExercise: exerciseId, limit: 1).first
        let workingSets = lastResult?.workingSets ?? []
        
        // Determine if last session was a failure
        let targetRepsLower = prescription.targetRepsRange.lowerBound
        let lastSessionWasFailure = !workingSets.isEmpty && workingSets.contains { $0.reps < targetRepsLower }
        
        // Determine if last session was a grinder (success but RIR significantly below target)
        //
        // "True grinder" requires meaningful RIR shortfall to avoid false positives:
        // - If target RIR = 2 and observed RIR = 1, that's NOT a grinder (just slightly harder)
        // - If target RIR = 2 and observed RIR = 0, that's a grinder (truly grinding)
        //
        // This prevents over-deloading from marginal RIR misses.
        let targetRIR = prescription.targetRIR
        let observedRIRs = workingSets.compactMap(\.rirObserved)
        let grinderRirDelta = DirectionPolicyConfig.default.grinderRirDelta // Minimum shortfall to count as grinder
        let lastSessionWasGrinder: Bool = {
            guard !observedRIRs.isEmpty, !lastSessionWasFailure else { return false }
            guard targetRIR > 0 else { return false }
            let minObserved = observedRIRs.min() ?? targetRIR
            // Require RIR shortfall > delta to count as true grinder
            // E.g., if delta=1 and targetRIR=2, only observed RIR<=0 is a grinder
            return minObserved <= (targetRIR - grinderRirDelta - 1)
        }()
        
        // Average observed RIR
        let avgRIR: Double? = observedRIRs.isEmpty ? nil : Double(observedRIRs.reduce(0, +)) / Double(observedRIRs.count)
        
        // Compute recent session RIRs for "two easy sessions" gate (V10 conservative progression).
        // Look at last 5 sessions and compute average RIR for each.
        let recentResults = history.exerciseResults(forExercise: exerciseId, limit: 5)
        let recentSessionRIRs: [Double] = recentResults.compactMap { result in
            let workingRIRs = result.workingSets.compactMap(\.rirObserved)
            guard !workingRIRs.isEmpty else { return nil }
            return Double(workingRIRs.reduce(0, +)) / Double(workingRIRs.count)
        }
        
        // Count consecutive "easy" sessions (most recent first).
        //
        // V10: For advanced/elite upper-body presses, the "two easy sessions" gate is meant to be
        // STRICT and confirmation-based: we require consecutive easy sessions, not just 2-of-last-5.
        // This reduces premature hold→increase flips in microloading regimes.
        let easyMargin: Double = {
            let isUpperBodyPress = exercise.movementPattern == .horizontalPush || exercise.movementPattern == .verticalPush
            if isUpperBodyPress && (userProfile.experience == .advanced || userProfile.experience == .elite) {
                return 1.0
            }
            return 0.5
        }()
        let easyRirThreshold = Double(targetRIR) + easyMargin
        
        var recentEasySessionCount = 0
        for sessionAvgRIR in recentSessionRIRs {
            if sessionAvgRIR >= easyRirThreshold {
                recentEasySessionCount += 1
            } else {
                break
            }
        }
        
        // Days since last exposure
        let daysSinceLastExposure = liftState.daysSinceLastSession(from: date, calendar: calendar)
        
        // Days since last deload
        let daysSinceDeload = liftState.daysSinceDeload(from: date, calendar: calendar)
        
        // Infer session intent from prescription (or use template-level intent if available)
        let sessionIntent = SessionIntent.infer(from: prescription)
        
        return LiftSignals(
            exerciseId: exerciseId,
            movementPattern: exercise.movementPattern,
            equipment: exercise.equipment,
            lastWorkingWeight: liftState.lastWorkingWeight,
            rollingE1RM: liftState.rollingE1RM,
            failStreak: liftState.failStreak,
            highRpeStreak: liftState.highRpeStreak,
            daysSinceLastExposure: daysSinceLastExposure,
            daysSinceDeload: daysSinceDeload,
            trend: liftState.trend,
            successfulSessionsCount: liftState.successfulSessionsCount,
            successStreak: liftState.successStreak,
            lastSessionWasFailure: lastSessionWasFailure,
            lastSessionWasGrinder: lastSessionWasGrinder,
            lastSessionAvgRIR: avgRIR,
            lastSessionReps: workingSets.map(\.reps),
            recentSessionRIRs: recentSessionRIRs,
            recentEasySessionCount: recentEasySessionCount,
            todayReadiness: todayReadiness,
            recentReadinessScores: liftState.recentReadinessScores,
            prescription: prescription,
            experienceLevel: userProfile.experience,
            sex: userProfile.sex,
            bodyWeight: userProfile.bodyWeight,
            sessionDeloadTriggered: sessionDeloadTriggered,
            sessionDeloadReason: sessionDeloadReason,
            sessionIntent: sessionIntent,
            primaryGoal: userProfile.goals.first
        )
    }
    
    /// Computes the target load using the direction/magnitude system.
    private static func computeTargetLoadWithDirectionMagnitude(
        signals: LiftSignals,
        baseTargetLoad: Load,
        liftState: LiftState,
        plan: TrainingPlan,
        directionConfig: DirectionPolicyConfig? = nil,
        magnitudeConfig: MagnitudePolicyConfig? = nil
    ) -> (load: Load, direction: DirectionDecision, magnitude: MagnitudeParams, volumeAdjustment: Int, checks: [PolicyCheckResult]) {
        // Build direction config, deriving readiness thresholds from plan.deloadConfig when available.
        // This ensures test harnesses and production code use consistent thresholds.
        let effectiveDirectionConfig: DirectionPolicyConfig = {
            if let explicit = directionConfig {
                return explicit
            }
            // Derive from plan.deloadConfig if available
            if let deloadConfig = plan.deloadConfig {
                return DirectionPolicyConfig(
                    extendedBreakDays: DirectionPolicyConfig.default.extendedBreakDays,
                    trainingGapDays: DirectionPolicyConfig.default.trainingGapDays,
                    readinessThreshold: deloadConfig.readinessThreshold,
                    severeLowReadinessThreshold: max(20, deloadConfig.readinessThreshold - 10),
                    persistentLowReadinessExposures: DirectionPolicyConfig.default.persistentLowReadinessExposures,
                    baseFailStreakThreshold: DirectionPolicyConfig.default.baseFailStreakThreshold,
                    baseHighRpeStreakThreshold: DirectionPolicyConfig.default.baseHighRpeStreakThreshold,
                    grinderRirDelta: DirectionPolicyConfig.default.grinderRirDelta
                )
            }
            return .default
        }()
        
        // Build magnitude config, deriving deload parameters from plan.deloadConfig when available.
        let effectiveMagnitudeConfig: MagnitudePolicyConfig = {
            if let explicit = magnitudeConfig {
                return explicit
            }
            // Derive from plan.deloadConfig if available
            if let deloadConfig = plan.deloadConfig {
                return MagnitudePolicyConfig(
                    enableMicroloading: MagnitudePolicyConfig.default.enableMicroloading,
                    baseDeloadReduction: deloadConfig.intensityReduction,
                    deloadVolumeReduction: deloadConfig.volumeReduction,
                    baseBreakResetReduction: MagnitudePolicyConfig.default.baseBreakResetReduction,
                    acuteReadinessVolumeReduction: MagnitudePolicyConfig.default.acuteReadinessVolumeReduction
                )
            }
            return .default
        }()
        
        // Get direction decision with trace
        let (direction, policyChecks) = DirectionPolicy.decideWithTrace(signals: signals, config: effectiveDirectionConfig)
        
        // Get magnitude params
        let magnitude = MagnitudePolicy.compute(
            direction: direction,
            signals: signals,
            baseRoundingPolicy: plan.loadRoundingPolicy,
            config: effectiveMagnitudeConfig
        )
        
        // Compute final load
        var finalLoad = baseTargetLoad
        
        // Apply multiplier first
        if magnitude.loadMultiplier != 1.0 {
            finalLoad = finalLoad * magnitude.loadMultiplier
        }
        
        // Apply absolute increment
        if magnitude.absoluteIncrement.value != 0 {
            finalLoad = finalLoad + magnitude.absoluteIncrement
        }
        
        // Apply rounding
        finalLoad = finalLoad.rounded(using: magnitude.roundingPolicy)
        
        // For hold/decrease directions, don't exceed the baseTargetLoad (not lastWorkingWeight).
        // This prevents rounding from accidentally increasing load while still allowing
        // %e1RM programs to prescribe loads that exceed the last working weight.
        // The baseTargetLoad represents the "intended" load before direction/magnitude adjustments.
        switch direction.direction {
        case .hold, .decreaseSlightly:
            let clampTarget = baseTargetLoad.converted(to: finalLoad.unit)
            // Only clamp if final load exceeds the base target (due to rounding)
            // Allow small epsilon for floating-point comparison
            let epsilon = magnitude.roundingPolicy.increment * 0.1
            if clampTarget.value > 0 && finalLoad.value > clampTarget.value + epsilon {
                finalLoad = clampTarget.rounded(using: magnitude.roundingPolicy)
            }
        default:
            break
        }
        
        // SAFETY CLAMPS: Prevent unsafe step changes (except explicit reset/deload cases).
        // This guards against unit mistakes or outlier prescriptions causing massive jumps.
        // 
        // IMPORTANT: These clamps apply against lastWorkingWeight, not against the program's
        // target load. For %e1RM prescriptions that legitimately exceed lastWorkingWeight
        // (e.g., program change or e1RM improvement), we should allow the jump.
        // We detect this by checking if baseTargetLoad significantly differs from lastWorkingWeight.
        let lastWorkingLb = liftState.lastWorkingWeight.converted(to: finalLoad.unit)
        let baseTargetLb = baseTargetLoad.converted(to: finalLoad.unit)
        
        if lastWorkingLb.value > 0 {
            let ratio = finalLoad.value / lastWorkingLb.value
            let programRequestedRatio = baseTargetLb.value / lastWorkingLb.value
            
            // If the program (via %e1RM or prescription change) explicitly requests a different
            // load than lastWorkingWeight, allow it within broader safety bounds.
            let isProgramDrivenJump = abs(programRequestedRatio - 1.0) > 0.05 // >5% program change
            
            // Determine max allowed change ratio based on direction and movement pattern
            let (minRatio, maxRatio): (Double, Double) = {
                switch direction.direction {
                case .deload, .resetAfterBreak:
                    // Allow larger drops for deloads/resets
                    return (0.60, 1.10)
                case .increase:
                    // Upper body gets tighter caps
                    if signals.isUpperBodyPress {
                        return (0.95, 1.15)
                    } else {
                        return (0.90, 1.25)
                    }
                default:
                    // Hold/decrease: shouldn't increase more than a rounding step
                    // UNLESS the program explicitly requests a different load
                    if isProgramDrivenJump {
                        // Allow program-driven changes up to 25% (covers most program transitions)
                        return (0.75, 1.25)
                    }
                    if signals.isUpperBodyPress {
                        return (0.85, 1.03)
                    } else {
                        return (0.80, 1.05)
                    }
                }
            }()
            
            // Clamp if out of bounds
            if ratio < minRatio {
                finalLoad = Load(value: lastWorkingLb.value * minRatio, unit: finalLoad.unit)
                    .rounded(using: magnitude.roundingPolicy)
            } else if ratio > maxRatio {
                finalLoad = Load(value: lastWorkingLb.value * maxRatio, unit: finalLoad.unit)
                    .rounded(using: magnitude.roundingPolicy)
            }
        }
        
        return (finalLoad, direction, magnitude, magnitude.volumeAdjustment, policyChecks)
    }
    
    // MARK: - Cold start / initial loading
    
    /// Estimate a safe, non-zero starting load for a lift when there is no prior history/state.
    ///
    /// This is intended to approximate "onboarding working weights" that a real app would collect.
    /// It uses coarse strength-standard ratios (1RM as a multiple of bodyweight) and converts to a
    /// working weight at the prescription's reps/RIR using inverse Brzycki.
    ///
    /// If bodyweight is missing, returns nil (caller should fall back to 0).
    private static func initialWorkingLoadEstimate(
        for exercise: Exercise,
        prescription: SetPrescription,
        userProfile: UserProfile,
        roundingPolicy: LoadRoundingPolicy
    ) -> Load? {
        // Never estimate external load for bodyweight exercises.
        guard exercise.equipment != .bodyweight else { return .zero }
        
        guard let bw = userProfile.bodyWeight?.converted(to: .pounds).value, bw > 0 else {
            return nil
        }
        
        // Map sex "other" to the mid-point of male/female ratios.
        func blend(_ male: Double, _ female: Double) -> Double {
            switch userProfile.sex {
            case .male: return male
            case .female: return female
            case .other: return (male + female) / 2.0
            }
        }
        
        // Cold-start e1RM ratios are intentionally CONSERVATIVE to avoid over-prescribing
        // for new users or returning lifters. It's better to start too light and progress
        // than to start too heavy and need immediate deloads.
        //
        // These ratios are approximately 15-20% lower than typical strength standards,
        // allowing room for technique refinement and building work capacity.
        let ratio1RM: Double? = {
            // Strength standards are most meaningful for compound patterns.
            switch exercise.movementPattern {
            case .horizontalPush:
                switch userProfile.experience {
                case .beginner: return blend(0.95, 0.45) // Was 1.18/0.55
                case .intermediate: return blend(1.05, 0.60) // Was 1.25/0.75
                case .advanced: return blend(1.20, 0.75) // Was 1.40/0.90
                case .elite: return blend(1.35, 0.90) // Was 1.55/1.05
                }
            case .verticalPush:
                switch userProfile.experience {
                case .beginner: return blend(0.60, 0.28) // Was 0.77/0.35
                case .intermediate: return blend(0.70, 0.40) // Was 0.85/0.50
                case .advanced: return blend(0.80, 0.50) // Was 0.95/0.60
                case .elite: return blend(0.90, 0.60) // Was 1.05/0.70
                }
            case .squat:
                switch userProfile.experience {
                case .beginner: return blend(1.25, 0.72) // Was 1.57/0.90
                case .intermediate: return blend(1.40, 0.95) // Was 1.70/1.20
                case .advanced: return blend(1.55, 1.15) // Was 1.85/1.40
                case .elite: return blend(1.75, 1.35) // Was 2.10/1.60
                }
            case .hipHinge:
                switch userProfile.experience {
                case .beginner: return blend(1.40, 0.80) // Was 1.73/1.00
                case .intermediate: return blend(1.65, 1.15) // Was 2.00/1.40
                case .advanced: return blend(1.80, 1.35) // Was 2.20/1.65
                case .elite: return blend(2.10, 1.55) // Was 2.50/1.85
                }
            case .horizontalPull, .verticalPull:
                // Pulling strength varies widely by exercise selection; keep conservative.
                switch userProfile.experience {
                case .beginner: return blend(0.65, 0.45) // Was 0.80/0.55
                case .intermediate: return blend(0.80, 0.55) // Was 0.95/0.70
                case .advanced: return blend(0.90, 0.65) // Was 1.10/0.80
                case .elite: return blend(1.00, 0.75) // Was 1.20/0.90
                }
            case .lunge:
                // Unilateral lower body: treat as a conservative fraction of squat strength.
                switch userProfile.experience {
                case .beginner: return blend(0.85, 0.60) // Was 1.05/0.75
                case .intermediate: return blend(0.95, 0.75) // Was 1.20/0.95
                case .advanced: return blend(1.10, 0.90) // Was 1.35/1.10
                case .elite: return blend(1.25, 1.00) // Was 1.55/1.25
                }
            default:
                return nil
            }
        }()
        
        guard let ratio1RM else { return nil }
        let e1rmEstimate = bw * ratio1RM
        
        // Interpret targetRIR as "reps in reserve": estimated failure reps ≈ target reps + RIR.
        let targetReps = max(1, prescription.targetRepsRange.lowerBound)
        let repsToFailure = max(1, min(12, targetReps + max(0, prescription.targetRIR)))
        let rawWorking = E1RMCalculator.workingWeight(fromE1RM: e1rmEstimate, targetReps: repsToFailure)
        
        // Equipment-specific minimums to avoid returning tiny loads for barbell patterns.
        let minLb: Double = {
            switch exercise.equipment {
            case .barbell, .trapBar, .ezBar:
                return 45
            case .smithMachine, .plateLoaded:
                return 45
            case .dumbbell, .kettlebell:
                return 5
            case .machine, .cable, .resistanceBand:
                return 10
            default:
                return 0
            }
        }()
        
        let clamped = max(minLb, rawWorking)
        return Load(value: clamped, unit: .pounds)
            .converted(to: roundingPolicy.unit)
            .rounded(using: roundingPolicy)
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
                ProgressionContext(
                    userProfile: $0,
                    exercise: exercise,
                    date: date,
                    calendar: calendar,
                    sessionIntent: SessionIntent.infer(from: prescription)
                )
            }
            
            let candidate: Load = {
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
            
            // Cold start: estimate a starting load if we have no baseline and no history.
            if candidate.value <= 0.0001,
               liftState.lastWorkingWeight.value <= 0.0001,
               history.exerciseResults(forExercise: exerciseId, limit: 1).isEmpty,
               let up = userProfile,
               let estimated = initialWorkingLoadEstimate(
                for: exercise,
                prescription: prescription,
                userProfile: up,
                roundingPolicy: roundingPolicy
               )
            {
                return estimated
            }
            
            return candidate
        }()
        
        // Detraining reduction for long hiatuses.
        let detrainingReduction: Double = {
            guard let last = liftState.lastSessionDate else { return 0 }
            let lastDay = calendar.startOfDay(for: last)
            let today = calendar.startOfDay(for: date)
            let days = calendar.dateComponents([.day], from: lastDay, to: today).day ?? 0
            
            switch days {
            case 0..<14:
                return 0
            case 14..<28:
                return 0.05
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
        // Use ~40% volume reduction for deloads per rulebook intent.
        let setCount: Int = {
            guard isDeload else { return prescription.setCount }
            let base = prescription.setCount
            let reductionSets = max(1, Int(round(0.4 * Double(base))))
            return max(1, base - reductionSets)
        }()
        
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
    
    // MARK: - ML Training Data Logging
    
    /// Internal helper to log decisions when logging is enabled.
    private static func logDecisionIfEnabled(
        sessionId: UUID,
        userId: String,
        sessionDate: Date,
        exerciseId: String,
        history: WorkoutHistory,
        liftState: LiftState,
        signals: LiftSignals,
        direction: DirectionDecision,
        magnitude: MagnitudeParams,
        baselineLoad: Load,
        finalLoad: Load,
        targetReps: Int,
        targetRIR: Int,
        setCount: Int,
        volumeAdjustment: Int,
        isSessionDeload: Bool,
        adjustmentKind: SessionAdjustmentKind,
        policyChecks: [PolicyCheckResult],
        plan: TrainingPlan,
        userProfile: UserProfile,
        exercise: Exercise,
        originalExercise: Exercise,
        familyResolution: LiftFamilyResolution,
        stateIsExerciseSpecific: Bool,
        isPlannedDeloadWeek: Bool,
        calendar: Calendar
    ) {
        // Build variation context
        let variationContext = VariationContext(
            isPrimaryExercise: exercise.id == originalExercise.id,
            isSubstitution: exercise.id != originalExercise.id,
            originalExerciseId: exercise.id != originalExercise.id ? originalExercise.id : nil,
            familyReferenceKey: familyResolution.referenceStateKey,
            familyUpdateKey: familyResolution.updateStateKey,
            familyCoefficient: familyResolution.coefficient,
            movementPattern: exercise.movementPattern,
            equipment: exercise.equipment,
            stateIsExerciseSpecific: stateIsExerciseSpecific
        )
        
        TrainingDataLogger.shared.logDecision(
            sessionId: sessionId,
            exerciseId: exerciseId,
            userId: userId,
            sessionDate: sessionDate,
            history: history,
            liftState: liftState,
            signals: signals,
            direction: direction,
            magnitude: magnitude,
            baselineLoad: baselineLoad,
            finalLoad: finalLoad,
            targetReps: targetReps,
            targetRIR: targetRIR,
            setCount: setCount,
            volumeAdjustment: volumeAdjustment,
            isSessionDeload: isSessionDeload,
            adjustmentKind: adjustmentKind,
            policyChecks: policyChecks,
            plan: plan,
            userProfile: userProfile,
            variationContext: variationContext,
            isPlannedDeloadWeek: isPlannedDeloadWeek,
            calendar: calendar
        )
    }
    
    /// Records outcome for a completed exercise result.
    /// Call this after a session is completed to link outcomes to decisions.
    public static func recordOutcome(
        sessionId: UUID,
        exerciseResult: ExerciseSessionResult,
        readinessScore: Int?
    ) {
        TrainingDataLogger.shared.recordOutcome(
            sessionId: sessionId,
            exerciseId: exerciseResult.exerciseId,
            exerciseResult: exerciseResult,
            readinessScore: readinessScore
        )
    }
    
    /// Links next-session performance to a previous session.
    /// Call this when the same exercise is performed again to capture longitudinal outcomes.
    public static func linkNextSessionPerformance(
        previousSessionId: UUID,
        exerciseId: String,
        nextSessionDate: Date,
        nextExerciseResult: ExerciseSessionResult,
        previousSessionDate: Date,
        previousE1RM: Double,
        calendar: Calendar = .current
    ) {
        TrainingDataLogger.shared.linkNextSessionPerformance(
            previousSessionId: previousSessionId,
            exerciseId: exerciseId,
            nextSessionDate: nextSessionDate,
            nextExerciseResult: nextExerciseResult,
            previousSessionDate: previousSessionDate,
            previousE1RM: previousE1RM,
            calendar: calendar
        )
    }
    
    /// Enables or disables ML training data logging.
    public static func setLoggingEnabled(_ enabled: Bool) {
        TrainingDataLogger.shared.isEnabled = enabled
    }
    
    /// Sets a custom log handler for ML training data.
    public static func setLogHandler(_ handler: @escaping (DecisionLogEntry) -> Void) {
        TrainingDataLogger.shared.logHandler = handler
    }
    
    /// Creates a file-based JSONL log handler.
    public static func createFileLogHandler(path: String) -> (DecisionLogEntry) -> Void {
        TrainingDataLogger.fileLogHandler(path: path)
    }
    
    /// Adds a counterfactual policy for comparison logging.
    public static func addCounterfactualPolicy(_ policy: CounterfactualPolicy) {
        TrainingDataLogger.shared.counterfactualPolicies.append(policy)
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
    /// NOTE: State is stored under canonical family keys for progression continuity.
    public static func updateLiftState(afterSession session: CompletedSession) -> [LiftState] {
        var updatedStates: [LiftState] = []
        
        for exerciseResult in session.exerciseResults {
            let exerciseId = exerciseResult.exerciseId
            
            // Resolve state keys: referenceStateKey for reading, updateStateKey for writing
            let stateKeyResolution = LiftFamilyResolver.resolveStateKeys(fromId: exerciseId)
            let referenceStateKey = stateKeyResolution.referenceStateKey
            let updateStateKey = stateKeyResolution.updateStateKey
            let familyCoefficient = stateKeyResolution.coefficient
            
            // Look up existing state. For variations/substitutions:
            // - First try the exercise's own update key (it may have its own state)
            // - Then fall back to the family reference key (for initial load estimation)
            var state: LiftState = {
                // Try update key first (exercise-specific state)
                if let existing = session.previousLiftStates[updateStateKey] {
                    return existing
                }
                // Try reference key (family baseline) if different
                if updateStateKey != referenceStateKey, let existing = session.previousLiftStates[referenceStateKey] {
                    // Scale the reference state's values by coefficient for migration
                    let scaledLastWorkingWeight = existing.lastWorkingWeight * familyCoefficient
                    let scaledRollingE1RM = existing.rollingE1RM * familyCoefficient
                    return LiftState(
                        exerciseId: updateStateKey,
                        lastWorkingWeight: scaledLastWorkingWeight,
                        rollingE1RM: scaledRollingE1RM,
                        failureCount: 0, // Fresh start for this exercise
                        highRpeStreak: 0,
                        lastDeloadDate: existing.lastDeloadDate, // Inherit deload timing
                        trend: .stable,
                        e1rmHistory: [],
                        lastSessionDate: nil,
                        successfulSessionsCount: 0,
                        recentReadinessScores: [],
                        postBreakRamp: nil
                    )
                }
                // Try exercise ID if different from update key
                if let existing = session.previousLiftStates[exerciseId], exerciseId != updateStateKey {
                    return existing
                }
                return LiftState(exerciseId: updateStateKey)
            }()
            
            // Ensure state uses the correct update key
            if state.exerciseId != updateStateKey {
                state = LiftState(
                    exerciseId: updateStateKey,
                    lastWorkingWeight: state.lastWorkingWeight,
                    rollingE1RM: state.rollingE1RM,
                    failureCount: state.failureCount,
                    highRpeStreak: state.highRpeStreak,
                    lastDeloadDate: state.lastDeloadDate,
                    trend: state.trend,
                    e1rmHistory: state.e1rmHistory,
                    lastSessionDate: state.lastSessionDate,
                    successfulSessionsCount: state.successfulSessionsCount,
                    recentReadinessScores: state.recentReadinessScores,
                    postBreakRamp: state.postBreakRamp
                )
            }
            
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
            
            // For variations/substitutions (updateStateKey != referenceStateKey), store the load directly
            // (no coefficient conversion). For direct family members, also store directly.
            // 
            // Previous behavior converted back to family baseline, but this caused state contamination
            // where variations would overwrite the base lift's state.
            //
            // New behavior:
            // - Variations/substitutions maintain their own state at their own scale
            // - When we need to estimate a variation's load, we read from family baseline and apply coefficient
            // - When we update, we write to the variation's own state at the performed scale
            let performedLoad = maxLoad.converted(to: sessionUnit)
            var proposedLastWorkingWeight: Load = performedLoad

            // Compute session e1RM (best estimated 1RM from any set, at the performed scale)
            var sessionE1RM: Double = {
                let performedE1RM = workingSets
                    .map { set -> Double in
                        let w = set.load.converted(to: sessionUnit).value
                        return E1RMCalculator.brzycki(weight: w, reps: set.reps)
                    }
                    .max() ?? 0
                
                return performedE1RM
            }()
            
            // Check if session was a failure (any set below lower bound of rep range)
            let prescription = exerciseResult.prescription
            let anyFailure = workingSets.contains { $0.reps < prescription.targetRepsRange.lowerBound }
            
            // Check if session was a grinder (all reps achieved but RIR significantly below target)
            // Use stricter definition to avoid over-counting marginal RIR misses
            let targetRIR = prescription.targetRIR
            let observedRIRs = workingSets.compactMap(\.rirObserved)
            let grinderRirDelta = DirectionPolicyConfig.default.grinderRirDelta
            let wasGrinder: Bool = {
                guard !observedRIRs.isEmpty, !anyFailure else { return false }
                guard targetRIR > 0 else { return false }
                let minObserved = observedRIRs.min() ?? targetRIR
                // Require meaningful RIR shortfall (> delta) to count as true grinder
                return minObserved <= (targetRIR - grinderRirDelta - 1)
            }()
            
            // Update readiness history if we have a readiness score
            if let readiness = session.readinessScore {
                state.appendReadinessScore(readiness)
            }
            
            // Determine if baseline should be updated based on adjustment kind.
            // Prefer per-exercise adjustment kind when present; fall back to session-level.
            let effectiveAdjustmentKind = exerciseResult.adjustmentKind ?? session.adjustmentKind
            let shouldUpdateBaseline: Bool = {
                switch effectiveAdjustmentKind {
                case .none:
                    return true
                case .deload, .readinessCut:
                    return false
                case .breakReset:
                    // Break resets do update baseline (they're the new reality)
                    return true
                }
            }()

            // IMPORTANT: Deload and readiness-cut sessions should not overwrite the lift's working-weight baseline.
            //
            // Why:
            // - These sessions intentionally reduce load and/or volume.
            // - If we treat them as normal datapoints, the baseline can drift down.
            //
            // We still update:
            // - lastSessionDate (so detraining logic stays correct)
            // - lastDeloadDate (for deloads)
            // - failureCount / highRpeStreak
            // - recentReadinessScores
            // - postBreakRamp progress
            if !shouldUpdateBaseline && effectiveAdjustmentKind != .breakReset {
                let daysSinceLast: Int = {
                    var cal = Calendar(identifier: .gregorian)
                    cal.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
                    guard let last = state.lastSessionDate else { return Int.max }
                    let lastDay = cal.startOfDay(for: last)
                    let today = cal.startOfDay(for: session.date)
                    return cal.dateComponents([.day], from: lastDay, to: today).day ?? 0
                }()
                
                state.lastSessionDate = session.date
                
                // Update deload date if this was a true deload
                if effectiveAdjustmentKind == .deload {
                    state.lastDeloadDate = session.date
                    // Reset streaks after deload (includes successStreak)
                    state.resetStreaks()
                    
                    // Start post-deload ramp if not already ramping
                    // The target is the pre-deload working weight (stored in state.lastWorkingWeight)
                    if state.postDeloadRamp == nil && state.lastWorkingWeight.value > 0 {
                        state.startPostDeloadRamp(
                            targetWeight: state.lastWorkingWeight,
                            sessions: 2,
                            date: session.date
                        )
                    }
                } else {
                    // For readiness cuts: DON'T track failure/grinder streaks
                    // Readiness cuts are intentional load reductions, so failures/grinders
                    // during a cut are NOT evidence that you need to deload.
                    // 
                    // We only reset success streak (cut sessions shouldn't count toward progression)
                    // but we preserve failure/grinder counts - a cut shouldn't add to deload evidence.
                    state.successStreak = 0
                    // Note: we intentionally do NOT modify failureCount or highRpeStreak here
                }
                
                let priorW = state.lastWorkingWeight.value
                let currentW = proposedLastWorkingWeight.value
                let ratio = (priorW > 0 && currentW > 0) ? (currentW / priorW) : 1.0
                let isLargeBaselineShift = ratio < 0.75 || ratio > 1.35
                
                // Special case: long gaps or large baseline shifts should update even for deloads
                if daysSinceLast >= 28 || isLargeBaselineShift {
                    state.lastWorkingWeight = proposedLastWorkingWeight
                    
                    let alpha = 0.3
                    if state.rollingE1RM > 0 {
                        state.rollingE1RM = alpha * sessionE1RM + (1 - alpha) * state.rollingE1RM
                    } else {
                        state.rollingE1RM = sessionE1RM
                    }
                    
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
                
                if ratio < 0.60 || ratio > 1.67 {
                    let kgToLb = 2.20462
                    let lbToKg = 0.453592
                    
                    func within(_ x: Double, _ lo: Double, _ hi: Double) -> Bool { x >= lo && x <= hi }
                    
                    let strongSignal = abs(ratio - lbToKg) < 0.03 || abs(ratio - kgToLb) < 0.12
                    let allowCorrection = strongSignal || (daysSinceLast < 56)
                    if allowCorrection {
                        if abs(ratio - lbToKg) < 0.08 {
                            let corrected = current * kgToLb
                            if within(corrected / prior, 0.75, 1.35) {
                                proposedLastWorkingWeight = Load(value: corrected, unit: sessionUnit)
                                sessionE1RM *= kgToLb
                            }
                        } else if abs(ratio - kgToLb) < 0.25 {
                            let corrected = current * lbToKg
                            if within(corrected / prior, 0.75, 1.35) {
                                proposedLastWorkingWeight = Load(value: corrected, unit: sessionUnit)
                                sessionE1RM *= lbToKg
                            }
                        }
                    }
                }
            }
            
            // Normal session or break reset: update working baseline and performance signals.
            state.lastWorkingWeight = proposedLastWorkingWeight
            
            // Update rolling e1RM with exponential smoothing
            let alpha = 0.3
            if state.rollingE1RM > 0 {
                state.rollingE1RM = alpha * sessionE1RM + (1 - alpha) * state.rollingE1RM
            } else {
                state.rollingE1RM = sessionE1RM
            }
            
            // Update streak counters
            if anyFailure {
                state.failureCount += 1
                state.highRpeStreak = 0
                state.successStreak = 0 // Reset success streak on failure
            } else if wasGrinder {
                state.failureCount = 0
                state.highRpeStreak += 1
                state.successStreak = 0 // Reset success streak on grinder
            } else {
                // Clean success - reset negative streaks, increment success streak
                state.failureCount = 0
                state.highRpeStreak = 0
                state.successStreak += 1
            }
            
            // Update trend based on e1RM history
            state.e1rmHistory.append(E1RMSample(date: session.date, value: sessionE1RM))
            if state.e1rmHistory.count > 10 {
                state.e1rmHistory.removeFirst(state.e1rmHistory.count - 10)
            }
            
            state.trend = TrendCalculator.compute(from: state.e1rmHistory)
            state.lastSessionDate = session.date
            if !anyFailure {
                state.successfulSessionsCount += 1
            }
            
            // Handle post-break ramp progress
            if effectiveAdjustmentKind == .breakReset {
                // Start ramp if not already ramping (first session after break)
                if state.postBreakRamp == nil && state.lastWorkingWeight.value > 0 {
                    state.startPostBreakRamp(
                        targetWeight: state.lastWorkingWeight,
                        sessions: 2,
                        date: session.date
                    )
                }
                state.incrementRampProgress()
            } else if state.postBreakRamp != nil && state.postBreakRamp?.isComplete == true {
                // Clear completed ramp
                state.clearPostBreakRamp()
            }
            
            // Handle post-deload ramp progress on normal sessions
            if let deloadRamp = state.postDeloadRamp {
                if effectiveAdjustmentKind == .none || effectiveAdjustmentKind == .readinessCut {
                    // Non-deload session while in deload ramp: progress the ramp
                    state.incrementDeloadRampProgress()
                }
                // If deload ramp is complete, clear it
                if deloadRamp.isComplete {
                    state.clearPostDeloadRamp()
                }
            }
            
            updatedStates.append(state)
        }
        
        return updatedStates
    }
}
