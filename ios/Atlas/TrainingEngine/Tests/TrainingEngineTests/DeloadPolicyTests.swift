import XCTest
@testable import TrainingEngine

final class DeloadPolicyTests: XCTestCase {
    
    let calendar = Calendar.current
    
    // MARK: - Performance Decline Tests
    
    func testTwoSessionDecline_TriggersDeload() {
        // Given: e1RM declining over last 3 sessions
        let now = Date()
        let samples = [
            E1RMSample(date: calendar.date(byAdding: .day, value: -14, to: now)!, value: 300),
            E1RMSample(date: calendar.date(byAdding: .day, value: -7, to: now)!, value: 290),
            E1RMSample(date: now, value: 280)
        ]
        
        let hasTwoSessionDecline = TrendCalculator.hasTwoSessionDecline(samples: samples)
        
        // Then
        XCTAssertTrue(hasTwoSessionDecline)
    }
    
    func testOneSessionDecline_DoesNotTrigger() {
        // Given: Only one session decline
        let now = Date()
        let samples = [
            E1RMSample(date: calendar.date(byAdding: .day, value: -14, to: now)!, value: 300),
            E1RMSample(date: calendar.date(byAdding: .day, value: -7, to: now)!, value: 305),
            E1RMSample(date: now, value: 300)  // One decline, not two
        ]
        
        let hasTwoSessionDecline = TrendCalculator.hasTwoSessionDecline(samples: samples)
        
        // Then
        XCTAssertFalse(hasTwoSessionDecline)
    }
    
    func testNotEnoughSamples_DoesNotTrigger() {
        // Given: Only 2 samples
        let now = Date()
        let samples = [
            E1RMSample(date: calendar.date(byAdding: .day, value: -7, to: now)!, value: 300),
            E1RMSample(date: now, value: 280)
        ]
        
        let hasTwoSessionDecline = TrendCalculator.hasTwoSessionDecline(samples: samples)
        
        // Then
        XCTAssertFalse(hasTwoSessionDecline)
    }
    
    // MARK: - Trend Calculation Tests
    
    func testTrendCalculation_Improving() {
        let now = Date()
        let samples = (0..<5).map { i in
            E1RMSample(
                date: calendar.date(byAdding: .day, value: -i * 7, to: now)!,
                value: 300 - Double(i * 10)  // Increasing backwards = improving forward
            )
        }.reversed()
        
        let trend = TrendCalculator.compute(from: Array(samples))
        XCTAssertEqual(trend, .improving)
    }
    
    func testTrendCalculation_Declining() {
        let now = Date()
        let samples = (0..<5).map { i in
            E1RMSample(
                date: calendar.date(byAdding: .day, value: -i * 7, to: now)!,
                value: 300 + Double(i * 10)  // Decreasing backwards = declining forward
            )
        }.reversed()
        
        let trend = TrendCalculator.compute(from: Array(samples))
        XCTAssertEqual(trend, .declining)
    }
    
    func testTrendCalculation_Stable() {
        let now = Date()
        let samples = (0..<5).map { i in
            E1RMSample(
                date: calendar.date(byAdding: .day, value: -i * 7, to: now)!,
                value: 300 + Double(i % 2)  // Tiny variation
            )
        }
        
        let trend = TrendCalculator.compute(from: samples)
        XCTAssertEqual(trend, .stable)
    }
    
    func testTrendCalculation_InsufficientData() {
        let samples = [
            E1RMSample(date: Date(), value: 300)
        ]
        
        let trend = TrendCalculator.compute(from: samples)
        XCTAssertEqual(trend, .insufficient)
    }
    
    // MARK: - Scheduled Deload Tests
    
    func testScheduledDeload_TriggersAfterConfiguredWeeks() {
        let deloadConfig = DeloadConfig(
            scheduledDeloadWeeks: 4
        )
        
        let now = Date()
        let fiveWeeksAgo = calendar.date(byAdding: .weekOfYear, value: -5, to: now)!
        
        let liftState = LiftState(
            exerciseId: "squat",
            lastDeloadDate: fiveWeeksAgo  // 5 weeks since last deload
        )
        
        let history = WorkoutHistory(
            sessions: [],
            liftStates: ["squat": liftState]
        )
        
        let plan = createTestPlan(deloadConfig: deloadConfig)
        let userProfile = createTestUserProfile()
        
        let decision = DeloadPolicy.evaluate(
            userProfile: userProfile,
            plan: plan,
            history: history,
            readiness: 80,
            date: now,
            calendar: calendar
        )
        
        XCTAssertTrue(decision.shouldDeload)
        XCTAssertEqual(decision.reason, .scheduledDeload)
    }
    
