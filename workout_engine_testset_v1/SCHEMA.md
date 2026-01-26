# Workout Engine Testset v1

Synthetic, label-rich dataset to test a workout prescription engine that starts producing prescriptions after each user's first two sessions.

## Recommended evaluation flow

1. Load `test_cases.jsonl`
2. For each line:
   - Feed `input` to your engine
   - Compare your engine's plan vs `expected_output.workout_plan`
3. Use `all_sessions_log.jsonl` if you also want to evaluate "plan vs execution" logic.

## Files

- `users.json`: user profiles and constraints
- `test_cases.jsonl`: supervised input/label pairs (sessions >= 3)
- `all_sessions_log.jsonl`: full session logs (including sessions 1-2)
- `sessions_flattened.csv`: tabular view (one row per session-exercise)

## Edge cases included

- U001: strong newbie gains, one travel day, one missed session, and a bench stall (two missed last sets on bench days).
- U002: menstrual cycle readiness windows, rep-range double progression, plus a planned deload week.
- U003: detrained but strong user with chronic low recovery, programmed deload, knee-friendly squat substitution, and a forced deadlift miss.
- U004: older novice with a 2-week illness gap, conservative return week, and shoulder pain flares that deload pressing.

## Labels inside plans

Each exercise prescription includes `plan_tag`, which you can use for error analysis:
- baseline
- linear_add_load
- double_progression_add_reps
- double_progression_add_load
- double_progression_reduce_assistance
- repeat_conservative
- repeat_after_failure
- deload
- forced_deload_event

