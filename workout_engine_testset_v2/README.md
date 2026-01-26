# Workout Engine Test Set v2

This dataset targets backend improvements for:
- Cold start estimation (no prior lift history)
- Microloading (1.25 lb increments where appropriate)
- Decision vs magnitude separation (increase, hold, small decrease, deload, reset)
- Readiness-based small reductions (not full deload)
- Plateau-triggered deloads (fail or high-RPE streaks)
- Program-aware targets (heavy vs volume days for DUP)
- Variation and substitution handling

## Files
- workout_engine_testset_v2.jsonl
- schema.json
- mainlift_summary.csv
- score_predictions.py (optional helper)
- examples/example_record.json

## How to test
1) For each JSONL line, feed only `input` into your engine.
2) Compare engine output to `expected.session_prescription_for_today`.
3) Optionally test next-session recommendation against `expected.expected_next_session_prescription` (labels assume readiness='ok' for determinism).

## Default scoring
See `expected.scoring` inside each record:
- main lifts: squat, bench, deadlift, ohp
- tolerance: 2.5 lb
- strict fields: prescribed_weight_lb and decision

## Users and stress cases
- U101: lightweight with high relative strength, requires frequent 1.25 lb microloading
- U102: cold start novice with no starting history or 1RMs
- U103: intermediate in deficit, planned deloads, one missed session, frequent low-readiness downshifts
- U104: advanced DUP, planned deloads, missed volume days, bench variation due to elbow irritation
- U105: returning novice in deficit, squat substituted to leg press due to knee pain starting week 5
