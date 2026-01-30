import Foundation
import Combine
import TrainingEngine

@MainActor
final class WorkoutStore: ObservableObject {
    @Published private(set) var templates: [WorkoutTemplate] = []
    @Published private(set) var sessions: [WorkoutSession] = []
    @Published var activeSession: WorkoutSession?
    @Published private(set) var exerciseStates: [String: ExerciseState] = [:]
    
    /// Default is an offline seed library. You can switch to ExerciseDB by setting:
    /// - `ironforge.exerciseDB.baseURL` (e.g. `http://localhost:3000`)
    /// - optional `ironforge.exerciseDB.rapidAPIKey`
    /// - optional `ironforge.exerciseDB.rapidAPIHost`
    let exerciseRepository: ExerciseRepository
    
    /// Shared shadow mode policy selector for ML data collection.
    /// Uses UserDefaults-backed bandit state store. Shadow mode executes baseline
    /// but logs what the bandit would have chosen for offline evaluation.
    nonisolated(unsafe) static let sharedPolicySelector: ProgressionPolicySelector = ShadowModePolicySelector(
        stateStore: UserDefaultsBanditStateStore.shared
    )
    
    // V2 keys to reset old data and use TrainingEngine-powered persistence
    private let templatesKey = "ironforge.workoutTemplates.v2"
    private let sessionsKey = "ironforge.workoutSessions.v2"
    private let exerciseStatesKey = "ironforge.liftStates.v2"
    private let activeSessionKey = "ironforge.activeSession.v2"
    
    init(exerciseRepository: ExerciseRepository = WorkoutStore.makeDefaultExerciseRepository()) {
        self.exerciseRepository = exerciseRepository
        load()
    }
    
    nonisolated private static func makeDefaultExerciseRepository() -> ExerciseRepository {
        let base = UserDefaults.standard.string(forKey: "ironforge.exerciseDB.baseURL")?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let base, !base.isEmpty, let url = URL(string: base) else {
            return LocalExerciseRepository()
        }
        
        let key = UserDefaults.standard.string(forKey: "ironforge.exerciseDB.rapidAPIKey")
        let host = UserDefaults.standard.string(forKey: "ironforge.exerciseDB.rapidAPIHost")
        
        return ExerciseDBRepository(
            config: .init(
                baseURL: url,
                rapidAPIKey: key,
                rapidAPIHost: host
            )
        )
    }
    
    // MARK: - Templates
    
    func createTemplate(name: String, exercises: [WorkoutTemplateExercise]) {
        var t = WorkoutTemplate(name: name, exercises: exercises)
        t.updatedAt = Date()
        templates.insert(t, at: 0)
        save()
    }
    
    func updateTemplate(_ template: WorkoutTemplate) {
        guard let idx = templates.firstIndex(where: { $0.id == template.id }) else { return }
        var t = template
        t.updatedAt = Date()
        templates[idx] = t
        save()
    }
    
    func deleteTemplate(_ template: WorkoutTemplate) {
        templates.removeAll { $0.id == template.id }
        save()
    }
    
    // MARK: - Sessions
    
    /// Start a session from a template using TrainingEngine recommendations
    func startSession(
        from template: WorkoutTemplate,
        userProfile: UserProfile? = nil,
        readiness: Int = 75,
        dailyBiometrics: [DailyBiometrics] = [],
        policySelector: ProgressionPolicySelector? = nil
    ) {
        // Use TrainingEngine to get recommended session plan
        let sessionPlan = TrainingEngineBridge.recommendSessionForTemplate(
            date: Date(),
            templateId: template.id,
            userProfile: userProfile ?? UserProfile(),
            templates: templates,
            sessions: sessions,
            liftStates: exerciseStates,
            readiness: readiness,
            dailyBiometrics: dailyBiometrics,
            policySelector: policySelector ?? Self.sharedPolicySelector
        )
        
        // If TrainingEngine returns exercises, use them; otherwise fallback to template-based seeding
        if !sessionPlan.exercises.isEmpty {
            activeSession = TrainingEngineBridge.convertSessionPlanToUIModel(
                sessionPlan,
                templateId: template.id,
                templateName: template.name,
                computedReadinessScore: readiness,
                exerciseStates: exerciseStates,
                sessions: sessions
            )
        } else {
            // Fallback: seed from template directly (for edge cases)
            let seededExercises: [ExercisePerformance] = template.exercises.map { te in
                let exerciseId = te.exercise.id
                let workingWeight = exerciseStates[exerciseId]?.currentWorkingWeight ?? 0
                let sets = seedSets(plannedSets: te.setsTarget, targetReps: te.repRangeMin, weight: workingWeight)
                return ExercisePerformance(from: te, sets: sets)
            }
            
            activeSession = WorkoutSession(
                templateId: template.id,
                name: template.name,
                startedAt: Date(),
                endedAt: nil,
                exercises: seededExercises,
                computedReadinessScore: readiness
            )
        }
        
        // Persist active session so user can continue after closing the app
        saveActiveSession()
    }
    
