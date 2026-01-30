import Foundation
import TrainingEngine

// BanditAuditHarness.swift
//
// A macOS-native audit harness for the IronForge bandit selectors.
//
// Why this exists:
// - The TrainingEngine v9/v10 replay tests live in the TrainingEngine Swift package and (currently)
//   do NOT pass a `policySelectionProvider`, so they do not exercise the IronForge bandit selectors.
// - This harness compiles the IronForge selectors on macOS, links against locally-built TrainingEngine
//   objects, and proves (with runtime evidence):
//   1) policy selection is invoked,
//   2) decisions/outcomes are logged,
//   3) learning updates mutate priors (in explore mode only).
//
// Build + run (from repo root):
// swift test -q  (in ios/Atlas/TrainingEngine)  # ensures macOS TrainingEngine objects exist
//
// swiftc -emit-executable -O -DDEBUG \
//   -I "ios/Atlas/TrainingEngine/.build/arm64-apple-macosx/debug/Modules" \
//   "IronForgeTests/BanditAuditHarness.swift" \
//   "IronForge/Services/ProgressionPolicySelector.swift" \
//   "IronForge/Services/BanditStateStore.swift" \
//   "IronForge/Services/ThompsonSamplingBanditPolicySelector.swift" \
//   "IronForge/Services/ShadowModePolicySelector.swift" \
//   "ios/Atlas/TrainingEngine/.build/arm64-apple-macosx/debug/TrainingEngine.build/"*.o \
//   -o "/tmp/ironforge-bandit-audit" && "/tmp/ironforge-bandit-audit"

// MARK: - Minimal shim (to compile bandit selectors on macOS)
//
// The IronForge app target defines this in `IronForge/Models/WorkoutModels.swift`.
// This harness is compiled outside the app target, so we provide a minimal definition
// to satisfy references from `ThompsonSamplingBanditPolicySelector`.

enum PolicyExplorationMode: String, Codable, Hashable, CaseIterable {
    case control = "control"
    case shadow = "shadow"
    case explore = "explore"
    
    init(normalizing raw: String) {
        let v = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch v {
        case "explore":
            self = .explore
        case "shadow":
            self = .shadow
        default:
            self = .control
        }
    }
}

// MARK: - Deterministic RNG (splitmix64)

struct SeededRNG: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { self.state = seed != 0 ? seed : 0x9E3779B97F4A7C15 }
    
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

// MARK: - Thread-safe helpers (for @Sendable closures)

final class ThreadSafePolicyMap: @unchecked Sendable {
    private let lock = NSLock()
    private var bySession: [UUID: String] = [:]
    
    func set(sessionId: UUID, policyId: String) {
        lock.lock()
        bySession[sessionId] = policyId
        lock.unlock()
    }
    
    func get(sessionId: UUID) -> String? {
        lock.lock()
        let v = bySession[sessionId]
        lock.unlock()
        return v
    }
}

final class ThreadSafeStats: @unchecked Sendable {
    struct PhaseStats {
        var sessions: Int = 0
        var decisionsLogged: Int = 0
        var outcomesLogged: Int = 0
        var byExecutedPolicy: [String: Int] = [:]
        var byShadowPolicy: [String: Int] = [:]
        var byExplorationMode: [String: Int] = [:]
    }
    
    private let lock = NSLock()
    private(set) var stats = PhaseStats()
    private(set) var latestFamilyKey: String?
    
    func reset() {
        lock.lock()
        stats = PhaseStats()
        latestFamilyKey = nil
        lock.unlock()
    }
    
    func incrementSessions() {
        lock.lock()
        stats.sessions += 1
        lock.unlock()
    }
    
    func handleLogEntry(_ entry: DecisionLogEntry) {
        lock.lock()
        defer { lock.unlock() }
        
        stats.byExplorationMode[entry.explorationMode, default: 0] += 1
        stats.byExecutedPolicy[entry.executedPolicyId, default: 0] += 1
        if let shadow = entry.shadowPolicyId {
            stats.byShadowPolicy[shadow, default: 0] += 1
        }
        if latestFamilyKey == nil {
            latestFamilyKey = entry.variationContext.familyReferenceKey
        }
        
        if entry.outcome == nil {
            stats.decisionsLogged += 1
        } else {
            stats.outcomesLogged += 1
        }
    }
    
