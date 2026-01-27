# Workout Engine Test Set v7 (science-rooted; test-case format)

This bundle targets five user archetypes:
1) Beginners and early intermediates (novice LP), including microload vs no-microload and early stall + deload.
2) Beginner with interruptions and messy adherence, including 7/10/14/21-day breaks with explicit break resets.
3) Microloading-constrained presser (bench/OHP) alternating gyms with different plate steps.
4) Intermediate cutting/recomping with BW trending down, block shifts, false fatigue, and true regression week.
5) Intermediate using substitutions/variations with state separation and conservative return-to-standard ramping.

## Folder layout
- ./scenarios/*.jsonl  (each line is a test case)
- schema.json, manifest.json, RULEBOOK.md
- summary_mainlifts.csv (quick scan)

## Record format
See schema.json; each line follows:
{ test_id, test_category, description, input, expected_output, assertions }

Notes:
- `equipment_config.load_step_lb` enforces plate math / rounding constraints.
- Expected prescriptions include `acceptable_range_lb` for tolerance-based scoring.
