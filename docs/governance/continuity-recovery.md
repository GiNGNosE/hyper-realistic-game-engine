# Continuity and Recovery Governance

This document defines operational continuity controls for decade-scale project reliability.

## Asset Classes

- `Source`: code, configs, rules, docs.
- `Baselines`: replay/perf/metrics artifacts and their indexes.
- `Truth Outputs`: offline render/audio/snapshot references.
- `Working Data`: temporary intermediate outputs.

## Backup Cadence

- Source: daily snapshot + remote mirror.
- Baselines: on every accepted promotion event.
- Truth outputs: weekly snapshot for canonical benchmark set.
- Working data: optional and best-effort only.

## Integrity and Verification

- Every promoted baseline archive must include checksums and lineage metadata.
- Weekly integrity job verifies random sample restores from archives.
- Any checksum mismatch is a `Red` risk in `risk-register.md`.

## Restore Drill Policy

Run one restore drill every quarter:

1. Simulate loss of local working environment.
2. Restore source, rules, baselines, and one canonical benchmark bundle.
3. Re-run deterministic replay and one real-time benchmark.
4. Re-run LPG (`.github/scripts/run-performance-lane.sh`) against restored baseline index and metrics input.
5. Compare metrics to previous accepted evidence pack.

## Recovery Targets

- `RPO` (acceptable data loss window): <= 24 hours for source; <= one promotion event for baselines.
- `RTO` (time to operational recovery): <= 48 hours to replay-capable state.

If targets are missed, open corrective action and track in next cycle closure.

## Recovery Runbook Minimum

Maintain a versioned runbook that covers:

- environment bootstrap order,
- data restore steps and verification commands,
- baseline registry reconstruction,
- LPG baseline index reconstruction (`baselines/metrics/lpg-index.json`) and checksum verification,
- deterministic replay verification procedure,
- performance benchmark verification procedure.

## Ownership and Audit Trail

- Owner is `self` (solo governance).
- Each drill produces a dated report with pass/fail and corrective actions.
- Keep all drill reports for historical trend review; never rewrite old reports.
