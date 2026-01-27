import Foundation

// MARK: - Pilot Guardrails
/// Enforces conservative safety constraints for the friend pilot.
///
/// Design principles:
/// - Default to conservative (never harm the user)
/// - Cap increases, never increase after grinders/misses
/// - Respect pain flags absolutely
/// - Manual override is always available (but logged)
/// - All interventions are transparent to the user
enum PilotGuardrails {
    
    // MARK: - Configuration
    
    struct Config {
        /// Maximum weekly load increase per lift (as percentage of current weight)
        let maxWeeklyIncreasePercent: Double
        
        /// Maximum single-session load increase (lbs)
        let maxSingleSessionIncreaseLbs: Double
        
        /// Minimum readiness score to allow load increases
        let minReadinessForIncrease: Int
        
        /// Block increases for N days after a grinder (RPE >= 9.5)
        let grinderCooldownDays: Int
        
        /// Block increases for N sessions after a miss
        let missBufferSessions: Int
        
        /// Minimum days between deload triggers
        let minDaysBetweenDeloads: Int
        
        /// Maximum deload reduction (percentage)
        let maxDeloadReductionPercent: Double
        
        /// Whether pain flags immediately block the exercise
        let painFlagBlocksExercise: Bool
        
        static let conservative = Config(
            maxWeeklyIncreasePercent: 5.0,
            maxSingleSessionIncreaseLbs: 10.0,
            minReadinessForIncrease: 50,
            grinderCooldownDays: 3,
            missBufferSessions: 1,
            minDaysBetweenDeloads: 7,
            maxDeloadReductionPercent: 15.0,
            painFlagBlocksExercise: true
        )
        
        static let moderate = Config(
            maxWeeklyIncreasePercent: 7.5,
            maxSingleSessionIncreaseLbs: 15.0,
            minReadinessForIncrease: 40,
            grinderCooldownDays: 2,
            missBufferSessions: 1,
            minDaysBetweenDeloads: 5,
            maxDeloadReductionPercent: 20.0,
            painFlagBlocksExercise: true
        )
    }
    
    // MARK: - Guardrail Check Result
    
    struct CheckResult {
        let allowed: Bool
        let intervention: Intervention?
        let warnings: [Warning]
        
        static let pass = CheckResult(allowed: true, intervention: nil, warnings: [])
        
        static func block(_ intervention: Intervention, warnings: [Warning] = []) -> CheckResult {
            CheckResult(allowed: false, intervention: intervention, warnings: warnings)
        }
        
        static func warn(_ warnings: [Warning]) -> CheckResult {
            CheckResult(allowed: true, intervention: nil, warnings: warnings)
        }
    }
    
    struct Intervention {
        let type: InterventionType
        let reason: String
        let originalValue: Double?
        let modifiedValue: Double?
        let userMessage: String
        
        var telemetryType: String {
            switch type {
            case .maxWeeklyCap: return "max_weekly_cap"
            case .maxSessionCap: return "max_session_cap"
            case .grinderBlock: return "grinder_block"
            case .missBlock: return "miss_block"
            case .lowReadinessBlock: return "low_readiness_block"
            case .painFlagBlock: return "pain_flag_block"
            case .recentDeloadBlock: return "recent_deload_block"
            case .deloadCapAdjustment: return "deload_cap_adjustment"
            }
        }
    }
    
    enum InterventionType {
        case maxWeeklyCap
        case maxSessionCap
        case grinderBlock
        case missBlock
        case lowReadinessBlock
        case painFlagBlock
        case recentDeloadBlock
        case deloadCapAdjustment
    }
    
    struct Warning {
        let type: WarningType
        let message: String
    }
    
    enum WarningType {
        case approachingWeeklyCap
        case lowReadiness
        case recentGrinder
        case highFatigue
    }
    
    // MARK: - Context for Checks
    
