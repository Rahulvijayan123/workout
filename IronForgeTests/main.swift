import Foundation
import TrainingEngine

// main.swift (Two-year daily simulation)
//
// Purpose:
// - Simulate ~2 years of daily workouts (720 sessions) using the *integrated* IronForge → TrainingEngine bridge.
// - Exercise: many workout types (bodyweight + loaded), multiple splits/templates, equipment availability changes,
//   overly-hard phases (forced failures), overly-easy phases, and long hiatus detraining.
//
// Build + run (from repo root) — links against the locally-built TrainingEngine package objects:
//
// swift test -q  (in ios/Atlas/TrainingEngine)  # ensures TrainingEngine macOS objects exist
//
// swiftc -emit-executable -DDEBUG \
//   -I "ios/Atlas/TrainingEngine/.build/arm64-apple-macosx/debug/Modules" \
//   "IronForgeTests/main.swift" \
//   "IronForge/Models/Exercise.swift" \
//   "IronForge/Models/FreeExerciseDBModels.swift" \
//   "IronForge/Repositories/ExerciseLoader.swift" \
//   "IronForge/Models/WorkoutModels.swift" \
//   "IronForge/Models/UserProfile.swift" \
//   "IronForge/Services/TrainingEngineBridge.swift" \
//   "ios/Atlas/TrainingEngine/.build/arm64-apple-macosx/debug/TrainingEngine.build/"*.o \
//   -o "/tmp/ironforge-two-year-sim" && "/tmp/ironforge-two-year-sim"

// MARK: - Deterministic RNG (splitmix64)

struct SeededRNG {
    private var state: UInt64
    init(seed: UInt64) { self.state = seed != 0 ? seed : 0x9E3779B97F4A7C15 }
    
    mutating func nextUInt64() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
    
    mutating func nextDouble01() -> Double {
        let v = nextUInt64() >> 11
        return Double(v) / Double(1 << 53)
    }
    
    mutating func int(in range: ClosedRange<Int>) -> Int {
        let lower = range.lowerBound
        let upper = range.upperBound
        if lower == upper { return lower }
        let span = UInt64(upper - lower + 1)
        return lower + Int(nextUInt64() % span)
    }
    
    mutating func bool(p: Double) -> Bool {
        nextDouble01() < p
    }
    
    mutating func pick<T>(_ array: [T]) -> T? {
        guard !array.isEmpty else { return nil }
        let idx = int(in: 0...(array.count - 1))
        return array[idx]
    }
}

// MARK: - Helpers

let laCalendar: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "America/Los_Angeles")!
    return c
}()

func noon(_ date: Date) -> Date {
    let comps = laCalendar.dateComponents([.year, .month, .day], from: date)
    return laCalendar.date(from: DateComponents(year: comps.year, month: comps.month, day: comps.day, hour: 12))!
}

func loadExercisesFromRepoJSON(path: String) -> [Exercise] {
    let url = URL(fileURLWithPath: path)
    do {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        let source = try decoder.decode([FreeExerciseDBExercise].self, from: data)
        return source.map(ExerciseLoader.transform)
    } catch {
        fputs("FAIL: Could not load exercises.json at \(path): \(error)\n", stderr)
        return []
    }
}

func stableUnique<T: Hashable>(_ items: [T]) -> [T] {
    var seen: Set<T> = []
    var out: [T] = []
    out.reserveCapacity(items.count)
    for x in items {
        if seen.insert(x).inserted {
            out.append(x)
        }
    }
    return out
}

func roundTo(_ value: Double, step: Double) -> Double {
    guard step > 0 else { return value }
    return (value / step).rounded() * step
}

func roundLoadLbForEquipment(_ loadLb: Double, equipment: TEEquipment) -> Double {
    let step: Double = {
        switch equipment {
        case .barbell, .ezBar, .trapBar:
            return 2.5
        case .dumbbell, .kettlebell, .machine, .cable, .smithMachine, .plateLoaded, .resistanceBand:
            return 5.0
        case .bodyweight:
            return 0.0
        default:
            return 2.5
        }
    }()
    guard step > 0 else { return max(0, loadLb) }
    return max(0, roundTo(loadLb, step: step))
}

func initialWorkingWeightLb(for exercise: Exercise, rng: inout SeededRNG) -> Double {
    let eq = TrainingEngineBridge.mapEquipment(exercise.equipment)
    
    // Bodyweight exercises are handled as 0 external load.
    if eq == .bodyweight { return 0 }
    
    // Very rough, intentionally wide bands to simulate real-world diversity.
    switch eq {
    case .barbell:
        return roundTo(Double(rng.int(in: 45...185)), step: 5)
    case .dumbbell:
        return roundTo(Double(rng.int(in: 10...70)), step: 5)
    case .kettlebell:
        return roundTo(Double(rng.int(in: 10...70)), step: 5)
    case .cable:
        return roundTo(Double(rng.int(in: 10...120)), step: 5)
    case .machine, .smithMachine:
        return roundTo(Double(rng.int(in: 20...200)), step: 5)
    case .resistanceBand:
        return roundTo(Double(rng.int(in: 5...40)), step: 5)
    case .ezBar, .trapBar:
        return roundTo(Double(rng.int(in: 45...185)), step: 5)
    default:
        return roundTo(Double(rng.int(in: 10...100)), step: 5)
    }
}

// Brzycki inverse: reps ≈ 37 - 36*w/e1RM (clamped)
func expectedReps(weight: Double, e1rm: Double) -> Int {
    guard weight > 0, e1rm > 0 else { return 12 }
    let r = 37.0 - (36.0 * weight / e1rm)
    if r.isNaN || !r.isFinite { return 8 }
    return max(0, min(20, Int(r.rounded(.down))))
}

func updateTrueE1RM(
    prior: Double,
    bestSetWeight: Double,
    bestSetReps: Int,
    readiness: Int,
    wasSuccess: Bool,
    experience: WorkoutExperience
) -> Double {
    // Lightweight muscle-gain proxy: successful training nudges e1RM upward, failures stagnate/decay slightly.
    let readinessFactor = 0.5 + (Double(max(0, min(100, readiness))) / 200.0) // 0.5 .. 1.0
    let experienceMultiplier: Double = {
        switch experience {
        case .newbie: return 1.15
        case .beginner: return 1.00
        case .intermediate: return 0.70
        case .advanced: return 0.45
        case .expert: return 0.30
        }
    }()
    let sessionE1RM: Double = {
        guard bestSetWeight > 0, bestSetReps > 0 else { return 0 }
        return E1RMCalculator.brzycki(weight: bestSetWeight, reps: bestSetReps)
    }()
    
    if wasSuccess {
        let baseGain = max(0.0003, 0.0012 * readinessFactor) // ~0.03% .. 0.12% per session
        let gain = baseGain * experienceMultiplier
        let target = max(prior, sessionE1RM)
        return max(1, target * (1.0 + gain))
    } else {
        // Small fatigue decay on repeated failures.
        let baseDecay = 0.0008 * (1.0 - readinessFactor) // 0 .. 0.04%
        let decay = baseDecay * (2.0 - experienceMultiplier) // more punitive for advanced stalls
        return max(1, prior * (1.0 - decay))
    }
}

// MARK: - Data load + template construction

var rng = SeededRNG(seed: 0xC0FFEE_2026)

let allExercises = loadExercisesFromRepoJSON(path: "IronForge/Resources/exercises.json")
if allExercises.isEmpty {
    exit(1)
}

// Build equipment buckets so we can deterministically draw variety.
var byEquipment: [TEEquipment: [Exercise]] = [:]
for ex in allExercises {
    let eq = TrainingEngineBridge.mapEquipment(ex.equipment)
    byEquipment[eq, default: []].append(ex)
}

func findExercise(nameContains needle: String, equipment: TEEquipment? = nil) -> Exercise? {
    let n = needle.lowercased()
    let candidates = allExercises.filter { ex in
        let okName = ex.name.lowercased().contains(n)
        if !okName { return false }
        if let equipment {
            return TrainingEngineBridge.mapEquipment(ex.equipment) == equipment
        }
        return true
    }
    // Stable pick: lexicographically smallest id.
    return candidates.sorted { $0.id < $1.id }.first
}

// Canonical anchors (used for “showcase” traces).
let bench = findExercise(nameContains: "bench press", equipment: .barbell)
let squat = findExercise(nameContains: "squat", equipment: .barbell)
let deadlift = findExercise(nameContains: "deadlift", equipment: .barbell)
let pullup = findExercise(nameContains: "pull", equipment: .bodyweight) ?? findExercise(nameContains: "pull-up")

// MARK: - Archetype knobs (long-horizon, real-world-ish)

