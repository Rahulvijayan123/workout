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
    @Published var syncError: Error?  // Made settable for external error reporting
    
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
        /// Training phase: cut, maintenance, bulk, recomp (ML critical)
        var trainingPhase: String?
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
        var wasDeload: Bool?
        var deloadReason: String?
        
        // Pre-session subjective signals
        var preWorkoutReadiness: Int?       // 1-5 scale
        var preWorkoutSoreness: Int?        // 0-10 scale
        var preWorkoutEnergy: Int?          // 1-5 scale
        var preWorkoutMotivation: Int?      // 1-5 scale
        
        // Post-session subjective signals
        var sessionRpe: Int?                // 1-10 scale (validated internal load metric)
        var postWorkoutFeeling: Int?        // 1-5 scale
        var harderThanExpected: Bool?
        
        // Session-level pain/injury (safety critical)
        var sessionPainEntriesJson: String? // JSON array of pain entries
        var maxPainLevel: Int?              // 0-10 scale
        var anyStoppedDueToPain: Bool?
        
        // Life stress flags
        var hasIllness: Bool?
        var hasTravel: Bool?
        var hasWorkStress: Bool?
        var hasPoorSleep: Bool?
        var hasOtherStress: Bool?
        var stressNotes: String?
        
        // Context signals
        var timeOfDay: String?              // TimeOfDay raw value
        var wasFasted: Bool?
        var hoursSinceLastMeal: Double?
        var sleepQualityLastNight: Int?     // 1-5 scale
        var sleepHoursLastNight: Double?
        
        // Location (optional)
        var gymName: String?
        var latitude: Double?
        var longitude: Double?
        
        // Computed readiness score (0-100) captured at session start
        var computedReadinessScore: Int?
        
        // Legacy fields (kept for backward compatibility)
        var readinessScore: Int?
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
        var targetRir: Int?
        var restSeconds: Int?
        
        // Tempo prescription
        var tempoEccentric: Int?
        var tempoPauseBottom: Int?
        var tempoConcentric: Int?
        var tempoPauseTop: Int?
        
        var sortOrder: Int
        var isCompleted: Bool?
        var completedAt: Date?
        var totalSetsCompleted: Int?
        var totalRepsCompleted: Int?
        var totalVolumeKg: Double?
        
        // Pain/injury tracking (safety critical)
        var painEntriesJson: String?        // JSON array of pain entries
        var overallPainLevel: Int?          // 0-10 scale
        var stoppedDueToPain: Bool?
        
        // Substitution tracking
        var originalExerciseId: String?
        var originalExerciseName: String?
        var substitutionReason: String?     // SubstitutionReason raw value
        var isSubstitution: Bool?
        
        // Equipment variation
        var equipmentVariation: String?     // EquipmentVariation raw value
        
        // Exercise-level compliance
        var exerciseCompliance: String?     // RecommendationCompliance raw value
        var exerciseComplianceReason: String? // ComplianceReasonCode raw value
        
        // Technique limitations
        var hasLimitedRom: Bool?
        var hasGripIssue: Bool?
        var hasStabilityIssue: Bool?
        var hasBreathingIssue: Bool?
        var hasTechniqueOther: Bool?
        var techniqueLimitationNotes: String?
        
        // ML CRITICAL: Recommendation event link
        var recommendationEventId: String?
        
        // ML CRITICAL: Planned prescription (frozen at session start)
        var plannedTopSetWeightKg: Double?
        var plannedTopSetReps: Int?
        var plannedTargetRir: Int?
        
        // ML CRITICAL: State snapshot at session start (JSONB)
        var stateAtRecommendation: String?
        
        // ML CRITICAL: Exposure definition
        var exposureRole: String?
        
        // ML CRITICAL: Outcome labels (computed at session end)
        var exposureOutcome: String?
        var setsSuccessful: Int?
        var setsFailed: Int?
        var setsUnknownDifficulty: Int?
        var sessionE1rmKg: Double?
        var rawTopSetE1rmKg: Double?
        var e1rmDeltaKg: Double?
        
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
        
        // Target effort (prescription)
        var targetRir: Int?
        var targetRpe: Double?
        
        // Observed effort (actual)
        var rirObserved: Int?
        var rpeObserved: Double?
        
        // Timing
        var completedAt: Date?
        var actualRestSeconds: Int?
        
        // Set classification
        var isWarmup: Bool?
        var isDropset: Bool?
        var isFailure: Bool?
        var isCompleted: Bool?
        
        // Recommendation compliance (ML critical)
        var compliance: String?            // RecommendationCompliance raw value
        var complianceReason: String?      // ComplianceReasonCode raw value
        var recommendedWeightKg: Double?
        var recommendedReps: Int?
        
        // ML CRITICAL: Planned set link (join key)
        var plannedSetId: String?
        
        // ML CRITICAL: User modification tracking
        var isUserModified: Bool?
        var originalPrescribedWeightKg: Double?
        var originalPrescribedReps: Int?
        var modificationReason: String?    // ComplianceReasonCode raw value
        
        // ML CRITICAL: Outcome labels
        var setOutcome: String?
        var metRepTarget: Bool?
        var metEffortTarget: Bool?
        
        // Tempo (actual, if different from prescribed)
        var tempoEccentric: Int?
        var tempoPauseBottom: Int?
        var tempoConcentric: Int?
        var tempoPauseTop: Int?
        
        // Technique limitations
        var hasLimitedRom: Bool?
        var hasGripIssue: Bool?
        var hasStabilityIssue: Bool?
        var hasBreathingIssue: Bool?
        var hasTechniqueOther: Bool?
        var techniqueLimitationNotes: String?
        
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
        /// DEPRECATED: Raw e1rm values without dates. Use e1rmHistoryJson instead.
        var e1rmHistory: [Double]?
        /// ML CRITICAL: JSON array of {date: ISO8601, valueKg: Double} objects.
        /// Stores actual session dates instead of fabricated ones.
        var e1rmHistoryJson: String?
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
    
    /// Helper struct for storing e1rm history with proper dates.
    struct DBE1RMSample: Codable {
        var date: Date
        var valueKg: Double
    }
    
    struct DBDailyBiometrics: Codable {
        var id: String?
        var userId: String
        var date: String // YYYY-MM-DD format
        
        // MARK: - Core Recovery Metrics
        var sleepMinutes: Double?
        var hrvSdnn: Double?
        var restingHr: Double?
        var vo2Max: Double?
        var respiratoryRate: Double?
        var oxygenSaturation: Double?
        
        // MARK: - Activity Metrics
        var activeEnergy: Double?
        var steps: Double?
        var exerciseTimeMinutes: Double?
        var standHours: Int?
        
        // MARK: - Walking Metrics (Injury Detection)
        var walkingHeartRateAvg: Double?
        var walkingAsymmetry: Double?
        var walkingSpeed: Double?
        var walkingStepLength: Double?
        var walkingDoubleSupport: Double?
        var stairAscentSpeed: Double?
        var stairDescentSpeed: Double?
        var sixMinuteWalkDistance: Double?
        
        // MARK: - Sleep Details (iOS 16+)
        var timeInBedMinutes: Double?
        var sleepAwakeMinutes: Double?
        var sleepCoreMinutes: Double?
        var sleepDeepMinutes: Double?
        var sleepRemMinutes: Double?
        var timeInDaylightMinutes: Double?
        var wristTemperatureCelsius: Double?
        
        // MARK: - Body Composition
        var bodyWeightKg: Double?
        var bodyFatPercentage: Double?
        var leanBodyMassKg: Double?
        var bodyWeightFromHealthkit: Bool?
        
        // MARK: - Nutrition (HealthKit)
        var dietaryEnergyKcal: Double?
        var dietaryProteinGrams: Double?
        var dietaryCarbsGrams: Double?
        var dietaryFatGrams: Double?
        var waterIntakeLiters: Double?
        var caffeineMg: Double?
        
        // MARK: - Nutrition Buckets (Manual)
        var nutritionBucket: String?
        var proteinBucket: String?
        var proteinGrams: Int?
        var totalCalories: Int?
        var hydrationLevel: Int?
        var alcoholLevel: Int?
        
        // MARK: - Female Health (HealthKit - Opt-in)
        var menstrualFlowRaw: Int?
        var cervicalMucusQualityRaw: Int?
        var basalBodyTemperatureCelsius: Double?
        var cyclePhase: String?
        var cycleDayNumber: Int?
        var onHormonalBirthControl: Bool?
        
        // MARK: - Mindfulness
        var mindfulMinutes: Double?
        
        // MARK: - Subjective Daily Metrics
        var sleepQuality: Int?
        var sleepDisruptions: Int?
        var energyLevel: Int?
        var stressLevel: Int?
        var moodScore: Int?
        var overallSoreness: Int?
        var readinessScore: Int?
        
        // MARK: - Life Stress Flags
        var hasIllness: Bool?
        var hasTravel: Bool?
        var hasWorkStress: Bool?
        var hadPoorSleep: Bool?
        var hasOtherStress: Bool?
        var stressNotes: String?
        
        // MARK: - Data Source Flags
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
    
    // MARK: - ML Training Data Models
    
    struct DBRecommendationEvent: Codable {
        var id: String?
        var userId: String
        var sessionId: String?
        var sessionExerciseId: String?
        var exerciseId: String
        
        // What was recommended
        var recommendedWeightKg: Double
        var recommendedReps: Int
        var recommendedSets: Int
        var recommendedRir: Int
        
        // Policy metadata
        var policyVersion: String
        var policyType: String
        var actionType: String
        var reasonCodes: [String]?
        
        // Confidence/exploration
        var modelConfidence: Double?
        var isExploration: Bool?
        var explorationDeltaKg: Double?
        
        // Counterfactual
        var deterministicWeightKg: Double?
        var deterministicReps: Int?
        
        // State snapshot (JSONB)
        var stateAtRecommendation: String?
        
        // ML CRITICAL: Policy selection metadata (bandit/shadow mode)
        var executedPolicyId: String?
        var executedActionProbability: Double?
        var explorationMode: String?
        var shadowPolicyId: String?
        var shadowActionProbability: Double?
        
        var generatedAt: Date?
    }
    
    struct DBPlannedSet: Codable {
        var id: String?
        var sessionExerciseId: String
        var recommendationEventId: String?
        
        var setNumber: Int
        var targetWeightKg: Double
        var targetReps: Int
        var targetRir: Int?
        var targetRestSeconds: Int?
        
        // Tempo
        var targetTempoEccentric: Int?
        var targetTempoPauseBottom: Int?
        var targetTempoConcentric: Int?
        var targetTempoPauseTop: Int?
        
        var isWarmup: Bool?
        var createdAt: Date?
    }
    
    struct DBPainEvent: Codable {
        var id: String?
        var userId: String
        var sessionId: String?
        var sessionExerciseId: String?
        var sessionSetId: String?
        
        var bodyRegion: String
        var severity: Int
        var painType: String?
        var causedStop: Bool?
        var notes: String?
        
        var reportedAt: Date?
    }
    
    struct DBUserSensitiveContext: Codable {
        var id: String?
        var userId: String
        var date: String  // YYYY-MM-DD
        
        // Menstrual cycle
        var cyclePhase: String?
        var cycleDayNumber: Int?
        var onHormonalBirthControl: Bool?
        
        // Nutrition
        var nutritionBucket: String?
        var proteinBucket: String?
        
        // Mood/stress
        var moodScore: Int?
        var stressLevel: Int?
        
        // Consent
        var consentedToMlTraining: Bool?
        var consentTimestamp: Date?
        
        var createdAt: Date?
        var updatedAt: Date?
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
            onboardingCompletedAt: Date(),
            trainingPhase: profile.trainingPhase.rawValue
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
        
        // Encode pain entries to JSON
        let sessionPainJson: String? = {
            guard let entries = session.sessionPainEntries, !entries.isEmpty else { return nil }
            let encoder = JSONEncoder()
            if let data = try? encoder.encode(entries), let str = String(data: data, encoding: .utf8) {
                return str
            }
            return nil
        }()
        
        // Sync session with all new fields
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
            // Pre-session signals
            preWorkoutReadiness: session.preWorkoutReadiness,
            preWorkoutSoreness: session.preWorkoutSoreness,
            preWorkoutEnergy: session.preWorkoutEnergy,
            preWorkoutMotivation: session.preWorkoutMotivation,
            // Post-session signals
            sessionRpe: session.sessionRPE,
            postWorkoutFeeling: session.postWorkoutFeeling,
            harderThanExpected: session.harderThanExpected,
            // Pain/injury
            sessionPainEntriesJson: sessionPainJson,
            maxPainLevel: session.maxPainLevel,
            anyStoppedDueToPain: session.anyExerciseStoppedDueToPain,
            // Life stress flags
            hasIllness: session.lifeStressFlags?.illness,
            hasTravel: session.lifeStressFlags?.travel,
            hasWorkStress: session.lifeStressFlags?.workStress,
            hasPoorSleep: session.lifeStressFlags?.poorSleep,
            hasOtherStress: session.lifeStressFlags?.other,
            stressNotes: session.lifeStressFlags?.notes,
            // Context signals
            timeOfDay: session.timeOfDay?.rawValue ?? TimeOfDay.from(date: session.startedAt).rawValue,
            wasFasted: session.wasFasted,
            hoursSinceLastMeal: session.hoursSinceLastMeal,
            sleepQualityLastNight: session.sleepQualityLastNight,
            sleepHoursLastNight: session.sleepHoursLastNight,
            // Computed readiness score
            computedReadinessScore: session.computedReadinessScore,
            // Notes and stats
            notes: session.sessionNotes,
            totalSets: totalSets,
            totalReps: totalReps,
            totalVolumeKg: totalVolume,
            exerciseCount: session.exercises.count
        )
        
        let _: DBWorkoutSession? = try await supabase.upsert(into: "workout_sessions", values: dbSession)
        
        // Track synced IDs for ghost row cleanup
        var syncedExerciseIds: [String] = []
        var syncedSetIdsByExercise: [String: [String]] = [:]
        
        // Insert exercises and sets
        for (idx, ex) in session.exercises.enumerated() {
            // Track this exercise ID for ghost row cleanup
            syncedExerciseIds.append(ex.id.uuidString)
            // ML CRITICAL: Only use real recommendationEventId if present.
            // Do NOT fabricate join keys for manual/ad-hoc exercises.
            
            var exSets = 0
            var exReps = 0
            var exVolume: Double = 0
            
            for set in ex.sets where set.isCompleted {
                exSets += 1
                exReps += set.reps
                exVolume += set.weight * Double(set.reps) * 0.453592
            }
            
            // Encode exercise pain entries to JSON
            let exercisePainJson: String? = {
                guard let entries = ex.painEntries, !entries.isEmpty else { return nil }
                let encoder = JSONEncoder()
                if let data = try? encoder.encode(entries), let str = String(data: data, encoding: .utf8) {
                    return str
                }
                return nil
            }()
            
            // Encode state snapshot to JSON for ML
            let stateSnapshotJson: String? = {
                guard let snapshot = ex.stateSnapshot else { return nil }
                let encoder = JSONEncoder()
                if let data = try? encoder.encode(snapshot), let str = String(data: data, encoding: .utf8) {
                    return str
                }
                return nil
            }()
            
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
                targetRir: ex.targetRIR,
                restSeconds: ex.restSeconds,
                // Tempo prescription
                tempoEccentric: ex.tempo.eccentric,
                tempoPauseBottom: ex.tempo.pauseBottom,
                tempoConcentric: ex.tempo.concentric,
                tempoPauseTop: ex.tempo.pauseTop,
                sortOrder: idx,
                isCompleted: ex.isCompleted,
                totalSetsCompleted: exSets,
                totalRepsCompleted: exReps,
                totalVolumeKg: exVolume,
                // Pain/injury
                painEntriesJson: exercisePainJson,
                overallPainLevel: ex.overallPainLevel,
                stoppedDueToPain: ex.stoppedDueToPain,
                // Substitution
                originalExerciseId: ex.originalExerciseId,
                originalExerciseName: ex.originalExerciseName,
                substitutionReason: ex.substitutionReason?.rawValue,
                isSubstitution: ex.isSubstitution,
                // Equipment/compliance
                equipmentVariation: ex.equipmentVariation?.rawValue,
                exerciseCompliance: ex.exerciseCompliance?.rawValue,
                exerciseComplianceReason: ex.exerciseComplianceReason?.rawValue,
                // Technique limitations
                hasLimitedRom: ex.techniqueLimitations?.limitedROM,
                hasGripIssue: ex.techniqueLimitations?.gripIssue,
                hasStabilityIssue: ex.techniqueLimitations?.stabilityIssue,
                hasBreathingIssue: ex.techniqueLimitations?.breathingIssue,
                hasTechniqueOther: ex.techniqueLimitations?.other,
                techniqueLimitationNotes: ex.techniqueLimitations?.notes,
                // ML CRITICAL: Recommendation event link (only set for engine-planned exercises)
                recommendationEventId: ex.recommendationEventId?.uuidString,
                // ML CRITICAL: Planned prescription
                plannedTopSetWeightKg: ex.plannedTopSetWeightLbs.map { $0 * 0.453592 },
                plannedTopSetReps: ex.plannedTopSetReps,
                plannedTargetRir: ex.plannedTargetRIR,
                // ML CRITICAL: State snapshot
                stateAtRecommendation: stateSnapshotJson,
                // ML CRITICAL: Exposure definition
                exposureRole: ex.exposureRole?.rawValue,
                // ML CRITICAL: Outcome labels
                exposureOutcome: ex.exposureOutcome?.rawValue,
                setsSuccessful: ex.setsSuccessful,
                setsFailed: ex.setsFailed,
                setsUnknownDifficulty: ex.setsUnknownDifficulty,
                sessionE1rmKg: ex.sessionE1rmLbs.map { $0 * 0.453592 },
                rawTopSetE1rmKg: ex.rawTopSetE1rmLbs.map { $0 * 0.453592 },
                e1rmDeltaKg: ex.e1rmDeltaLbs.map { $0 * 0.453592 }
            )
            
            let _: DBSessionExercise? = try await supabase.upsert(into: "session_exercises", values: dbExercise)
            
            // Insert sets with all new fields
            let dbSets: [DBSessionSet] = ex.sets.enumerated().map { setIdx, set in
                return DBSessionSet(
                    id: set.id.uuidString,
                    sessionExerciseId: ex.id.uuidString,
                    setNumber: setIdx + 1,
                    reps: set.reps,
                    weightKg: set.weight * 0.453592,
                    // Target effort
                    targetRir: set.targetRIR,
                    targetRpe: set.targetRPE,
                    // Observed effort
                    rirObserved: set.rirObserved,
                    rpeObserved: set.rpeObserved,
                    // Timing
                    completedAt: set.completedAt,
                    actualRestSeconds: set.actualRestSeconds,
                    // Set classification
                    isWarmup: set.isWarmup,
                    isDropset: set.isDropSet,
                    isFailure: set.isFailure,
                    isCompleted: set.isCompleted,
                    // Recommendation compliance
                    compliance: set.compliance?.rawValue,
                    complianceReason: set.complianceReason?.rawValue,
                    recommendedWeightKg: set.recommendedWeight.map { $0 * 0.453592 },
                    recommendedReps: set.recommendedReps,
                    // ML CRITICAL: Planned set link (only set for engine-planned sets)
                    plannedSetId: set.plannedSetId?.uuidString,
                    // ML CRITICAL: User modification tracking
                    isUserModified: set.isUserModified,
                    originalPrescribedWeightKg: set.originalPrescribedWeight.map { $0 * 0.453592 },
                    originalPrescribedReps: set.originalPrescribedReps,
                    modificationReason: set.modificationReason?.rawValue,
                    // ML CRITICAL: Outcome labels
                    setOutcome: set.setOutcome?.rawValue,
                    metRepTarget: set.metRepTarget,
                    metEffortTarget: set.metEffortTarget,
                    // Tempo actual
                    tempoEccentric: set.tempoActual?.eccentric,
                    tempoPauseBottom: set.tempoActual?.pauseBottom,
                    tempoConcentric: set.tempoActual?.concentric,
                    tempoPauseTop: set.tempoActual?.pauseTop,
                    // Technique limitations
                    hasLimitedRom: set.techniqueLimitations?.limitedROM,
                    hasGripIssue: set.techniqueLimitations?.gripIssue,
                    hasStabilityIssue: set.techniqueLimitations?.stabilityIssue,
                    hasBreathingIssue: set.techniqueLimitations?.breathingIssue,
                    hasTechniqueOther: set.techniqueLimitations?.other,
                    techniqueLimitationNotes: set.techniqueLimitations?.notes,
                    notes: set.notes
                )
            }
            
            // Track set IDs for ghost row cleanup
            let setIds = ex.sets.map { $0.id.uuidString }
            syncedSetIdsByExercise[ex.id.uuidString] = setIds
            
            if !dbSets.isEmpty {
                // Use upsert to make sync idempotent (safe on resync) and to allow
                // incremental set logging (weight/reps/RIR edits) without duplicates.
                try await supabase.upsertBatch(
                    into: "session_sets",
                    values: dbSets,
                    onConflict: "id",
                    resolution: .mergeDuplicates
                )
                
                // Clean up ghost rows: delete sets that were removed from this exercise
                try await supabase.deleteNotIn(
                    from: "session_sets",
                    scopeColumn: "session_exercise_id",
                    scopeValue: ex.id.uuidString,
                    idColumn: "id",
                    idsToKeep: setIds
                )
            }
            
            // ML CRITICAL: Only generate recommendation_events and planned_sets for
            // engine-planned exercises (those with a real recommendationEventId).
            // Manual/ad-hoc exercises should NOT have fabricated ML data.
            if let recEventId = ex.recommendationEventId {
                do {
                    // Build state snapshot for recommendation event
                    let recStateSnapshot = RecommendationEvent.LiftStateSnapshot(
                        rollingE1rmLbs: ex.stateSnapshot?.rollingE1rmLbs,
                        rawE1rmLbs: ex.stateSnapshot?.rawE1rmLbs,
                        consecutiveFailures: ex.stateSnapshot?.consecutiveFailures ?? 0,
                        consecutiveSuccesses: ex.stateSnapshot?.consecutiveSuccesses ?? 0,
                        highRPEStreak: ex.stateSnapshot?.highRPEStreak ?? 0,
                        daysSinceLastExposure: ex.stateSnapshot?.daysSinceLastExposure,
                        daysSinceLastDeload: ex.stateSnapshot?.daysSinceLastDeload,
                        lastSessionWeightLbs: ex.stateSnapshot?.lastWeightLbs,
                        lastSessionReps: ex.stateSnapshot?.lastReps,
                        lastSessionRIR: ex.stateSnapshot?.lastRIR,
                        lastSessionOutcome: ex.stateSnapshot?.lastOutcome,
                        exposuresLast14Days: ex.stateSnapshot?.exposuresLast14Days ?? 0,
                        volumeLast7DaysLbs: ex.stateSnapshot?.volumeLast7DaysLbs,
                        successfulSessionsCount: ex.stateSnapshot?.successfulSessionsCount ?? 0,
                        totalSessionsCount: ex.stateSnapshot?.totalSessionsCount ?? 0,
                        e1rmTrend: ex.stateSnapshot?.e1rmTrend,
                        templateVersion: ex.stateSnapshot?.templateVersion
                    )
                    
                    // ML CRITICAL: Skip recommendation events if core prescription fields are missing.
                    // Emitting events with recommendedWeight=0 poisons training data.
                    guard let recommendedWeightLbs = ex.plannedTopSetWeightLbs,
                          recommendedWeightLbs > 0 else {
                        // Skip this exercise - lacks proper prescription data
                        continue
                    }
                    
                    let recommendedReps = ex.plannedTopSetReps ?? ex.repRangeMin
                    let recommendedRIR = ex.plannedTargetRIR ?? ex.targetRIR
                    
                    // Derive action type from engine's direction decision (not hardcoded)
                    let actionType: RecommendationEvent.RecommendationActionType = {
                        // Use the engine's direction decision if available
                        if let direction = ex.progressionDirection {
                            switch direction {
                            case "increase":
                                return .increaseLoad
                            case "hold":
                                return .holdLoad
                            case "decrease_slightly":
                                return .decreaseLoad
                            case "deload":
                                return .deload
                            case "reset_after_break":
                                return .reset
                            default:
                                break
                            }
                        }
                        
                        // Fallback: derive from session/state context
                        if session.wasDeload { return .deload }
                        
                        // If we have state snapshot, derive from weight delta
                        if let lastWeight = ex.stateSnapshot?.lastWeightLbs,
                           lastWeight > 0 {
                            let delta = recommendedWeightLbs - lastWeight
                            if delta > 0.5 { return .increaseLoad }
                            if delta < -0.5 { return .decreaseLoad }
                        }
                        
                        return .holdLoad
                    }()
                    
                    var recommendationEvent = RecommendationEvent(
                        id: recEventId,
                        sessionId: session.id,
                        sessionExerciseId: ex.id,
                        exerciseId: ex.exercise.id,
                        recommendedWeightLbs: recommendedWeightLbs,
                        recommendedReps: recommendedReps,
                        recommendedSets: ex.setsTarget,
                        recommendedRIR: recommendedRIR,
                        policyVersion: "v1.0",
                        policyType: .deterministic,
                        actionType: actionType,
                        stateSnapshot: recStateSnapshot,
                        generatedAt: session.startedAt
                    )
                    
                    // Populate policy selection metadata from snapshot (bandit/shadow mode)
                    if let policySnapshot = ex.policySelectionSnapshot {
                        recommendationEvent.executedPolicyId = policySnapshot.executedPolicyId
                        recommendationEvent.executedActionProbability = policySnapshot.executedActionProbability
                        recommendationEvent.explorationModeTag = policySnapshot.explorationMode
                        recommendationEvent.shadowPolicyId = policySnapshot.shadowPolicyId
                        recommendationEvent.shadowActionProbability = policySnapshot.shadowActionProbability
                    }
                    
                    // Persist recommendation event (idempotent; never overwrite existing row).
                    try await syncRecommendationEvent(recommendationEvent)
                } catch {
                    // Bubble up any failure — recommendation_events is ML-critical.
                    throw error
                }
                
                // ML CRITICAL: Only generate PlannedSet for sets with real plannedSetId and recommendedWeight.
                // Do NOT fabricate IDs or fall back to performed values.
                let plannedSets: [PlannedSet] = ex.sets.enumerated().compactMap { setIdx, set in
                    // Only emit planned sets that have proper prescription data
                    guard let plannedSetId = set.plannedSetId,
                          let targetWeight = set.recommendedWeight else {
                        return nil  // Skip sets without proper planned data
                    }
                    
                    return PlannedSet(
                        id: plannedSetId,
                        sessionExerciseId: ex.id,
                        recommendationEventId: recEventId,
                        setNumber: setIdx + 1,
                        targetWeightLbs: targetWeight,
                        targetReps: set.recommendedReps ?? ex.repRangeMin,
                        targetRIR: set.targetRIR ?? ex.targetRIR,
                        targetRestSeconds: ex.restSeconds,
                        targetTempo: ex.tempo,
                        isWarmup: set.isWarmup,
                        createdAt: session.startedAt
                    )
                }
                
                if !plannedSets.isEmpty {
                    try await syncPlannedSets(plannedSets)
                }
            }
        }
        
        // Clean up ghost rows: delete session_exercises that were removed from this session.
        // This prevents orphaned rows from accumulating when users remove exercises.
        if !syncedExerciseIds.isEmpty {
            try await supabase.deleteNotIn(
                from: "session_exercises",
                scopeColumn: "session_id",
                scopeValue: session.id.uuidString,
                idColumn: "id",
                idsToKeep: syncedExerciseIds
            )
        }
    }
    
    /// Sync lift states to Supabase
    func syncLiftStates(_ states: [String: ExerciseState]) async throws {
        guard supabase.isAuthenticated, let userId = supabase.currentUserId else {
            throw SupabaseError.notAuthenticated
        }
        
        for (_, state) in states {
            let rollingKg = state.rollingE1RM.map { $0 * 0.453592 }
            
            // DEPRECATED: Keep for backwards compatibility
            let historyKg: [Double]? = {
                guard !state.e1rmHistory.isEmpty else { return nil }
                return state.e1rmHistory.map { $0.value * 0.453592 }
            }()
            
            // ML CRITICAL: Store history with actual dates (not fabricated)
            let historyJson: String? = {
                guard !state.e1rmHistory.isEmpty else { return nil }
                let samples = state.e1rmHistory.map { sample in
                    DBE1RMSample(date: sample.date, valueKg: sample.value * 0.453592)
                }
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .iso8601
                if let data = try? encoder.encode(samples), let str = String(data: data, encoding: .utf8) {
                    return str
                }
                return nil
            }()
            
            let dbState = DBLiftState(
                userId: userId,
                exerciseId: state.exerciseId,
                exerciseName: state.exerciseId, // TODO: Get actual name
                lastWorkingWeightKg: state.currentWorkingWeight * 0.453592,
                rollingE1rmKg: rollingKg,
                e1rmTrend: state.e1rmTrend.rawValue,
                e1rmHistory: historyKg,
                e1rmHistoryJson: historyJson,
                consecutiveFailures: state.failuresCount,
                lastDeloadAt: state.lastDeloadAt,
                lastSessionAt: state.updatedAt,
                successfulSessionsCount: state.successfulSessionsCount
            )
            
            // Upsert on the natural key (user_id, exercise_id). This avoids duplicates and
            // requires the corresponding UNIQUE constraint in Supabase.
            let _: DBLiftState? = try await supabase.upsert(
                into: "lift_states",
                values: dbState,
                onConflict: "user_id,exercise_id"
            )
        }
    }
    
    /// Sync daily biometrics to Supabase
    func syncDailyBiometrics(_ biometrics: DailyBiometrics) async throws {
        guard supabase.isAuthenticated, let userId = supabase.currentUserId else {
            throw SupabaseError.notAuthenticated
        }
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        
        let dbBiometrics = DBDailyBiometrics(
            userId: userId,
            date: dateFormatter.string(from: biometrics.date),
            
            // Core Recovery
            sleepMinutes: biometrics.sleepMinutes,
            hrvSdnn: biometrics.hrvSDNN,
            restingHr: biometrics.restingHR,
            vo2Max: biometrics.vo2Max,
            respiratoryRate: biometrics.respiratoryRate,
            oxygenSaturation: biometrics.oxygenSaturation,
            
            // Activity
            activeEnergy: biometrics.activeEnergy,
            steps: biometrics.steps,
            exerciseTimeMinutes: biometrics.exerciseTimeMinutes,
            standHours: biometrics.standHours,
            
            // Walking Metrics
            walkingHeartRateAvg: biometrics.walkingHeartRateAvg,
            walkingAsymmetry: biometrics.walkingAsymmetry,
            walkingSpeed: biometrics.walkingSpeed,
            walkingStepLength: biometrics.walkingStepLength,
            walkingDoubleSupport: biometrics.walkingDoubleSupport,
            stairAscentSpeed: biometrics.stairAscentSpeed,
            stairDescentSpeed: biometrics.stairDescentSpeed,
            sixMinuteWalkDistance: biometrics.sixMinuteWalkDistance,
            
            // Sleep Details
            timeInBedMinutes: biometrics.timeInBedMinutes,
            sleepAwakeMinutes: biometrics.sleepAwakeMinutes,
            sleepCoreMinutes: biometrics.sleepCoreMinutes,
            sleepDeepMinutes: biometrics.sleepDeepMinutes,
            sleepRemMinutes: biometrics.sleepRemMinutes,
            timeInDaylightMinutes: biometrics.timeInDaylightMinutes,
            wristTemperatureCelsius: biometrics.wristTemperatureCelsius,
            
            // Body Composition
            bodyWeightKg: biometrics.bodyWeightKg,
            bodyFatPercentage: biometrics.bodyFatPercentage,
            leanBodyMassKg: biometrics.leanBodyMassKg,
            bodyWeightFromHealthkit: biometrics.bodyWeightFromHealthKit,
            
            // Nutrition (HealthKit)
            dietaryEnergyKcal: biometrics.dietaryEnergyKcal,
            dietaryProteinGrams: biometrics.dietaryProteinGrams,
            dietaryCarbsGrams: biometrics.dietaryCarbsGrams,
            dietaryFatGrams: biometrics.dietaryFatGrams,
            waterIntakeLiters: biometrics.waterIntakeLiters,
            caffeineMg: biometrics.caffeineMg,
            
            // Nutrition Buckets (Manual)
            nutritionBucket: biometrics.nutritionBucket?.rawValue,
            proteinBucket: biometrics.proteinBucket?.rawValue,
            proteinGrams: biometrics.proteinGrams,
            totalCalories: biometrics.totalCalories,
            hydrationLevel: biometrics.hydrationLevel,
            alcoholLevel: biometrics.alcoholLevel,
            
            // Female Health
            menstrualFlowRaw: biometrics.menstrualFlowRaw,
            cervicalMucusQualityRaw: biometrics.cervicalMucusQualityRaw,
            basalBodyTemperatureCelsius: biometrics.basalBodyTemperatureCelsius,
            cyclePhase: biometrics.cyclePhase?.rawValue,
            cycleDayNumber: biometrics.cycleDayNumber,
            onHormonalBirthControl: biometrics.onHormonalBirthControl,
            
            // Mindfulness
            mindfulMinutes: biometrics.mindfulMinutes,
            
            // Subjective Metrics
            sleepQuality: biometrics.sleepQuality,
            sleepDisruptions: biometrics.sleepDisruptions,
            energyLevel: biometrics.energyLevel,
            stressLevel: biometrics.stressLevel,
            moodScore: biometrics.moodScore,
            overallSoreness: biometrics.overallSoreness,
            readinessScore: biometrics.readinessScore,
            
            // Life Stress Flags
            hasIllness: biometrics.hasIllness,
            hasTravel: biometrics.hasTravel,
            hasWorkStress: biometrics.hasWorkStress,
            hadPoorSleep: biometrics.hadPoorSleep,
            hasOtherStress: biometrics.hasOtherStress,
            stressNotes: biometrics.stressNotes,
            
            // Data Source Flags
            fromHealthkit: biometrics.fromHealthKit,
            fromManualEntry: biometrics.fromManualEntry
        )
        
        // Upsert on the natural key (user_id, date). This avoids duplicates and
        // requires the corresponding UNIQUE constraint in Supabase.
        let _: DBDailyBiometrics? = try await supabase.upsert(
            into: "daily_biometrics",
            values: dbBiometrics,
            onConflict: "user_id,date"
        )
    }
    
    // MARK: - ML Training Data Sync
    
    /// Sync a recommendation event (immutable - never update)
    func syncRecommendationEvent(_ event: RecommendationEvent) async throws {
        guard supabase.isAuthenticated, let userId = supabase.currentUserId else {
            throw SupabaseError.notAuthenticated
        }
        
        // Encode state snapshot to JSON
        let stateJson: String? = {
            let encoder = JSONEncoder()
            if let data = try? encoder.encode(event.stateSnapshot), let str = String(data: data, encoding: .utf8) {
                return str
            }
            return nil
        }()
        
        let dbEvent = DBRecommendationEvent(
            id: event.id.uuidString,
            userId: userId,
            sessionId: event.sessionId?.uuidString,
            sessionExerciseId: event.sessionExerciseId?.uuidString,
            exerciseId: event.exerciseId,
            recommendedWeightKg: event.recommendedWeightLbs * 0.453592,
            recommendedReps: event.recommendedReps,
            recommendedSets: event.recommendedSets,
            recommendedRir: event.recommendedRIR,
            policyVersion: event.policyVersion,
            policyType: event.policyType.rawValue,
            actionType: event.actionType.rawValue,
            reasonCodes: event.reasonCodes.map { $0.rawValue },
            modelConfidence: event.modelConfidence,
            isExploration: event.isExploration,
            explorationDeltaKg: event.explorationDeltaLbs.map { $0 * 0.453592 },
            deterministicWeightKg: event.deterministicWeightLbs.map { $0 * 0.453592 },
            deterministicReps: event.deterministicReps,
            stateAtRecommendation: stateJson,
            // Policy selection metadata (bandit/shadow mode)
            executedPolicyId: event.executedPolicyId,
            executedActionProbability: event.executedActionProbability,
            explorationMode: event.explorationModeTag,
            shadowPolicyId: event.shadowPolicyId,
            shadowActionProbability: event.shadowActionProbability,
            generatedAt: event.generatedAt
        )
        
        // Immutable log: insert once, ignore duplicates on resync.
        let _: DBRecommendationEvent? = try await supabase.upsert(
            into: "recommendation_events",
            values: dbEvent,
            onConflict: "id",
            returning: false,
            resolution: .ignoreDuplicates
        )
    }
    
    /// Sync planned sets (immutable - created at session start)
    func syncPlannedSets(_ sets: [PlannedSet]) async throws {
        guard supabase.isAuthenticated else {
            throw SupabaseError.notAuthenticated
        }
        
        let dbSets = sets.map { set in
            DBPlannedSet(
                id: set.id.uuidString,
                sessionExerciseId: set.sessionExerciseId.uuidString,
                recommendationEventId: set.recommendationEventId?.uuidString,
                setNumber: set.setNumber,
                targetWeightKg: set.targetWeightLbs * 0.453592,
                targetReps: set.targetReps,
                targetRir: set.targetRIR,
                targetRestSeconds: set.targetRestSeconds,
                targetTempoEccentric: set.targetTempo?.eccentric,
                targetTempoPauseBottom: set.targetTempo?.pauseBottom,
                targetTempoConcentric: set.targetTempo?.concentric,
                targetTempoPauseTop: set.targetTempo?.pauseTop,
                isWarmup: set.isWarmup,
                createdAt: set.createdAt
            )
        }
        
        if !dbSets.isEmpty {
            // Immutable prescription: insert once, ignore duplicates on resync.
            try await supabase.upsertBatch(
                into: "planned_sets",
                values: dbSets,
                onConflict: "id",
                resolution: .ignoreDuplicates
            )
        }
    }
    
    /// Sync pain events (normalized, one per pain report)
    func syncPainEvents(_ events: [PainEvent]) async throws {
        guard supabase.isAuthenticated, let userId = supabase.currentUserId else {
            throw SupabaseError.notAuthenticated
        }
        
        let dbEvents = events.map { event in
            DBPainEvent(
                id: event.id.uuidString,
                userId: userId,
                sessionId: event.sessionId?.uuidString,
                sessionExerciseId: event.sessionExerciseId?.uuidString,
                sessionSetId: event.sessionSetId?.uuidString,
                bodyRegion: event.bodyRegion.rawValue,
                severity: event.severity,
                painType: event.painType?.rawValue,
                causedStop: event.causedStop,
                notes: event.notes,
                reportedAt: event.reportedAt
            )
        }
        
        if !dbEvents.isEmpty {
            // Pain events are immutable: insert once, ignore duplicates on resync.
            try await supabase.upsertBatch(
                into: "pain_events",
                values: dbEvents,
                onConflict: "id",
                resolution: .ignoreDuplicates
            )
        }
    }
    
    /// Sync user sensitive context (opt-in data)
    func syncUserSensitiveContext(_ context: UserSensitiveContext) async throws {
        guard supabase.isAuthenticated, let userId = supabase.currentUserId else {
            throw SupabaseError.notAuthenticated
        }
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        
        let dbContext = DBUserSensitiveContext(
            userId: userId,
            date: dateFormatter.string(from: context.date),
            cyclePhase: context.cyclePhase?.rawValue,
            cycleDayNumber: context.cycleDayNumber,
            onHormonalBirthControl: context.onHormonalBirthControl,
            nutritionBucket: context.nutritionBucket?.rawValue,
            proteinBucket: context.proteinBucket?.rawValue,
            moodScore: context.moodScore,
            stressLevel: context.stressLevel,
            consentedToMlTraining: context.consentedToMLTraining,
            consentTimestamp: context.consentTimestamp
        )
        
        // Upsert on the natural key (user_id, date). This avoids duplicates and
        // requires the corresponding UNIQUE constraint in Supabase.
        let _: DBUserSensitiveContext? = try await supabase.upsert(
            into: "user_sensitive_context",
            values: dbContext,
            onConflict: "user_id,date"
        )
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
    
    // MARK: - Data Pull (from Supabase to Local)
    
    /// Pull all data from Supabase and merge with local storage
    func pullAllData(
        into appState: AppState,
        workoutStore: WorkoutStore
    ) async {
        guard supabase.isAuthenticated else { return }
        
        isSyncing = true
        syncError = nil
        
        do {
            // Pull user profile
            if let dbProfile = try await supabase.fetchUserProfile() {
                let localProfile = convertToLocalProfile(dbProfile, existing: appState.userProfile)
                await MainActor.run {
                    appState.userProfile = localProfile
                    // Check if onboarding was completed
                    if dbProfile.onboardingCompleted == true {
                        appState.hasCompletedOnboarding = true
                        UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
                    }
                }
            }
            
            // Pull lift states first (needed for templates/sessions)
            let dbLiftStates = try await supabase.fetchLiftStates()
            let localLiftStates = convertToLocalLiftStates(dbLiftStates)
            
            // Pull workout templates with exercises
            let dbTemplates = try await supabase.fetchWorkoutTemplates()
            var localTemplates: [WorkoutTemplate] = []
            
            for dbTemplate in dbTemplates {
                if let templateId = dbTemplate.id {
                    let dbExercises = try await supabase.fetchTemplateExercises(templateId: templateId)
                    let localTemplate = convertToLocalTemplate(dbTemplate, exercises: dbExercises)
                    localTemplates.append(localTemplate)
                }
            }
            
            // Pull workout sessions (last 50)
            let dbSessions = try await supabase.fetchWorkoutSessions(limit: 50)
            var localSessions: [WorkoutSession] = []
            
            for dbSession in dbSessions {
                if let sessionId = dbSession.id {
                    let dbExercises = try await supabase.fetchSessionExercises(sessionId: sessionId)
                    var exercisesWithSets: [(DBSessionExercise, [DBSessionSet])] = []
                    
                    for dbExercise in dbExercises {
                        if let exerciseId = dbExercise.id {
                            let dbSets = try await supabase.fetchSessionSets(sessionExerciseId: exerciseId)
                            exercisesWithSets.append((dbExercise, dbSets))
                        }
                    }
                    
                    let localSession = convertToLocalSession(dbSession, exercises: exercisesWithSets)
                    localSessions.append(localSession)
                }
            }
            
            // Merge with local data (remote wins for conflicts, merge by ID for collections)
            await MainActor.run {
                // Merge lift states
                var mergedLiftStates = workoutStore.exerciseStates
                for (key, value) in localLiftStates {
                    // Remote wins if it exists and is newer
                    if let existing = mergedLiftStates[key] {
                        if value.updatedAt > existing.updatedAt {
                            mergedLiftStates[key] = value
                        }
                    } else {
                        mergedLiftStates[key] = value
                    }
                }
                
                // Merge templates (by ID, remote wins)
                var mergedTemplates = workoutStore.templates
                for remoteTemplate in localTemplates {
                    if let idx = mergedTemplates.firstIndex(where: { $0.id == remoteTemplate.id }) {
                        // Remote wins if newer
                        if remoteTemplate.updatedAt > mergedTemplates[idx].updatedAt {
                            mergedTemplates[idx] = remoteTemplate
                        }
                    } else {
                        mergedTemplates.append(remoteTemplate)
                    }
                }
                
                // Merge sessions (by ID, no duplicates)
                var mergedSessions = workoutStore.sessions
                let existingSessionIds = Set(mergedSessions.map { $0.id })
                for remoteSession in localSessions {
                    if !existingSessionIds.contains(remoteSession.id) {
                        mergedSessions.append(remoteSession)
                    }
                }
                // Sort by date descending
                mergedSessions.sort { $0.startedAt > $1.startedAt }
                
                // Update workout store
                workoutStore.mergeRemoteData(
                    templates: mergedTemplates,
                    sessions: mergedSessions,
                    liftStates: mergedLiftStates
                )
            }
            
            lastSyncAt = Date()
            await trackEvent(name: "data_pull_completed", category: "sync")
            
        } catch {
            syncError = error
            print("Pull error: \(error)")
        }
        
        isSyncing = false
    }
    
    // MARK: - Conversion Helpers (DB -> Local)
    
    private func convertToLocalProfile(_ db: DBUserProfile, existing: UserProfile) -> UserProfile {
        var profile = existing
        
        if let name = db.displayName {
            profile.name = name
        }
        if let age = db.age {
            profile.age = age
        }
        if let sexStr = db.sex, let sex = Sex(rawValue: sexStr) {
            profile.sex = sex
        } else if let sexStr = db.sex {
            // Try lowercase match
            profile.sex = Sex.allCases.first { $0.rawValue.lowercased() == sexStr.lowercased() } ?? profile.sex
        }
        if let expStr = db.workoutExperience, let exp = WorkoutExperience(rawValue: expStr) {
            profile.workoutExperience = exp
        } else if let expStr = db.workoutExperience {
            profile.workoutExperience = WorkoutExperience.allCases.first { $0.rawValue.lowercased() == expStr.lowercased() } ?? profile.workoutExperience
        }
        if let goals = db.fitnessGoals {
            profile.goals = goals.compactMap { goalStr in
                FitnessGoal(rawValue: goalStr) ?? FitnessGoal.allCases.first { $0.rawValue.lowercased() == goalStr.lowercased() }
            }
        }
        if let freq = db.weeklyFrequency {
            profile.weeklyFrequency = freq
        }
        if let gymStr = db.gymType, let gym = GymType(rawValue: gymStr) {
            profile.gymType = gym
        } else if let gymStr = db.gymType {
            profile.gymType = GymType.allCases.first { $0.rawValue.lowercased() == gymStr.lowercased() } ?? profile.gymType
        }
        if let weightKg = db.bodyWeightKg {
            profile.bodyWeightLbs = weightKg / 0.453592  // Convert kg to lbs
        }
        if let phaseStr = db.trainingPhase, let phase = TrainingPhase(rawValue: phaseStr) {
            profile.trainingPhase = phase
        } else if let phaseStr = db.trainingPhase {
            // Case-insensitive fallback
            profile.trainingPhase = TrainingPhase.allCases.first { $0.rawValue.lowercased() == phaseStr.lowercased() } ?? .maintenance
        }
        
        return profile
    }
    
    private func convertToLocalLiftStates(_ dbStates: [DBLiftState]) -> [String: ExerciseState] {
        var result: [String: ExerciseState] = [:]
        
        for db in dbStates {
            let weightLbs = db.lastWorkingWeightKg / 0.453592  // Convert kg to lbs
            let rollingE1rmLbs = db.rollingE1rmKg.map { $0 / 0.453592 }
            let trend = ExerciseState.E1RMTrend(rawValue: db.e1rmTrend ?? "insufficient") ?? .insufficient
            
            // ML CRITICAL: Use e1rmHistoryJson with real dates when available
            let history: [ExerciseState.E1RMSampleLite] = {
                // Prefer JSON history with actual dates
                if let jsonStr = db.e1rmHistoryJson,
                   let jsonData = jsonStr.data(using: .utf8) {
                    let decoder = JSONDecoder()
                    decoder.dateDecodingStrategy = .iso8601
                    if let samples = try? decoder.decode([DBE1RMSample].self, from: jsonData) {
                        return samples.map { sample in
                            ExerciseState.E1RMSampleLite(
                                date: sample.date,
                                value: sample.valueKg / 0.453592
                            )
                        }
                    }
                }
                
                // DEPRECATED FALLBACK: Use old format with fabricated dates for backwards compatibility
                // This should only happen for old data that hasn't been re-synced.
                // NOTE: These dates are NOT real - they are fabricated based on index offset.
                // Any ML model using these dates for temporal features will learn from noise.
                guard let oldHistory = db.e1rmHistory, !oldHistory.isEmpty else { return [] }
                return oldHistory.enumerated().map { idx, valueKg in
                    ExerciseState.E1RMSampleLite(
                        date: db.lastSessionAt ?? Date().addingTimeInterval(TimeInterval(-idx * 86400)),
                        value: valueKg / 0.453592
                    )
                }
            }()
            
            let state = ExerciseState(
                exerciseId: db.exerciseId,
                currentWorkingWeight: weightLbs,
                failuresCount: db.consecutiveFailures ?? 0,
                rollingE1RM: rollingE1rmLbs,
                e1rmTrend: trend,
                e1rmHistory: history,
                lastDeloadAt: db.lastDeloadAt,
                successfulSessionsCount: db.successfulSessionsCount ?? 0,
                updatedAt: db.updatedAt ?? Date()
            )
            
            result[db.exerciseId] = state
        }
        
        return result
    }
    
    private func convertToLocalTemplate(_ db: DBWorkoutTemplate, exercises: [DBTemplateExercise]) -> WorkoutTemplate {
        let localExercises = exercises.map { dbEx -> WorkoutTemplateExercise in
            let exerciseRef = ExerciseRef(
                id: dbEx.exerciseId,
                name: dbEx.exerciseName,
                bodyPart: dbEx.exerciseTarget ?? "other",
                equipment: dbEx.exerciseEquipment ?? "other",
                target: dbEx.exerciseTarget ?? "other"
            )
            
            let incrementLbs = (dbEx.incrementKg ?? 2.27) / 0.453592  // Convert kg to lbs
            
            return WorkoutTemplateExercise(
                id: UUID(uuidString: dbEx.id ?? UUID().uuidString) ?? UUID(),
                exercise: exerciseRef,
                setsTarget: dbEx.setsTarget,
                repRangeMin: dbEx.repRangeMin,
                repRangeMax: dbEx.repRangeMax,
                targetRIR: dbEx.targetRir ?? 2,
                restSeconds: dbEx.restSeconds ?? 120,
                increment: incrementLbs,
                deloadFactor: dbEx.deloadFactor ?? ProgressionDefaults.deloadFactor,
                failureThreshold: dbEx.failureThreshold ?? ProgressionDefaults.failureThreshold
            )
        }
        
        return WorkoutTemplate(
            id: UUID(uuidString: db.id ?? UUID().uuidString) ?? UUID(),
            name: db.name,
            exercises: localExercises,
            createdAt: db.createdAt ?? Date(),
            updatedAt: db.updatedAt ?? Date()
        )
    }
    
    private func convertToLocalSession(_ db: DBWorkoutSession, exercises: [(DBSessionExercise, [DBSessionSet])]) -> WorkoutSession {
        let localExercises = exercises.map { (dbEx, dbSets) -> ExercisePerformance in
            let exerciseRef = ExerciseRef(
                id: dbEx.exerciseId,
                name: dbEx.exerciseName,
                bodyPart: dbEx.exerciseTarget ?? "other",
                equipment: dbEx.exerciseEquipment ?? "other",
                target: dbEx.exerciseTarget ?? "other"
            )
            
            let localSets = dbSets.map { dbSet -> WorkoutSet in
                let weightLbs = dbSet.weightKg / 0.453592  // Convert kg to lbs
                return WorkoutSet(
                    id: UUID(uuidString: dbSet.id ?? UUID().uuidString) ?? UUID(),
                    reps: dbSet.reps,
                    weight: weightLbs,
                    isCompleted: dbSet.isCompleted ?? true,
                    rirObserved: dbSet.rirObserved,
                    rpeObserved: dbSet.rpeObserved,
                    isWarmup: dbSet.isWarmup ?? false,
                    notes: dbSet.notes
                )
            }
            
            let incrementLbs = (dbEx.incrementKg ?? 2.27) / 0.453592
            
            return ExercisePerformance(
                id: UUID(uuidString: dbEx.id ?? UUID().uuidString) ?? UUID(),
                exercise: exerciseRef,
                setsTarget: dbEx.setsTarget,
                repRangeMin: dbEx.repRangeMin,
                repRangeMax: dbEx.repRangeMax,
                increment: incrementLbs,
                deloadFactor: dbEx.deloadFactor ?? ProgressionDefaults.deloadFactor,
                failureThreshold: dbEx.failureThreshold ?? ProgressionDefaults.failureThreshold,
                sets: localSets,
                isCompleted: dbEx.isCompleted ?? true
            )
        }
        
        return WorkoutSession(
            id: UUID(uuidString: db.id ?? UUID().uuidString) ?? UUID(),
            templateId: db.templateId.flatMap { UUID(uuidString: $0) },
            name: db.name,
            startedAt: db.startedAt,
            endedAt: db.endedAt,
            wasDeload: db.wasDeload ?? false,
            deloadReason: db.deloadReason,
            exercises: localExercises,
            computedReadinessScore: db.computedReadinessScore
        )
    }
}