    /// Start a recommended session using TrainingEngine's scheduler
    func startRecommendedSession(
        userProfile: UserProfile,
        readiness: Int = 75,
        dailyBiometrics: [DailyBiometrics] = [],
        policySelector: ProgressionPolicySelector? = nil
    ) {
        guard !templates.isEmpty else { return }
        
        // Use TrainingEngine to recommend a session for today
        let sessionPlan = TrainingEngineBridge.recommendSession(
            date: Date(),
            userProfile: userProfile,
            templates: templates,
            sessions: sessions,
            liftStates: exerciseStates,
            readiness: readiness,
            dailyBiometrics: dailyBiometrics,
            policySelector: policySelector ?? Self.sharedPolicySelector
        )
        
        // Find the template name
        let templateName: String
        if let templateId = sessionPlan.templateId,
           let template = templates.first(where: { $0.id == templateId }) {
            templateName = template.name
        } else if let firstTemplate = templates.first {
            templateName = firstTemplate.name
        } else {
            templateName = "Workout"
        }
        
        if !sessionPlan.exercises.isEmpty {
            activeSession = TrainingEngineBridge.convertSessionPlanToUIModel(
                sessionPlan,
                templateId: sessionPlan.templateId,
                templateName: templateName,
                computedReadinessScore: readiness,
                exerciseStates: exerciseStates,
                sessions: sessions
            )
            // Persist active session so user can continue after closing the app
            saveActiveSession()
        } else {
            // Fallback: start from first template (startSession will call saveActiveSession)
            if let template = templates.first {
                startSession(from: template, userProfile: userProfile, readiness: readiness, dailyBiometrics: dailyBiometrics, policySelector: policySelector)
            }
        }
    }
    
    /// Helper to seed sets (used for fallback)
    private func seedSets(plannedSets: Int, targetReps: Int, weight: Double) -> [WorkoutSet] {
        let reps = max(0, targetReps)
        let w = max(0, weight)
        return (0..<max(1, plannedSets)).map { _ in
            WorkoutSet(reps: reps, weight: w, isCompleted: false)
        }
    }
    
    func startEmptySession(name: String = "Quick Session") {
        activeSession = WorkoutSession(
            templateId: nil,
            name: name,
            startedAt: Date(),
            endedAt: nil,
            exercises: []
        )
        // Persist active session so user can continue after closing the app
        saveActiveSession()
    }
    
    func addExerciseToActiveSession(_ exercise: ExerciseRef) {
        guard var session = activeSession else { return }
        
        // Get the stored working weight for this exercise, or default to 0
        let workingWeight = exerciseStates[exercise.id]?.currentWorkingWeight ?? 0
        
        let defaultSettings = WorkoutTemplateExercise(exercise: exercise)
        let sets = seedSets(
            plannedSets: defaultSettings.setsTarget,
            targetReps: defaultSettings.repRangeMin,
            weight: workingWeight
        )
        
        let performance = ExercisePerformance(from: defaultSettings, sets: sets)
        session.exercises.append(performance)
        activeSession = session
        
        // Persist changes to active session
        saveActiveSession()
    }
    
    func updateActiveSession(_ session: WorkoutSession) {
        activeSession = session
        // Persist changes to active session so user can continue after closing the app
        saveActiveSession()
    }
    
