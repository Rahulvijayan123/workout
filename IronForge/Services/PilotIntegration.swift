import Foundation

// MARK: - Pilot Integration
/// Bridges the pilot telemetry and guardrails into the main workout flow.
/// This extension adds pilot-aware versions of key WorkoutStore methods.

extension WorkoutStore {
    
    // MARK: - Pilot-Aware Session Start
    
    /// Start a session with pilot telemetry and guardrails applied
    func startPilotSession(
        from template: WorkoutTemplate,
        userProfile: UserProfile? = nil,
        readiness: Int = 75,
        dailyBiometrics: [DailyBiometrics] = [],
        pilotService: PilotTelemetryService,
        guardrailConfig: PilotGuardrails.Config = .conservative
    ) {
        // 1. Get engine recommendation (unmodified)
        let sessionPlan = TrainingEngineBridge.recommendSessionForTemplate(
            date: Date(),
            templateId: template.id,
            userProfile: userProfile ?? UserProfile(),
            templates: templates,
            sessions: sessions,
            liftStates: exerciseStates,
            readiness: readiness,
            dailyBiometrics: dailyBiometrics
        )
        
        // 2. Start session with pilot metadata
        pilotService.onSessionStart(sessionId: UUID())
        
        // 3. Record trajectories and apply guardrails for each exercise
        var modifiedExercisePlans: [(exercise: TrainingEngine.ExercisePlan, wasModified: Bool, intervention: PilotGuardrails.Intervention?)] = []
        
        for exercisePlan in sessionPlan.exercises {
            let exerciseId = exercisePlan.exercise.id
            let exerciseName = exercisePlan.exercise.name
            let priorState = exerciseStates[exerciseId]
            
            // Get recent history for guardrails
            let recentHistory = buildRecentHistory(for: exerciseId)
            
            // Build engine recommendation for guardrail check
            let engineRec = PilotGuardrails.EngineRecommendation(
                type: mapDecisionType(from: sessionPlan, for: exerciseId),
                weightLbs: exercisePlan.sets.first?.targetLoad.converted(to: .pounds).value ?? 0,
                reps: exercisePlan.sets.first?.targetReps ?? 0,
                deloadReductionPercent: sessionPlan.isDeload ? 10.0 : nil
            )
            
            // Apply guardrails
            let guardrailed = PilotGuardrails.applyGuardrails(
                exerciseId: exerciseId,
                exerciseName: exerciseName,
                engineRecommendation: engineRec,
                currentState: priorState,
                readinessScore: readiness,
                recentHistory: recentHistory,
                config: guardrailConfig
            )
            
            // Record trajectory
            let prescription = PrescriptionContext(
                setsTarget: exercisePlan.prescription.setCount,
                repRangeMin: exercisePlan.prescription.targetRepsRange.lowerBound,
                repRangeMax: exercisePlan.prescription.targetRepsRange.upperBound,
                targetRIR: exercisePlan.prescription.targetRIR,
                increment: exercisePlan.prescription.increment.converted(to: .pounds).value
            )
            
            let decision = EngineDecision(
                type: mapToTelemetryDecisionType(engineRec.type),
                prescribedWeight: guardrailed.finalWeightLbs,
                prescribedReps: exercisePlan.sets.first?.targetReps ?? prescription.repRangeMin,
                weightDelta: priorState.map { guardrailed.finalWeightLbs - $0.currentWorkingWeight },
                weightDeltaPercent: priorState.map { 
                    $0.currentWorkingWeight > 0 
                        ? ((guardrailed.finalWeightLbs - $0.currentWorkingWeight) / $0.currentWorkingWeight) * 100 
                        : nil 
                } ?? nil,
                isDeload: sessionPlan.isDeload,
                deloadReason: sessionPlan.deloadReason?.rawValue,
                deloadIntensityReduction: sessionPlan.isDeload ? 10.0 : nil,
                deloadVolumeReduction: sessionPlan.isDeload ? 1 : nil,
                wasBreakReturn: detectBreakReturn(for: exerciseId),
                breakDurationDays: calculateBreakDays(for: exerciseId),
                reasons: buildDecisionReasons(for: exercisePlan, sessionPlan: sessionPlan)
            )
            
            let guardrailIntervention: GuardrailIntervention? = guardrailed.intervention.map {
                GuardrailIntervention(
                    type: $0.telemetryType,
                    originalDecisionType: mapToTelemetryDecisionType(engineRec.type),
                    originalWeight: engineRec.weightLbs
                )
            }
            
            pilotService.recordTrajectory(
                exerciseId: exerciseId,
                exerciseName: exerciseName,
                sessionId: activeSession?.id,
                priorState: priorState,
                readiness: readiness,
                prescription: prescription,
                decision: decision,
                guardrailIntervention: guardrailIntervention
            )
            
            modifiedExercisePlans.append((exercisePlan, guardrailed.wasModified, guardrailed.intervention))
        }
        
        // 4. Convert to UI model (with guardrailed weights if any interventions occurred)
        if !sessionPlan.exercises.isEmpty {
            var session = TrainingEngineBridge.convertSessionPlanToUIModel(
                sessionPlan,
                templateId: template.id,
                templateName: template.name,
                computedReadinessScore: readiness
            )
            
            // Apply guardrail modifications to the session
            for (index, (_, wasModified, intervention)) in modifiedExercisePlans.enumerated() where wasModified {
                if index < session.exercises.count,
                   let intervention = intervention,
                   let modifiedWeight = intervention.modifiedValue {
                    // Update all sets in this exercise to the guardrailed weight
                    for setIndex in session.exercises[index].sets.indices {
                        session.exercises[index].sets[setIndex].weight = modifiedWeight
                    }
                }
            }
            
            activeSession = session
        } else {
            // Fallback
            startSession(from: template, userProfile: userProfile, readiness: readiness, dailyBiometrics: dailyBiometrics)
        }
    }
    
