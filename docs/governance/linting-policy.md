# Linting and Static Analysis Policy

This document defines the mandatory lint strategy for repository quality gates.

## Purpose

The lint program is designed to keep long-term maintainability high while preserving deterministic, performance-critical engineering constraints.

## Scope

Lint enforcement applies to changed files in pull requests using these path classes:

- C++: `**/*.c`, `**/*.cc`, `**/*.cpp`, `**/*.cxx`, `**/*.h`, `**/*.hh`, `**/*.hpp`, `**/*.hxx`
- Shell: `**/*.sh`
- GitHub Actions and governance YAML: `**/*.yml`, `**/*.yaml`
- Governance and technical docs: `**/*.md`

## Required Tools and Pinned Versions

The CI lane must install and run the exact pinned versions declared in the workflow environment:

- `clang-tidy` (pinned LLVM major)
- `clang-format` (pinned LLVM major)
- `shellcheck`
- `shfmt`
- `actionlint`
- `yamllint`
- `markdownlint-cli2`

Tool versions are emitted to artifacts and checked against workflow pin values.

## Merge-Blocking Severity Model

- `error`: merge-blocking.
- `warning`: merge-blocking unless explicitly waived through the suppression process in this policy.

No silent downgrades are allowed on policy-protected paths.

## Suppression Process

Suppressions are allowed only for short-lived, scoped exceptions and must be tracked in `docs/governance/lint-suppressions.json`.

Each suppression entry must include:

- `id`
- `tool`
- `scope`
- `rule_or_code`
- `reason`
- `owner` (must be `self`)
- `created_on`
- `expires_on`
- `rollback_plan`

Suppression records with expired `expires_on` are treated as lint failures.

## CI Artifacts

The correctness lane emits:

- `artifacts/policy/lane-correctness.json`
- `artifacts/policy/lint-summary.json`
- `artifacts/policy/lint-cpp.json`
- `artifacts/policy/lint-shell.json`
- `artifacts/policy/lint-yaml.json`
- `artifacts/policy/lint-docs.json`
- `artifacts/policy/lint-tool-versions.json`

Each artifact includes deterministic keys with pass/fail status, checked files, and failure reasons.

## Local Parity

The repository provides a single local entrypoint:

- `./.github/scripts/run-lint-suite.sh`
- `make lint` (resolves changed paths, then runs the same suite)

This command mirrors CI logic and writes the same policy artifacts.

## Review Cadence

- Weekly: review new suppressions and expiry windows.
- Per cycle closeout: verify lint findings trend and suppression burn-down.
- Quarterly: ratchet strictness (new checks can tighten; existing checks may not relax without governance record).

## Version Update Procedure

1. Update pinned versions in workflow/tool bootstrap.
2. Run lint suite and compare before/after outcomes.
3. Update this policy document with rationale and impact.
4. Record any required suppression adjustments with expiry.

## Verification Scenarios

Expected behavior:

- malformed shell script -> shell lint fails and blocks merge,
- workflow YAML issues -> YAML lint fails and blocks merge,
- markdown style violations in docs -> docs lint fails and blocks merge,
- C++ formatting drift -> C++ lint fails and blocks merge,
- all checks clean -> lint summary passes and policy lane may pass.

### Reference Execution Evidence

Executed during implementation:

1. `./.github/scripts/run-lint-suite.sh` without toolchain installation:
   - result: `fail`,
   - evidence: missing tool binaries are reported as merge-blocking failures in lint artifacts.
2. `./.github/scripts/run-lint-suite.sh` with pinned-version mock toolchain and non-linted changed path:
   - result: `pass`,
   - evidence: lint suite reports `pass` with version pin checks satisfied.