    func snapshot() -> (PhaseStats, String?) {
        lock.lock()
        let s = stats
        let key = latestFamilyKey
        lock.unlock()
        return (s, key)
    }
}

final class ThreadSafeOutcomeSink: @unchecked Sendable {
    private let lock = NSLock()
    private var handler: ((DecisionLogEntry) -> Void)?
    
    func set(_ newHandler: ((DecisionLogEntry) -> Void)?) {
        lock.lock()
        handler = newHandler
        lock.unlock()
    }
    
    func handleIfConfigured(_ entry: DecisionLogEntry) {
        lock.lock()
        let h = handler
        lock.unlock()
        h?(entry)
    }
}

@main
struct BanditAuditHarness {
    
    static func main() {
        let started = Date()
        let runId = String(UUID().uuidString.prefix(8))
        let suiteName = "ironforge.bandit_audit.\(runId)"
        
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            fatalError("Could not create UserDefaults suite")
        }
        defaults.removePersistentDomain(forName: suiteName)
        
        let stateStore = UserDefaultsBanditStateStore(defaults: defaults, keyPrefix: "bandit_audit_prior")
        let userId = "audit-user"
        
        // Minimal plan: single template, single exercise.
        let exercise = Exercise.barbellBenchPress
        let template = WorkoutTemplate(
            name: "Audit Template",
            exercises: [
                TemplateExercise(
                    exercise: exercise,
                    prescription: .hypertrophy,
                    order: 0
                )
            ]
        )
        
        let trainingPlan = TrainingPlan(
            name: "Audit Plan",
            templates: [template.id: template],
            schedule: .rotation(order: [template.id]),
            progressionPolicies: [exercise.id: .doubleProgression(config: .default)],
            loadRoundingPolicy: .standardPounds
        )
        
        let profile = UserProfile(
            id: userId,
            sex: .male,
            experience: .intermediate,
            goals: [.strength],
            weeklyFrequency: 4,
            availableEquipment: .commercialGym,
            preferredUnit: .pounds,
            bodyWeight: .pounds(176)
        )
        
        func makeHistory(successfulSessionsCount: Int) -> WorkoutHistory {
            let liftState = LiftState(
                exerciseId: exercise.id,
                lastWorkingWeight: .pounds(135),
                rollingE1RM: 185,
                failureCount: 0,
                highRpeStreak: 0,
                lastDeloadDate: Calendar.current.date(byAdding: .day, value: -30, to: Date()),
                trend: .stable,
                e1rmHistory: [],
                lastSessionDate: Calendar.current.date(byAdding: .day, value: -3, to: Date()),
                successfulSessionsCount: successfulSessionsCount,
                successStreak: successfulSessionsCount,
                recentReadinessScores: [75, 78, 72]
            )
            
            return WorkoutHistory(
                sessions: [],
                liftStates: [exercise.id: liftState],
                readinessHistory: [ReadinessRecord(date: Date(), score: 75)],
                recentVolumeByDate: [:]
            )
        }
        
        let stats = ThreadSafeStats()
        let outcomeSink = ThreadSafeOutcomeSink()
        Engine.setLoggingEnabled(true)
        Engine.setLogHandler { entry in
            stats.handleLogEntry(entry)
            if entry.outcome != nil {
                outcomeSink.handleIfConfigured(entry)
            }
        }
        
        func printHeader(_ title: String) {
            print("")
            print("============================================================")
            print(title)
            print("============================================================")
        }
        
        func printStats(_ label: String) {
            let (s, familyKey) = stats.snapshot()
            print("")
            print("— \(label)")
            print("  sessions: \(s.sessions)")
            print("  decisions_logged: \(s.decisionsLogged)")
            print("  outcomes_logged:  \(s.outcomesLogged)")
            if let familyKey {
                print("  example_familyKey: \(familyKey)")
            }
            print("  exploration_modes: \(s.byExplorationMode)")
            print("  executed_policies: \(s.byExecutedPolicy)")
            if !s.byShadowPolicy.isEmpty {
                print("  shadow_policies:   \(s.byShadowPolicy)")
            }
        }
        
        // MARK: - Phase A: Explore selector with DEFAULT gate (fresh user => should be blocked)
        