    func finishActiveSession() {
        guard var session = activeSession else { return }
        session.endedAt = Date()
        
        // Mark all exercises with completed sets as completed and compute outcomes
        for idx in session.exercises.indices {
            var performance = session.exercises[idx]
            let completedSets = performance.sets.filter { $0.isCompleted }
            if !completedSets.isEmpty {
                performance.isCompleted = true
                
                // ML CRITICAL: Compute set outcomes (metRepTarget, metEffortTarget, setOutcome)
                for setIdx in performance.sets.indices {
                    var set = performance.sets[setIdx]
                    if set.isCompleted && !set.isWarmup {
                        let targetReps = set.recommendedReps ?? performance.repRangeMin
                        let targetRIR = set.targetRIR ?? performance.targetRIR
                        set.computeOutcome(targetReps: targetReps, targetRIR: targetRIR)
                    }
                    performance.sets[setIdx] = set
                }
                
                // ML CRITICAL: Compute exposure outcomes (exposureOutcome, setsSuccessful, etc.)
                performance.computeOutcomes()
                
                session.exercises[idx] = performance
            }
        }
        
        // Use TrainingEngine to update lift states
        let priorStates = exerciseStates
        let updatedStates = TrainingEngineBridge.updateLiftStates(
            afterSession: session,
            previousLiftStates: exerciseStates
        )
        exerciseStates = updatedStates
        
        // Compute progression snapshots for UI display (using legacy engine for now)
        for idx in session.exercises.indices {
            var performance = session.exercises[idx]
            let exerciseId = performance.exercise.id
            
            let completedSets = performance.sets.filter { $0.isCompleted }
            guard !completedSets.isEmpty else { continue }
            if performance.nextPrescription != nil { continue }
            
            // Build snapshot from updated state
            if let updatedState = exerciseStates[exerciseId] {
                let prevWeight = priorStates[exerciseId]?.currentWorkingWeight ?? 0
                let reason = determineProgressionReason(
                    performance: performance,
                    previousWeight: prevWeight,
                    newWeight: updatedState.currentWorkingWeight
                )
                let targetReps = computeTargetReps(performance: performance, reason: reason)
                
                let snapshot = NextPrescriptionSnapshot(
                    exerciseId: exerciseId,
                    nextWorkingWeight: updatedState.currentWorkingWeight,
                    targetReps: targetReps,
                    setsTarget: performance.setsTarget,
                    repRangeMin: performance.repRangeMin,
                    repRangeMax: performance.repRangeMax,
                    increment: performance.increment,
                    deloadFactor: performance.deloadFactor,
                    failureThreshold: performance.failureThreshold,
                    reason: reason
                )
                performance.nextPrescription = snapshot
                session.exercises[idx] = performance
            }
        }
        
        sessions.insert(session, at: 0)
        activeSession = nil
        save()
        
        // Clear the persisted active session since workout is complete
        UserDefaults.standard.removeObject(forKey: activeSessionKey)
        
        // Sync completed session to Supabase
        let completedSession = session
        let currentLiftStates = exerciseStates
        Task { @MainActor in
            guard SupabaseService.shared.isAuthenticated else { return }
            
            do {
                try await DataSyncService.shared.syncWorkoutSession(completedSession)
            } catch {
                print("[WorkoutStore] Failed to sync workout session: \(error)")
                DataSyncService.shared.syncError = error
            }
            
            do {
                try await DataSyncService.shared.syncLiftStates(currentLiftStates)
            } catch {
                print("[WorkoutStore] Failed to sync lift states: \(error)")
                DataSyncService.shared.syncError = error
            }
        }
    }
    
    /// Determine progression reason based on weight change
    private func determineProgressionReason(performance: ExercisePerformance, previousWeight: Double, newWeight: Double) -> ProgressionReason {
        let completedSets = performance.sets.filter { $0.isCompleted }
        guard !completedSets.isEmpty else { return .hold }
        
        let reps = completedSets.map(\.reps)
        let allAtOrAboveUpper = reps.allSatisfy { $0 >= performance.repRangeMax }
        let allAtOrAboveLower = reps.allSatisfy { $0 >= performance.repRangeMin }
        
        if newWeight > previousWeight {
            return .increaseWeight
        } else if newWeight < previousWeight {
            return .deload
        } else if allAtOrAboveUpper {
            return .increaseWeight
        } else if allAtOrAboveLower {
            return .increaseReps
        } else {
            return .hold
        }
    }

    /// Compute a simple next-session rep target for UI display.
    ///
    /// TrainingEngine currently owns load updates (via `updateLiftStates`), but IronForge UI still needs a
    /// deterministic rep target for the next exposure. We derive it from the completed reps and the
    /// inferred progression reason so we don't incorrectly default to `repRangeMin`.
    private func computeTargetReps(performance: ExercisePerformance, reason: ProgressionReason) -> Int {
        let lb = performance.repRangeMin
        let ub = max(lb, performance.repRangeMax)

        switch reason {
        case .increaseReps:
            let completed = performance.sets.filter { $0.isCompleted }
            let sample = completed.isEmpty ? performance.sets : completed
            let minReps = sample.map(\.reps).min() ?? lb
            return max(lb, min(ub, minReps + 1))
        case .increaseWeight, .deload, .hold:
            return lb
        }
    }
    
