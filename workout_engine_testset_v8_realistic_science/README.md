# Workout Engine Test Set v8 (realistic + sex/BW scaling)

## Goals
- Stress-test sex/bodyweight-aware increment scaling around tier thresholds.
- Preserve realism: BW drift, imperfect adherence, readiness noise, and occasional grinders.
- Provide stable expected outputs with tolerances for rounding/plate math.

## Layout
- scenarios/*.jsonl
- manifest.json, schema.json
- RULEBOOK.md
- summary_mainlifts.csv

## Record format
{ test_id, test_category, description, input, expected_output, assertions }
