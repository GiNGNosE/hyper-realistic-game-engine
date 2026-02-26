# Rule Activation Matrix by Phase

This matrix is authoritative for when each governance rule becomes mandatory.

## Pre-Phase 0 (must be active before implementation)

- `00-core-governance-cpp.mdc`
- `05-build-toolchain-gates.mdc`
- `10-cpp-safety-subset.mdc`
- `12-program-roadmap-governance.mdc`
- `15-test-discipline.mdc`
- `30-failsafe-error-logging-contract.mdc`
- `40-determinism-envelope-and-replay.mdc`
- `45-serialization-compatibility-integrity.mdc`
- `55-operational-resilience-and-backups.mdc`
- `65-dual-objective-and-escalation.mdc`
- `70-validation-matrix-enforcement.mdc`
- `75-annual-benchmark-ladder.mdc`

## Phase 1

- Add strict enforcement:
  - `20-performance-critical-design.mdc`
  - `35-api-abi-versioning-contract.mdc`
  - `80-cross-subsystem-invariants.mdc`

## Phase 2

- Add strict enforcement:
  - `25-gpu-and-shader-governance.mdc`
  - `50-baseline-and-promotion-policy.mdc`

## Phase 3 to Phase 4

- Full pack mandatory including:
  - `06-dependency-governance.mdc`
  - `60-waiver-and-risk-control.mdc`
  - `90-migration-and-deprecation-safety.mdc`

## Notes

- Early phases may run reduced workloads, but gate semantics remain unchanged.
- Any rule marked active is merge-blocking through `policy-verdict`.
- CI rule resolution for proof enforcement must derive from this matrix and emit `artifacts/policy/required-rules.json`.
- Ambiguity-trigger enforcement is additive and does not alter active rule membership by phase.
