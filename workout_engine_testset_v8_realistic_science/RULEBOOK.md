# RULEBOOK — v8 (realistic + sex/bodyweight scaling)

This dataset is designed to calibrate a progressive overload engine where increment sizing can depend on relative strength (e1RM / bodyweight) and biological sex.

Anchors
- RIR-based RPE is used to avoid increasing load after grinder sets and to bias toward holds or small reductions during low readiness.
- Upper body lifts generally warrant smaller jumps; lower body can tolerate larger novice jumps.
- After layoffs, conservative load reductions plus re-ramping are realistic.
- Readiness metrics are noisy; performance can remain stable during "false fatigue" periods.

Engine-aligned sex/BW scaling
- Relative strength tier = rollingE1RM / body_weight_lb.
- Tier thresholds (bench): male (1.25 / 1.75), female (0.78 / 1.09), other (1.01 / 1.42) for medium/high.
- Tier impacts increment magnitude and rounding feasibility, not direction decisions.

Files
- sex_bw_thresholds.jsonl: tier boundary tests.
- beginner_lp_realistic.jsonl: novice LP with BW drift, low-sleep week, first grinders, and deload.
- microloading_sex_bw_scaling.jsonl: microloading + alternating plate constraints.
- cut_rel_strength_drift.jsonl: BW drops during cut; tier shifts bias toward holds.
- messy_adherence_sex_pairs.jsonl: layoffs with break resets; male/female paired cases.
