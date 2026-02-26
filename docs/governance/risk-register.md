# Risk Register and Escalation Triggers

This register governs risks that can derail the dual objective: scientific fidelity plus high real-time performance.

## Severity Model

- `Green`: acceptable variance, proceed normally.
- `Yellow`: watchlist; corrective action required in the same cycle.
- `Red`: escalation; freeze affected scope until mitigation is verified.

## Triggered Risk Register

| Risk ID | Risk | Trigger | Severity | Mandatory Response |
|---|---|---|---|---|
| R1 | Determinism drift | `D1_ReplayHashMatchRate < 100%` on canonical replay | Red | Freeze feature merges touching simulation state, run replay root-cause, restore exact hash parity before resume |
| R2 | Physical plausibility degradation | `M4_EnergyBalanceError > 0.05` in Phase 1+ suite | Red | Roll back offending change set or add correction patch and re-baseline only with full evidence |
| R3 | Runtime performance regression | Real-time benchmark budget miss beyond approved envelope for two checkpoints | Red | Freeze non-performance scope, run focused profiling cycle, ship only fixes until budget restored |
| R4 | Visual surrogate drift | Phase-2+ visual gate failures (`V1` or `V2`) in benchmark suite | Yellow -> Red after 2nd failure | Lock new visual surrogate features, fix calibration or bake process |
| R5 | Audio fidelity timing drift | `A2_TransientOnsetErrorMs > 8 ms` in qualified scenarios | Yellow -> Red after 2nd failure | Pause new audio features, correct event sync and rerun truth comparison |
| R6 | Baseline integrity loss | Missing/invalid baseline lineage or checksum mismatch | Red | Block promotion, rebuild lineage index, restore from verified archive |
| R7 | Policy coverage erosion | New subsystem change lands without mapped policy gate | Yellow | Add policy mapping within cycle; cannot promote cycle without closure |

## Escalation Protocol

When a `Red` trigger fires:

1. Record incident with timestamp, impacted subsystems, and first failing artifact.
2. Enter correction mode: no new feature scope in impacted area.
3. Publish mitigation plan with owner (`self`) and verification criteria.
4. Resume normal scope only after validation evidence passes all affected gates.

## Review Cadence

- Re-evaluate risk entries every 12-week cycle closure.
- Add new risk IDs when novel failure modes are observed.
- Never delete historic risk entries; mark status as `active`, `mitigated`, or `retired`.
