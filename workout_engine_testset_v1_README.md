# Workout Engine Test Set v1 (JSONL)

This dataset is designed to test a workout progression engine. Each line is a JSON object representing one scheduled training day for one user.

## Core concept
- Use the **input** object as the model input.
- Compare your engine output (recommended load, sets, reps) to the **expected.session_prescription_for_today** and, if you are predicting forward, to **expected.expected_next_session_prescription**.

## Record layout
Top-level:
- user_id: string
- date: ISO-8601 date
- session_type: string, one of A/B, UpperA/LowerA/UpperB/LowerB, UpperHeavy/LowerHeavy/UpperVolume/LowerVolume
- input: object (feed this to your engine)
- expected: object (ground-truth labels)

### input.user_profile
Static-like fields for the scenario:
- sex, age, height_cm
- experience_level: novice or intermediate or advanced (note: U004 is novice-returning but normalized to novice for simple logic)
- program: program label
- goal: strength_hypertrophy or fat_loss_strength_maintenance

### input.today_metrics
Represents the biometric and recovery context:
- body_weight_lb
- sleep_hours
- hrv_ms
- resting_hr_bpm
- soreness_1_to_10
- stress_1_to_10
- steps
- calories_est

### input.today_session_template
List of exercises planned for today, without loads.
Fields per exercise:
- lift: string
- sets: integer
- reps: integer (or seconds/meters for a small number of accessories via unit)

### input.recent_lift_history
A rolling window of the last 0 to 3 exposures per main lift (bench, squat, deadlift, ohp).

### input.event_flags
- missed_session: boolean
- injury_flags: object keyed by lift name with boolean values

## expected.session_prescription_for_today
List of per-exercise prescriptions.
For main lifts (bench, squat, deadlift, ohp):
- prescribed_weight_lb is always set
- reason_code explains why the load was changed or held:
  - progress
  - hold_due_to_high_rpe
  - repeat_due_to_miss
  - deload
  - deload_after_plateau
  - reset_after_break
  - and modifiers like _and_low_readiness or _variation_change

For accessories, prescriptions exist but are not intended to be scored strictly.

## expected.actual_logged_performance
Simulated logged sets including achieved reps and RPE. Failures appear mostly as missed reps on the last set.

## expected.expected_next_session_prescription
Optional forward-looking label for the next non-missed scheduled session.
- readiness_assumption_for_label is fixed to "ok" to keep labels deterministic.
- This allows you to test next-session recommendation, given the post-session updated state.

## Users and edge cases
- U001: novice male in surplus, linear progression, travel break in week 4 and reset week 5
- U002: intermediate female in deficit, planned deload week 5, squat stagnation risk
- U003: advanced male, DUP style, planned deload weeks 4 and 8, elbow irritation from week 6 changes bench variation and load
- U004: novice-returning nonbinary in deficit, early deload week 3, knee discomfort from week 4 substitutes squat with leg press

