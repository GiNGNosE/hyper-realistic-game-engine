# Decade-Ready Criteria

This checklist defines when governance is considered mature enough for sustained 10-year execution.

## Category A: Governance Execution

- At least 8 consecutive 12-week cycles completed with evidence packs.
- Every cycle includes updated risk review and ADR linkage.
- No cycle marked complete with missing required evidence artifacts.

## Category B: Technical Integrity

- Determinism policy sustained with `D1_ReplayHashMatchRate = 100%` on canonical replays.
- No unresolved red risk in determinism, baseline integrity, or schema compatibility.
- Baseline promotions always include lineage and integrity verification.

## Category C: Dual-Objective Performance

- Quality gates (`M*`, `V*`, `A*`, `D*`) pass on all active benchmark scenarios at cycle closure.
- Runtime performance budgets meet or beat approved targets at cycle closure.
- No accepted promotion that passes one objective while failing the other.

## Category D: Long-Horizon Continuity

- Restore drills completed at least quarterly for 4 consecutive quarters.
- RPO/RTO targets met in at least 3 of the last 4 drills.
- Recovery runbook is current and validated by latest drill report.

## Category E: Improvement Trajectory

- Annual benchmark ladder shows monotonic progress or documented hold with corrective ADR.
- At least one measurable improvement in fidelity and one in runtime each year.
- Missed annual ratchets are closed with corrective plan by next annual cycle.

## Declaration Rule

Project can be declared `decade-ready` only when all categories pass simultaneously.

If any category regresses to fail state, declaration is suspended until recovery evidence is accepted.
