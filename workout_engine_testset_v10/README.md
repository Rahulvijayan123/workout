# Workout Engine Testset V10 (Conservative, Realistic Synthetic)

This dataset is designed to stress failure modes observed in V9:
1) Microloading magnitude & rounding drift
2) Conservative holds across cut/maintenance phases
3) Isolation rep-range double progression
4) State continuity across variations, substitutions, and messy adherence
5) Cross-signal tie-breakers (performance vs readiness, noisy RPE, localized pain flags)

## Folder layout
- scenarios/*.jsonl  One JSON object per line (self-contained test case)
- schema.json        Minimal JSON Schema (permissive)
- manifest.json      File list + counts + tags
- scoring_config.json Scoring emphasis + invariants

## Notes on realism
- Session dates run across late-2025 with realistic weekly cadence and occasional gaps.
- Plate profiles include micro plates (1.25 lb), standard 2.5 lb, kg increments (~1.102 lb), and no-microplate gyms.
- Cut phases include “false fatigue” weeks: low readiness metrics but stable performance.
- Isolation lifts use rep-range targets and conservative load increases (reps-first).
- Corrupted history entries are present and must be ignored (future dates, unit mix, duplicates, out-of-order).

## Expected-output philosophy
This dataset is intentionally conservative:
- Many sessions are holds.
- Increases require clear non-grindy success and good readiness.
- In cut phases, increases additionally require explicit surplus confirmation.
