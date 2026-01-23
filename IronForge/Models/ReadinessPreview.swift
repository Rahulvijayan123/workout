import Foundation

struct ReadinessPreview: Sendable, Equatable {
    enum Confidence: String, Sendable {
        case low
        case medium
        case high
    }
    
    var readinessConfidence: Confidence
    var drivers: [String]
    
    static func fromCachedBiometrics(
        _ biometrics: [DailyBiometrics],
        calendar: Calendar = .current
    ) -> ReadinessPreview {
        guard !biometrics.isEmpty else {
            return ReadinessPreview(readinessConfidence: .low, drivers: [])
        }
        
        let sorted = biometrics.sorted { $0.date < $1.date }
        guard let latest = sorted.last else {
            return ReadinessPreview(readinessConfidence: .low, drivers: [])
        }
        
        let baselineStart = calendar.date(byAdding: .day, value: -7, to: latest.date) ?? latest.date
        let baselinePool = sorted.filter { $0.date >= baselineStart && $0.date < latest.date }
        
        func baselineAverage(_ extract: (DailyBiometrics) -> Double?) -> Double? {
            let values = baselinePool.compactMap(extract)
            guard values.count >= 3 else { return nil }
            return values.reduce(0, +) / Double(values.count)
        }
        
        let sleepBaseline = baselineAverage { $0.sleepMinutes }
        let hrvBaseline = baselineAverage { $0.hrvSDNN }
        let rhrBaseline = baselineAverage { $0.restingHR }
        let energyBaseline = baselineAverage { $0.activeEnergy }
        let stepsBaseline = baselineAverage { $0.steps }
        
        var drivers: [String] = []
        
        if let sleep = latest.sleepMinutes, let baseline = sleepBaseline {
            if sleep < baseline * 0.85 { drivers.append("Sleep below baseline") }
            else if sleep > baseline * 1.10 { drivers.append("Sleep above baseline") }
        }
        
        if let hrv = latest.hrvSDNN, let baseline = hrvBaseline {
            if hrv < baseline * 0.90 { drivers.append("HRV below baseline") }
            else if hrv > baseline * 1.10 { drivers.append("HRV above baseline") }
        }
        
        if let rhr = latest.restingHR, let baseline = rhrBaseline {
            if rhr > baseline * 1.05 { drivers.append("Resting HR above baseline") }
            else if rhr < baseline * 0.95 { drivers.append("Resting HR below baseline") }
        }
        
        if let energy = latest.activeEnergy, let baseline = energyBaseline {
            if energy < baseline * 0.70 { drivers.append("Activity below baseline") }
        } else if let steps = latest.steps, let baseline = stepsBaseline {
            if steps < baseline * 0.70 { drivers.append("Steps below baseline") }
        }
        
        let presentMetricsCount = [
            latest.sleepMinutes,
            latest.hrvSDNN,
            latest.restingHR,
            latest.activeEnergy,
            latest.steps
        ].compactMap { $0 }.count
        
        let baselineMetricsCount = [
            sleepBaseline,
            hrvBaseline,
            rhrBaseline,
            energyBaseline,
            stepsBaseline
        ].compactMap { $0 }.count
        
        let confidence: Confidence
        if presentMetricsCount >= 3, baselineMetricsCount >= 2 {
            confidence = .high
        } else if presentMetricsCount >= 2 {
            confidence = .medium
        } else {
            confidence = .low
        }
        
        return ReadinessPreview(readinessConfidence: confidence, drivers: drivers)
    }
    
    static var demo: ReadinessPreview {
        ReadinessPreview(
            readinessConfidence: .medium,
            drivers: [
                "Sleep below baseline",
                "HRV below baseline"
            ]
        )
    }
}