        do {
            stats.reset()
            printHeader("PHASE A: Explore selector with DEFAULT gate (fresh user)")
            
            let exploreBandit = ThompsonSamplingBanditPolicySelector(
                stateStore: stateStore,
                gateConfig: .default,
                isEnabled: true,
                rng: SeededRNG(seed: 0xA11DCAFE)
            )
            
            let history = makeHistory(successfulSessionsCount: 0)
            let readiness = 75
            
            // Wire outcomes into the selector (no-op because explorationMode will be "control" here).
            outcomeSink.set { entry in
                exploreBandit.recordOutcome(entry, userId: entry.userId)
            }
            
            for _ in 0..<100 {
                let sessionId = UUID()
                let planningContext = SessionPlanningContext(
                    sessionId: sessionId,
                    userId: userId,
                    sessionDate: Date()
                )
                
                let policyProvider: PolicySelectionProvider = { signals, variationContext in
                    exploreBandit.selectPolicy(for: signals, variationContext: variationContext, userId: userId)
                }
                
                let plan = Engine.recommendSessionForTemplate(
                    date: Date(),
                    templateId: template.id,
                    userProfile: profile,
                    plan: trainingPlan,
                    history: history,
                    readiness: readiness,
                    planningContext: planningContext,
                    policySelectionProvider: policyProvider
                )
                
                stats.incrementSessions()
                
                // Record a clean success outcome for the executed action.
                if let ex = plan.exercises.first {
                    let setResults = ex.sets.filter { !$0.isWarmup }.map { setPlan in
                        SetResult(
                            id: UUID(),
                            reps: setPlan.targetReps,
                            load: setPlan.targetLoad,
                            rirObserved: setPlan.targetRIR,
                            completed: true,
                            isWarmup: false
                        )
                    }
                    
                    let result = ExerciseSessionResult(
                        id: UUID(),
                        exerciseId: ex.exercise.id,
                        prescription: ex.prescription,
                        sets: setResults,
                        order: 0,
                        notes: nil
                    )
                    
                    Engine.recordOutcome(
                        sessionId: sessionId,
                        exerciseResult: result,
                        readinessScore: readiness,
                        executionContext: .normal
                    )
                }
            }
            
            printStats("Expected: exploration blocked ⇒ mode=control, executed=baseline")
        }
        
        // MARK: - Phase B: Shadow selector (baseline executed, counterfactual logged)
        
        do {
            stats.reset()
            printHeader("PHASE B: Shadow selector (baseline executed, counterfactual logged)")
            
            let shadowSelector = ShadowModePolicySelector(stateStore: stateStore)
            let history = makeHistory(successfulSessionsCount: 0)
            let readiness = 75
            
            // Shadow selector intentionally does not learn.
            outcomeSink.set { entry in
                shadowSelector.recordOutcome(entry, userId: entry.userId)
            }
            
            for _ in 0..<100 {
                let sessionId = UUID()
                let planningContext = SessionPlanningContext(
                    sessionId: sessionId,
                    userId: userId,
                    sessionDate: Date()
                )
                
                let policyProvider: PolicySelectionProvider = { signals, variationContext in
                    shadowSelector.selectPolicy(for: signals, variationContext: variationContext, userId: userId)
                }
                
                let plan = Engine.recommendSessionForTemplate(
                    date: Date(),
                    templateId: template.id,
                    userProfile: profile,
                    plan: trainingPlan,
                    history: history,
                    readiness: readiness,
                    planningContext: planningContext,
                    policySelectionProvider: policyProvider
                )
                
                stats.incrementSessions()
                
                // Record a clean success outcome (shadow mode should not learn).
                if let ex = plan.exercises.first {
                    let setResults = ex.sets.filter { !$0.isWarmup }.map { setPlan in
                        SetResult(
                            id: UUID(),
                            reps: setPlan.targetReps,
                            load: setPlan.targetLoad,
                            rirObserved: setPlan.targetRIR,
                            completed: true,
                            isWarmup: false
                        )
                    }
                    
                    let result = ExerciseSessionResult(
                        id: UUID(),
                        exerciseId: ex.exercise.id,
                        prescription: ex.prescription,
                        sets: setResults,
                        order: 0,
                        notes: nil
                    )
                    
                    Engine.recordOutcome(
                        sessionId: sessionId,
                        exerciseResult: result,
                        readinessScore: readiness,
                        executionContext: .normal
                    )
                }
            }
            
            printStats("Expected: mode=shadow, executed=baseline, shadowPolicyId!=baseline")
        }
        