    // MARK: - Pilot-Aware Exercise Completion
    
    /// Complete an exercise with pilot outcome recording
    @discardableResult
    func completePilotExercise(
        performanceId: UUID,
        pilotService: PilotTelemetryService,
        observedRIR: Int? = nil,
        observedRPE: Double? = nil,
        painReported: Bool = false,
        painLocation: String? = nil
    ) -> NextPrescriptionSnapshot? {
        guard let session = activeSession,
              let performance = session.exercises.first(where: { $0.id == performanceId }) else {
            return nil
        }
        
        // Get the prescription snapshot using normal completion
        let snapshot = completeExercise(performanceId: performanceId)
        
        // Record outcome for pilot telemetry
        let completedSets = performance.sets.filter { $0.isCompleted }
        let actualReps = completedSets.map { $0.reps }
        let actualWeight = completedSets.first?.weight ?? 0
        
        // Determine if user overrode the prescription
        let prescribedWeight = performance.sets.first?.weight ?? 0
        let userOverrode = abs(actualWeight - prescribedWeight) > 2.5 // More than 2.5 lb difference
        
        pilotService.recordOutcome(
            exerciseId: performance.exercise.id,
            sessionId: session.id,
            actualWeightLbs: actualWeight,
            actualReps: actualReps,
            observedRIR: observedRIR ?? completedSets.compactMap { $0.rirObserved }.first,
            observedRPE: observedRPE ?? completedSets.compactMap { $0.rpeObserved }.first,
            wasCompleted: !completedSets.isEmpty,
            wasSkipped: completedSets.isEmpty,
            painReported: painReported,
            painLocation: painLocation,
            userOverrode: userOverrode
        )
        
        return snapshot
    }
    
    // MARK: - Manual Override Recording
    
    /// Record when user manually changes a prescribed weight
    func recordPilotOverride(
        performance: ExercisePerformance,
        enginePrescribedWeight: Double,
        userChosenWeight: Double,
        reason: OverrideReason,
        pilotService: PilotTelemetryService,
        notes: String? = nil
    ) {
        pilotService.recordManualOverride(
            exerciseId: performance.exercise.id,
            exerciseName: performance.exercise.name,
            sessionId: activeSession?.id,
            enginePrescribedWeightLbs: enginePrescribedWeight,
            enginePrescribedReps: performance.repRangeMin,
            engineDecisionType: "unknown", // Could derive from snapshot if available
            userChosenWeightLbs: userChosenWeight,
            userChosenReps: performance.repRangeMin,
            reason: reason,
            notes: notes
        )
    }
    
    // MARK: - Pilot-Aware Session Finish
    
    /// Finish session with pilot telemetry cleanup
    func finishPilotSession(pilotService: PilotTelemetryService) {
        guard let session = activeSession else { return }
        
        // Record any pending outcomes for exercises that weren't explicitly completed
        for performance in session.exercises {
            let completedSets = performance.sets.filter { $0.isCompleted }
            if !completedSets.isEmpty && !performance.isCompleted {
                pilotService.recordOutcome(
                    exerciseId: performance.exercise.id,
                    sessionId: session.id,
                    actualWeightLbs: completedSets.first?.weight ?? 0,
                    actualReps: completedSets.map { $0.reps },
                    observedRIR: completedSets.compactMap { $0.rirObserved }.first,
                    observedRPE: completedSets.compactMap { $0.rpeObserved }.first,
                    wasCompleted: true,
                    wasSkipped: false,
                    painReported: false
                )
            }
        }
        
        // Signal session end to telemetry service
        pilotService.onSessionEnd(sessionId: session.id)
        
        // Normal session finish
        finishActiveSession()
    }
    
