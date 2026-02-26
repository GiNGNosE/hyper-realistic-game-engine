# Baseline Lifecycle (Git LFS)

This policy defines promotion, retention, and pruning for benchmark baselines.

## Storage Layout

- `baselines/replay/`
- `baselines/perf/`
- `baselines/metrics/`

LPG uses `baselines/metrics/lpg-index.json` as the active baseline registry for Lane Performance Gate comparisons.

All binary artifacts are stored with Git LFS and accompanied by metadata indexes.

## Promotion Requirements

- Promotion intent marker: `baseline-promotion`.
- Passing `policy-verdict`.
- Baseline index update with:
  - baseline id,
  - source commit,
  - scenario set and seeds,
  - environment fingerprints,
  - checksums and lineage.
- Baseline changelog entry summarizing deltas and rationale.

For LPG promotions, the baseline index entry must include:

- `baseline_id`,
- `parent_baseline_id` (or `null` for root),
- `metrics_path`,
- `artifact_checksum_sha256`,
- `phase`, `scenario_set_id`, and seeds.

## Retention Policy

- Active window: recent promoted set used by CI comparisons.
- Archive tier: older approved baselines preserved for historical comparability.
- Prune candidate tier: archive entries eligible for removal after policy checks.

## Pruning Rules

- Never prune without checksum and lineage verification.
- Keep at least one baseline per major schema/version epoch.
- Keep annual ratchet anchor baselines for each calendar year.
- Log pruned entries with reason and replacement reference.