enum SimulationArchetype: String, CaseIterable {
    case noviceBulk = "novice_bulk"
    case intermediateCut = "intermediate_cut"
    case advancedStrength = "advanced_strength"
    case busyParentMessy = "busy_parent_messy"
    case homeGymMinimal = "home_gym_minimal"
    case dailyMaxVariety = "daily_max_variety"
}

func parseArchetype() -> SimulationArchetype {
    // Usage:
    //   /tmp/ironforge-two-year-sim --archetype novice_bulk
    //   /tmp/ironforge-two-year-sim --archetype=advanced_strength
    //
    // Back-compat:
    //   --scenario beginner135  => novice_bulk
    //   --scenario advanced225  => advanced_strength
    for (i, arg) in CommandLine.arguments.enumerated() {
        if arg == "--archetype", i + 1 < CommandLine.arguments.count {
            let v = CommandLine.arguments[i + 1].lowercased()
            return SimulationArchetype.allCases.first(where: { v.contains($0.rawValue.replacingOccurrences(of: "_", with: "")) || v.contains($0.rawValue) }) ?? .advancedStrength
        }
        if arg.hasPrefix("--archetype=") {
            let v = String(arg.dropFirst("--archetype=".count)).lowercased()
            return SimulationArchetype.allCases.first(where: { v.contains($0.rawValue.replacingOccurrences(of: "_", with: "")) || v.contains($0.rawValue) }) ?? .advancedStrength
        }
        if arg == "--scenario", i + 1 < CommandLine.arguments.count {
            let v = CommandLine.arguments[i + 1].lowercased()
            if v.contains("beginner") { return .noviceBulk }
            if v.contains("advanced") { return .advancedStrength }
        }
        if arg.hasPrefix("--scenario=") {
            let v = String(arg.dropFirst("--scenario=".count)).lowercased()
            if v.contains("beginner") { return .noviceBulk }
            if v.contains("advanced") { return .advancedStrength }
        }
    }
    return .advancedStrength
}

func parseTotalWorkouts(defaultValue: Int = 720) -> Int {
    // Usage:
    //   --workouts 365
    //   --workouts=720
    for (i, arg) in CommandLine.arguments.enumerated() {
        if arg == "--workouts", i + 1 < CommandLine.arguments.count {
            return max(30, Int(CommandLine.arguments[i + 1]) ?? defaultValue)
        }
        if arg.hasPrefix("--workouts=") {
            let v = String(arg.dropFirst("--workouts=".count))
            return max(30, Int(v) ?? defaultValue)
        }
    }
    return defaultValue
}

let archetype: SimulationArchetype = parseArchetype()
let scenarioName: String = archetype.rawValue

let (baseBodyWeightLbs, baseExperience, weeklyFrequencyTarget, goalSet): (Double, WorkoutExperience, Int, [FitnessGoal]) = {
    switch archetype {
    case .noviceBulk:
        return (175, .beginner, 4, [.buildMuscle])
    case .intermediateCut:
        return (195, .intermediate, 4, [.loseFat, .gainStrength])
    case .advancedStrength:
        return (200, .expert, 4, [.gainStrength])
    case .busyParentMessy:
        return (185, .intermediate, 3, [.buildMuscle])
    case .homeGymMinimal:
        return (170, .beginner, 3, [.buildMuscle])
    case .dailyMaxVariety:
        return (185, .intermediate, 7, [.buildMuscle, .gainStrength])
    }
}()

let startingOverridesLb: [String: Double] = {
    var m: [String: Double] = [:]
    
    // Seed "strength tier" on canonical barbell lifts even if the archetype may not have barbells
    // (the engine will often substitute and we seed substitutes from these baselines).
    func setBigThree(bench b: Double, squat s: Double, deadlift d: Double) {
        if let id = bench?.id { m[id] = b }
        if let id = squat?.id { m[id] = s }
        if let id = deadlift?.id { m[id] = d }
    }
    
    switch archetype {
    case .noviceBulk:
        setBigThree(bench: 135, squat: 185, deadlift: 225)
    case .intermediateCut:
        setBigThree(bench: 185, squat: 255, deadlift: 315)
    case .advancedStrength:
        setBigThree(bench: 225, squat: 315, deadlift: 405)
    case .busyParentMessy:
        setBigThree(bench: 165, squat: 225, deadlift: 275)
    case .homeGymMinimal:
        setBigThree(bench: 155, squat: 225, deadlift: 275)
    case .dailyMaxVariety:
        setBigThree(bench: 185, squat: 255, deadlift: 315)
    }
    return m
}()

struct LoggingStyle {
    /// Probability the user actually trains on a planned training day.
    let adherence: Double
    
    /// Probability of skipping an exercise entirely (usually accessories).
    let skipExerciseProb: Double
    
    /// Probability of dropping the last set (time crunch).
    let dropLastSetProb: Double
    
    /// Probability a set is "not logged" (marked incomplete).
    let forgetSetProb: Double
    
    /// Probability the user overrides the planned load upward ("ego").
    let egoLoadProb: Double
    let egoMaxPct: Double
    
    /// Probability the user uses a lighter load than prescribed ("sandbag" / cautious).
    let sandbagLoadProb: Double
    let sandbagMaxPct: Double
    
    /// Probability of a severe unit/entry mistake (rare, mostly for messy archetype).
    let unitMistakeProb: Double
    
    /// Probability the user logs RIR for a set (or logs RPE and we derive RIR).
    let logRIRProb: Double
    let logRPEProb: Double
    
    /// Probability the user stops early (undershoots reps) even when capable.
    let undershootRepsProb: Double
    
    /// Probability the user pushes to failure (overshoots effort; RIR ~0).
    let toFailureProb: Double
    
    /// Probability the user doesn't save the session (so the engine never sees it).
    let sessionNotSavedProb: Double
}

let loggingStyle: LoggingStyle = {
    switch archetype {
    case .noviceBulk:
        return LoggingStyle(
            adherence: 0.88,
            skipExerciseProb: 0.02,
            dropLastSetProb: 0.05,
            forgetSetProb: 0.01,
            egoLoadProb: 0.03,
            egoMaxPct: 0.06,
            sandbagLoadProb: 0.05,
            sandbagMaxPct: 0.08,
            unitMistakeProb: 0.0002,
            logRIRProb: 0.10,
            logRPEProb: 0.05,
            undershootRepsProb: 0.05,
            toFailureProb: 0.06,
            sessionNotSavedProb: 0.01
        )
    case .intermediateCut:
        return LoggingStyle(
            adherence: 0.80,
            skipExerciseProb: 0.04,
            dropLastSetProb: 0.10,
            forgetSetProb: 0.02,
            egoLoadProb: 0.02,
            egoMaxPct: 0.05,
            sandbagLoadProb: 0.06,
            sandbagMaxPct: 0.10,
            unitMistakeProb: 0.0003,
            logRIRProb: 0.18,
            logRPEProb: 0.10,
            undershootRepsProb: 0.06,
            toFailureProb: 0.02,
            sessionNotSavedProb: 0.01
        )
    case .advancedStrength:
        return LoggingStyle(
            adherence: 0.82,
            skipExerciseProb: 0.03,
            dropLastSetProb: 0.06,
            forgetSetProb: 0.02,
            egoLoadProb: 0.06,
            egoMaxPct: 0.08,
            sandbagLoadProb: 0.06,
            sandbagMaxPct: 0.06,
            unitMistakeProb: 0.0002,
            logRIRProb: 0.22,
            logRPEProb: 0.15,
            undershootRepsProb: 0.06,
            toFailureProb: 0.05,
            sessionNotSavedProb: 0.01
        )
    case .busyParentMessy:
        return LoggingStyle(
            adherence: 0.68,
            skipExerciseProb: 0.15,
            dropLastSetProb: 0.25,
            forgetSetProb: 0.08,
            egoLoadProb: 0.08,
            egoMaxPct: 0.12,
            sandbagLoadProb: 0.18,
            sandbagMaxPct: 0.18,
            unitMistakeProb: 0.002,
            logRIRProb: 0.08,
            logRPEProb: 0.06,
            undershootRepsProb: 0.18,
            toFailureProb: 0.06,
            sessionNotSavedProb: 0.08
        )
    case .homeGymMinimal:
        return LoggingStyle(
            adherence: 0.85,
            skipExerciseProb: 0.08,
            dropLastSetProb: 0.18,
            forgetSetProb: 0.03,
            egoLoadProb: 0.03,
            egoMaxPct: 0.06,
            sandbagLoadProb: 0.10,
            sandbagMaxPct: 0.10,
            unitMistakeProb: 0.0004,
            logRIRProb: 0.12,
            logRPEProb: 0.10,
            undershootRepsProb: 0.10,
            toFailureProb: 0.04,
            sessionNotSavedProb: 0.03
        )
    case .dailyMaxVariety:
        return LoggingStyle(
            adherence: 0.95,
            skipExerciseProb: 0.02,
            dropLastSetProb: 0.06,
            forgetSetProb: 0.01,
            egoLoadProb: 0.04,
            egoMaxPct: 0.06,
            sandbagLoadProb: 0.04,
            sandbagMaxPct: 0.06,
            unitMistakeProb: 0.0002,
            logRIRProb: 0.25,
            logRPEProb: 0.15,
            undershootRepsProb: 0.04,
            toFailureProb: 0.05,
            sessionNotSavedProb: 0.01
        )
    }
}()

