# Workout Engine Test Set v6 (format matched)

Each JSONL line is a full session record:

{ "dataset_version": "v6", "user_id": "...", "date": "YYYY-MM-DD", "session_type": "...", "input": {...}, "expected": {...} }

Key properties:
- Records are globally chronological.
- input.recent_lift_history contains ONLY entries strictly BEFORE the record date.
- Includes progressive overload, deloads, readiness cuts, break resets, missed sessions, and variation overrides.

## Files
- workout_engine_testset_v6.jsonl
- manifest.json
- schema.json
- RULEBOOK.md
- mainlift_summary.csv
- score_predictions.py
- examples/example_record.json

## Users and edge cases
- U601 beginner: true cold-start + 2-week travel break forcing break_reset
- U602 beginner: microloading 1.25 lb step + illness week
- U603 intermediate: mild deficit fatigue proxy + missed lower session + deload week
- U604 intermediate: microloading + deadlift variation override on back tweak week
- U605 advanced DUP: planned deload cadence + close-grip bench variation after irritation
- U606 elite: coarse 5 lb step + readiness swings + late taper/deload with short-term water cut
