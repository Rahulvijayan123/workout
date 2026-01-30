import XCTest
import TrainingEngine
@testable import IronForge

final class PolicySelectionSnapshotIntegrationTests: XCTestCase {
    
    private final class FixedPolicySelector: ProgressionPolicySelector, @unchecked Sendable {
        private let selection: PolicySelection
        
        init(selection: PolicySelection) {
            self.selection = selection
        }
        
        func selectPolicy(
            for signals: LiftSignalsSnapshot,
            variationContext: VariationContext,
            userId: String
        ) -> PolicySelection {
            selection
        }
        
        func recordOutcome(_ entry: DecisionLogEntry, userId: String) {
            // no-op
        }
    }
    
    override func setUp() {
        super.setUp()
        PolicySelectionSnapshotStore.shared.clear()
    }
    
    override func tearDown() {
        PolicySelectionSnapshotStore.shared.clear()
        super.tearDown()
    }
    
    func testPolicySelectionSnapshotAttachedForControlMode() {
        let bench = ExerciseSeeds.defaultExercises[1]
        let template = WorkoutTemplate(
            name: "Test Template",
            exercises: [
                WorkoutTemplateExercise(exercise: ExerciseRef(from: bench))
            ]
        )
        
        let selector = FixedPolicySelector(selection: .baselineControl())
        
        let plan = TrainingEngineBridge.recommendSessionForTemplate(
            date: Date(),
            templateId: template.id,
            userProfile: UserProfile(),
            templates: [template],
            sessions: [],
            liftStates: [:],
            readiness: 75,
            dailyBiometrics: [],
            policySelector: selector
        )
        
        let session = TrainingEngineBridge.convertSessionPlanToUIModel(
            plan,
            templateId: template.id,
            templateName: template.name,
            computedReadinessScore: 75,
            exerciseStates: [:],
            sessions: []
        )
        
        guard let perf = session.exercises.first else {
            XCTFail("Expected at least one planned exercise")
            return
        }
        
        guard let snapshot = perf.policySelectionSnapshot else {
            XCTFail("Expected policySelectionSnapshot to be attached")
            return
        }
        
        XCTAssertEqual(snapshot.executedPolicyId, "baseline")
        XCTAssertEqual(snapshot.explorationMode, .control)
        XCTAssertEqual(snapshot.executedActionProbability, 1.0)
        XCTAssertNil(snapshot.shadowPolicyId)
        XCTAssertNil(snapshot.shadowActionProbability)
    }
    
    func testPolicySelectionSnapshotAttachedForExploreMode() {
        let bench = ExerciseSeeds.defaultExercises[1]
        let template = WorkoutTemplate(
            name: "Test Template",
            exercises: [
                WorkoutTemplateExercise(exercise: ExerciseRef(from: bench))
            ]
        )
        
        let selector = FixedPolicySelector(selection: .explore(policyId: "conservative", actionProbability: 0.42))
        
        let plan = TrainingEngineBridge.recommendSessionForTemplate(
            date: Date(),
            templateId: template.id,
            userProfile: UserProfile(),
            templates: [template],
            sessions: [],
            liftStates: [:],
            readiness: 75,
            dailyBiometrics: [],
            policySelector: selector
        )
        
        let session = TrainingEngineBridge.convertSessionPlanToUIModel(
            plan,
            templateId: template.id,
            templateName: template.name,
            computedReadinessScore: 75,
            exerciseStates: [:],
            sessions: []
        )
        
        guard let perf = session.exercises.first else {
            XCTFail("Expected at least one planned exercise")
            return
        }
        
        guard let snapshot = perf.policySelectionSnapshot else {
            XCTFail("Expected policySelectionSnapshot to be attached")
            return
        }
        
        XCTAssertEqual(snapshot.executedPolicyId, "conservative")
        XCTAssertEqual(snapshot.explorationMode, .explore)
        XCTAssertEqual(snapshot.executedActionProbability, 0.42, accuracy: 1e-9)
    }
}