// Small, deterministic sampling of a substitution pool.
// Keep it bounded so substitution ranking stays fast while still diverse.
let desiredSubPoolSize = 900
var subPool: [Exercise] = []
subPool.reserveCapacity(desiredSubPoolSize)

let diverseEquipmentOrder: [TEEquipment] = [
    .barbell, .dumbbell, .machine, .cable, .kettlebell, .resistanceBand, .bodyweight, .smithMachine, .ezBar, .trapBar
]

for eq in diverseEquipmentOrder {
    let bucket = byEquipment[eq] ?? []
    if bucket.isEmpty { continue }
    // Take up to ~90 per equipment type.
    let take = min(90, bucket.count)
    // Stable pick: choose evenly spaced by sorted id for determinism.
    let sorted = bucket.sorted { $0.id < $1.id }
    for i in 0..<take {
        let idx = (i * max(1, sorted.count / take))
        subPool.append(sorted[min(idx, sorted.count - 1)])
    }
}

// Fill remaining with deterministic random picks across the full dataset.
while subPool.count < desiredSubPoolSize {
    if let picked = rng.pick(allExercises) {
        subPool.append(picked)
    } else {
        break
    }
}
subPool = stableUnique(subPool).prefix(desiredSubPoolSize).map { $0 }

func makeTemplateExercise(_ ex: Exercise) -> WorkoutTemplateExercise {
    let eq = TrainingEngineBridge.mapEquipment(ex.equipment)
    let (sets, repMin, repMax, inc, targetRIR, restSeconds, tempo): (Int, Int, Int, Double, Int, Int, TempoSpec) = {
        switch eq {
        case .barbell, .trapBar, .ezBar:
            return (3, 5, 8, 5, 1, 180, .standard)
        case .dumbbell, .kettlebell:
            return (3, 8, 12, 5, 2, 120, .standard)
        case .machine, .smithMachine, .cable:
            return (3, 10, 15, 5, 2, 90, .standard)
        case .resistanceBand:
            return (3, 12, 20, 5, 2, 60, .standard)
        case .bodyweight:
            // Bodyweight strength: slightly higher RIR and shorter rests (more conditioning variability).
            return (3, 6, 12, 5, 2, 90, .standard)
        default:
            return (3, 8, 12, 5, 2, 120, .standard)
        }
    }()
    
    return WorkoutTemplateExercise(
        exercise: ExerciseRef(from: ex),
        setsTarget: sets,
        repRangeMin: repMin,
        repRangeMax: repMax,
        targetRIR: targetRIR,
        tempo: tempo,
        restSeconds: restSeconds,
        increment: inc,
        deloadFactor: ProgressionDefaults.deloadFactor,
        failureThreshold: ProgressionDefaults.failureThreshold
    )
}

func pickFrom(_ eq: TEEquipment, nameHint: String? = nil) -> Exercise? {
    let bucket = byEquipment[eq] ?? []
    guard !bucket.isEmpty else { return nil }
    if let nameHint {
        let hint = nameHint.lowercased()
        let filtered = bucket.filter { $0.name.lowercased().contains(hint) }
        if let best = filtered.sorted(by: { $0.id < $1.id }).first {
            return best
        }
    }
    // Deterministic random from bucket.
    return rng.pick(bucket)
}

func buildInitialTemplates() -> [WorkoutTemplate] {
    // 7-day rotation that mixes bodyweight + loaded + machine/cable.
    // Keep big compound anchors if we found them.
    let push: [Exercise] = stableUnique([
        bench,
        pickFrom(.dumbbell, nameHint: "shoulder press"),
        pickFrom(.machine, nameHint: "chest"),
        pickFrom(.cable, nameHint: "tricep"),
        pickFrom(.dumbbell, nameHint: "raise"),
        pickFrom(.bodyweight, nameHint: "push")
    ].compactMap { $0 })
    
    let pull: [Exercise] = stableUnique([
        pullup,
        pickFrom(.barbell, nameHint: "row"),
        pickFrom(.cable, nameHint: "row"),
        pickFrom(.dumbbell, nameHint: "curl"),
        pickFrom(.machine, nameHint: "lat"),
        pickFrom(.bodyweight, nameHint: "inverted")
    ].compactMap { $0 })
    
    let legs: [Exercise] = stableUnique([
        squat,
        deadlift,
        pickFrom(.machine, nameHint: "leg press"),
        pickFrom(.machine, nameHint: "leg extension"),
        pickFrom(.machine, nameHint: "leg curl"),
        pickFrom(.machine, nameHint: "calf")
    ].compactMap { $0 })
    
    let upper: [Exercise] = stableUnique([
        bench,
        pickFrom(.barbell, nameHint: "row"),
        pickFrom(.dumbbell, nameHint: "press"),
        pickFrom(.cable, nameHint: "pull"),
        pickFrom(.dumbbell, nameHint: "curl"),
        pickFrom(.cable, nameHint: "tricep")
    ].compactMap { $0 })
    
    let lower: [Exercise] = stableUnique([
        squat,
        deadlift,
        pickFrom(.dumbbell, nameHint: "lunge"),
        pickFrom(.machine, nameHint: "hack"),
        pickFrom(.machine, nameHint: "leg press"),
        pickFrom(.bodyweight, nameHint: "jump")
    ].compactMap { $0 })
    
    let fullBody: [Exercise] = stableUnique([
        squat,
        bench,
        pickFrom(.barbell, nameHint: "row"),
        pickFrom(.dumbbell, nameHint: "press"),
        pickFrom(.bodyweight, nameHint: "plank"),
        pickFrom(.cable, nameHint: "rotation")
    ].compactMap { $0 })
    
    // Bodyweight + mobility / conditioning flavored.
    // Include some "stretching" category exercises by name; if not found, just bodyweight.
    let mobility: [Exercise] = stableUnique([
        pickFrom(.bodyweight, nameHint: "sit-up"),
        pickFrom(.bodyweight, nameHint: "lunge"),
        pickFrom(.bodyweight, nameHint: "plank"),
        findExercise(nameContains: "hamstring"),
        findExercise(nameContains: "hip"),
        findExercise(nameContains: "stretch")
    ].compactMap { $0 })
    
    func template(name: String, exercises: [Exercise]) -> WorkoutTemplate {
        WorkoutTemplate(
            name: name,
            exercises: exercises.map(makeTemplateExercise)
        )
    }
    
    return [
        template(name: "Push", exercises: push),
        template(name: "Pull", exercises: pull),
        template(name: "Legs", exercises: legs),
        template(name: "Upper", exercises: upper),
        template(name: "Lower", exercises: lower),
        template(name: "Full Body", exercises: fullBody),
        template(name: "Bodyweight/Mobility", exercises: mobility)
    ]
}

var templates = buildInitialTemplates()
// Make template rotation representative of the user's weekly training frequency.
// If we keep 7 templates but the user trains 3–4 days/week, each lift can go >28 days between exposures,
// which triggers the engine's detraining reductions and produces unrealistic behavior.
func selectTemplatesForFrequency(_ templates: [WorkoutTemplate], weeklyFrequency: Int) -> [WorkoutTemplate] {
    guard !templates.isEmpty else { return templates }
    
    func byName(_ name: String) -> WorkoutTemplate? {
        templates.first(where: { $0.name.lowercased() == name.lowercased() })
    }
    
    switch weeklyFrequency {
    case 1...3:
        let preferred = ["Upper", "Lower", "Full Body"]
        let picked = preferred.compactMap(byName)
        if picked.count >= 2 { return picked }
        return Array(templates.prefix(3))
    case 4:
        // More balanced 4x/week split: ensure big lifts get ≥2 exposures per rotation.
        // - Bench is in Upper + Push
        // - Squat/Deadlift are in Lower + Legs
        let preferred = ["Upper", "Lower", "Push", "Legs"]
        let picked = preferred.compactMap(byName)
        if picked.count == 4 { return picked }
        return Array(templates.prefix(4))
    default:
        return templates
    }
}

templates = selectTemplatesForFrequency(templates, weeklyFrequency: weeklyFrequencyTarget)
if templates.isEmpty {
    fputs("FAIL: No templates could be built.\n", stderr)
    exit(1)
}

