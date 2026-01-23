import XCTest
@testable import TrainingEngine

final class AdaptiveProgressionNuanceTests: XCTestCase {
    
    func testAdaptiveIncrement_SmallerForAdvancedAndStrong() {
        let cal = Calendar(identifier: .gregorian)
        let d0 = Date(timeIntervalSince1970: 1_700_000_000) // stable anchor
        
        let bench = Exercise(
            id: "bench",
            name: "Bench Press",
            equipment: .barbell,
            primaryMuscles: [.chest],
            secondaryMuscles: [.triceps],
            movementPattern: .horizontalPush
        )
        
        let rx = SetPrescription(setCount: 3, targetRepsRange: 6...10, targetRIR: 2, restSeconds: 120, increment: .pounds(5))
        let cfg = DoubleProgressionConfig(sessionsAtTopBeforeIncrease: 1, loadIncrement: .pounds(5), deloadPercentage: 0.10, failuresBeforeDeload: 3)
        
        func historyFor(load: Double) -> (WorkoutHistory, LiftState) {
            let sets: [SetResult] = (0..<3).map { _ in SetResult(reps: 10, load: .pounds(load), completed: true) }
            let ex = ExerciseSessionResult(exerciseId: bench.id, prescription: rx, sets: sets, order: 0)
            let session = CompletedSession(
                date: d0,
                templateId: nil,
                name: "S",
                exerciseResults: [ex],
                startedAt: d0,
                endedAt: d0,
                wasDeload: false,
                previousLiftStates: [:],
                readinessScore: 80
            )
            let lift = LiftState(
                exerciseId: bench.id,
                lastWorkingWeight: .pounds(load),
                rollingE1RM: 0,
                failureCount: 0,
                lastDeloadDate: nil,
                trend: .insufficient,
                e1rmHistory: [],
                lastSessionDate: d0,
                successfulSessionsCount: 0
            )
            let hist = WorkoutHistory(sessions: [session], liftStates: [bench.id: lift], readinessHistory: [], recentVolumeByDate: [:])
            return (hist, lift)
        }
        
        // "135 → 225" style scenario (weaker + newer lifter).
        let (h1, s1) = historyFor(load: 135)
        let beginner = UserProfile(
            id: "u1",
            sex: .male,
            experience: .beginner,
            goals: [.hypertrophy],
            weeklyFrequency: 3,
            availableEquipment: .commercialGym,
            preferredUnit: .pounds,
            bodyWeight: .pounds(180)
        )
        let inc1 = DoubleProgressionPolicy.computeNextLoad(
            config: cfg,
            prescription: rx,
            liftState: s1,
            history: h1,
            exerciseId: bench.id,
            context: ProgressionContext(userProfile: beginner, exercise: bench, date: d0, calendar: cal)
        ).value - 135
        
        // "225 → 315" style scenario (stronger + advanced lifter).
        let (h2, s2) = historyFor(load: 225)
        let advanced = UserProfile(
            id: "u2",
            sex: .male,
            experience: .advanced,
            goals: [.strength],
            weeklyFrequency: 3,
            availableEquipment: .commercialGym,
            preferredUnit: .pounds,
            bodyWeight: .pounds(180)
        )
        let inc2 = DoubleProgressionPolicy.computeNextLoad(
            config: cfg,
            prescription: rx,
            liftState: s2,
            history: h2,
            exerciseId: bench.id,
            context: ProgressionContext(userProfile: advanced, exercise: bench, date: d0, calendar: cal)
        ).value - 225
        
        XCTAssertGreaterThanOrEqual(inc1, inc2, "Beginner/weaker lifter should generally get larger increments")
        XCTAssertTrue(inc2 == 2.5 || inc2 == 5.0, "Advanced increment should stay plate-friendly (got \(inc2))")
    }
    
    func testPlateauInsight_EmitsForStagnantE1RM() {
        let cal = Calendar(identifier: .gregorian)
        let bench = Exercise(
            id: "bench",
            name: "Bench Press",
            equipment: .barbell,
            primaryMuscles: [.chest],
            secondaryMuscles: [.triceps],
            movementPattern: .horizontalPush
        )
        
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let samples: [E1RMSample] = (0..<8).map { i in
            let d = cal.date(byAdding: .day, value: -(70 - i * 10), to: now)! // >6 weeks span across recent window
            return E1RMSample(date: d, value: 275)
        }
        
        let user = UserProfile(
            id: "u",
            sex: .male,
            experience: .advanced,
            goals: [.strength],
            weeklyFrequency: 3,
            availableEquipment: .commercialGym,
            preferredUnit: .pounds,
            bodyWeight: .pounds(180),
            dailyProteinGrams: 120,
            sleepHours: 6.5
        )
        
        let lift = LiftState(
            exerciseId: bench.id,
            lastWorkingWeight: .pounds(225),
            rollingE1RM: 275,
            failureCount: 0,
            lastDeloadDate: cal.date(byAdding: .day, value: -40, to: now),
            trend: .stable,
            e1rmHistory: samples,
            lastSessionDate: now,
            successfulSessionsCount: 20
        )
        
        let rx = SetPrescription(
            setCount: 3,
            targetRepsRange: 6...10,
            targetRIR: 2,
            tempo: .standard,
            restSeconds: 120,
            loadStrategy: .absolute,
            targetPercentage: nil,
            increment: .pounds(5)
        )
        
        let sessions: [CompletedSession] = samples.map { s in
            let sets: [SetResult] = (0..<3).map { _ in
                SetResult(reps: 8, load: .pounds(225), rirObserved: nil, completed: true)
            }
            let ex = ExerciseSessionResult(exerciseId: bench.id, prescription: rx, sets: sets, order: 0)
            return CompletedSession(
                date: s.date,
                templateId: nil,
                name: "Bench",
                exerciseResults: [ex],
                startedAt: s.date,
                endedAt: s.date,
                wasDeload: false,
                previousLiftStates: [bench.id: lift],
                readinessScore: 80
            )
        }
        
        let history = WorkoutHistory(sessions: sessions, liftStates: [bench.id: lift], readinessHistory: [], recentVolumeByDate: [:])
        
        let insights = CoachingInsightsPolicy.insightsForExercise(
            exerciseId: bench.id,
            exercise: bench,
            liftState: lift,
            userProfile: user,
            history: history,
            date: now,
            calendar: cal,
            currentReadiness: 80,
            substitutions: []
        )
        
        XCTAssertTrue(insights.contains(where: { $0.topic == .plateau }), "Expected plateau insight to be emitted")
    }
}

