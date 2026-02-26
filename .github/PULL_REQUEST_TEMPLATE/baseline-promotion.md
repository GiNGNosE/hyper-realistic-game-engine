# Baseline Promotion Pull Request

<!-- pr_template: baseline-promotion -->

## Summary

Describe what baseline is being promoted and why promotion is requested.

## Promotion Intent Metadata

- intent: `baseline-promotion`
- target_baseline_path:
- baseline_index_update:
- baseline_changelog_update:

## Baseline Delta And Lineage

- Delta summary:
- Lineage checksum references:
- Integrity verification result:

## Dual-Objective Evidence

- Fidelity/determinism evidence:
- Runtime/performance evidence:
- Explicit statement that neither objective regresses:

## Test Matrix

- [ ] Required phase gates executed
- [ ] Determinism/replay checks executed when applicable
- [ ] Performance/fidelity checks executed

## Artifact Links

- `artifacts/policy/baseline-delta.json`:
- `artifacts/policy/baseline-integrity.json`:
- `artifacts/policy/lane-performance.json`:
- `artifacts/policy/proof-integrity-validation.json`:

## Governance Checklist

- [ ] Promotion does not overwrite accepted baselines in place
- [ ] Retention policy requirements were respected
- [ ] Risk register and waiver implications reviewed