// Seed lift states for any exercise we might reasonably touch:
// - all exercises in templates
// - substitution pool (bounded)
let seededExerciseIds = Set(templates.flatMap { $0.exercises.map(\.exercise.id) } + subPool.map(\.id))

let simulationStart = noon(laCalendar.date(from: DateComponents(year: 2025, month: 1, day: 1, hour: 12))!)
var liftStates: [String: ExerciseState] = [:]
liftStates.reserveCapacity(seededExerciseIds.count)

// Also keep a "true" e1RM per exercise for generating realistic reps.
var trueE1RM: [String: Double] = [:]
trueE1RM.reserveCapacity(seededExerciseIds.count)

// IMPORTANT: `Set` iteration order is non-deterministic across builds/runs.
// Sort IDs so the RNG draw sequence (and therefore weights/e1RMs) is stable.
for id in seededExerciseIds.sorted() {
    if let ex = allExercises.first(where: { $0.id == id }) {
        var w = initialWorkingWeightLb(for: ex, rng: &rng)
        if let forced = startingOverridesLb[id] {
            w = forced
        }
        liftStates[id] = ExerciseState(
            exerciseId: id,
            currentWorkingWeight: w,
            failuresCount: 0,
            rollingE1RM: (w > 0 ? (w * 1.30) : nil),
            e1rmTrend: .insufficient,
            e1rmHistory: [],
            lastDeloadAt: nil,
            successfulSessionsCount: 0,
            updatedAt: simulationStart
        )
        // Seed "true" e1RM high enough that early sessions are usually completable.
        // (If this is too low, the simulated user immediately fails and the engine correctly deloads into the ground.)
        trueE1RM[id] = max(1, w > 0 ? (w * 1.45) : 120)
    }
}

var sessions: [WorkoutSession] = []
sessions.reserveCapacity(720)

// Synthetic biometrics store (for readinessHistory + today readiness).
// We keep this in-memory for the simulation runner.
var biometricsByDay: [Date: DailyBiometrics] = [:]
biometricsByDay.reserveCapacity(800)

// Simple accumulated fatigue proxy (0..~2). Drives biometrics in the simulation.
var fatigue: Double = 0

// MARK: - Logging / adherence counters (to validate "messy real world" behavior)
var plannedTrainingDaysCount: Int = 0
var missedPlannedTrainingDaysCount: Int = 0
var restDaysCount: Int = 0
var skippedExercisesCount: Int = 0
var droppedSetsCount: Int = 0
var forgottenSetsCount: Int = 0
var manualLoadOverrideCount: Int = 0
var unitMistakeCount: Int = 0
var unsavedSessionsCount: Int = 0
var unitMistakeExamples: [String] = []

struct UnitMistakeEvent {
    let day: Int
    let exerciseId: String
    let priorW: Double
    let planned: Double
    let performed: Double
}

// MARK: - Simulation metrics

struct ExerciseMetrics {
    var plannedOccurrences: Int = 0
    var completedOccurrences: Int = 0
    var loadIncreases: Int = 0
    var loadDecreases: Int = 0
    var repTargetIncreases: Int = 0
    var failures: Int = 0
    var deloadDrops10pctOrMore: Int = 0
    
    var lastPlannedLoad: Double?
    var lastTargetReps: Int?
}

var metricsByExerciseId: [String: ExerciseMetrics] = [:]
metricsByExerciseId.reserveCapacity(512)

enum Phase: String, CaseIterable {
    case baseline
    case homeGym
    case overreach
    case hiatus
    case postHiatus
}

struct PhaseTotals {
    var sessions: Int = 0
    var deloadSessions: Int = 0
    var plannedExercises: Int = 0
    var loadUps: Int = 0
    var loadDowns: Int = 0
    var repUps: Int = 0
    var failures: Int = 0
    var plateauInsights: Int = 0
    var readinessSum: Int = 0
    var readinessCount: Int = 0
    var volumeKgReps: Double = 0
}

var phaseTotals: [Phase: PhaseTotals] = [:]
phaseTotals.reserveCapacity(Phase.allCases.count)

var deloadReasonCounts: [String: Int] = [:]
var insightTopicCounts: [String: Int] = [:]
var loadIncreaseStepHistogramByExerciseId: [String: [Double: Int]] = [:]
var plateauExamples: [String] = []

func recordPlanMetrics(exerciseId: String, plannedLoad: Double, targetReps: Int, phase: Phase) {
    var m = metricsByExerciseId[exerciseId] ?? ExerciseMetrics()
    m.plannedOccurrences += 1
    phaseTotals[phase, default: PhaseTotals()].plannedExercises += 1
    if let last = m.lastPlannedLoad {
        if plannedLoad > last + 1e-9 {
            m.loadIncreases += 1
            phaseTotals[phase, default: PhaseTotals()].loadUps += 1
            
            let delta = roundTo(plannedLoad - last, step: 0.5)
            var hist = loadIncreaseStepHistogramByExerciseId[exerciseId] ?? [:]
            hist[delta, default: 0] += 1
            loadIncreaseStepHistogramByExerciseId[exerciseId] = hist
        }
        if plannedLoad + 1e-9 < last {
            m.loadDecreases += 1
            phaseTotals[phase, default: PhaseTotals()].loadDowns += 1
        }
        if last > 0, plannedLoad <= last * 0.89 { m.deloadDrops10pctOrMore += 1 } // ~10% drop
    }
    if let lastR = m.lastTargetReps, targetReps > lastR {
        m.repTargetIncreases += 1
        phaseTotals[phase, default: PhaseTotals()].repUps += 1
    }
    m.lastPlannedLoad = plannedLoad
    m.lastTargetReps = targetReps
    metricsByExerciseId[exerciseId] = m
}

func recordOutcome(exerciseId: String, phase: Phase, wasCompleted: Bool, wasSuccess: Bool) {
    var m = metricsByExerciseId[exerciseId] ?? ExerciseMetrics()
    if wasCompleted { m.completedOccurrences += 1 }
    if !wasSuccess {
        m.failures += 1
        phaseTotals[phase, default: PhaseTotals()].failures += 1
    }
    metricsByExerciseId[exerciseId] = m
}

// Keep a small narrative trace for a few canonical exercises.
let tracedIds: [String] = stableUnique([
    bench?.id,
    squat?.id,
    deadlift?.id,
    pullup?.id
].compactMap { $0 })

var traceLines: [String] = []
traceLines.reserveCapacity(200)

func maybeTrace(day: Int, sessionPlan: SessionPlan, performedSession: WorkoutSession) {
    // Print compact checkpoints every ~60 days and on failure clusters.
    let checkpoint = (day % 60 == 0)
    
    // Detect any exercise failures today.
    var anyFailure = false
    for ex in performedSession.exercises {
        let lb = ex.repRangeMin
        let working = ex.sets.filter { $0.isCompleted && $0.reps > 0 }
        if !working.isEmpty && working.contains(where: { $0.reps < lb }) {
            anyFailure = true
            break
        }
    }
    
    guard checkpoint || anyFailure else { return }
    
    var parts: [String] = []
    parts.append("d=\(day)")
    parts.append("template=\(performedSession.name)")
    parts.append("deload=\(sessionPlan.isDeload ? "Y" : "N")")
    if sessionPlan.isDeload, let reason = sessionPlan.deloadReason?.rawValue {
        parts.append("reason=\(reason)")
    }
    
    for id in tracedIds {
        if let exPlan = sessionPlan.exercises.first(where: { $0.exercise.id == id }) {
            let load = exPlan.sets.first?.targetLoad.converted(to: .pounds).value ?? 0
            let reps = exPlan.sets.first?.targetReps ?? 0
            parts.append("\(id)=\(Int(load))x\(reps)")
        }
    }
    
    traceLines.append(parts.joined(separator: " "))
}

// MARK: - Main simulation

let totalWorkouts = parseTotalWorkouts(defaultValue: 720)

// Track consecutive failures per exercise to confirm “too hard” behavior and deload response.
var consecutiveFailures: [String: Int] = [:]

