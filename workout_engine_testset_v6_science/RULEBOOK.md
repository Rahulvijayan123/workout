# RULEBOOK — v6 (science-rooted synthetic progression labels)

This dataset is synthetic and intended for software evaluation. It encodes an evidence-aligned progression policy.

Primary evidence inputs:
- ACSM Progression Models in Resistance Training for Healthy Adults: progressive overload and load progression heuristics.
- NSCA Training Load Chart: typical repetitions-to-%1RM relationships used to set plausible prescription intensities.
- RIR-based RPE autoregulation literature: adjust training based on proximity-to-failure and day-to-day readiness.
- Deload and taper literature: meaningful volume reduction, with intensity maintained or modestly reduced depending on context.

Encoded policy (summary):
1) Base load selection
- If rolling e1RM exists: choose %1RM based on reps (approx. NSCA mapping) and adjust slightly for lower target RPE.
- If cold start: use conservative bodyweight-based initial working weight; initialize rolling e1RM from that set.

2) Progressive overload decisions
- Increase when prior exposure clearly exceeded target reps at or below target effort.
- Hold when target reps achieved at approximately target effort.
- Single grinder/miss for intermediate+: slight reduction (~2.5%) for one exposure, then reassess.
- Fatigue deload after repeated failures/grinders: reduce load ~10% and sets ~40%.

3) Readiness and breaks
- Low readiness: apply ~5% reduction (readiness_cut) unless already deloading.
- >14 days since lift exposure: apply ~10% reduction (break_reset).

Scoring:
- Load agreement should use acceptable_range_lb (± ~2% plus minimum load step).
- Decision accuracy uses the decision field for main lifts.