    /// Compute execution context for an exercise based on pain data.
    ///
    /// Returns `.injuryDiscomfort` if:
    /// - `stoppedDueToPain == true`, OR
    /// - Any `painEntry.severity >= 5`, OR
    /// - `overallPainLevel >= 5`
    ///
    /// Otherwise returns `.normal`.
    private func computeExecutionContext(for performance: ExercisePerformance) -> TrainingEngine.ExecutionContext {
        let painThreshold = 5
        
        // Check if stopped due to pain
        if performance.stoppedDueToPain {
            return .injuryDiscomfort
        }
        
        // Check if any pain entry has severity >= threshold
        if let painEntries = performance.painEntries,
           painEntries.contains(where: { $0.severity >= painThreshold }) {
            return .injuryDiscomfort
        }
        
        // Check if overall pain level >= threshold
        if let overallPain = performance.overallPainLevel, overallPain >= painThreshold {
            return .injuryDiscomfort
        }
        
        return .normal
    }
    
    func cancelActiveSession() {
        activeSession = nil
        // Clear the persisted active session
        UserDefaults.standard.removeObject(forKey: activeSessionKey)
    }
    
    func lastSession(for exerciseId: String) -> WorkoutSession? {
        sessions.first { s in
            s.exercises.contains(where: { $0.exercise.id == exerciseId })
        }
    }
    
    // MARK: - Exercise State & Progression
    
    /// Get the current state for an exercise
    func getExerciseState(for exerciseId: String) -> ExerciseState? {
        exerciseStates[exerciseId]
    }
    
    /// Save exercise progress without marking it as completed.
    /// Exercises remain editable until the entire workout is finalized.
    /// - Parameters:
    ///   - performanceId: The ID of the ExercisePerformance to save
    /// - Returns: The computed next prescription snapshot (preview), or nil if not found
    @discardableResult
    func saveExerciseProgress(performanceId: UUID) -> NextPrescriptionSnapshot? {
        guard var session = activeSession,
              let idx = session.exercises.firstIndex(where: { $0.id == performanceId }) else {
            return nil
        }
        
        var performance = session.exercises[idx]
        let exerciseId = performance.exercise.id
        
        // Only compute progression if there are completed sets
        let completedSets = performance.sets.filter { $0.isCompleted }
        guard !completedSets.isEmpty else {
            // No completed sets, just update session
            activeSession = session
            return nil
        }
        
        // Get prior state
        let priorState = exerciseStates[exerciseId]
        let previousWeight = priorState?.currentWorkingWeight ?? 0
        
        // Create a temporary completed session for this exercise to preview updated state
        // NOTE: We do NOT permanently update lift states here - that happens at workout finalization
        var tempSession = session
        tempSession.endedAt = Date()
        var tempPerformance = performance
        tempPerformance.isCompleted = true
        tempSession.exercises[idx] = tempPerformance
        
        // Use TrainingEngine to compute what the updated lift state WOULD be (preview only)
        let previewStates = TrainingEngineBridge.updateLiftStates(
            afterSession: tempSession,
            previousLiftStates: exerciseStates
        )
        
        let previewState = previewStates[exerciseId] ?? ExerciseState(
            exerciseId: exerciseId,
            currentWorkingWeight: previousWeight,
            failuresCount: 0
        )

        let reason = determineProgressionReason(
            performance: performance,
            previousWeight: previousWeight,
            newWeight: previewState.currentWorkingWeight
        )
        let targetReps = computeTargetReps(performance: performance, reason: reason)
        
        // Build snapshot for UI preview (shows what next session would look like)
        let snapshot = NextPrescriptionSnapshot(
            exerciseId: exerciseId,
            nextWorkingWeight: previewState.currentWorkingWeight,
            targetReps: targetReps,
            setsTarget: performance.setsTarget,
            repRangeMin: performance.repRangeMin,
            repRangeMax: performance.repRangeMax,
            increment: performance.increment,
            deloadFactor: performance.deloadFactor,
            failureThreshold: performance.failureThreshold,
            reason: reason
        )
        
        // Update performance with preview snapshot but DO NOT mark as completed
        // Exercise remains editable until workout is finalized
        performance.nextPrescription = snapshot
        // performance.isCompleted stays false - only set when workout is finished
        session.exercises[idx] = performance
        
        // Update session (but don't update lift states permanently yet)
        activeSession = session
        
        // Save the active session to persist through app restarts
        saveActiveSession()
        
        return snapshot
    }
    
