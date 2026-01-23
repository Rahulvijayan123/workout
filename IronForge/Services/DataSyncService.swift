import Foundation
import UIKit

// MARK: - Data Sync Service
/// Manages synchronization between local storage and Supabase
@MainActor
final class DataSyncService: ObservableObject {
    
    static let shared = DataSyncService()
    
    // MARK: - Properties
    
    private let supabase = SupabaseService.shared
    
    @Published private(set) var isSyncing = false
    @Published private(set) var lastSyncAt: Date?
    @Published private(set) var syncError: Error?
    
    // MARK: - Supabase Data Models
    
    // These mirror the database schema
    
    struct DBUserProfile: Codable {
        var id: String?
        var displayName: String?
        var email: String?
        var age: Int?
        var sex: String?
        var heightCm: Double?
        var bodyWeightKg: Double?
        var bodyFatPercentage: Double?
        var workoutExperience: String?
        var trainingAgeMonths: Int?
        var fitnessGoals: [String]?
        var weeklyFrequency: Int?
        var preferredWorkoutDurationMinutes: Int?
        var preferredWorkoutDays: [String]?
        var gymType: String?
        var availableEquipment: [String]?
        var preferredWeightUnit: String?
        var preferredDistanceUnit: String?
        var notificationsEnabled: Bool?
        var restTimerEnabled: Bool?
        var defaultRestSeconds: Int?
        var onboardingCompleted: Bool?
        var onboardingCompletedAt: Date?
        var createdAt: Date?
        var updatedAt: Date?
    }
    
    struct DBWorkoutTemplate: Codable {
        var id: String?
        var userId: String?
        var name: String
        var description: String?
        var templateType: String?
        var splitType: String?
        var estimatedDurationMinutes: Int?
        var targetMuscleGroups: [String]?
        var sortOrder: Int?
        var isActive: Bool?
        var createdAt: Date?
        var updatedAt: Date?
    }
    
    struct DBTemplateExercise: Codable {
        var id: String?
        var templateId: String
        var exerciseId: String
        var exerciseName: String
        var exerciseEquipment: String?
        var exerciseTarget: String?
        var setsTarget: Int
        var repRangeMin: Int
        var repRangeMax: Int
        var incrementKg: Double?
        var deloadFactor: Double?
        var failureThreshold: Int?
        var restSeconds: Int?
        var targetRir: Int?
        var supersetGroupId: String?
        var sortOrder: Int
        var notes: String?
        var createdAt: Date?
        var updatedAt: Date?
    }
    
    struct DBWorkoutSession: Codable {
        var id: String?
        var userId: String
        var templateId: String?
        var templateName: String?
        var name: String
        var startedAt: Date
        var endedAt: Date?
        var durationSeconds: Int?
        var readinessScore: Int?
        var wasDeload: Bool?
        var deloadReason: String?
        var gymName: String?
        var latitude: Double?
        var longitude: Double?
        var perceivedDifficulty: Int?
        var overallFeeling: String?
        var notes: String?
        var totalSets: Int?
        var totalReps: Int?
        var totalVolumeKg: Double?
        var exerciseCount: Int?
        var createdAt: Date?
        var updatedAt: Date?
    }
    
    struct DBSessionExercise: Codable {
        var id: String?
        var sessionId: String
        var exerciseId: String
        var exerciseName: String
        var exerciseEquipment: String?
        var exerciseTarget: String?
        var setsTarget: Int
        var repRangeMin: Int
        var repRangeMax: Int
        var incrementKg: Double?
        var deloadFactor: Double?
        var failureThreshold: Int?
        var sortOrder: Int
        var isCompleted: Bool?
        var completedAt: Date?
        var totalSetsCompleted: Int?
        var totalRepsCompleted: Int?
        var totalVolumeKg: Double?
        var notes: String?
        var createdAt: Date?
        var updatedAt: Date?
    }
    
