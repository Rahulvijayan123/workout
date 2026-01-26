# Workout Engine Test Set v4 (science-rooted, substitution-safe)

## Files
- workout_engine_testset_v4.jsonl
- schema.json
- RULEBOOK.md
- mainlift_summary.csv
- score_predictions.py
- examples/example_record.json

## What changed vs earlier sets
Substitution and variation no longer contaminate the base lift state. Each prescription includes `updates_state_for`.

## Substitution representation
For squat substitutions:
- lift = "squat"
- performed_exercise = "leg_press"
- updates_state_for = {"type":"exercise","name":"leg_press"}

If your engine outputs a separate leg_press line item instead, adjust your scorer accordingly (a scorer is included here that already supports this).

## Users
- U301: novice cold start + missed session
- U302: microloading (1.25 lb step)
- U303: intermediate deficit + planned deloads + missed session
- U304: advanced DUP + bench variation (close grip) + missed volume days
- U305: novice deficit + squat->leg_press substitution from week 6
- U306: intermediate with 5 lb increment constraints
