# TrainingEngine Progression Specification

This document explains the algorithms implemented in the `TrainingEngine` Swift module for workout progression, deload logic, and exercise substitutions.

## Design Philosophy

The TrainingEngine is designed around three core principles:

1. **Determinism**: Given the same inputs (user profile, plan, history, readiness), the engine always produces the same output. This ensures reproducible training recommendations and enables testing.

2. **Transparency**: Every decision (load increase, deload trigger, substitution ranking) includes explicit reasons that can be shown to users.

3. **Flexibility**: The engine supports both AI-generated training plans and user-defined workouts through a normalized `TrainingPlan` interface.

## Inspiration from Liftosaur

The `TrainingEngine` takes inspiration from [Liftosaur](https://www.liftosaur.com/), an open-source weightlifting tracker that pioneered the concept of programmable progression logic. Key concepts adapted from Liftosaur include:

### Per-Exercise State

Liftosaur models progression as code operating on persistent per-exercise state variables (e.g., `state.weight`, `state.failures`). Our `LiftState` struct mirrors this approach:

- `lastWorkingWeight`: The most recent successful working weight
- `rollingE1RM`: Exponentially smoothed estimated 1-rep max
- `failureCount`: Consecutive sessions where targets weren't met
- `lastDeloadDate`: When the exercise was last deloaded
- `trend`: Computed performance direction (improving/stable/declining)

### Progression as Functions

Liftosaur's scripting language (Liftoscript) allows users to define progression rules as code. We implement this concept through the `ProgressionPolicyType` enum with discrete, well-tested policy implementations rather than user scripts.

---

## Progression Policies

### 1. Double Progression

**Concept**: Progress reps first, then load.

**Algorithm**:
1. If all working sets hit the **top of the rep range** (e.g., 3×10 when range is 6-10):
   - Increase load by configured increment (default: 5 lbs)
   - Reset target reps to lower bound of range
2. If all sets hit at least the **lower bound** of the rep range:
   - Target 1 more rep next session (e.g., 3×8 → 3×9)
   - Maintain current load
3. If any set falls **below the lower bound**:
   - Count as a failure
   - After N consecutive failures (default: 2), trigger deload

**Example**:
```
Session 1: 100 lbs × 8, 8, 7 (within range) → Next: 100 lbs × 9, 9, 8 target
Session 2: 100 lbs × 9, 9, 8 (within range) → Next: 100 lbs × 10, 10, 9 target
Session 3: 100 lbs × 10, 10, 10 (at top) → Next: 105 lbs × 6, 6, 6 target
```

**Liftosaur Parallel**: This mirrors Liftosaur's built-in `dp` (double progression) mode, which uses the same rep-then-load advancement pattern.

### 2. Top Set + Backoff

**Concept**: Perform one heavy "top set" to gauge daily strength, then do volume work at a reduced percentage.

**Algorithm**:
1. Plan a top set at the target weight (based on previous session performance)
2. Plan backoff sets at a configured percentage (default: 85%) of top set load
3. After completing the top set:
   - If reps exceeded target: suggest load increase for next session
   - If reps met minimum: maintain for next session
   - If reps missed: investigate fatigue/recovery

**Backoff Calculation**:
```
Top set load: 225 lbs
Backoff percentage: 85%
Backoff load: 225 × 0.85 = 191.25 → rounded to 190 lbs
```

**Daily Max Autoregulation** (optional):
After the top set, compute an estimated daily max using the Brzycki formula and recalculate backoff sets based on actual performance rather than planned load.

### 3. RIR-Based Autoregulation

**Concept**: Adjust load based on perceived effort (Reps In Reserve).

**Algorithm**:
1. Each set has a target RIR (e.g., RIR 2 = "could do 2 more reps")
2. After completing a set, compare observed RIR to target
3. Adjust next set's load:
   - Observed RIR < target (harder): Decrease load by `(target - observed) × adjustmentPerRIR`
   - Observed RIR > target (easier): Optionally increase load
4. Cap adjustments to prevent wild swings (default max: 10% per set)

**Example**:
```
Set 1: Target RIR 2, Observed RIR 0 (to failure)
Deviation: -2 RIR
Adjustment: -2 × 2.5% = -5%
Next set load: 100 lbs × 0.95 = 95 lbs
```

### 4. Linear Progression

**Concept**: Add fixed weight each successful session.

**Algorithm**:
1. If all sets completed at target reps: Add increment (default: 5 lbs)
2. If targets missed: Count failure, maintain load
3. After N failures (default: 3): Deload by percentage (default: 10%)

**Liftosaur Parallel**: This is equivalent to Liftosaur's `lp` (linear progression) built-in.

---

## Deload Logic

### Trigger Conditions

The engine evaluates multiple deload triggers and applies a deload if **any** trigger fires:

#### 1. Performance Decline (2-Session Rule)

**Trigger**: The rolling e1RM for an exercise has declined for 2 consecutive sessions.

**Detection**:
```
Session N-2: e1RM = 300 lbs
Session N-1: e1RM = 290 lbs (decline 1)
Session N:   e1RM = 280 lbs (decline 2) → TRIGGER
```

**Rationale**: Two consecutive declines suggest accumulated fatigue rather than a one-off bad day.

#### 2. Low Readiness Threshold

**Trigger**: Readiness score below threshold (default: 50) for N consecutive days (default: 3).

**Detection**:
- Track daily readiness scores
- Count consecutive days below threshold
- Fire if count ≥ required days

#### 3. High Accumulated Fatigue

**Trigger**: Low readiness (current session) combined with recent volume >120% of baseline.

**Detection**:
```
Baseline = average daily volume over last 28 days
Recent = total volume over last 7 days / 7
If current readiness < threshold AND recent/baseline > 1.20 → TRIGGER
```

#### 4. Scheduled Deload

**Trigger**: N weeks since last deload (configurable, default: off).

**Detection**:
- Track `lastDeloadDate` per exercise
- Compare to configured `scheduledDeloadWeeks`

### Deload Application

When a deload is triggered:

1. **Intensity Reduction**: Reduce all working set loads by configured percentage (default: 10%)
2. **Volume Reduction**: Remove N sets per exercise (default: 1 set)

Example:
```
Normal session: 3×8 @ 225 lbs
Deload session: 2×8 @ 202.5 lbs (→ rounded to 202.5 or 200)
```

---

## Exercise Substitutions

### Ranking Algorithm

When an exercise is unavailable, rank substitutes by weighted scoring:

| Factor | Default Weight | Description |
|--------|---------------|-------------|
| Primary muscle overlap | 40% | Shared primary muscles |
| Secondary muscle overlap | 15% | Shared secondary muscles |
| Movement pattern | 30% | Same or similar pattern |
| Equipment available | 15% | User has the equipment |
| Equipment match bonus | 5% | Same equipment type |

### Scoring Formula

```
score = (primaryOverlap × 0.40) +
        (secondaryOverlap × 0.15) +
        (movementSimilarity × 0.30) +
        (equipmentAvailable × 0.15) +
        (equipmentMatch × 0.05)
```

### Tie-Breaking

When scores are equal, sort alphabetically by exercise name for deterministic ordering.

### Example

Finding substitutes for **Barbell Bench Press**:

| Candidate | Primary | Movement | Equipment | Score |
|-----------|---------|----------|-----------|-------|
| DB Bench Press | 100% (chest) | 100% (horizontal push) | Available + Bonus | 0.95 |
| Incline Bench | 100% (chest) | 100% (horizontal push) | Available + Match | 0.98 |
| Cable Fly | 100% (chest) | 100% (horizontal push) | Available | 0.87 |
| Tricep Pushdown | 0% | 0% | Available | 0.15 |

---

## State Updates After Session

After completing a session, `updateLiftState` computes:

1. **Last Working Weight**: Highest completed load from working sets
2. **Session e1RM**: Best estimated 1RM from any working set (Brzycki formula)
3. **Rolling e1RM**: `α × sessionE1RM + (1-α) × previousRollingE1RM` where α=0.3
4. **Failure Count**: Increment if any set below rep range lower bound; reset to 0 on success
5. **e1RM History**: Append new sample, keep last 10
6. **Trend**: Compute from e1RM history using linear regression slope

---

## E1RM Formulas

### Brzycki Formula

```
e1RM = weight × (36 / (37 - reps))
```

Most accurate for 1-10 rep range.

### Inverse (Computing Working Weight)

```
workingWeight = e1RM × (37 - targetReps) / 36
```

---

## API Summary

### `TrainingEngine.recommendSession`

**Input**:
- `date`: Session date
- `userProfile`: Sex, experience, goals, available equipment
- `plan`: Templates, schedule, progression policies
- `history`: Recent sessions, lift states, readiness records
- `readiness`: Today's readiness score (0-100)

**Output**: `SessionPlan` with:
- Selected template
- Per-exercise plans with target loads/reps
- Deload decision and reason (if applicable)
- Substitution options for each exercise

### `TrainingEngine.adjustDuringSession`

**Input**:
- `currentSetResult`: Just-completed set with observed RIR
- `plannedNextSet`: Originally planned next set

**Output**: `SetPlan` with adjusted load based on RIR deviation

### `TrainingEngine.updateLiftState`

**Input**: `CompletedSession` with all exercise results

**Output**: Array of updated `LiftState` for each performed exercise

---

## Testing Strategy

The module includes comprehensive unit tests covering:

- **Progression edge cases**: Hitting rep range bounds, load increases, rep resets
- **Deload triggers**: 2-session decline detection, single-session non-trigger
- **RIR autoregulation**: Adjustment caps, minimum load enforcement, determinism
- **Substitution ranking**: Score ordering, tie-breaking, equipment filtering

All tests verify determinism by running multiple iterations and comparing outputs.