    struct ExerciseContext {
        let exerciseId: String
        let exerciseName: String
        let currentWeightLbs: Double
        let proposedWeightLbs: Double
        let readinessScore: Int
        let lastSessionDate: Date?
        let lastGrinderDate: Date?
        let lastMissDate: Date?
        let lastDeloadDate: Date?
        let recentWeeklyIncreaseLbs: Double
        let hasPainFlag: Bool
        let painLocation: String?
        let consecutiveFailures: Int
    }
    
    // MARK: - Main Check Functions
    
    /// Check if a proposed weight increase is allowed
    static func checkIncrease(
        context: ExerciseContext,
        config: Config = .conservative
    ) -> CheckResult {
        var warnings: [Warning] = []
        
        // 1. Pain flag - absolute block
        if config.painFlagBlocksExercise && context.hasPainFlag {
            return .block(Intervention(
                type: .painFlagBlock,
                reason: "Pain reported at \(context.painLocation ?? "unknown location")",
                originalValue: context.proposedWeightLbs,
                modifiedValue: context.currentWeightLbs,
                userMessage: "Load increase blocked due to reported discomfort. Focus on form and recovery."
            ))
        }
        
        // 2. Low readiness - block increases
        if context.readinessScore < config.minReadinessForIncrease {
            return .block(Intervention(
                type: .lowReadinessBlock,
                reason: "Readiness score \(context.readinessScore) below threshold \(config.minReadinessForIncrease)",
                originalValue: context.proposedWeightLbs,
                modifiedValue: context.currentWeightLbs,
                userMessage: "Holding load steady today. Readiness is lower than usual—let's build from here."
            ))
        }
        
        // 3. Recent grinder - block increases
        if let grinderDate = context.lastGrinderDate {
            let daysSinceGrinder = Calendar.current.dateComponents([.day], from: grinderDate, to: Date()).day ?? 0
            if daysSinceGrinder < config.grinderCooldownDays {
                return .block(Intervention(
                    type: .grinderBlock,
                    reason: "Grinder \(daysSinceGrinder) days ago, cooldown is \(config.grinderCooldownDays) days",
                    originalValue: context.proposedWeightLbs,
                    modifiedValue: context.currentWeightLbs,
                    userMessage: "Last session was tough. Consolidating at current weight before pushing further."
                ))
            }
        }
        
        // 4. Recent miss - block increases
        if context.consecutiveFailures > 0 {
            return .block(Intervention(
                type: .missBlock,
                reason: "Has \(context.consecutiveFailures) consecutive failure(s)",
                originalValue: context.proposedWeightLbs,
                modifiedValue: context.currentWeightLbs,
                userMessage: "Recent miss detected. Let's nail the current weight before adding more."
            ))
        }
        
        // 5. Max single-session increase cap
        let sessionIncrease = context.proposedWeightLbs - context.currentWeightLbs
        if sessionIncrease > config.maxSingleSessionIncreaseLbs {
            let cappedWeight = context.currentWeightLbs + config.maxSingleSessionIncreaseLbs
            return .block(Intervention(
                type: .maxSessionCap,
                reason: "Session increase \(sessionIncrease) lbs exceeds cap \(config.maxSingleSessionIncreaseLbs) lbs",
                originalValue: context.proposedWeightLbs,
                modifiedValue: cappedWeight,
                userMessage: "Capping increase to \(Int(config.maxSingleSessionIncreaseLbs)) lbs for this session."
            ))
        }
        
        // 6. Max weekly increase cap
        let totalWeeklyIncrease = context.recentWeeklyIncreaseLbs + sessionIncrease
        let weeklyCapLbs = context.currentWeightLbs * (config.maxWeeklyIncreasePercent / 100.0)
        
        if totalWeeklyIncrease > weeklyCapLbs {
            let remainingAllowedIncrease = max(0, weeklyCapLbs - context.recentWeeklyIncreaseLbs)
            if remainingAllowedIncrease < sessionIncrease {
                let cappedWeight = context.currentWeightLbs + remainingAllowedIncrease
                return .block(Intervention(
                    type: .maxWeeklyCap,
                    reason: "Weekly increase \(totalWeeklyIncrease) lbs exceeds cap \(weeklyCapLbs) lbs",
                    originalValue: context.proposedWeightLbs,
                    modifiedValue: cappedWeight,
                    userMessage: "Weekly increase limit reached. Holding here to build a solid base."
                ))
            }
        }
        
        // 7. Warnings (non-blocking)
        if context.readinessScore < config.minReadinessForIncrease + 10 {
            warnings.append(Warning(
                type: .lowReadiness,
                message: "Readiness is on the lower end. Listen to your body."
            ))
        }
        
        let weeklyUsage = totalWeeklyIncrease / weeklyCapLbs
        if weeklyUsage > 0.7 {
            warnings.append(Warning(
                type: .approachingWeeklyCap,
                message: "Approaching weekly increase limit (\(Int(weeklyUsage * 100))% used)."
            ))
        }
        
        if !warnings.isEmpty {
            return .warn(warnings)
        }
        
        return .pass
    }
    