    // MARK: - Helper Methods
    
    private func buildRecentHistory(for exerciseId: String) -> PilotGuardrails.RecentHistory {
        // Look through recent sessions for this exercise
        let recentPerformances = performanceHistory(for: exerciseId, limit: 5)
        
        // Find last grinder (RPE >= 9.5 or RIR 0)
        var lastGrinderDate: Date?
        var lastMissDate: Date?
        var weeklyIncrease: Double = 0
        
        let oneWeekAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        var previousWeight: Double?
        
        for (index, perf) in recentPerformances.enumerated() {
            let session = sessions.first { s in s.exercises.contains { $0.id == perf.id } }
            let sessionDate = session?.startedAt ?? Date()
            
            // Check for grinders
            for set in perf.sets where set.isCompleted {
                if let rpe = set.rpeObserved, rpe >= 9.5 {
                    if lastGrinderDate == nil { lastGrinderDate = sessionDate }
                }
                if let rir = set.rirObserved, rir == 0 {
                    if lastGrinderDate == nil { lastGrinderDate = sessionDate }
                }
            }
            
            // Check for misses
            let completedSets = perf.sets.filter { $0.isCompleted }
            if completedSets.contains(where: { $0.reps < perf.repRangeMin }) {
                if lastMissDate == nil { lastMissDate = sessionDate }
            }
            
            // Calculate weekly increase
            if sessionDate >= oneWeekAgo {
                let currentWeight = completedSets.first?.weight ?? 0
                if let prev = previousWeight, currentWeight > prev {
                    weeklyIncrease += (currentWeight - prev)
                }
                previousWeight = currentWeight
            }
        }
        
        // Check for pain flags (from most recent session)
        // Note: In a full implementation, this would come from a dedicated pain/discomfort log
        let hasPainFlag = false
        let painLocation: String? = nil
        
        return PilotGuardrails.RecentHistory(
            lastGrinderDate: lastGrinderDate,
            lastMissDate: lastMissDate,
            weeklyIncreaseLbs: weeklyIncrease,
            hasPainFlag: hasPainFlag,
            painLocation: painLocation
        )
    }
    
    private func mapDecisionType(from sessionPlan: TrainingEngine.SessionPlan, for exerciseId: String) -> PilotGuardrails.RecommendationType {
        if sessionPlan.isDeload {
            return .deload
        }
        
        // Check if weight increased from last session
        guard let priorState = exerciseStates[exerciseId],
              let exercisePlan = sessionPlan.exercises.first(where: { $0.exercise.id == exerciseId }),
              let targetLoad = exercisePlan.sets.first?.targetLoad else {
            return .hold
        }
        
        let targetWeightLbs = targetLoad.converted(to: .pounds).value
        let priorWeightLbs = priorState.currentWorkingWeight
        
        if targetWeightLbs > priorWeightLbs + 1 {
            return .increaseWeight
        } else if targetWeightLbs < priorWeightLbs - 1 {
            return .deload
        } else {
            return .hold
        }
    }
    
    private func mapToTelemetryDecisionType(_ type: PilotGuardrails.RecommendationType) -> DecisionType {
        switch type {
        case .increaseWeight: return .increaseWeight
        case .increaseReps: return .increaseReps
        case .hold: return .hold
        case .deload: return .deload
        case .breakReset: return .breakReset
        }
    }
    
    private func detectBreakReturn(for exerciseId: String) -> Bool {
        guard let lastSession = lastSession(for: exerciseId) else { return false }
        let daysSince = Calendar.current.dateComponents([.day], from: lastSession.startedAt, to: Date()).day ?? 0
        return daysSince >= 7
    }
    
    private func calculateBreakDays(for exerciseId: String) -> Int? {
        guard let lastSession = lastSession(for: exerciseId) else { return nil }
        let days = Calendar.current.dateComponents([.day], from: lastSession.startedAt, to: Date()).day ?? 0
        return days >= 7 ? days : nil
    }
    
    private func buildDecisionReasons(for exercisePlan: TrainingEngine.ExercisePlan, sessionPlan: TrainingEngine.SessionPlan) -> [String] {
        var reasons: [String] = []
        
        if sessionPlan.isDeload {
            if let deloadReason = sessionPlan.deloadReason {
                reasons.append("deload_\(deloadReason.rawValue)")
            } else {
                reasons.append("scheduled_deload")
            }
        }
        
        // Add more reasons based on the exercise plan configuration
        // These would come from TrainingEngine's decision metadata
        
        return reasons
    }
}

// MARK: - Type Alias for TrainingEngine Access

import TrainingEngine
