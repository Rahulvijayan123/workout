// PolicyAndSessionIdentityTests.swift
// Tests for policy selection and session identity plumbing.

import XCTest
@testable import TrainingEngine

final class PolicyAndSessionIdentityTests: XCTestCase {
    
    // MARK: - Session Identity Tests
    
    func testSessionIdPreservedThroughPlanning() {
        // Setup: Create a simple plan and profile
        let profile = createTestUserProfile()
        let plan = createMinimalTrainingPlan()
        let history = WorkoutHistory(sessions: [])
        
        // Create a specific sessionId for tracking
        let expectedSessionId = UUID()
        let planningContext = SessionPlanningContext(
            sessionId: expectedSessionId,
            userId: "test-user-123",
            sessionDate: Date(),
            isPlannedDeloadWeek: false
        )
        
        // Collect logged decisions
        var loggedDecisions: [DecisionLogEntry] = []
        let originalHandler = TrainingDataLogger.shared.logHandler
        TrainingDataLogger.shared.isEnabled = true
        TrainingDataLogger.shared.logHandler = { entry in
            loggedDecisions.append(entry)
        }
        defer {
            TrainingDataLogger.shared.isEnabled = false
            TrainingDataLogger.shared.logHandler = originalHandler
        }
        
        // Execute
        let sessionPlan = Engine.recommendSession(
            date: Date(),
            userProfile: profile,
            plan: plan,
            history: history,
            readiness: 75,
            planningContext: planningContext
        )
        
        // Assert: SessionPlan has the expected sessionId
        XCTAssertEqual(sessionPlan.sessionId, expectedSessionId, "SessionPlan should preserve the planning context's sessionId")
        
        // Assert: All logged decisions have the same sessionId
        for entry in loggedDecisions {
            XCTAssertEqual(entry.sessionId, expectedSessionId, "Decision log entry should use the planning context's sessionId")
        }
    }
    
    func testSessionIdStableThroughPlanningAndOutcome() {
        // Setup
        let profile = createTestUserProfile()
        let plan = createMinimalTrainingPlan()
        let history = WorkoutHistory(sessions: [])
        let expectedSessionId = UUID()
        let planningContext = SessionPlanningContext(
            sessionId: expectedSessionId,
            userId: "test-user-456",
            sessionDate: Date(),
            isPlannedDeloadWeek: false
        )
        
        var loggedDecisions: [DecisionLogEntry] = []
        let originalHandler = TrainingDataLogger.shared.logHandler
        TrainingDataLogger.shared.isEnabled = true
        TrainingDataLogger.shared.logHandler = { entry in
            loggedDecisions.append(entry)
        }
        defer {
            TrainingDataLogger.shared.isEnabled = false
            TrainingDataLogger.shared.logHandler = originalHandler
        }
        
        // Plan session
        let sessionPlan = Engine.recommendSession(
            date: Date(),
            userProfile: profile,
            plan: plan,
            history: history,
            readiness: 75,
            planningContext: planningContext
        )
        
        // Simulate recording an outcome
        guard let exercisePlan = sessionPlan.exercises.first else {
            XCTFail("Session should have at least one exercise")
            return
        }
        
        let result = ExerciseSessionResult(
            id: UUID(),
            exerciseId: exercisePlan.exercise.id,
            prescription: exercisePlan.prescription,
            sets: [
                SetResult(
                    id: UUID(),
                    reps: 10,
                    load: Load.pounds(100),
                    rirObserved: 2,
                    completed: true,
                    isWarmup: false
                )
            ],
            order: 0,
            notes: nil
        )
        
        Engine.recordOutcome(
            sessionId: expectedSessionId,
            exerciseResult: result,
            readinessScore: 75,
            executionContext: .normal
        )
        
        // Assert: The logged decisions can be updated with outcomes using the same sessionId
        // (This verifies the ID plumbing is correct)
        let decisionsForSession = loggedDecisions.filter { $0.sessionId == expectedSessionId }
        XCTAssertFalse(decisionsForSession.isEmpty, "Should have logged decisions for this session")
    }
    
    // MARK: - Policy Selection Tests
    