    /// Check if a proposed deload is appropriate
    static func checkDeload(
        context: ExerciseContext,
        proposedReductionPercent: Double,
        config: Config = .conservative
    ) -> CheckResult {
        
        // 1. Check if deload is too soon after last deload
        if let lastDeload = context.lastDeloadDate {
            let daysSinceDeload = Calendar.current.dateComponents([.day], from: lastDeload, to: Date()).day ?? 0
            if daysSinceDeload < config.minDaysBetweenDeloads {
                return .block(Intervention(
                    type: .recentDeloadBlock,
                    reason: "Last deload was \(daysSinceDeload) days ago, minimum is \(config.minDaysBetweenDeloads)",
                    originalValue: proposedReductionPercent,
                    modifiedValue: nil,
                    userMessage: "Recent deload detected. Continuing at current load to assess recovery."
                ))
            }
        }
        
        // 2. Cap deload reduction
        if proposedReductionPercent > config.maxDeloadReductionPercent {
            return .block(Intervention(
                type: .deloadCapAdjustment,
                reason: "Deload \(proposedReductionPercent)% exceeds cap \(config.maxDeloadReductionPercent)%",
                originalValue: proposedReductionPercent,
                modifiedValue: config.maxDeloadReductionPercent,
                userMessage: "Deload capped at \(Int(config.maxDeloadReductionPercent))% to maintain training stimulus."
            ))
        }
        
        return .pass
    }
    
    // MARK: - Convenience Methods
    
    /// Apply guardrails to an engine recommendation and return modified prescription
    static func applyGuardrails(
        exerciseId: String,
        exerciseName: String,
        engineRecommendation: EngineRecommendation,
        currentState: ExerciseState?,
        readinessScore: Int,
        recentHistory: RecentHistory,
        config: Config = .conservative
    ) -> GuardrailedRecommendation {
        
        let context = ExerciseContext(
            exerciseId: exerciseId,
            exerciseName: exerciseName,
            currentWeightLbs: currentState?.currentWorkingWeight ?? 0,
            proposedWeightLbs: engineRecommendation.weightLbs,
            readinessScore: readinessScore,
            lastSessionDate: currentState?.updatedAt,
            lastGrinderDate: recentHistory.lastGrinderDate,
            lastMissDate: recentHistory.lastMissDate,
            lastDeloadDate: currentState?.lastDeloadAt,
            recentWeeklyIncreaseLbs: recentHistory.weeklyIncreaseLbs,
            hasPainFlag: recentHistory.hasPainFlag,
            painLocation: recentHistory.painLocation,
            consecutiveFailures: currentState?.failuresCount ?? 0
        )
        
        // Check based on recommendation type
        let result: CheckResult
        
        switch engineRecommendation.type {
        case .increaseWeight, .increaseReps:
            result = checkIncrease(context: context, config: config)
        case .deload:
            let reduction = engineRecommendation.deloadReductionPercent ?? 10.0
            result = checkDeload(context: context, proposedReductionPercent: reduction, config: config)
        case .hold, .breakReset:
            result = .pass
        }
        
        // Build guardrailed recommendation
        var finalWeight = engineRecommendation.weightLbs
        var finalType = engineRecommendation.type
        
        if let intervention = result.intervention {
            if let modifiedValue = intervention.modifiedValue {
                finalWeight = modifiedValue
            }
            // Convert increase to hold if blocked
            if !result.allowed && (engineRecommendation.type == .increaseWeight || engineRecommendation.type == .increaseReps) {
                finalType = .hold
            }
        }
        
        return GuardrailedRecommendation(
            originalRecommendation: engineRecommendation,
            finalWeightLbs: finalWeight,
            finalType: finalType,
            wasModified: result.intervention != nil,
            intervention: result.intervention,
            warnings: result.warnings
        )
    }
}