    /// Complete an exercise in the active session and compute progression
    /// NOTE: This is now only called during workout finalization
    /// - Parameters:
    ///   - performanceId: The ID of the ExercisePerformance to complete
    /// - Returns: The computed next prescription snapshot, or nil if not found
    @discardableResult
    func completeExercise(performanceId: UUID) -> NextPrescriptionSnapshot? {
        guard var session = activeSession,
              let idx = session.exercises.firstIndex(where: { $0.id == performanceId }) else {
            return nil
        }
        
        var performance = session.exercises[idx]
        let exerciseId = performance.exercise.id
        
        // Get prior state
        let priorState = exerciseStates[exerciseId]
        let previousWeight = priorState?.currentWorkingWeight ?? 0
        
        // Create a temporary completed session for this exercise to get updated state
        var tempSession = session
        tempSession.endedAt = Date()
        performance.isCompleted = true
        tempSession.exercises[idx] = performance
        
        // Use TrainingEngine to compute updated lift state
        let updatedStates = TrainingEngineBridge.updateLiftStates(
            afterSession: tempSession,
            previousLiftStates: exerciseStates
        )
        
        let updatedState = updatedStates[exerciseId] ?? ExerciseState(
            exerciseId: exerciseId,
            currentWorkingWeight: previousWeight,
            failuresCount: 0
        )

        let reason = determineProgressionReason(
            performance: performance,
            previousWeight: previousWeight,
            newWeight: updatedState.currentWorkingWeight
        )
        let targetReps = computeTargetReps(performance: performance, reason: reason)
        
        // Build snapshot for UI
        let snapshot = NextPrescriptionSnapshot(
            exerciseId: exerciseId,
            nextWorkingWeight: updatedState.currentWorkingWeight,
            targetReps: targetReps,
            setsTarget: performance.setsTarget,
            repRangeMin: performance.repRangeMin,
            repRangeMax: performance.repRangeMax,
            increment: performance.increment,
            deloadFactor: performance.deloadFactor,
            failureThreshold: performance.failureThreshold,
            reason: reason
        )
        
        // Update performance with snapshot and mark complete
        performance.nextPrescription = snapshot
        performance.isCompleted = true
        session.exercises[idx] = performance
        
        // Update state
        exerciseStates[exerciseId] = updatedState
        
        // Update session
        activeSession = session
        
        // Save state (session will be saved when finished)
        saveExerciseStates()
        
        return snapshot
    }
    
    /// Initialize exercise state for a new exercise (first time logging)
    func initializeExerciseState(exerciseId: String, initialWeight: Double) {
        if exerciseStates[exerciseId] == nil {
            exerciseStates[exerciseId] = ExerciseState(
                exerciseId: exerciseId,
                currentWorkingWeight: initialWeight,
                failuresCount: 0
            )
            saveExerciseStates()
        }
    }
    
    // MARK: - History Helpers
    
    /// Get the last performance for an exercise from session history
    func lastPerformance(for exerciseId: String) -> ExercisePerformance? {
        for session in sessions {
            if let performance = session.exercises.first(where: { $0.exercise.id == exerciseId }) {
                return performance
            }
        }
        return nil
    }
    
    /// Get all performances for an exercise from session history
    func performanceHistory(for exerciseId: String, limit: Int = 10) -> [ExercisePerformance] {
        var results: [ExercisePerformance] = []
        for session in sessions {
            if let performance = session.exercises.first(where: { $0.exercise.id == exerciseId }) {
                results.append(performance)
                if results.count >= limit {
                    break
                }
            }
        }
        return results
    }
    
    // MARK: - Remote Data Merge
    
    /// Merge remote data from Supabase into local storage
    func mergeRemoteData(
        templates: [WorkoutTemplate],
        sessions: [WorkoutSession],
        liftStates: [String: ExerciseState]
    ) {
        self.templates = templates
        self.sessions = sessions
        self.exerciseStates = liftStates
        save()
    }
    
    // MARK: - Persistence
    
    private func save() {
        saveTemplates()
        saveSessions()
        saveExerciseStates()
    }
    
    private func saveTemplates() {
        if let data = try? JSONEncoder().encode(templates) {
            UserDefaults.standard.set(data, forKey: templatesKey)
        }
    }
    
    private func saveSessions() {
        if let data = try? JSONEncoder().encode(sessions) {
            UserDefaults.standard.set(data, forKey: sessionsKey)
        }
    }
    
    private func saveExerciseStates() {
        if let data = try? JSONEncoder().encode(exerciseStates) {
            UserDefaults.standard.set(data, forKey: exerciseStatesKey)
        }
    }
    