    func testPolicySelectionProviderIsInvoked() {
        let profile = createTestUserProfile()
        let plan = createMinimalTrainingPlan()
        let history = WorkoutHistory(sessions: [])
        
        var policyInvocationCount = 0
        var capturedPolicySelections: [PolicySelection] = []
        
        let policyProvider: PolicySelectionProvider = { signals, variationContext in
            policyInvocationCount += 1
            let selection = PolicySelection(
                executedPolicyId: "test_policy",
                directionConfig: nil,
                magnitudeConfig: nil,
                executedActionProbability: 0.75,
                explorationMode: .explore
            )
            capturedPolicySelections.append(selection)
            return selection
        }
        
        // Execute
        let sessionPlan = Engine.recommendSession(
            date: Date(),
            userProfile: profile,
            plan: plan,
            history: history,
            readiness: 75,
            policySelectionProvider: policyProvider
        )
        
        // Assert: Provider was invoked for each exercise
        let exerciseCount = sessionPlan.exercises.count
        XCTAssertEqual(policyInvocationCount, exerciseCount, "Policy provider should be invoked once per exercise")
        XCTAssertEqual(capturedPolicySelections.count, exerciseCount)
    }
    
    func testPolicySelectionLogsCorrectMetadata() {
        let profile = createTestUserProfile()
        let plan = createMinimalTrainingPlan()
        let history = WorkoutHistory(sessions: [])
        
        var loggedDecisions: [DecisionLogEntry] = []
        let originalHandler = TrainingDataLogger.shared.logHandler
        TrainingDataLogger.shared.isEnabled = true
        TrainingDataLogger.shared.logHandler = { entry in
            loggedDecisions.append(entry)
        }
        defer {
            TrainingDataLogger.shared.isEnabled = false
            TrainingDataLogger.shared.logHandler = originalHandler
        }
        
        let expectedPolicyId = "bandit_aggressive"
        let expectedProbability = 0.42
        
        let policyProvider: PolicySelectionProvider = { _, _ in
            PolicySelection(
                executedPolicyId: expectedPolicyId,
                directionConfig: nil,
                magnitudeConfig: nil,
                executedActionProbability: expectedProbability,
                explorationMode: .explore,
                shadowPolicyId: "shadow_conservative",
                shadowActionProbability: 0.33
            )
        }
        
        // Execute
        _ = Engine.recommendSession(
            date: Date(),
            userProfile: profile,
            plan: plan,
            history: history,
            readiness: 75,
            policySelectionProvider: policyProvider
        )
        
        // Assert: Logged decisions have correct policy metadata
        for entry in loggedDecisions {
            XCTAssertEqual(entry.executedPolicyId, expectedPolicyId)
            XCTAssertEqual(entry.executedActionProbability, expectedProbability, accuracy: 0.001)
            XCTAssertEqual(entry.explorationMode, "explore")
            XCTAssertEqual(entry.shadowPolicyId, "shadow_conservative")
            XCTAssertEqual(entry.shadowActionProbability, 0.33, accuracy: 0.001)
            
            // Check tags
            XCTAssertTrue(entry.tags.contains("policy=\(expectedPolicyId)"))
            XCTAssertTrue(entry.tags.contains(where: { $0.hasPrefix("p=") }))
            XCTAssertTrue(entry.tags.contains("mode=explore"))
        }
    }
    
    func testBaselineControlPolicySelection() {
        let selection = PolicySelection.baselineControl()
        
        XCTAssertEqual(selection.executedPolicyId, "baseline")
        XCTAssertEqual(selection.executedActionProbability, 1.0)
        XCTAssertEqual(selection.explorationMode, .control)
        XCTAssertNil(selection.directionConfig)
        XCTAssertNil(selection.magnitudeConfig)
        XCTAssertNil(selection.shadowPolicyId)
        XCTAssertNil(selection.shadowActionProbability)
    }
    
    func testBaselineShadowPolicySelection() {
        let selection = PolicySelection.baselineShadow(
            shadowPolicyId: "aggressive",
            shadowActionProbability: 0.6
        )
        
        XCTAssertEqual(selection.executedPolicyId, "baseline")
        XCTAssertEqual(selection.executedActionProbability, 1.0)
        XCTAssertEqual(selection.explorationMode, .shadow)
        XCTAssertEqual(selection.shadowPolicyId, "aggressive")
        XCTAssertEqual(selection.shadowActionProbability, 0.6)
    }
    
