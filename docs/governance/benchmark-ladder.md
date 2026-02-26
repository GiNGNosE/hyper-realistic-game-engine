# Annual Benchmark Ladder

This ladder forces year-over-year ratcheting of both scientific fidelity and real-time performance.

## Rules

- Ratchets can hold or tighten; they cannot be relaxed without an ADR and explicit rollback window.
- Quality and runtime objectives are promoted together.
- Benchmark scenarios and seeds stay fixed for comparability unless replaced via ADR.

## Baseline Year (Y0)

Use currently accepted thresholds in `docs/pipeline/validation-metrics.md` and current real-time budget as baseline.

## Ladder Template (per year)

- `Y1`
  - Fidelity ratchet: tighten at least one of `M*` or `V*`.
  - Determinism ratchet: keep `D1 = 100%` and reduce tolerated variance budget.
  - Runtime ratchet: improve median frame time or throughput target by
    measurable margin.
  - Promotion condition: all gates pass and no red risks at cycle close.
- `Y2`
  - Fidelity ratchet: tighten at least two metrics across
    physics/render/audio.
  - Determinism ratchet: preserve exact replay parity with a narrower variance
    envelope.
  - Runtime ratchet: improve P95 performance budget and stability.
  - Promotion condition: same as Y1.
- `Y3+`
  - Fidelity ratchet: continue monotonic tightening with documented rationale.
  - Determinism ratchet: no determinism regressions accepted.
  - Runtime ratchet: continue monotonic runtime improvement.
  - Promotion condition: same as Y1.

## Measurement Discipline

- Use stable hardware class and pinned perf environment for runtime measurements.
- Use canonical scenario suite (`S1`, `S2`, `S3`) and fixed camera/listener paths.
- Report median and P95 where applicable.
- Record ladder checkpoints from LPG artifacts:
  - `artifacts/policy/lane-performance-thresholds.json`,
  - `artifacts/policy/baseline-delta.json`,
  - `artifacts/policy/lane-performance-risk-signals.json`.
  - `artifacts/policy/lpg-trend-report.json`.

Weekly drift review must consume the latest LPG trend report and update cycle
notes when pass/fail streaks or runtime trends indicate regression risk.
Use `artifacts/policy/lpg-artifact-review.json` as the machine-generated triage input for weekly review.

## Failure Handling

If annual ratchet target is missed:

1. Mark year as `partial`.
2. Open ADR with root causes and revised path.
3. Carry forward unresolved ratchet target to next annual thesis.