    /// Save the active session to persist through app restarts.
    /// This allows users to close the app and continue their workout later.
    func saveActiveSession() {
        if let session = activeSession,
           let data = try? JSONEncoder().encode(session) {
            UserDefaults.standard.set(data, forKey: activeSessionKey)
        } else {
            // Clear active session if nil
            UserDefaults.standard.removeObject(forKey: activeSessionKey)
        }
    }
    
    private func load() {
        loadTemplates()
        loadSessions()
        loadExerciseStates()
        loadActiveSession()
        seedTemplatesIfNeeded()
    }
    
    private func loadTemplates() {
        if let data = UserDefaults.standard.data(forKey: templatesKey),
           let decoded = try? JSONDecoder().decode([WorkoutTemplate].self, from: data) {
            templates = decoded
        }
    }
    
    private func loadSessions() {
        if let data = UserDefaults.standard.data(forKey: sessionsKey),
           let decoded = try? JSONDecoder().decode([WorkoutSession].self, from: data) {
            sessions = decoded
        }
    }
    
    private func loadExerciseStates() {
        if let data = UserDefaults.standard.data(forKey: exerciseStatesKey),
           let decoded = try? JSONDecoder().decode([String: ExerciseState].self, from: data) {
            exerciseStates = decoded
        }
    }
    
    /// Load any active session that was in progress when the app was closed.
    /// This allows users to continue their workout after closing and reopening the app.
    private func loadActiveSession() {
        if let data = UserDefaults.standard.data(forKey: activeSessionKey),
           let decoded = try? JSONDecoder().decode(WorkoutSession.self, from: data) {
            // Only restore if the session doesn't have an end time (still in progress)
            if decoded.endedAt == nil {
                activeSession = decoded
            } else {
                // Session was ended but not saved properly, clear it
                UserDefaults.standard.removeObject(forKey: activeSessionKey)
            }
        }
    }
    