for workoutIndex in 0..<totalWorkouts {
    let date = noon(laCalendar.date(byAdding: .day, value: workoutIndex, to: simulationStart)!)
    let dayStart = laCalendar.startOfDay(for: date)
    
    // Phases to stress edge cases.
    // - 0..239: commercial gym, normal variability
    // - 240..319: home gym (forces substitutions away from barbells/machines/cables)
    // - 320..399: commercial + "overreach" period (forced failures on big lifts)
    // - 400..439: hiatus (no training) → detraining reduction
    // - 440..719: commercial with monthly exercise rotations and rep-range tweaks
    // Phase durations scale with run length, but also vary by archetype.
    // Some users should be mostly "steady state" (novice bulk), while others are stress tests (advanced/busy).
    let phaseFractions: (baseline: Double, homeGym: Double, overreach: Double, hiatus: Double) = {
        switch archetype {
        case .noviceBulk:
            return (baseline: 0.60, homeGym: 0.10, overreach: 0.05, hiatus: 0.00)
        case .intermediateCut:
            return (baseline: 0.50, homeGym: 0.10, overreach: 0.10, hiatus: 0.05)
        case .advancedStrength:
            return (baseline: 0.33, homeGym: 0.11, overreach: 0.11, hiatus: 0.055)
        case .busyParentMessy:
            return (baseline: 0.40, homeGym: 0.05, overreach: 0.07, hiatus: 0.10)
        case .homeGymMinimal:
            return (baseline: 0.50, homeGym: 0.00, overreach: 0.08, hiatus: 0.05)
        case .dailyMaxVariety:
            return (baseline: 0.35, homeGym: 0.10, overreach: 0.12, hiatus: 0.03)
        }
    }()
    
    let baselineDays = max(60, Int(Double(totalWorkouts) * phaseFractions.baseline))
    let homeGymDays: Int = (phaseFractions.homeGym > 0) ? max(14, Int(Double(totalWorkouts) * phaseFractions.homeGym)) : 0
    let overreachDays: Int = (phaseFractions.overreach > 0) ? max(14, Int(Double(totalWorkouts) * phaseFractions.overreach)) : 0
    let hiatusDays: Int = (phaseFractions.hiatus > 0) ? max(14, Int(Double(totalWorkouts) * phaseFractions.hiatus)) : 0
    
    let baselineEnd = baselineDays
    let homeGymEnd = baselineEnd + homeGymDays
    let overreachEnd = homeGymEnd + overreachDays
    let hiatusEnd = overreachEnd + hiatusDays
    
    let phase: Phase = {
        switch workoutIndex {
        case 0..<baselineEnd: return .baseline
        case baselineEnd..<homeGymEnd: return .homeGym
        case homeGymEnd..<overreachEnd: return .overreach
        case overreachEnd..<hiatusEnd: return .hiatus
        default: return .postHiatus
        }
    }()
    
    let gymType: GymType = {
        // Archetype-specific equipment context:
        // - homeGymMinimal: always home gym
        // - others: mimic earlier "commercial -> home gym outage -> commercial" pattern
        switch archetype {
        case .homeGymMinimal:
            return .homeGym
        default:
            switch phase {
            case .homeGym:
                return .homeGym
            default:
                return .commercial
            }
        }
    }()
    
    // Hiatus: intentionally skip training to test detraining reductions (Engine has 28/56/84-day tiers).
    if phase == .hiatus {
        // Recovery during a break.
        fatigue = max(0, fatigue * 0.85)
        // Still generate biometrics for the day so readiness history isn't sparse.
        let sleep = 450.0 + Double(rng.int(in: -15...15))
        let hrv = 60.0 + Double(rng.int(in: -5...5))
        let rhr = 52.0 + Double(rng.int(in: -3...3))
        biometricsByDay[dayStart] = DailyBiometrics(
            date: dayStart,
            sleepMinutes: sleep,
            hrvSDNN: hrv,
            restingHR: rhr,
            activeEnergy: nil,
            steps: nil
        )
        continue
    }
    
    // Simulate periodic exercise selection changes (swap 2 accessory exercises every 30 days) after hiatus.
    if phase == .postHiatus, workoutIndex > 0, workoutIndex % 30 == 0 {
        // For each template, swap the last 2 exercises to new ones of similar equipment (best-effort).
        for tIdx in templates.indices {
            var t = templates[tIdx]
            if t.exercises.count < 4 { continue }
            let keepCount = max(1, t.exercises.count - 2)
            let kept = Array(t.exercises.prefix(keepCount))
            
            // Choose replacements from the same equipment buckets as the dropped ones, else random.
            let dropped = Array(t.exercises.suffix(t.exercises.count - keepCount))
            var replacements: [WorkoutTemplateExercise] = []
            for d in dropped {
                let eq = TrainingEngineBridge.mapEquipment(d.exercise.equipment)
                let candidate = pickFrom(eq) ?? rng.pick(allExercises)
                if let candidate {
                    replacements.append(makeTemplateExercise(candidate))
                    // Seed state for new exercises so we don’t get stuck at 0 lb forever.
                    if liftStates[candidate.id] == nil {
                        let w = initialWorkingWeightLb(for: candidate, rng: &rng)
                        liftStates[candidate.id] = ExerciseState(exerciseId: candidate.id, currentWorkingWeight: w, failuresCount: 0, updatedAt: date)
                        trueE1RM[candidate.id] = max(1, w > 0 ? (w * 1.40) : 120)
                    }
                }
            }
            t.exercises = kept + replacements
            t.updatedAt = date
            templates[tIdx] = t
        }
    }
    
    // Periodic protocol tweak to simulate user editing templates (every 60 days, post-hiatus only).
    if phase == .postHiatus, workoutIndex > 0, workoutIndex % 60 == 0 {
        // Pick one template and adjust protocol slightly:
        // - widen rep ranges (rep-based progression)
        // - shorten rests a bit (overload via density)
        // - occasionally add a slower eccentric (tempo overload)
        let tIdx = rng.int(in: 0...(templates.count - 1))
        var t = templates[tIdx]
        for eIdx in t.exercises.indices {
            var te = t.exercises[eIdx]
            // Only adjust non-barbell accessories.
            let eq = TrainingEngineBridge.mapEquipment(te.exercise.equipment)
            if eq == .barbell { continue }
            te.repRangeMin = max(3, te.repRangeMin + 1)
            te.repRangeMax = max(te.repRangeMin, te.repRangeMax + 2)
            
            // Shorten rest slightly (bounded).
            te.restSeconds = max(45, te.restSeconds - 15)
            
            // Occasionally make tempo stricter (bounded).
            if rng.bool(p: 0.35) {
                te.tempo = TempoSpec(
                    eccentric: min(4, te.tempo.eccentric + 1),
                    pauseBottom: min(2, te.tempo.pauseBottom + (rng.bool(p: 0.5) ? 1 : 0)),
                    concentric: te.tempo.concentric,
                    pauseTop: te.tempo.pauseTop
                )
            }
            t.exercises[eIdx] = te
            break
        }
        t.updatedAt = date
        templates[tIdx] = t
    }
    
    // Update fatigue (daily decay) and synthesize today's biometrics.
    fatigue = max(0, fatigue * 0.92)
    
    // Overreach block: make biometrics worse (sleep down, HRV down, RHR up) to create low readiness streaks.
    let overreach = (phase == .overreach)
    let fatigueBump = overreach ? 0.25 : 0.0
    fatigue = min(2.0, fatigue + fatigueBump)
    
    let sleepMinutes = max(300.0, min(540.0, 420.0 - (fatigue * 70.0) + Double(rng.int(in: -25...25))))
    let hrvMs = max(20.0, min(90.0, 55.0 - (fatigue * 18.0) + Double(rng.int(in: -6...6))))
    let restingHr = max(40.0, min(85.0, 55.0 + (fatigue * 8.0) + Double(rng.int(in: -3...3))))
    
    biometricsByDay[dayStart] = DailyBiometrics(
        date: dayStart,
        sleepMinutes: sleepMinutes,
        hrvSDNN: hrvMs,
        restingHR: restingHr,
        activeEnergy: nil,
        steps: nil
    )
    
    let recentBiometrics = biometricsByDay
        .filter { $0.key <= dayStart }
        .sorted { $0.key < $1.key }
        .suffix(60)
        .map { $0.value }
    
    // Compute readiness from biometrics so the engine can use it (and its history) deterministically.
    let readiness = ReadinessScoreCalculator.todayScore(from: Array(recentBiometrics), referenceDate: date, calendar: laCalendar) ?? 75
    
    // Training-day gating (to simulate realistic weekly frequency + inconsistent adherence).
    //
    // NOTE: The engine's rotation schedule advances only when sessions exist (WorkoutHistory.nextTemplateInRotation),
    // so skipping a day is a good proxy for "missed workout" without accidentally fast-forwarding the split.
    let isPlannedTrainingDay: Bool = {
        // Create a deterministic week pattern anchored on the simulation start.
        let weekday = laCalendar.component(.weekday, from: dayStart) // 1..7
        
        func isTrainingDayForFrequency(_ freq: Int) -> Bool {
            switch freq {
            case 7: return true
            case 6: return weekday != 1
            case 5: return weekday != 1 && weekday != 7
            case 4: return weekday == 2 || weekday == 3 || weekday == 5 || weekday == 6
            case 3: return weekday == 2 || weekday == 4 || weekday == 6
            default:
                return weekday == 2 || weekday == 5
            }
        }
        
        // Most archetypes: follow target frequency.
        // homeGymMinimal: keep frequency lower and stable.
        return isTrainingDayForFrequency(weeklyFrequencyTarget)
    }()
    
    // If today isn't a planned training day, or the user "misses" the workout, skip logging a session
    // but still log biometrics so readiness history is realistic.
    if isPlannedTrainingDay {
        plannedTrainingDaysCount += 1
    } else {
        restDaysCount += 1
    }
    let adherenceRoll = rng.bool(p: loggingStyle.adherence)
    if isPlannedTrainingDay && !adherenceRoll {
        missedPlannedTrainingDaysCount += 1
    }
    let willTrainToday = isPlannedTrainingDay && adherenceRoll
    if !willTrainToday {
        // Still accumulate some recovery noise:
        fatigue = max(0, fatigue * 0.95)
        continue
    }
    
    // From here on, we will actually log a training session today.
    phaseTotals[phase, default: PhaseTotals()].sessions += 1
    phaseTotals[phase, default: PhaseTotals()].readinessSum += readiness
    phaseTotals[phase, default: PhaseTotals()].readinessCount += 1
    
    // User profile for the bridge.
    var profile = UserProfile()
    profile.sex = .male
    profile.age = 28
    profile.workoutExperience = baseExperience
    profile.goals = goalSet
    profile.weeklyFrequency = weeklyFrequencyTarget
    profile.gymType = gymType
    profile.bodyWeightLbs = baseBodyWeightLbs
    
    // Nutrition/sleep archetype knobs.
    profile.dailyProteinGrams = {
        switch archetype {
        case .intermediateCut: return 170
        case .advancedStrength: return 185
        case .busyParentMessy: return 135
        case .homeGymMinimal: return 140
        case .noviceBulk: return 155
        case .dailyMaxVariety: return 175
        }
    }()
    profile.sleepHours = {
        switch archetype {
        case .busyParentMessy: return 6.2
        case .intermediateCut: return 7.0
        case .dailyMaxVariety: return 7.3
        default: return 7.2
        }
    }()
    
    // Bodyweight trend proxy (bulk/cut/maintain).
    // This is used by the progression system for relative-strength scaling today,
    // and later will be used for expectation-setting.
    let bwDeltaTotal: Double = {
        switch archetype {
        case .noviceBulk: return 8.0
        case .intermediateCut: return -10.0
        case .advancedStrength: return 1.0
        case .busyParentMessy: return 0.0
        case .homeGymMinimal: return 2.0
        case .dailyMaxVariety: return 4.0
        }
    }()
    profile.bodyWeightLbs = (profile.bodyWeightLbs ?? baseBodyWeightLbs) + (bwDeltaTotal * (Double(workoutIndex) / Double(max(1, totalWorkouts))))
    
    // Recommend a session via the bridge (this is the “integrated system” path).
    let plan = TrainingEngineBridge.recommendSession(
        date: date,
        userProfile: profile,
        templates: templates,
        sessions: sessions,
        liftStates: liftStates,
        readiness: readiness,
        substitutionPool: subPool,
        dailyBiometrics: Array(recentBiometrics),
        calendar: laCalendar
    )

    if plan.isDeload {
        phaseTotals[phase, default: PhaseTotals()].deloadSessions += 1
        if let reason = plan.deloadReason?.rawValue {
            deloadReasonCounts[reason, default: 0] += 1
        } else {
            deloadReasonCounts["(none)", default: 0] += 1
        }
    }
    
    // Track coaching insights (plateau/recovery/etc).
    if !plan.insights.isEmpty {
        for ins in plan.insights {
            insightTopicCounts[ins.topic.rawValue, default: 0] += 1
            if ins.topic == .plateau {
                phaseTotals[phase, default: PhaseTotals()].plateauInsights += 1
                if plateauExamples.count < 8 {
                    let exId = ins.relatedExerciseId ?? "(none)"
                    plateauExamples.append("d=\(workoutIndex) ex=\(exId) title=\(ins.title)")
                }
            }
        }
    }
    
    let templateName: String = {
        if let id = plan.templateId, let t = templates.first(where: { $0.id == id }) { return t.name }
        return templates.first?.name ?? "Workout"
    }()
    
    var baseSession = TrainingEngineBridge.convertSessionPlanToUIModel(
        plan,
        templateId: plan.templateId,
        templateName: templateName
    )
    baseSession.startedAt = date
    baseSession.endedAt = laCalendar.date(byAdding: .minute, value: max(20, min(120, plan.estimatedDurationMinutes)), to: date)
    
    // We explicitly split:
    // - performedSession: what the user actually did (drives fatigue + true e1RM adaptation)
    // - loggedSession: what the engine sees (may miss sets/exercises due to logging messiness)
    var performedSession = baseSession
    var loggedSession = baseSession
    var pendingUnitMistakes: [UnitMistakeEvent] = []
    pendingUnitMistakes.reserveCapacity(2)
    
    // Apply performance simulation: generate realistic reps based on a "true" e1RM model,
    // and intentionally force some big-lift failures during the overreach block.
    for exIdx in performedSession.exercises.indices {
        var performedPerf = performedSession.exercises[exIdx]
        var loggedPerf = loggedSession.exercises[exIdx]
        let exerciseId = performedPerf.exercise.id
        let eq = TrainingEngineBridge.mapEquipment(performedPerf.exercise.equipment)
        
        // Pull the planned load/reps from the engine plan (same order as UI conversion).
        guard exIdx < plan.exercises.count else { continue }
        let plannedEx = plan.exercises[exIdx]
        let plannedLoadLb = plannedEx.sets.first?.targetLoad.converted(to: .pounds).value ?? 0
        let targetReps = plannedEx.sets.first?.targetReps ?? performedPerf.repRangeMin
        
        recordPlanMetrics(exerciseId: exerciseId, plannedLoad: plannedLoadLb, targetReps: targetReps, phase: phase)
        
        // Ensure we have a "true" e1RM baseline for modeling.
        if trueE1RM[exerciseId] == nil {
            trueE1RM[exerciseId] = max(1, plannedLoadLb > 0 ? plannedLoadLb * 1.40 : 120)
        }
        
        // If the engine suggests 0 lb for a non-bodyweight lift, simulate the user entering a starting weight.
        let effectivePlannedLoadLb: Double = {
            if eq != .bodyweight && plannedLoadLb <= 0.0001 {
                // Pick a starting weight and persist it by logging it.
                let guessed = initialWorkingWeightLb(
                    for: Exercise(id: performedPerf.exercise.id, name: performedPerf.exercise.name, bodyPart: performedPerf.exercise.bodyPart, equipment: performedPerf.exercise.equipment, gifUrl: nil, target: performedPerf.exercise.target, secondaryMuscles: [], instructions: []),
                    rng: &rng
                )
                return max(5, guessed)
            }
            return plannedLoadLb
        }()
        
        let lb = performedPerf.repRangeMin
        let ub = performedPerf.repRangeMax
        
        let isBigLift = (exerciseId == bench?.id || exerciseId == squat?.id || exerciseId == deadlift?.id)
        
        // Occasionally skip accessories entirely (busy/messy logging).
        if !isBigLift && rng.bool(p: loggingStyle.skipExerciseProb) {
            skippedExercisesCount += 1
            for setIdx in performedPerf.sets.indices {
                var pSet = performedPerf.sets[setIdx]
                pSet.isCompleted = false
                pSet.reps = 0
                pSet.rirObserved = nil
                pSet.rpeObserved = nil
                performedPerf.sets[setIdx] = pSet
                
                var lSet = loggedPerf.sets[setIdx]
                lSet.isCompleted = false
                lSet.reps = 0
                lSet.rirObserved = nil
                lSet.rpeObserved = nil
                loggedPerf.sets[setIdx] = lSet
            }
            performedPerf.isCompleted = false
            loggedPerf.isCompleted = false
            performedSession.exercises[exIdx] = performedPerf
            loggedSession.exercises[exIdx] = loggedPerf
            
            // Don't treat "skipped" as a performance failure (engine will ignore empty working sets).
            recordOutcome(exerciseId: exerciseId, phase: phase, wasCompleted: false, wasSuccess: true)
            continue
        }
        
        // Simulate the user occasionally overriding load (ego/sandbag/unit mistake).
        var didUnitMistake = false
        var didManualOverride = false
        var performedLoadLb: Double = effectivePlannedLoadLb
        if eq == .bodyweight {
            performedLoadLb = 0
        } else {
            // Rare, severe entry mistake (kg↔lb confusion).
            if rng.bool(p: loggingStyle.unitMistakeProb) {
                didUnitMistake = true
                // 50/50: accidentally convert in the wrong direction.
                performedLoadLb *= rng.bool(p: 0.5) ? 2.20462 : 0.453592
            } else if rng.bool(p: loggingStyle.egoLoadProb) {
                didManualOverride = true
                performedLoadLb *= (1.0 + (rng.nextDouble01() * loggingStyle.egoMaxPct))
            } else if rng.bool(p: loggingStyle.sandbagLoadProb) {
                didManualOverride = true
                performedLoadLb *= max(0.0, (1.0 - (rng.nextDouble01() * loggingStyle.sandbagMaxPct)))
            }
            performedLoadLb = roundLoadLbForEquipment(performedLoadLb, equipment: eq)
        }
        
        if didUnitMistake { unitMistakeCount += 1 }
        if didUnitMistake, unitMistakeExamples.count < 10 {
            let priorW = liftStates[exerciseId]?.currentWorkingWeight ?? 0
            pendingUnitMistakes.append(
                UnitMistakeEvent(
                    day: workoutIndex,
                    exerciseId: exerciseId,
                    priorW: priorW,
                    planned: effectivePlannedLoadLb,
                    performed: performedLoadLb
                )
            )
        }
        if didManualOverride && abs(performedLoadLb - effectivePlannedLoadLb) > 0.0001 {
            manualLoadOverrideCount += 1
        }
        
        // Force a plateau/failure cluster on big lifts during overreach block.
        let forceFail = isBigLift && overreach && rng.bool(p: 0.18)
        
        var bestE1RMSet: (w: Double, r: Int) = (0, 0)
        var anyWorkingSetPerformed = false
        var anyWorkingSetLogged = false
        var successPerformed = true
        
        for setIdx in performedPerf.sets.indices {
            var performedSet = performedPerf.sets[setIdx]
            var loggedSet = loggedPerf.sets[setIdx]
            
            // Keep weight stable per exercise for simplicity.
            performedSet.weight = performedLoadLb
            loggedSet.weight = performedLoadLb
            
            let e1rm = trueE1RM[exerciseId] ?? max(1, max(1, performedLoadLb) * 1.40)
            let baseExpected = expectedReps(weight: performedLoadLb, e1rm: e1rm)
            
            // Convert readiness → a performance cap (max reps possible at this weight today).
            //
            // Key modeling choice:
            // - The user still *tries* to hit the target reps.
            // - Low readiness primarily reduces *capacity*, not intent (we avoid "doing 1 rep on purpose").
            let readinessPenalty: Int = {
                if readiness < 35 { return rng.int(in: 3...5) }
                if readiness < 50 { return rng.int(in: 2...4) }
                if readiness < 65 { return rng.int(in: 1...3) }
                if readiness < 80 { return rng.int(in: 0...2) }
                return rng.int(in: 0...1)
            }()
            
            // Protocol modifiers:
            // - Shorter rest tends to reduce capacity (especially on multi-set accessories).
            // - Slower tempos increase time-under-tension and usually reduce max reps at a given load.
            let restPenalty: Int = {
                if performedPerf.restSeconds >= 150 { return 0 }
                if performedPerf.restSeconds >= 120 { return rng.int(in: 0...1) }
                if performedPerf.restSeconds >= 90 { return rng.int(in: 1...2) }
                if performedPerf.restSeconds >= 60 { return rng.int(in: 2...3) }
                return rng.int(in: 3...4)
            }()
            let tempoTotal = performedPerf.tempo.eccentric + performedPerf.tempo.pauseBottom + performedPerf.tempo.concentric + performedPerf.tempo.pauseTop
            let tempoPenalty: Int = {
                // Standard is 2-0-1-0 -> 3 sec/rep. Penalize each extra second modestly.
                let extra = max(0, tempoTotal - 3)
                return min(4, extra)
            }()
            
            let performanceCap = max(0, baseExpected - readinessPenalty - restPenalty - tempoPenalty + rng.int(in: -1...1))
            
            let achievedReps: Int = {
                if forceFail && setIdx == 0 {
                    // Occasionally miss the first (top) set during overreach (more realistic than failing every set).
                    return max(0, min(performanceCap, lb - rng.int(in: 1...3)))
                }
                
                // If the user has capacity to hit the target, they usually stop at the target (with small overshoot).
                if performanceCap >= targetReps {
                    // Sometimes the user stops early (under-effort) even though they could do more.
                    if rng.bool(p: loggingStyle.undershootRepsProb) {
                        // Under-effort should usually still stay within the programmed rep floor.
                        // If the user can hit the target, they rarely undershoot below the *minimum*.
                        let undershoot = targetReps - rng.int(in: 0...2)
                        return max(0, min(ub + 4, max(lb, undershoot)))
                    }
                    
                    // Sometimes they push to (near) failure.
                    if rng.bool(p: loggingStyle.toFailureProb) {
                        return max(0, min(ub + 4, performanceCap))
                    }
                    
                    let bonus: Int = {
                        if readiness >= 85 { return rng.int(in: 0...3) }
                        if readiness >= 70 { return rng.int(in: 0...2) }
                        return rng.int(in: 0...1)
                    }()
                    return max(0, min(ub + 4, min(performanceCap, targetReps + bonus)))
                }
                
                // Otherwise, fail near capacity (but often still within the rep range floor).
                return max(0, min(ub + 4, performanceCap + rng.int(in: -1...0)))
            }()
            
            // Messy logging / time crunch:
            // - sometimes the last set is dropped
            // - sometimes a set isn't logged (marked incomplete)
            let droppedByTime = (setIdx == performedPerf.sets.count - 1) && rng.bool(p: loggingStyle.dropLastSetProb)
            let forgotten = rng.bool(p: loggingStyle.forgetSetProb)
            if droppedByTime { droppedSetsCount += 1 }
            if forgotten { forgottenSetsCount += 1 }
            
            // Rare aborted set (bounded).
            let aborted = rng.bool(p: 0.02)
            let performedCompleted = achievedReps > 0 && !droppedByTime && !aborted
            let loggedCompleted = performedCompleted && !forgotten
            
            performedSet.isCompleted = performedCompleted
            performedSet.reps = performedCompleted ? achievedReps : 0
            
            loggedSet.isCompleted = loggedCompleted
            loggedSet.reps = loggedCompleted ? achievedReps : 0
            
            // Optional RIR/RPE logging.
            loggedSet.rirObserved = nil
            loggedSet.rpeObserved = nil
            if loggedCompleted && achievedReps > 0 {
                let rirEstimate = max(0, performanceCap - achievedReps)
                if rng.bool(p: loggingStyle.logRIRProb) {
                    loggedSet.rirObserved = min(10, rirEstimate)
                } else if rng.bool(p: loggingStyle.logRPEProb) {
                    let noise = Double(rng.int(in: -1...1)) * 0.3
                    let rpe = max(1.0, min(10.0, 10.0 - Double(rirEstimate) + noise))
                    loggedSet.rpeObserved = rpe
                }
            }
            performedSet.rirObserved = nil
            performedSet.rpeObserved = nil
            
            performedPerf.sets[setIdx] = performedSet
            loggedPerf.sets[setIdx] = loggedSet
            
            if performedCompleted && achievedReps > 0 {
                anyWorkingSetPerformed = true
                let e = E1RMCalculator.brzycki(weight: performedLoadLb, reps: achievedReps)
                if e > E1RMCalculator.brzycki(weight: bestE1RMSet.w, reps: bestE1RMSet.r) {
                    bestE1RMSet = (performedLoadLb, achievedReps)
                }
                if achievedReps < lb {
                    successPerformed = false
                }
            }
            if loggedCompleted && achievedReps > 0 {
                anyWorkingSetLogged = true
            }
        }
        
        // If there were no completed sets, treat it as a “non-completed” exercise (don’t penalize too hard).
        if !anyWorkingSetPerformed {
            successPerformed = false
        }
        
        performedPerf.isCompleted = anyWorkingSetPerformed
        loggedPerf.isCompleted = anyWorkingSetLogged
        performedSession.exercises[exIdx] = performedPerf
        loggedSession.exercises[exIdx] = loggedPerf
        
        // Update failure streak tracking.
        if successPerformed {
            consecutiveFailures[exerciseId] = 0
        } else {
            consecutiveFailures[exerciseId] = (consecutiveFailures[exerciseId] ?? 0) + 1
        }
        
        recordOutcome(exerciseId: exerciseId, phase: phase, wasCompleted: anyWorkingSetPerformed, wasSuccess: successPerformed)
        
        // Update the “true” e1RM to mimic muscle gain / fatigue.
        let prior = trueE1RM[exerciseId] ?? 100
        trueE1RM[exerciseId] = updateTrueE1RM(
            prior: prior,
            bestSetWeight: bestE1RMSet.w,
            bestSetReps: bestE1RMSet.r,
            readiness: readiness,
            wasSuccess: successPerformed,
            experience: baseExperience
        )
    }
    
    // Persist the session into history by updating lift states (bridge path) and appending session.
    // Some archetypes occasionally "don't save" the session (engine never sees it).
    let saveSession = !rng.bool(p: loggingStyle.sessionNotSavedProb)
    if saveSession {
        liftStates = TrainingEngineBridge.updateLiftStates(afterSession: loggedSession, previousLiftStates: liftStates)
        sessions.insert(loggedSession, at: 0)
    } else {
        unsavedSessionsCount += 1
    }
    
    if !pendingUnitMistakes.isEmpty, unitMistakeExamples.count < 10 {
        for ev in pendingUnitMistakes {
            guard unitMistakeExamples.count < 10 else { break }
            let updatedW: Double? = saveSession ? liftStates[ev.exerciseId]?.currentWorkingWeight : nil
            let ratio = (ev.priorW > 0) ? (ev.performed / ev.priorW) : 0
            let updatedStr = updatedW.map { String(format: "%.1f", $0) } ?? "(unsaved)"
            unitMistakeExamples.append(
                "d=\(ev.day) ex=\(ev.exerciseId) prior=\(String(format: "%.1f", ev.priorW)) planned=\(String(format: "%.1f", ev.planned)) performed=\(String(format: "%.1f", ev.performed)) ratio=\(String(format: "%.3f", ratio)) updated=\(updatedStr)"
            )
        }
    }

    // Update fatigue based on how demanding the session was.
    // Use (kg*reps) volume and penalize failures; deload sessions count as reduced stress.
    var sessionVolumeKgReps = 0.0
    var anyFailure = false
    for ex in performedSession.exercises {
        let lb = ex.repRangeMin
        let working = ex.sets.filter { $0.isCompleted && $0.reps > 0 }
        if !working.isEmpty && working.contains(where: { $0.reps < lb }) {
            anyFailure = true
        }
        for set in working {
            sessionVolumeKgReps += (set.weight * 0.453592) * Double(set.reps)
        }
    }
    
    phaseTotals[phase, default: PhaseTotals()].volumeKgReps += sessionVolumeKgReps
    
    let volumeStress = min(1.0, sessionVolumeKgReps / 8000.0)
    let failureStress = anyFailure ? 0.25 : 0.0
    let deloadRelief = performedSession.wasDeload ? 0.35 : 0.0
    fatigue = min(2.0, max(0, fatigue + (volumeStress * 0.75) + failureStress - deloadRelief))
    
    // Minimal invariants on updated states.
    for st in liftStates.values {
        if !st.currentWorkingWeight.isFinite || st.currentWorkingWeight < 0 {
            fputs("FAIL: Non-finite or negative working weight for \(st.exerciseId): \(st.currentWorkingWeight)\n", stderr)
            exit(1)
        }
        if st.failuresCount < 0 {
            fputs("FAIL: Negative failuresCount for \(st.exerciseId): \(st.failuresCount)\n", stderr)
            exit(1)
        }
    }
    
    maybeTrace(day: workoutIndex, sessionPlan: plan, performedSession: performedSession)
}