        // MARK: - Phase C: Explore selector with BYPASS gate + synthetic outcomes (learning)
        
        do {
            stats.reset()
            printHeader("PHASE C: Explore selector with BYPASS gate + synthetic outcomes (learning)")
            
            let bypassGate = BanditGateConfig(
                minBaselineExposures: 0,
                minDaysSinceDeload: 0,
                maxFailStreak: Int.max,
                minReadiness: 0,
                allowDuringDeload: true
            )
            
            let exploreBandit = ThompsonSamplingBanditPolicySelector(
                stateStore: stateStore,
                gateConfig: bypassGate,
                isEnabled: true,
                rng: SeededRNG(seed: 0xBADC0FFE)
            )
            
            let policyMap = ThreadSafePolicyMap()
            let history = makeHistory(successfulSessionsCount: 20)
            let readiness = 75
            
            // Wire outcomes into the selector (this should update priors because explorationMode="explore").
            outcomeSink.set { entry in
                exploreBandit.recordOutcome(entry, userId: entry.userId)
            }
            
            for _ in 0..<500 {
                let sessionId = UUID()
                let planningContext = SessionPlanningContext(
                    sessionId: sessionId,
                    userId: userId,
                    sessionDate: Date()
                )
                
                let policyProvider: PolicySelectionProvider = { signals, variationContext in
                    let selection = exploreBandit.selectPolicy(for: signals, variationContext: variationContext, userId: userId)
                    policyMap.set(sessionId: sessionId, policyId: selection.executedPolicyId)
                    return selection
                }
                
                let plan = Engine.recommendSessionForTemplate(
                    date: Date(),
                    templateId: template.id,
                    userProfile: profile,
                    plan: trainingPlan,
                    history: history,
                    readiness: readiness,
                    planningContext: planningContext,
                    policySelectionProvider: policyProvider
                )
                
                stats.incrementSessions()
                
                // Outcome synthesis:
                // - If executed policy is "aggressive": force a failure (reward=0)
                // - Otherwise: clean success (reward=1)
                let executedPolicyId = policyMap.get(sessionId: sessionId) ?? "baseline"
                let shouldFail = (executedPolicyId == "aggressive")
                
                if let ex = plan.exercises.first {
                    let targetLower = ex.prescription.targetRepsRange.lowerBound
                    
                    let setResults: [SetResult] = ex.sets.filter { !$0.isWarmup }.map { setPlan in
                        let reps = shouldFail ? max(0, targetLower - 1) : setPlan.targetReps
                        return SetResult(
                            id: UUID(),
                            reps: reps,
                            load: setPlan.targetLoad,
                            rirObserved: shouldFail ? 0 : setPlan.targetRIR,
                            completed: true,
                            isWarmup: false
                        )
                    }
                    
                    let result = ExerciseSessionResult(
                        id: UUID(),
                        exerciseId: ex.exercise.id,
                        prescription: ex.prescription,
                        sets: setResults,
                        order: 0,
                        notes: nil
                    )
                    
                    Engine.recordOutcome(
                        sessionId: sessionId,
                        exerciseResult: result,
                        readinessScore: readiness,
                        executionContext: .normal
                    )
                }
            }
            
            printStats("Expected: mode=explore and executedPolicyId shifts away from aggressive")
            
            let (_, familyKey) = stats.snapshot()
            if let familyKey {
                print("\nLearned priors for familyKey=\(familyKey):")
                for arm in exploreBandit.arms {
                    let prior = stateStore.getPrior(userId: userId, familyKey: familyKey, armId: arm.id)
                    let mean = prior.mean
                    print("  arm=\(arm.id)  alpha=\(String(format: "%.1f", prior.alpha))  beta=\(String(format: "%.1f", prior.beta))  mean=\(String(format: "%.3f", mean))")
                }
                print("\nInterpretation: mean≈P(clean_success) per arm under this synthetic reward model.")
            } else {
                print("\nWARN: No familyKey captured; cannot print priors by family.")
            }
        }
        
        Engine.setLoggingEnabled(false)
        
        let elapsed = Date().timeIntervalSince(started)
        print("\nDone. Elapsed: \(String(format: "%.2f", elapsed))s")
        print("UserDefaults suite used: \(suiteName)")
        print("(Suite is isolated and safe to delete.)")
    }
}