    private func seedTemplatesIfNeeded() {
        guard templates.isEmpty else { return }
        
        // Helper to find exercise by name
        func findExercise(containing keyword: String) async -> Exercise? {
            let results = await exerciseRepository.search(query: keyword)
            return results.first(where: { $0.name.lowercased().contains(keyword.lowercased()) })
        }
        
        // We need to run async search, but this is called from init which is not async.
        // Use a Task to seed templates asynchronously.
        Task { @MainActor in
            guard self.templates.isEmpty else { return }
            
            // Try to find exercises by name from the repository
            let benchPress = await findExercise(containing: "bench press")
            let squat = await findExercise(containing: "squat")
            let pullUp = await findExercise(containing: "pull-up")
            let deadlift = await findExercise(containing: "deadlift")
            let shoulderPress = await findExercise(containing: "shoulder press")
            let inclinePress = await findExercise(containing: "incline")
            let tricepExtension = await findExercise(containing: "tricep")
            let lateralRaise = await findExercise(containing: "lateral raise")
            let barbellRow = await findExercise(containing: "barbell row")
            let bicepCurl = await findExercise(containing: "bicep curl")
            let facePull = await findExercise(containing: "face pull")
            let legPress = await findExercise(containing: "leg press")
            let romanianDeadlift = await findExercise(containing: "romanian")
            let legCurl = await findExercise(containing: "leg curl")
            let calfRaise = await findExercise(containing: "calf raise")
            
            // Fallback to hardcoded exercises if not found (for graceful degradation)
            let benchPressEx = benchPress ?? ExerciseSeeds.defaultExercises[1]
            let squatEx = squat ?? ExerciseSeeds.defaultExercises[0]
            let pullUpEx = pullUp ?? ExerciseSeeds.defaultExercises[3]
            let deadliftEx = deadlift ?? ExerciseSeeds.defaultExercises[2]
            let shoulderPressEx = shoulderPress ?? ExerciseSeeds.defaultExercises[4]
            
            // Create fallback exercises for ones that may not be found
            let inclinePressEx = inclinePress ?? Exercise(
                id: "incline_dumbbell_press",
                name: "incline dumbbell press",
                bodyPart: "chest",
                equipment: "dumbbell",
                gifUrl: nil,
                target: "upper pectorals",
                secondaryMuscles: ["triceps", "front deltoids"],
                instructions: ["Set bench to 30-45 degrees.", "Press dumbbells up and together."]
            )
            let tricepEx = tricepExtension ?? Exercise(
                id: "tricep_pushdown",
                name: "tricep pushdown",
                bodyPart: "upper arms",
                equipment: "cable",
                gifUrl: nil,
                target: "triceps",
                secondaryMuscles: [],
                instructions: ["Keep elbows pinned.", "Push down until arms are straight."]
            )
            let lateralRaiseEx = lateralRaise ?? Exercise(
                id: "dumbbell_lateral_raise",
                name: "dumbbell lateral raise",
                bodyPart: "shoulders",
                equipment: "dumbbell",
                gifUrl: nil,
                target: "side deltoids",
                secondaryMuscles: [],
                instructions: ["Raise arms to shoulder height.", "Control the descent."]
            )
            let barbellRowEx = barbellRow ?? Exercise(
                id: "barbell_row",
                name: "barbell row",
                bodyPart: "back",
                equipment: "barbell",
                gifUrl: nil,
                target: "lats",
                secondaryMuscles: ["biceps", "rear deltoids"],
                instructions: ["Hinge at hips.", "Pull bar to lower chest."]
            )
            let bicepCurlEx = bicepCurl ?? Exercise(
                id: "dumbbell_bicep_curl",
                name: "dumbbell bicep curl",
                bodyPart: "upper arms",
                equipment: "dumbbell",
                gifUrl: nil,
                target: "biceps",
                secondaryMuscles: [],
                instructions: ["Keep elbows stable.", "Curl weight up with control."]
            )
            let facePullEx = facePull ?? Exercise(
                id: "cable_face_pull",
                name: "cable face pull",
                bodyPart: "shoulders",
                equipment: "cable",
                gifUrl: nil,
                target: "rear deltoids",
                secondaryMuscles: ["traps", "rotator cuff"],
                instructions: ["Pull rope to face.", "Spread hands apart at end."]
            )
            let legPressEx = legPress ?? Exercise(
                id: "leg_press",
                name: "leg press",
                bodyPart: "upper legs",
                equipment: "machine",
                gifUrl: nil,
                target: "quads",
                secondaryMuscles: ["glutes", "hamstrings"],
                instructions: ["Place feet shoulder width.", "Lower with control."]
            )
            let rdlEx = romanianDeadlift ?? Exercise(
                id: "romanian_deadlift",
                name: "romanian deadlift",
                bodyPart: "upper legs",
                equipment: "barbell",
                gifUrl: nil,
                target: "hamstrings",
                secondaryMuscles: ["glutes", "erector spinae"],
                instructions: ["Hinge at hips with slight knee bend.", "Feel stretch in hamstrings."]
            )
            let legCurlEx = legCurl ?? Exercise(
                id: "lying_leg_curl",
                name: "lying leg curl",
                bodyPart: "upper legs",
                equipment: "machine",
                gifUrl: nil,
                target: "hamstrings",
                secondaryMuscles: [],
                instructions: ["Curl weight up.", "Squeeze at top."]
            )
            let calfRaiseEx = calfRaise ?? Exercise(
                id: "standing_calf_raise",
                name: "standing calf raise",
                bodyPart: "lower legs",
                equipment: "machine",
                gifUrl: nil,
                target: "calves",
                secondaryMuscles: [],
                instructions: ["Rise onto toes.", "Lower with full stretch."]
            )
            
            // Full workout templates (same for both DEBUG and production)
            self.templates = [
                WorkoutTemplate(
                    name: "Push Day",
                    exercises: [
                        WorkoutTemplateExercise(
                            exercise: ExerciseRef(from: benchPressEx),
                            setsTarget: 4,
                            repRangeMin: 6,
                            repRangeMax: 10,
                            increment: 5,
                            deloadFactor: ProgressionDefaults.deloadFactor,
                            failureThreshold: ProgressionDefaults.failureThreshold
                        ),
                        WorkoutTemplateExercise(
                            exercise: ExerciseRef(from: shoulderPressEx),
                            setsTarget: 3,
                            repRangeMin: 8,
                            repRangeMax: 12,
                            increment: 5,
                            deloadFactor: ProgressionDefaults.deloadFactor,
                            failureThreshold: ProgressionDefaults.failureThreshold
                        ),
                        WorkoutTemplateExercise(
                            exercise: ExerciseRef(from: inclinePressEx),
                            setsTarget: 3,
                            repRangeMin: 8,
                            repRangeMax: 12,
                            increment: 5,
                            deloadFactor: ProgressionDefaults.deloadFactor,
                            failureThreshold: ProgressionDefaults.failureThreshold
                        ),
                        WorkoutTemplateExercise(
                            exercise: ExerciseRef(from: lateralRaiseEx),
                            setsTarget: 3,
                            repRangeMin: 12,
                            repRangeMax: 15,
                            increment: 2.5,
                            deloadFactor: ProgressionDefaults.deloadFactor,
                            failureThreshold: ProgressionDefaults.failureThreshold
                        ),
                        WorkoutTemplateExercise(
                            exercise: ExerciseRef(from: tricepEx),
                            setsTarget: 3,
                            repRangeMin: 10,
                            repRangeMax: 15,
                            increment: 5,
                            deloadFactor: ProgressionDefaults.deloadFactor,
                            failureThreshold: ProgressionDefaults.failureThreshold
                        )
                    ]
                ),
                WorkoutTemplate(
                    name: "Pull Day",
                    exercises: [
                        WorkoutTemplateExercise(
                            exercise: ExerciseRef(from: deadliftEx),
                            setsTarget: 3,
                            repRangeMin: 3,
                            repRangeMax: 6,
                            increment: 10,
                            deloadFactor: ProgressionDefaults.deloadFactor,
                            failureThreshold: ProgressionDefaults.failureThreshold
                        ),
                        WorkoutTemplateExercise(
                            exercise: ExerciseRef(from: pullUpEx),
                            setsTarget: 4,
                            repRangeMin: 6,
                            repRangeMax: 10,
                            increment: 5,
                            deloadFactor: ProgressionDefaults.deloadFactor,
                            failureThreshold: ProgressionDefaults.failureThreshold
                        ),
                        WorkoutTemplateExercise(
                            exercise: ExerciseRef(from: barbellRowEx),
                            setsTarget: 3,
                            repRangeMin: 8,
                            repRangeMax: 12,
                            increment: 5,
                            deloadFactor: ProgressionDefaults.deloadFactor,
                            failureThreshold: ProgressionDefaults.failureThreshold
                        ),
                        WorkoutTemplateExercise(
                            exercise: ExerciseRef(from: facePullEx),
                            setsTarget: 3,
                            repRangeMin: 12,
                            repRangeMax: 15,
                            increment: 5,
                            deloadFactor: ProgressionDefaults.deloadFactor,
                            failureThreshold: ProgressionDefaults.failureThreshold
                        ),
                        WorkoutTemplateExercise(
                            exercise: ExerciseRef(from: bicepCurlEx),
                            setsTarget: 3,
                            repRangeMin: 10,
                            repRangeMax: 15,
                            increment: 2.5,
                            deloadFactor: ProgressionDefaults.deloadFactor,
                            failureThreshold: ProgressionDefaults.failureThreshold
                        )
                    ]
                ),
                WorkoutTemplate(
                    name: "Leg Day",
                    exercises: [
                        WorkoutTemplateExercise(
                            exercise: ExerciseRef(from: squatEx),
                            setsTarget: 4,
                            repRangeMin: 5,
                            repRangeMax: 8,
                            increment: 10,
                            deloadFactor: ProgressionDefaults.deloadFactor,
                            failureThreshold: ProgressionDefaults.failureThreshold
                        ),
                        WorkoutTemplateExercise(
                            exercise: ExerciseRef(from: legPressEx),
                            setsTarget: 3,
                            repRangeMin: 10,
                            repRangeMax: 15,
                            increment: 10,
                            deloadFactor: ProgressionDefaults.deloadFactor,
                            failureThreshold: ProgressionDefaults.failureThreshold
                        ),
                        WorkoutTemplateExercise(
                            exercise: ExerciseRef(from: rdlEx),
                            setsTarget: 3,
                            repRangeMin: 8,
                            repRangeMax: 12,
                            increment: 10,
                            deloadFactor: ProgressionDefaults.deloadFactor,
                            failureThreshold: ProgressionDefaults.failureThreshold
                        ),
                        WorkoutTemplateExercise(
                            exercise: ExerciseRef(from: legCurlEx),
                            setsTarget: 3,
                            repRangeMin: 10,
                            repRangeMax: 15,
                            increment: 5,
                            deloadFactor: ProgressionDefaults.deloadFactor,
                            failureThreshold: ProgressionDefaults.failureThreshold
                        ),
                        WorkoutTemplateExercise(
                            exercise: ExerciseRef(from: calfRaiseEx),
                            setsTarget: 4,
                            repRangeMin: 12,
                            repRangeMax: 20,
                            increment: 5,
                            deloadFactor: ProgressionDefaults.deloadFactor,
                            failureThreshold: ProgressionDefaults.failureThreshold
                        )
                    ]
                )
            ]
            
            self.saveTemplates()
        }
    }
}
