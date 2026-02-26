# CI Environments for Governance Gates

Two CI environments are required to control noise and preserve fairness.

## Replay Reference Environment

- Purpose: deterministic replay and correctness gates.
- Characteristics:
  - pinned toolchain,
  - deterministic flags profile,
  - reproducible runtime container image.

## Performance Stable Environment

- Purpose: performance and fidelity gates.
- Characteristics:
  - stable runner class,
  - controlled hardware envelope,
  - unchanged benchmark harness between baseline comparisons.

## Required Fingerprint Payload

Each run must publish:

- compiler and toolchain version,
- operating system/runtime image digest,
- CPU/GPU class,
- key compile flags and perf profile identifier.
