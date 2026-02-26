# Resource and Sustainability Envelopes

This policy defines practical envelopes for effort and infrastructure spend so progress remains stable over long horizons.

## Workload Envelope

- Plan each 12-week cycle with explicit buffer for hardening and recovery tasks.
- Reserve at least one checkpoint per cycle for maintenance-only work.
- If red risks are active, suspend scope expansion until risk is mitigated.

## Compute Envelope

- Define per-cycle compute budget targets before major benchmark runs.
- Track heavy jobs by scenario and pipeline stage for trend analysis.
- If compute usage exceeds planned envelope without measurable ladder progress, trigger optimization review.

## Storage Envelope

- Keep active baselines in fast storage; archive older accepted baselines.
- Enforce baseline retention lifecycle and integrity checks before pruning.
- Track growth trend per artifact class to avoid unbounded accumulation.

## Escalation

- Two consecutive cycle overruns in workload or infrastructure spend require corrective ADR.
- Corrective ADR must include scope adjustment, technical optimization, or retention policy update.