    struct DBSessionSet: Codable {
        var id: String?
        var sessionExerciseId: String
        var setNumber: Int
        var reps: Int
        var weightKg: Double
        var durationSeconds: Int?
        var distanceMeters: Double?
        var rirObserved: Int?
        var rpeObserved: Double?
        var isWarmup: Bool?
        var isDropset: Bool?
        var isFailure: Bool?
        var isCompleted: Bool?
        var completedAt: Date?
        var notes: String?
        var createdAt: Date?
    }
    
    struct DBLiftState: Codable {
        var id: String?
        var userId: String
        var exerciseId: String
        var exerciseName: String
        var lastWorkingWeightKg: Double
        var rollingE1rmKg: Double?
        var e1rmTrend: String?
        var e1rmHistory: [Double]?
        var consecutiveFailures: Int?
        var lastDeloadAt: Date?
        var lastSessionAt: Date?
        var successfulSessionsCount: Int?
        var totalSessionsCount: Int?
        var lastSessionVolumeKg: Double?
        var averageSessionVolumeKg: Double?
        var createdAt: Date?
        var updatedAt: Date?
    }
    
    struct DBDailyBiometrics: Codable {
        var id: String?
        var userId: String
        var date: String // YYYY-MM-DD format
        var sleepHours: Double?
        var sleepQuality: Int?
        var timeInBedHours: Double?
        var hrvMs: Double?
        var restingHeartRate: Int?
        var steps: Int?
        var activeCalories: Int?
        var totalCalories: Int?
        var exerciseMinutes: Int?
        var standHours: Int?
        var bodyWeightKg: Double?
        var bodyFatPercentage: Double?
        var energyLevel: Int?
        var stressLevel: Int?
        var sorenessLevel: Int?
        var mood: Int?
        var readinessScore: Int?
        var fromHealthkit: Bool?
        var fromManualEntry: Bool?
        var createdAt: Date?
        var updatedAt: Date?
    }
    
    struct DBAppEvent: Codable {
        var id: String?
        var userId: String?
        var eventName: String
        var eventCategory: String?
        var properties: [String: String]?
        var appVersion: String?
        var osVersion: String?
        var deviceModel: String?
        var screenName: String?
        var sessionId: String?
        var occurredAt: Date?
    }
    
    // MARK: - Sync Operations
    
    /// Sync user profile to Supabase
    func syncUserProfile(_ profile: UserProfile) async throws {
        guard supabase.isAuthenticated, let userId = supabase.currentUserId else {
            throw SupabaseError.notAuthenticated
        }
        
        let dbProfile = DBUserProfile(
            id: userId,
            displayName: profile.name,
            age: profile.age,
            sex: profile.sex.rawValue,
            workoutExperience: profile.workoutExperience.rawValue,
            fitnessGoals: profile.goals.map { $0.rawValue },
            weeklyFrequency: profile.weeklyFrequency,
            gymType: profile.gymType.rawValue,
            preferredWeightUnit: "pounds",
            onboardingCompleted: true,
            onboardingCompletedAt: Date()
        )
        
        let _: DBUserProfile? = try await supabase.upsert(into: "user_profiles", values: dbProfile)
    }
    
    /// Sync workout template to Supabase
    func syncWorkoutTemplate(_ template: WorkoutTemplate) async throws {
        guard supabase.isAuthenticated, let userId = supabase.currentUserId else {
            throw SupabaseError.notAuthenticated
        }
        
        // Sync template
        let dbTemplate = DBWorkoutTemplate(
            id: template.id.uuidString,
            userId: userId,
            name: template.name,
            templateType: "custom",
            isActive: true,
            createdAt: template.createdAt,
            updatedAt: template.updatedAt
        )
        
        let _: DBWorkoutTemplate? = try await supabase.upsert(into: "workout_templates", values: dbTemplate)
        
        // Delete existing exercises for this template
        try await supabase.delete(from: "workout_template_exercises", filter: ["template_id": template.id.uuidString])
        
        // Insert exercises
        let dbExercises = template.exercises.enumerated().map { idx, ex in
            DBTemplateExercise(
                id: ex.id.uuidString,
                templateId: template.id.uuidString,
                exerciseId: ex.exercise.id,
                exerciseName: ex.exercise.name,
                exerciseEquipment: ex.exercise.equipment,
                exerciseTarget: ex.exercise.target,
                setsTarget: ex.setsTarget,
                repRangeMin: ex.repRangeMin,
                repRangeMax: ex.repRangeMax,
                incrementKg: ex.increment * 0.453592, // Convert lbs to kg
                deloadFactor: ex.deloadFactor,
                failureThreshold: ex.failureThreshold,
                sortOrder: idx
            )
        }
        
        if !dbExercises.isEmpty {
            try await supabase.insertBatch(into: "workout_template_exercises", values: dbExercises)
        }
    }
    
