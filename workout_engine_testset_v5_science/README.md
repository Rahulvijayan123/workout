# Workout Engine Test Set v5 (format matched)

This dataset matches the exact record-level structure you specified and enforces evolving histories:

- Each record is a single session JSON object in JSONL.
- `input.recent_lift_history` contains ONLY entries with dates strictly BEFORE the record's `date`.
- `input.user_profile.body_weight_lb` is present each session (for cold-start and relative strength logic).

## Files
- workout_engine_testset_v5.jsonl
- schema.json
- RULEBOOK.md
- mainlift_summary.csv
- score_predictions.py
- examples/example_record.json

## Users and edge cases
- U501 (beginner): true cold-start; two-week travel break (missed sessions) to force >14d break_reset behavior
- U502 (intermediate): microloading with 1.25 lb step
- U503 (intermediate): fatigue/deficit proxy; one missed lower day; planned deload week
- U504 (advanced DUP): planned deload cadence; bench irritation forces close-grip variation on upper days
- U505 (elite): coarse 5 lb increments; readiness variability; late deload/taper week

## How to test
Feed only `input` into your engine. Compare against `expected.session_prescription_for_today` for main lifts.