    func testScheduledDeload_DoesNotTriggerBeforeConfiguredWeeks() {
        let deloadConfig = DeloadConfig(
            scheduledDeloadWeeks: 4
        )
        
        let now = Date()
        let twoWeeksAgo = calendar.date(byAdding: .weekOfYear, value: -2, to: now)!
        
        let liftState = LiftState(
            exerciseId: "squat",
            lastDeloadDate: twoWeeksAgo  // Only 2 weeks since last deload
        )
        
        let history = WorkoutHistory(
            sessions: [],
            liftStates: ["squat": liftState]
        )
        
        let plan = createTestPlan(deloadConfig: deloadConfig)
        let userProfile = createTestUserProfile()
        
        let decision = DeloadPolicy.evaluate(
            userProfile: userProfile,
            plan: plan,
            history: history,
            readiness: 80,
            date: now,
            calendar: calendar
        )
        
        // Should not trigger based on schedule alone
        // (other triggers might still fire)
        let scheduledTriggered = decision.triggeredRules.first { $0.trigger == .scheduledDeload }?.triggered ?? false
        XCTAssertFalse(scheduledTriggered)
    }
    
    // MARK: - Low Readiness Tests
    
    func testLowReadiness_TriggersAfterConsecutiveDays() {
        let deloadConfig = DeloadConfig(
            readinessThreshold: 50,
            lowReadinessDaysRequired: 3
        )
        
        let now = Date()
        
        // 3 consecutive days of low readiness
        let readinessHistory = [
            ReadinessRecord(date: calendar.date(byAdding: .day, value: -2, to: now)!, score: 40),
            ReadinessRecord(date: calendar.date(byAdding: .day, value: -1, to: now)!, score: 45),
            ReadinessRecord(date: now, score: 35)
        ]
        
        let history = WorkoutHistory(
            sessions: [],
            liftStates: [:],
            readinessHistory: readinessHistory
        )
        
        let plan = createTestPlan(deloadConfig: deloadConfig)
        let userProfile = createTestUserProfile()
        
        let decision = DeloadPolicy.evaluate(
            userProfile: userProfile,
            plan: plan,
            history: history,
            readiness: 40,  // Current readiness also low
            date: now,
            calendar: calendar
        )
        
        let lowReadinessTriggered = decision.triggeredRules.first { $0.trigger == .lowReadiness }?.triggered ?? false
        XCTAssertTrue(lowReadinessTriggered)
    }
    
    // MARK: - Deload Application Tests
    
    func testDeloadApplication_ReducesLoadAndSets() {
        let deloadConfig = DeloadConfig(
            intensityReduction: 0.10,
            volumeReduction: 1
        )
        
        let exercisePlan = ExercisePlan(
            exercise: .barbellSquat,
            prescription: .hypertrophy,
            sets: [
                SetPlan(setIndex: 0, targetLoad: .pounds(225), targetReps: 8, targetRIR: 2, restSeconds: 120),
                SetPlan(setIndex: 1, targetLoad: .pounds(225), targetReps: 8, targetRIR: 2, restSeconds: 120),
                SetPlan(setIndex: 2, targetLoad: .pounds(225), targetReps: 8, targetRIR: 2, restSeconds: 120)
            ],
            progressionPolicy: .doubleProgression(config: .default)
        )
        
        let deloadedPlan = DeloadPolicy.applyDeload(
            config: deloadConfig,
            exercisePlan: exercisePlan
        )
        
        // Volume reduced: 3 sets - 1 = 2 sets
        XCTAssertEqual(deloadedPlan.sets.count, 2)
        
        // Intensity reduced: 225 * 0.90 = 202.5
        let expectedLoad = 225 * 0.90
        XCTAssertEqual(deloadedPlan.sets[0].targetLoad.value, expectedLoad, accuracy: 0.01)
    }
    
    // MARK: - Helpers
    
    private func createTestPlan(deloadConfig: DeloadConfig?) -> TrainingPlan {
        TrainingPlan(
            name: "Test Plan",
            templates: [:],
            schedule: .manual,
            deloadConfig: deloadConfig
        )
    }
    
    private func createTestUserProfile() -> UserProfile {
        UserProfile(
            sex: .male,
            experience: .intermediate,
            goals: [.strength]
        )
    }
}
