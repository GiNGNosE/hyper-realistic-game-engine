# Risk Register and Escalation Triggers

This register governs risks that can derail the dual objective: scientific fidelity plus high real-time performance.

## Severity Model

- `Green`: acceptable variance, proceed normally.
- `Yellow`: watchlist; corrective action required in the same cycle.
- `Red`: escalation; freeze affected scope until mitigation is verified.

## Triggered Risk Register

- `R1` Determinism drift
  - Trigger: `D1_ReplayHashMatchRate < 100%` on canonical replay.
  - Severity: `Red`.
  - Mandatory response: freeze feature merges touching simulation state, run
    replay root-cause, and restore exact hash parity before resume.
- `R2` Physical plausibility degradation
  - Trigger: `M4_EnergyBalanceError > 0.05` in Phase 1+ suite.
  - Severity: `Red`.
  - Mandatory response: roll back offending change set or add correction patch
    and re-baseline only with full evidence.
- `R3` Runtime performance regression
  - Trigger: real-time benchmark budget miss beyond approved envelope for two
    checkpoints (`lane-performance-thresholds.json` /
    `lane-performance-risk-signals.json`).
  - Severity: `Red`.
  - Mandatory response: freeze non-performance scope, run focused profiling
    cycle, and ship only fixes until budget is restored.
- `R4` Visual surrogate drift
  - Trigger: Phase-2+ visual gate failures (`V1` or `V2`) in benchmark suite.
  - Severity: `Yellow -> Red after 2nd failure`.
  - Mandatory response: lock new visual surrogate features, then fix
    calibration or bake process.
- `R5` Audio fidelity timing drift
  - Trigger: `A2_TransientOnsetErrorMs > 8 ms` in qualified scenarios.
  - Severity: `Yellow -> Red after 2nd failure`.
  - Mandatory response: pause new audio features, correct event sync, and rerun
    truth comparison.
- `R6` Baseline integrity loss
  - Trigger: missing or invalid baseline lineage, or checksum mismatch.
  - Severity: `Red`.
  - Mandatory response: block promotion, rebuild lineage index, and restore
    from verified archive.
- `R7` Policy coverage erosion
  - Trigger: new subsystem change lands without mapped policy gate.
  - Severity: `Yellow`.
  - Mandatory response: add policy mapping within cycle; cycle promotion cannot
    proceed without closure.

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
- Review weekly LPG drift signal artifacts
  (`artifacts/policy/lpg-trend-report.json`) and escalate to `Red` correction
  mode when streak/trend evidence matches trigger conditions.
