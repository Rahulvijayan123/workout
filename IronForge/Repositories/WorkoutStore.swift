import Foundation
import SwiftUI
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
    
    // V2 keys to reset old data and use TrainingEngine-powered persistence
    private let templatesKey = "ironforge.workoutTemplates.v2"
    private let sessionsKey = "ironforge.workoutSessions.v2"
    private let exerciseStatesKey = "ironforge.liftStates.v2"
    
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
        dailyBiometrics: [DailyBiometrics] = []
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
            dailyBiometrics: dailyBiometrics
        )
        
        // If TrainingEngine returns exercises, use them; otherwise fallback to template-based seeding
        if !sessionPlan.exercises.isEmpty {
            activeSession = TrainingEngineBridge.convertSessionPlanToUIModel(
                sessionPlan,
                templateId: template.id,
                templateName: template.name
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
                exercises: seededExercises
            )
        }
    }
    
    /// Start a recommended session using TrainingEngine's scheduler
    func startRecommendedSession(
        userProfile: UserProfile,
        readiness: Int = 75,
        dailyBiometrics: [DailyBiometrics] = []
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
            dailyBiometrics: dailyBiometrics
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
                templateName: templateName
            )
        } else {
            // Fallback: start from first template
            if let template = templates.first {
                startSession(from: template, userProfile: userProfile, readiness: readiness, dailyBiometrics: dailyBiometrics)
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
    }
    
    func updateActiveSession(_ session: WorkoutSession) {
        activeSession = session
    }
    
    func finishActiveSession() {
        guard var session = activeSession else { return }
        session.endedAt = Date()
        
        // Mark all exercises with completed sets as completed
        for idx in session.exercises.indices {
            var performance = session.exercises[idx]
            let completedSets = performance.sets.filter { $0.isCompleted }
            if !completedSets.isEmpty {
                performance.isCompleted = true
                session.exercises[idx] = performance
            }
        }
        
        // Use TrainingEngine to update lift states
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
                let snapshot = NextPrescriptionSnapshot(
                    exerciseId: exerciseId,
                    nextWorkingWeight: updatedState.currentWorkingWeight,
                    targetReps: performance.repRangeMin,
                    setsTarget: performance.setsTarget,
                    repRangeMin: performance.repRangeMin,
                    repRangeMax: performance.repRangeMax,
                    increment: performance.increment,
                    deloadFactor: performance.deloadFactor,
                    failureThreshold: performance.failureThreshold,
                    reason: determineProgressionReason(
                        performance: performance,
                        previousWeight: exerciseStates[exerciseId]?.currentWorkingWeight ?? 0,
                        newWeight: updatedState.currentWorkingWeight
                    )
                )
                performance.nextPrescription = snapshot
                session.exercises[idx] = performance
            }
        }
        
        sessions.insert(session, at: 0)
        activeSession = nil
        save()
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
    
    func cancelActiveSession() {
        activeSession = nil
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
    
    /// Complete an exercise in the active session and compute progression
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
        
        // Build snapshot for UI
        let snapshot = NextPrescriptionSnapshot(
            exerciseId: exerciseId,
            nextWorkingWeight: updatedState.currentWorkingWeight,
            targetReps: performance.repRangeMin,
            setsTarget: performance.setsTarget,
            repRangeMin: performance.repRangeMin,
            repRangeMax: performance.repRangeMax,
            increment: performance.increment,
            deloadFactor: performance.deloadFactor,
            failureThreshold: performance.failureThreshold,
            reason: determineProgressionReason(
                performance: performance,
                previousWeight: previousWeight,
                newWeight: updatedState.currentWorkingWeight
            )
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
    
    private func load() {
        loadTemplates()
        loadSessions()
        loadExerciseStates()
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
            
            // Fallback to hardcoded exercises if not found (for graceful degradation)
            let benchPressEx = benchPress ?? ExerciseSeeds.defaultExercises[1]
            let squatEx = squat ?? ExerciseSeeds.defaultExercises[0]
            let pullUpEx = pullUp ?? ExerciseSeeds.defaultExercises[3]
            let deadliftEx = deadlift ?? ExerciseSeeds.defaultExercises[2]
            let shoulderPressEx = shoulderPress ?? ExerciseSeeds.defaultExercises[4]
            
            #if DEBUG
            // Debug-only seed templates for testing the full flow
            self.templates = [
                WorkoutTemplate(
                    name: "Demo (Debug)",
                    exercises: [
                        WorkoutTemplateExercise(
                            exercise: ExerciseRef(from: benchPressEx),
                            setsTarget: 3,
                            repRangeMin: 6,
                            repRangeMax: 10,
                            increment: 5,
                            deloadFactor: ProgressionDefaults.deloadFactor,
                            failureThreshold: ProgressionDefaults.failureThreshold
                        ),
                        WorkoutTemplateExercise(
                            exercise: ExerciseRef(from: squatEx),
                            setsTarget: 3,
                            repRangeMin: 5,
                            repRangeMax: 8,
                            increment: 10,
                            deloadFactor: ProgressionDefaults.deloadFactor,
                            failureThreshold: ProgressionDefaults.failureThreshold
                        )
                    ]
                ),
                WorkoutTemplate(
                    name: "Push (Starter)",
                    exercises: [
                        WorkoutTemplateExercise(
                            exercise: ExerciseRef(from: benchPressEx),
                            setsTarget: 3,
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
                        )
                    ]
                ),
                WorkoutTemplate(
                    name: "Pull (Starter)",
                    exercises: [
                        WorkoutTemplateExercise(
                            exercise: ExerciseRef(from: pullUpEx),
                            setsTarget: 3,
                            repRangeMin: 6,
                            repRangeMax: 10,
                            increment: 5,
                            deloadFactor: ProgressionDefaults.deloadFactor,
                            failureThreshold: ProgressionDefaults.failureThreshold
                        ),
                        WorkoutTemplateExercise(
                            exercise: ExerciseRef(from: deadliftEx),
                            setsTarget: 2,
                            repRangeMin: 3,
                            repRangeMax: 5,
                            increment: 10,
                            deloadFactor: ProgressionDefaults.deloadFactor,
                            failureThreshold: ProgressionDefaults.failureThreshold
                        )
                    ]
                ),
                WorkoutTemplate(
                    name: "Legs (Starter)",
                    exercises: [
                        WorkoutTemplateExercise(
                            exercise: ExerciseRef(from: squatEx),
                            setsTarget: 3,
                            repRangeMin: 5,
                            repRangeMax: 8,
                            increment: 10,
                            deloadFactor: ProgressionDefaults.deloadFactor,
                            failureThreshold: ProgressionDefaults.failureThreshold
                        )
                    ]
                )
            ]
            #else
            // Production seed templates
            self.templates = [
                WorkoutTemplate(
                    name: "Push (Starter)",
                    exercises: [
                        WorkoutTemplateExercise(
                            exercise: ExerciseRef(from: benchPressEx),
                            setsTarget: 3,
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
                        )
                    ]
                ),
                WorkoutTemplate(
                    name: "Pull (Starter)",
                    exercises: [
                        WorkoutTemplateExercise(
                            exercise: ExerciseRef(from: pullUpEx),
                            setsTarget: 3,
                            repRangeMin: 6,
                            repRangeMax: 10,
                            increment: 5,
                            deloadFactor: ProgressionDefaults.deloadFactor,
                            failureThreshold: ProgressionDefaults.failureThreshold
                        ),
                        WorkoutTemplateExercise(
                            exercise: ExerciseRef(from: deadliftEx),
                            setsTarget: 2,
                            repRangeMin: 3,
                            repRangeMax: 5,
                            increment: 10,
                            deloadFactor: ProgressionDefaults.deloadFactor,
                            failureThreshold: ProgressionDefaults.failureThreshold
                        )
                    ]
                ),
                WorkoutTemplate(
                    name: "Legs (Starter)",
                    exercises: [
                        WorkoutTemplateExercise(
                            exercise: ExerciseRef(from: squatEx),
                            setsTarget: 3,
                            repRangeMin: 5,
                            repRangeMax: 8,
                            increment: 10,
                            deloadFactor: ProgressionDefaults.deloadFactor,
                            failureThreshold: ProgressionDefaults.failureThreshold
                        )
                    ]
                )
            ]
            #endif
            
            self.saveTemplates()
        }
    }
}
