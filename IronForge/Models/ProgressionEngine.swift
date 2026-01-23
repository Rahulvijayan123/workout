import Foundation

/// A small deterministic progression engine (Liftosaur-inspired) that supports
/// classic "double progression" for hypertrophy/strength work.
///
/// Rules:
/// - If all sets hit the top of the rep range -> increase weight by `increment`, reset reps to lower bound.
/// - Else if all sets hit at least the lower bound -> keep weight, target +1 rep next time (up to upper bound).
/// - Else -> increment failuresCount; deload only when failuresCount reaches failureThreshold.
enum ProgressionEngine {
    struct Inputs: Sendable, Hashable {
        var repRange: ClosedRange<Int>
        var increment: Double
        /// Legacy percent deload used only by `nextSuggestion`.
        var deloadPercent: Double = ProgressionDefaults.deloadPercentage
    }
    
    enum Suggestion: Sendable, Hashable {
        case increaseWeight(newWeight: Double, targetReps: Int)
        case increaseReps(targetReps: Int)
        case hold(targetReps: Int)
        case deload(newWeight: Double, targetReps: Int)
    }
    
    /// Legacy suggestion API (used by the dashboard self-test card).
    static func nextSuggestion(lastSets: [WorkoutSet], inputs: Inputs) -> Suggestion {
        let lb = inputs.repRange.lowerBound
        let ub = inputs.repRange.upperBound
        
        guard !lastSets.isEmpty else {
            return .hold(targetReps: lb)
        }
        
        let completed = lastSets.filter { $0.isCompleted }
        let setSample = completed.isEmpty ? lastSets : completed
        
        let avgWeight = setSample.map(\.weight).reduce(0, +) / Double(setSample.count)
        let roundedWeight = roundToIncrement(avgWeight, increment: 0.5)
        
        let reps = setSample.map(\.reps)
        let minReps = reps.min() ?? 0
        let allAtLeastLB = reps.allSatisfy { $0 >= lb }
        let allAtLeastUB = reps.allSatisfy { $0 >= ub }
        
        if allAtLeastUB {
            let newWeight = max(0, roundedWeight + inputs.increment)
            return .increaseWeight(newWeight: newWeight, targetReps: lb)
        }
        
        if allAtLeastLB {
            let target = min(ub, max(lb, minReps + 1))
            if target == minReps {
                return .hold(targetReps: target)
            }
            return .increaseReps(targetReps: target)
        }
        
        let newWeight = max(0, roundedWeight * (1.0 - inputs.deloadPercent))
        return .deload(newWeight: roundToIncrement(newWeight, increment: 0.5), targetReps: lb)
    }
    
    /// Computes the next prescription based on exercise performance and prior state.
    /// Returns both the snapshot for history and the updated exercise state.
    static func nextPrescription(
        performance: ExercisePerformance,
        priorState: ExerciseState?
    ) -> (snapshot: NextPrescriptionSnapshot, updatedState: ExerciseState) {
        let exerciseId = performance.exercise.id
        let lb = performance.repRangeMin
        let ub = performance.repRangeMax
        let increment = performance.increment
        let deloadFactor = performance.deloadFactor
        let failureThreshold = max(1, performance.failureThreshold)
        
        // Use completed sets if any, else all sets.
        let completed = performance.sets.filter { $0.isCompleted }
        let setSample = completed.isEmpty ? performance.sets : completed
        
        guard !setSample.isEmpty else {
            let state = priorState ?? ExerciseState(exerciseId: exerciseId, currentWorkingWeight: 0, failuresCount: 0)
            let snapshot = NextPrescriptionSnapshot(
                exerciseId: exerciseId,
                nextWorkingWeight: state.currentWorkingWeight,
                targetReps: lb,
                setsTarget: performance.setsTarget,
                repRangeMin: lb,
                repRangeMax: ub,
                increment: increment,
                deloadFactor: deloadFactor,
                failureThreshold: failureThreshold,
                reason: .hold
            )
            return (snapshot, state)
        }
        
        // Calculate base weight from the sample sets.
        let avgWeight = setSample.map(\.weight).reduce(0, +) / Double(setSample.count)
        let baseWeight = roundToIncrement(avgWeight, increment: 2.5)
        
        // Analyze rep performance.
        let reps = setSample.map(\.reps)
        let minReps = reps.min() ?? 0
        let allAtLeastLB = reps.allSatisfy { $0 >= lb }
        let allAtLeastUB = reps.allSatisfy { $0 >= ub }
        
        // Initialize or retrieve prior state.
        var currentState = priorState ?? ExerciseState(
            exerciseId: exerciseId,
            currentWorkingWeight: setSample.first?.weight ?? 0,
            failuresCount: 0
        )
        
        var nextWorkingWeight: Double
        var targetReps: Int
        var reason: ProgressionReason
        
        if allAtLeastUB {
            nextWorkingWeight = roundToIncrement(baseWeight + increment, increment: 2.5)
            targetReps = lb
            reason = .increaseWeight
            currentState.failuresCount = 0
        } else if allAtLeastLB {
            nextWorkingWeight = baseWeight
            targetReps = max(lb, min(ub, minReps + 1))
            reason = .increaseReps
            currentState.failuresCount = 0
        } else {
            currentState.failuresCount += 1
            
            if currentState.failuresCount >= failureThreshold {
                // Deload and reset failures.
                nextWorkingWeight = roundToIncrement(max(0, baseWeight * deloadFactor), increment: 2.5)
                targetReps = lb
                reason = .deload
                currentState.failuresCount = 0
            } else {
                // Hold and retry at rep floor.
                nextWorkingWeight = baseWeight
                targetReps = lb
                reason = .hold
            }
        }
        
        currentState.currentWorkingWeight = nextWorkingWeight
        currentState.updatedAt = Date()
        
        let snapshot = NextPrescriptionSnapshot(
            exerciseId: exerciseId,
            nextWorkingWeight: nextWorkingWeight,
            targetReps: targetReps,
            setsTarget: performance.setsTarget,
            repRangeMin: lb,
            repRangeMax: ub,
            increment: increment,
            deloadFactor: deloadFactor,
            failureThreshold: failureThreshold,
            reason: reason
        )
        
        return (snapshot, currentState)
    }
    
    static func seedSets(plannedSets: Int, targetReps: Int, weight: Double) -> [WorkoutSet] {
        let reps = max(0, targetReps)
        let w = max(0, weight)
        return (0..<max(1, plannedSets)).map { _ in
            WorkoutSet(reps: reps, weight: w, isCompleted: false)
        }
    }
    
    private static func roundToIncrement(_ value: Double, increment: Double) -> Double {
        guard increment > 0 else { return value }
        return (value / increment).rounded() * increment
    }
}