    /// Sync completed workout session to Supabase
    func syncWorkoutSession(_ session: WorkoutSession) async throws {
        guard supabase.isAuthenticated, let userId = supabase.currentUserId else {
            throw SupabaseError.notAuthenticated
        }
        
        // Calculate stats
        var totalSets = 0
        var totalReps = 0
        var totalVolume: Double = 0
        
        for ex in session.exercises {
            for set in ex.sets where set.isCompleted {
                totalSets += 1
                totalReps += set.reps
                totalVolume += set.weight * Double(set.reps) * 0.453592 // Convert to kg
            }
        }
        
        let durationSeconds: Int? = session.endedAt.map { Int($0.timeIntervalSince(session.startedAt)) }
        
        // Sync session
        let dbSession = DBWorkoutSession(
            id: session.id.uuidString,
            userId: userId,
            templateId: session.templateId?.uuidString,
            templateName: session.name,
            name: session.name,
            startedAt: session.startedAt,
            endedAt: session.endedAt,
            durationSeconds: durationSeconds,
            wasDeload: session.wasDeload,
            deloadReason: session.deloadReason,
            totalSets: totalSets,
            totalReps: totalReps,
            totalVolumeKg: totalVolume,
            exerciseCount: session.exercises.count
        )
        
        let _: DBWorkoutSession? = try await supabase.upsert(into: "workout_sessions", values: dbSession)
        
        // Delete existing exercises for this session
        try await supabase.delete(from: "session_exercises", filter: ["session_id": session.id.uuidString])
        
        // Insert exercises and sets
        for (idx, ex) in session.exercises.enumerated() {
            var exSets = 0
            var exReps = 0
            var exVolume: Double = 0
            
            for set in ex.sets where set.isCompleted {
                exSets += 1
                exReps += set.reps
                exVolume += set.weight * Double(set.reps) * 0.453592
            }
            
            let dbExercise = DBSessionExercise(
                id: ex.id.uuidString,
                sessionId: session.id.uuidString,
                exerciseId: ex.exercise.id,
                exerciseName: ex.exercise.name,
                exerciseEquipment: ex.exercise.equipment,
                exerciseTarget: ex.exercise.target,
                setsTarget: ex.setsTarget,
                repRangeMin: ex.repRangeMin,
                repRangeMax: ex.repRangeMax,
                incrementKg: ex.increment * 0.453592,
                deloadFactor: ex.deloadFactor,
                failureThreshold: ex.failureThreshold,
                sortOrder: idx,
                isCompleted: ex.isCompleted,
                totalSetsCompleted: exSets,
                totalRepsCompleted: exReps,
                totalVolumeKg: exVolume
            )
            
            let _: DBSessionExercise? = try await supabase.upsert(into: "session_exercises", values: dbExercise)
            
            // Insert sets
            let dbSets = ex.sets.enumerated().map { setIdx, set in
                DBSessionSet(
                    id: set.id.uuidString,
                    sessionExerciseId: ex.id.uuidString,
                    setNumber: setIdx + 1,
                    reps: set.reps,
                    weightKg: set.weight * 0.453592,
                    isCompleted: set.isCompleted
                )
            }
            
            if !dbSets.isEmpty {
                try await supabase.insertBatch(into: "session_sets", values: dbSets)
            }
        }
    }
    
