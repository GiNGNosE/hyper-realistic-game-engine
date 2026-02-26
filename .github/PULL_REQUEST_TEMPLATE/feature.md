# Feature Pull Request

<!-- pr_template: feature -->

## Summary

Describe the capability added and why this change is needed.

## Scope And Risk

- Subsystems touched:
- Risk level (`low` | `medium` | `high`):
- Rollback plan:

## Dual-Objective Evidence

- Fidelity/determinism impact:
- Runtime/performance impact:
- Explicit statement that neither objective regresses:

## Test Matrix

- [ ] Unit tests updated
- [ ] Integration tests updated
- [ ] Determinism/replay checks updated when state paths changed
- [ ] Performance checks updated for affected hot paths

## Artifact Links

- `artifacts/policy/lint-summary.json`:
- `artifacts/policy/lane-performance.json`:
- `artifacts/policy/proof-integrity-validation.json`:

## Governance Checklist

- [ ] `rule-read-receipt.json` updated for applicable rules
- [ ] Clarification evidence attached when ambiguity triggers exist
- [ ] No undocumented waivers introduced
- [ ] Required docs/ADR updates included for contract-impacting changes