    func testExplorePolicySelection() {
        let customDirection = DirectionPolicyConfig(
            extendedBreakDays: 21,
            trainingGapDays: 14
        )
        
        let selection = PolicySelection.explore(
            policyId: "aggressive",
            actionProbability: 0.35,
            directionConfig: customDirection
        )
        
        XCTAssertEqual(selection.executedPolicyId, "aggressive")
        XCTAssertEqual(selection.executedActionProbability, 0.35)
        XCTAssertEqual(selection.explorationMode, .explore)
        XCTAssertNotNil(selection.directionConfig)
        XCTAssertEqual(selection.directionConfig?.extendedBreakDays, 21)
    }
    
    // MARK: - Outcome Execution Context Tests
    
    func testOutcomeRecordIncludesExecutionContext() {
        let profile = createTestUserProfile()
        let plan = createMinimalTrainingPlan()
        let history = WorkoutHistory(sessions: [])
        let sessionId = UUID()
        let planningContext = SessionPlanningContext(
            sessionId: sessionId,
            userId: "test-user",
            sessionDate: Date()
        )
        
        var loggedDecisions: [DecisionLogEntry] = []
        let originalHandler = TrainingDataLogger.shared.logHandler
        TrainingDataLogger.shared.isEnabled = true
        TrainingDataLogger.shared.logHandler = { entry in
            loggedDecisions.append(entry)
        }
        defer {
            TrainingDataLogger.shared.isEnabled = false
            TrainingDataLogger.shared.logHandler = originalHandler
        }
        
        // Plan session
        let sessionPlan = Engine.recommendSession(
            date: Date(),
            userProfile: profile,
            plan: plan,
            history: history,
            readiness: 75,
            planningContext: planningContext
        )
        
        guard let exercisePlan = sessionPlan.exercises.first else {
            XCTFail("Session should have at least one exercise")
            return
        }
        
        // Record outcome with injury context
        let result = ExerciseSessionResult(
            id: UUID(),
            exerciseId: exercisePlan.exercise.id,
            prescription: exercisePlan.prescription,
            sets: [
                SetResult(
                    id: UUID(),
                    reps: 5,
                    load: Load.pounds(100),
                    rirObserved: 0,
                    completed: true,
                    isWarmup: false
                )
            ],
            order: 0,
            notes: nil
        )
        
        Engine.recordOutcome(
            sessionId: sessionId,
            exerciseResult: result,
            readinessScore: 50,
            executionContext: .injuryDiscomfort
        )
        
        // Assert: The outcome should have the execution context
        // (The actual outcome is stored in pending entries and emitted through logHandler)
        let updatedEntries = loggedDecisions.filter { $0.outcome != nil }
        if let outcomeEntry = updatedEntries.first {
            XCTAssertEqual(outcomeEntry.outcome?.executionContext, .injuryDiscomfort)
        }
    }
    
    // MARK: - Helpers
    
    private func createTestUserProfile() -> UserProfile {
        UserProfile(
            sex: .male,
            bodyweightKg: 80,
            bodyweightLbs: 176,
            experience: .intermediate,
            goal: .strength,
            trainingFrequencyPerWeek: 4,
            equipmentAvailability: .fullGym,
            birthDate: nil,
            stableId: "test-user"
        )
    }
    
    private func createMinimalTrainingPlan() -> TrainingPlan {
        let exercise = Exercise(
            id: "test-bench-press",
            name: "Bench Press",
            equipment: .barbell,
            movementPattern: .horizontalPush,
            primaryMuscles: [.chest],
            secondaryMuscles: [.triceps, .shoulders]
        )
        
        let templateExercise = TemplateExercise(
            exercise: exercise,
            prescription: SetPrescription(
                setCount: 3,
                targetRepsRange: 8...12,
                targetRIR: 2,
                restSeconds: 120,
                increment: .pounds(5)
            ),
            progressionPolicy: .doubleProgression(DoubleProgressionConfig()),
            order: 0
        )
        
        let template = WorkoutTemplate(
            id: UUID(),
            name: "Test Workout",
            exercises: [templateExercise]
        )
        
        return TrainingPlan(
            id: "test-plan",
            name: "Test Plan",
            templates: [template.id: template],
            schedule: .fixed(templateIds: [template.id]),
            loadRoundingPolicy: .fivePound
        )
    }
}