// MARK: - Supporting Types

extension PilotGuardrails {
    
    struct EngineRecommendation {
        let type: RecommendationType
        let weightLbs: Double
        let reps: Int
        let deloadReductionPercent: Double?
    }
    
    enum RecommendationType {
        case increaseWeight
        case increaseReps
        case hold
        case deload
        case breakReset
    }
    
    struct RecentHistory {
        let lastGrinderDate: Date?
        let lastMissDate: Date?
        let weeklyIncreaseLbs: Double
        let hasPainFlag: Bool
        let painLocation: String?
        
        static let empty = RecentHistory(
            lastGrinderDate: nil,
            lastMissDate: nil,
            weeklyIncreaseLbs: 0,
            hasPainFlag: false,
            painLocation: nil
        )
    }
    
    struct GuardrailedRecommendation {
        let originalRecommendation: EngineRecommendation
        let finalWeightLbs: Double
        let finalType: RecommendationType
        let wasModified: Bool
        let intervention: Intervention?
        let warnings: [Warning]
        
        var userFacingMessage: String? {
            intervention?.userMessage
        }
        
        var hasWarnings: Bool {
            !warnings.isEmpty
        }
    }
}

// MARK: - User Messaging

extension PilotGuardrails {
    
    /// Generate the disclaimer message for pilot users
    static func pilotDisclaimer() -> String {
        """
        This is an experimental training recommendation system.
        
        • Recommendations are suggestions, not medical advice
        • Always listen to your body
        • You can override any recommendation
        • Report any concerns immediately
        
        Your safety is the priority. When in doubt, hold or reduce.
        """
    }
    
    /// Generate a friendly explanation of why a guardrail triggered
    static func explanationFor(intervention: Intervention) -> String {
        switch intervention.type {
        case .maxWeeklyCap:
            return "We're capping your weekly progress to ensure sustainable gains. Small, consistent increases beat aggressive jumps."
            
        case .maxSessionCap:
            return "That's a bigger jump than recommended for one session. We've adjusted to a safer increment."
            
        case .grinderBlock:
            return "Your last session was really hard. Let's make sure you're fully recovered before adding weight."
            
        case .missBlock:
            return "You struggled with this weight recently. Nailing the current load builds confidence and strength."
            
        case .lowReadinessBlock:
            return "Your recovery metrics suggest today isn't the day to push harder. We'll get after it next time."
            
        case .painFlagBlock:
            return "You reported discomfort. Let's not make it worse. Focus on form and consider lighter work."
            
        case .recentDeloadBlock:
            return "You just had a deload. Give your body time to respond before reducing again."
            
        case .deloadCapAdjustment:
            return "We've limited how much we reduce to keep some training stimulus. You'll bounce back faster."
        }
    }
}
