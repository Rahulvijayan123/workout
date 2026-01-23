import Foundation

/// Heuristics for generating human-facing coaching insights.
///
/// These are deliberately conservative and only fire when the signal is strong; the goal is to
/// surface actionable guidance without being noisy.
enum CoachingInsightsPolicy {
    
    static func insightsForExercise(
        exerciseId: String,
        exercise: Exercise,
        liftState: LiftState,
        userProfile: UserProfile,
        history: WorkoutHistory,
        date: Date,
        calendar: Calendar,
        currentReadiness: Int,
        substitutions: [Substitution]
    ) -> [CoachingInsight] {
        var insights: [CoachingInsight] = []
        
        // 1) Plateau detection (based on e1RM trend and time).
        if let plateau = detectPlateau(
            liftState: liftState,
            userProfile: userProfile,
            exercise: exercise,
            history: history,
            date: date,
            calendar: calendar
        ) {
            let suggested = substitutions
                .filter { $0.score >= 0.65 }
                .prefix(2)
                .map { $0.exercise.name }
            
            let (avg7, lowDays) = recentReadinessSummary(history: history, from: date, calendar: calendar)
            
            var detailParts: [String] = []
            detailParts.append(String(format: "No meaningful e1RM increase for ~%.1f weeks (Δ≈%.1f%%).", plateau.weeks, plateau.deltaPct * 100))
            
            if !suggested.isEmpty {
                detailParts.append("Try a variation for 4–6 weeks: \(suggested.joined(separator: " / ")).")
            } else {
                detailParts.append("Try a variation for 4–6 weeks (same movement pattern, different angle/grip).")
            }
            
            if let avg7 {
                if avg7 < 60 || lowDays >= 3 || currentReadiness < 55 {
                    detailParts.append("Recovery looks limited recently (7d avg readiness \(Int(avg7))/100). Prioritize sleep/stress management and consider a deload week.")
                } else {
                    detailParts.append("Recovery looks OK. Consider adding a small amount of volume or pushing sets closer to the target effort (RIR) if safe.")
                }
            } else {
                detailParts.append("If you're sleeping poorly or highly stressed, address recovery before changing the plan.")
            }
            
            if let hours = userProfile.sleepHours, hours < 7 {
                detailParts.append(String(format: "Self-reported sleep is %.1f h/night; improving sleep can unstick progress.", hours))
            }
            
            if let protein = userProfile.dailyProteinGrams, let bw = userProfile.bodyWeight?.converted(to: .pounds).value, bw > 0 {
                let gPerLb = Double(protein) / bw
                if gPerLb < 0.7 {
                    detailParts.append("Protein looks potentially low for gaining muscle (≈\(String(format: "%.2f", gPerLb)) g/lb). Consider increasing protein and total calories.")
                }
            } else {
                detailParts.append("Also sanity-check nutrition (protein/calories) and technique—plateaus are rarely just 'bad programming'.")
            }
            
            detailParts.append("Remember: progress isn't only load. More reps at the same load, an extra set, cleaner ROM/tempo, shorter rests, or the same work at lower effort (higher RIR) all count.")
            
            insights.append(CoachingInsight(
                topic: .plateau,
                title: "Plateau flag: \(exercise.name)",
                detail: detailParts.joined(separator: " "),
                relatedExerciseId: exerciseId
            ))
        }
        
        return insights
    }
    
    // MARK: - Plateau detection
    
    private struct PlateauSignal {
        let weeks: Double
        let deltaPct: Double
    }
    
