# RULEBOOK — v5 progression labels (synthetic, science-rooted)

This dataset is synthetic and intended for software evaluation. It encodes a realistic, evidence-informed progression policy.

Policy encoded in labels:
- Increase: if last exposure exceeded rep target by ~1 rep at <= target effort; increase bounded by lift and experience (upper-body smaller; advanced/elite smaller).
- Hold: if last exposure is at/near target effort without clear excess performance.
- Single grinder/miss (intermediate+): small decrease (~2.5%) for one exposure, then reassess.
- Fatigue deload: after 2 failures or 3 grinders, reduce load ~10% and sets ~40%.
- Planned deload: same deload reductions on scheduled weeks.
- Readiness cut: on low readiness (sleep/HRV/stress/soreness), apply additional ~5% reduction unless already deloading.
- Break reset: if >14 days since last exposure, reduce ~10% on next exposure.

Scoring:
- Use acceptable_range_lb for load agreement to avoid overfitting to a single numeric label.
