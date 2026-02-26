# Annual Benchmark Ladder

This ladder forces year-over-year ratcheting of both scientific fidelity and real-time performance.

## Rules

- Ratchets can hold or tighten; they cannot be relaxed without an ADR and explicit rollback window.
- Quality and runtime objectives are promoted together.
- Benchmark scenarios and seeds stay fixed for comparability unless replaced via ADR.

## Baseline Year (Y0)

Use currently accepted thresholds in `docs/pipeline/validation-metrics.md` and current real-time budget as baseline.

## Ladder Template (per year)

| Year | Fidelity Ratchet | Determinism Ratchet | Runtime Ratchet | Promotion Condition |
|---|---|---|---|---|
| Y1 | Tighten at least one of `M*` or `V*` | Keep `D1 = 100%`, reduce tolerated variance budget | Improve median frame time or throughput target by measurable margin | All gates pass plus no red risks at cycle close |
| Y2 | Tighten at least two metrics across physics/render/audio | Preserve exact replay parity and narrower variance envelope | Improve P95 performance budget and stability | Same as Y1 |
| Y3+ | Continue monotonic tightening with documented rationale | No determinism regressions accepted | Continue monotonic runtime improvement | Same as Y1 |

## Measurement Discipline

- Use stable hardware class and pinned perf environment for runtime measurements.
- Use canonical scenario suite (`S1`, `S2`, `S3`) and fixed camera/listener paths.
- Report median and P95 where applicable.

## Failure Handling

If annual ratchet target is missed:

1. Mark year as `partial`.
2. Open ADR with root causes and revised path.
3. Carry forward unresolved ratchet target to next annual thesis.