    /// Sync lift states to Supabase
    func syncLiftStates(_ states: [String: ExerciseState]) async throws {
        guard supabase.isAuthenticated, let userId = supabase.currentUserId else {
            throw SupabaseError.notAuthenticated
        }
        
        for (_, state) in states {
            let rollingKg = state.rollingE1RM.map { $0 * 0.453592 }
            let historyKg: [Double]? = {
                guard !state.e1rmHistory.isEmpty else { return nil }
                return state.e1rmHistory.map { $0.value * 0.453592 }
            }()
            
            let dbState = DBLiftState(
                userId: userId,
                exerciseId: state.exerciseId,
                exerciseName: state.exerciseId, // TODO: Get actual name
                lastWorkingWeightKg: state.currentWorkingWeight * 0.453592,
                rollingE1rmKg: rollingKg,
                e1rmTrend: state.e1rmTrend.rawValue,
                e1rmHistory: historyKg,
                consecutiveFailures: state.failuresCount,
                lastDeloadAt: state.lastDeloadAt,
                lastSessionAt: state.updatedAt,
                successfulSessionsCount: state.successfulSessionsCount
            )
            
            let _: DBLiftState? = try await supabase.upsert(into: "lift_states", values: dbState)
        }
    }
    
    /// Sync daily biometrics to Supabase
    func syncDailyBiometrics(_ biometrics: DailyBiometrics) async throws {
        guard supabase.isAuthenticated, let userId = supabase.currentUserId else {
            throw SupabaseError.notAuthenticated
        }
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        
        // Convert sleep minutes to hours
        let sleepHours = biometrics.sleepMinutes.map { $0 / 60.0 }
        
        let dbBiometrics = DBDailyBiometrics(
            userId: userId,
            date: dateFormatter.string(from: biometrics.date),
            sleepHours: sleepHours,
            hrvMs: biometrics.hrvSDNN,
            restingHeartRate: biometrics.restingHR.map { Int($0) },
            steps: biometrics.steps.map { Int($0) },
            activeCalories: biometrics.activeEnergy.map { Int($0) },
            fromHealthkit: true
        )
        
        let _: DBDailyBiometrics? = try await supabase.upsert(into: "daily_biometrics", values: dbBiometrics)
    }
    
    /// Track app event
    func trackEvent(
        name: String,
        category: String? = nil,
        properties: [String: String]? = nil,
        screenName: String? = nil
    ) async {
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        
        #if os(iOS)
        let osVersion = await MainActor.run { UIDevice.current.systemVersion }
        let deviceModel = await MainActor.run { UIDevice.current.model }
        #else
        let osVersion: String? = nil
        let deviceModel: String? = nil
        #endif
        
        let event = DBAppEvent(
            userId: supabase.currentUserId,
            eventName: name,
            eventCategory: category,
            properties: properties,
            appVersion: appVersion,
            osVersion: osVersion,
            deviceModel: deviceModel,
            screenName: screenName,
            occurredAt: Date()
        )
        
        do {
            let _: DBAppEvent? = try await supabase.insert(into: "app_events", values: event)
        } catch {
            print("Failed to track event: \(error)")
        }
    }
    
    // MARK: - Full Sync
    
    /// Perform a full sync of all local data to Supabase
    func performFullSync(
        profile: UserProfile?,
        templates: [WorkoutTemplate],
        sessions: [WorkoutSession],
        liftStates: [String: ExerciseState]
    ) async {
        guard supabase.isAuthenticated else { return }
        
        isSyncing = true
        syncError = nil
        
        do {
            // Sync profile
            if let profile {
                try await syncUserProfile(profile)
            }
            
            // Sync templates
            for template in templates {
                try await syncWorkoutTemplate(template)
            }
            
            // Sync completed sessions
            for session in sessions where session.endedAt != nil {
                try await syncWorkoutSession(session)
            }
            
            // Sync lift states
            try await syncLiftStates(liftStates)
            
            lastSyncAt = Date()
            
            await trackEvent(name: "full_sync_completed", category: "sync")
            
        } catch {
            syncError = error
            print("Sync error: \(error)")
        }
        
        isSyncing = false
    }
}