// MARK: - Results

let uniqueExercisesTouched = metricsByExerciseId.keys.count
let totalPlannedExercises = metricsByExerciseId.values.reduce(0) { $0 + $1.plannedOccurrences }
let totalFailures = metricsByExerciseId.values.reduce(0) { $0 + $1.failures }
let totalLoadUps = metricsByExerciseId.values.reduce(0) { $0 + $1.loadIncreases }
let totalLoadDowns = metricsByExerciseId.values.reduce(0) { $0 + $1.loadDecreases }
let total10pctDrops = metricsByExerciseId.values.reduce(0) { $0 + $1.deloadDrops10pctOrMore }

print("✅ Two-year daily simulation complete (integrated IronForge ↔ TrainingEngine).")
print("  Scenario: \(scenarioName)")
if let b = bench?.id, let s = squat?.id, let d = deadlift?.id {
    let b0 = startingOverridesLb[b].map { String(format: "%.0f", $0) } ?? "var"
    let s0 = startingOverridesLb[s].map { String(format: "%.0f", $0) } ?? "var"
    let d0 = startingOverridesLb[d].map { String(format: "%.0f", $0) } ?? "var"
    print("  Starting big lifts (lb): bench=\(b0), squat=\(s0), deadlift=\(d0)")
}
print("  Workouts simulated: \(totalWorkouts)")
print("  Sessions recorded (saved): \(sessions.count)")
print("  Planned training days: \(plannedTrainingDaysCount) (missed planned: \(missedPlannedTrainingDaysCount), rest days: \(restDaysCount))")
if unsavedSessionsCount > 0 {
    print("  Unsaved sessions (engine never saw): \(unsavedSessionsCount)")
}
if skippedExercisesCount > 0 || droppedSetsCount > 0 || forgottenSetsCount > 0 {
    print("  Logging messiness: skippedExercises=\(skippedExercisesCount) droppedSets=\(droppedSetsCount) forgottenSets=\(forgottenSetsCount)")
}
if manualLoadOverrideCount > 0 || unitMistakeCount > 0 {
    print("  Manual load overrides: \(manualLoadOverrideCount) (unit mistakes: \(unitMistakeCount))")
}
if !unitMistakeExamples.isEmpty {
    print("  Unit mistake examples (bounded):")
    for x in unitMistakeExamples { print("    \(x)") }
}
print("  Unique exercises touched: \(uniqueExercisesTouched)")
print("  Planned exercise occurrences: \(totalPlannedExercises)")
print("  Failures (any set below rep floor or no completed sets): \(totalFailures)")
print("  Dial-ups: load increases=\(totalLoadUps), rep-target increases=\(metricsByExerciseId.values.reduce(0) { $0 + $1.repTargetIncreases })")
print("  Dial-downs: load decreases=\(totalLoadDowns) (≈10% deload drops counted=\(total10pctDrops))")