    private static func detectPlateau(
        liftState: LiftState,
        userProfile: UserProfile,
        exercise: Exercise,
        history: WorkoutHistory,
        date: Date,
        calendar: Calendar
    ) -> PlateauSignal? {
        // Be conservative about plateau messaging: only fire for compound, loaded lifts
        // where stalling is a meaningful signal (e.g., bench/squat/deadlift/press/row).
        let isCompound = exercise.movementPattern.isCompound
        let isBarbellLike = (exercise.equipment == .barbell || exercise.equipment == .trapBar || exercise.equipment == .ezBar)
        guard isCompound && isBarbellLike else { return nil }
        
        // If we just deloaded, don't immediately call a plateau.
        if let lastDeload = liftState.lastDeloadDate {
            let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: lastDeload), to: calendar.startOfDay(for: date)).day ?? 0
            if days >= 0 && days < 14 { return nil }
        }
        
        // Build plateau signal from session history (not LiftState.e1rmHistory) so we can:
        // - ignore deload sessions
        // - require comparable prescriptions (rep range / tempo / rest)
        // - treat volume/effort improvements as progress
        struct Sample {
            let date: Date
            let e1rmKg: Double
            let volumeKgReps: Double
            let avgRIR: Double?
            let prescription: SetPrescription
        }
        
        func prescriptionsComparable(_ a: SetPrescription, _ b: SetPrescription) -> Bool {
            if a.loadStrategy != b.loadStrategy { return false }
            if a.setCount != b.setCount { return false }
            if a.targetRepsRange != b.targetRepsRange { return false }
            if a.targetRIR != b.targetRIR { return false }
            if a.tempo != b.tempo { return false }
            if abs(a.restSeconds - b.restSeconds) > 15 { return false }
            return true
        }
        
        var samples: [Sample] = []
        samples.reserveCapacity(10)
        
        var baselinePrescription: SetPrescription?
        let evaluationDay = calendar.startOfDay(for: date)
        
        for session in history.sessions {
            let sessionDay = calendar.startOfDay(for: session.date)
            guard sessionDay <= evaluationDay else { continue }
            guard session.wasDeload == false else { continue }
            guard let ex = session.exerciseResults.first(where: { $0.exerciseId == exercise.id }) else { continue }
            
            if let baseline = baselinePrescription {
                guard prescriptionsComparable(ex.prescription, baseline) else { continue }
            } else {
                baselinePrescription = ex.prescription
            }
            
            let working = ex.workingSets
            guard !working.isEmpty else { continue }
            
            let e1rmKg = working
                .map { set in E1RMCalculator.brzycki(weight: set.load.inKilograms, reps: set.reps) }
                .max() ?? 0
            guard e1rmKg > 0 else { continue }
            
            let volumeKgReps = working.reduce(0.0) { partial, set in
                partial + (set.load.inKilograms * Double(set.reps))
            }
            
            let rirs = working.compactMap(\.rirObserved)
            let avgRIR: Double? = rirs.isEmpty ? nil : (Double(rirs.reduce(0, +)) / Double(rirs.count))
            
            samples.append(Sample(
                date: session.date,
                e1rmKg: e1rmKg,
                volumeKgReps: volumeKgReps,
                avgRIR: avgRIR,
                prescription: ex.prescription
            ))
            
            if samples.count >= 10 { break }
        }
        
        // Need enough signal; require most of the bounded window.
        guard samples.count >= 8 else { return nil }
        guard liftState.successfulSessionsCount >= 12 else { return nil }
        
        // Evaluate on the most recent 6 comparable samples (chronological).
        let chronological = samples.reversed()
        let recent = Array(chronological.suffix(6))
        guard let oldest = recent.first, let newest = recent.last else { return nil }
        let old = oldest.e1rmKg
        let new = newest.e1rmKg
        guard old > 0, new > 0 else { return nil }
        
        let days = max(1, calendar.dateComponents([.day], from: oldest.date, to: newest.date).day ?? 1)
        let weeks = Double(days) / 7.0
        guard weeks >= 6 else { return nil } // need at least ~6 weeks of signal
        
        // If volume meaningfully increased over the window, treat that as progress and avoid flagging a plateau.
        if oldest.volumeKgReps > 0 {
            let volumePct = (newest.volumeKgReps - oldest.volumeKgReps) / oldest.volumeKgReps
            if volumePct >= 0.05 { return nil }
        }
        
        // If observed effort dropped (higher RIR at similar work), treat as progress.
        if let o = oldest.avgRIR, let n = newest.avgRIR, (n - o) >= 1.0 {
            return nil
        }
        
        let deltaPct = (new - old) / old
        
        // Experience-aware plateau thresholds.
        let threshold: Double = {
            switch userProfile.experience {
            case .beginner:
                return 0.010  // <1.0% over ~3+ weeks is suspicious
            case .intermediate:
                return 0.006  // <0.6%
            case .advanced, .elite:
                return 0.003  // <0.3%
            }
        }()
        
        // Require either stable/declining trend OR very small delta.
        let trendSamples = recent.map { E1RMSample(date: $0.date, value: $0.e1rmKg) }
        let trend = TrendCalculator.compute(from: trendSamples)
        let trendBad = (trend == .stable || trend == .declining)
        if trendBad && deltaPct < threshold {
            return PlateauSignal(weeks: weeks, deltaPct: deltaPct)
        }
        
        return nil
    }
    
    private static func recentReadinessSummary(
        history: WorkoutHistory,
        from date: Date,
        calendar: Calendar
    ) -> (avg7: Double?, lowDays: Int) {
        let endDay = calendar.startOfDay(for: date)
        let startDay = calendar.date(byAdding: .day, value: -6, to: endDay) ?? endDay
        
        // Min score per day (conservative).
        var byDay: [Date: Int] = [:]
        for r in history.readinessHistory {
            let d = calendar.startOfDay(for: r.date)
            guard d >= startDay && d <= endDay else { continue }
            byDay[d] = min(byDay[d] ?? 100, r.score)
        }
        
        if byDay.isEmpty {
            return (avg7: nil, lowDays: 0)
        }
        
        let values = Array(byDay.values)
        let avg = Double(values.reduce(0, +)) / Double(values.count)
        let lowDays = values.filter { $0 < 50 }.count
        return (avg7: avg, lowDays: lowDays)
    }
}