if !deloadReasonCounts.isEmpty {
    let totalDeloads = deloadReasonCounts.values.reduce(0, +)
    print("  Deload sessions: \(totalDeloads)")
    for (k, v) in deloadReasonCounts.sorted(by: { $0.key < $1.key }) {
        print("    \(k): \(v)")
    }
}

if !insightTopicCounts.isEmpty {
    let totalInsights = insightTopicCounts.values.reduce(0, +)
    print("  Coaching insights emitted: \(totalInsights)")
    for (k, v) in insightTopicCounts.sorted(by: { $0.key < $1.key }) {
        print("    \(k): \(v)")
    }
    if !plateauExamples.isEmpty {
        print("  Plateau examples (bounded):")
        for x in plateauExamples { print("    \(x)") }
    }
}

print("  Phase breakdown:")
for p in Phase.allCases {
    let t = phaseTotals[p] ?? PhaseTotals()
    let avgReadiness = t.readinessCount > 0 ? (Double(t.readinessSum) / Double(t.readinessCount)) : 0
    let avgVol = t.sessions > 0 ? (t.volumeKgReps / Double(t.sessions)) : 0
    print("    \(p.rawValue): sessions=\(t.sessions) deloads=\(t.deloadSessions) plannedEx=\(t.plannedExercises) loadUps=\(t.loadUps) loadDowns=\(t.loadDowns) repUps=\(t.repUps) failures=\(t.failures) plateauInsights=\(t.plateauInsights) avgReadiness=\(String(format: "%.1f", avgReadiness)) avgVolKgReps=\(String(format: "%.0f", avgVol))")
}

// Showcase a few traced lifts (start/end weights from liftStates).
if !tracedIds.isEmpty {
    print("  Showcase (final working weights):")
    for id in tracedIds {
        let w = liftStates[id]?.currentWorkingWeight ?? 0
        print("    \(id): \(String(format: "%.1f", w)) lb")
    }
}

// Increment histograms for big lifts (what step sizes did we actually use?).
func printHistogram(for id: String, label: String) {
    guard let hist = loadIncreaseStepHistogramByExerciseId[id], !hist.isEmpty else { return }
    let parts = hist.sorted(by: { $0.key < $1.key }).map { "\($0.key):\($0.value)" }.joined(separator: " ")
    print("  \(label) load increment histogram (lb): \(parts)")
}
if let id = bench?.id { printHistogram(for: id, label: "Bench") }
if let id = squat?.id { printHistogram(for: id, label: "Squat") }
if let id = deadlift?.id { printHistogram(for: id, label: "Deadlift") }

print("  Trace (checkpoints + failure days):")
for line in traceLines.prefix(60) { // keep bounded
    print("    \(line)")
}

