# Agent Task Board

<!-- markdownlint-disable MD022 MD024 -->

BoardVersion: 2026-02-27.1
BoardHash: a0279ef76047d4c9a901a65b4a4a713c388853d5f9a418186ea75815d2aa0904
## ActiveTasks

### Task

TaskID: TB-001
OwnerAgent: agent1
Status: assigned
ScopePaths:

- `.github/scripts/validate-clarification-log.sh`
- `.github/scripts/test-validate-clarification-log-matrix.sh`
- `.github/scripts/fixtures/clarification-validator/**`

Acceptance:

- `T002 missing_target_scope` only fires when `event_name` is `pull_request` or `push`.
- `clarification-validation.json` includes `event_name`, `target_scope_required`, `required_clarification`, `errors`.

EvidenceArtifacts:

- `artifacts/policy/clarification-validator-matrix.json`
- `artifacts/policy/clarification-validator-matrix-summary.md`

### Task

TaskID: TB-002
OwnerAgent: agent2
Status: assigned
ScopePaths:

- `docs/governance/clarification-log-schema.md`
- `docs/governance/hybrid-proof-enforcement.md`
- `docs/governance/policy-verdict.md`

Acceptance:

- Trigger/event mapping is explicitly documented for scoped and unscoped contexts.
- Compatibility note states behavior refinement (no schema field removal).

EvidenceArtifacts:

- `docs/governance/clarification-log-schema.md`
- `docs/governance/hybrid-proof-enforcement.md`
- `docs/governance/policy-verdict.md`

### Task

TaskID: TB-003
OwnerAgent: agent3
Status: assigned
ScopePaths:

- `.github/workflows/agent-delivery.yml`
- `.github/workflows/reviewer-agent.yml`
- `.github/rulesets/main-protected-trunk.json`
- `.github/scripts/validate-agent-delivery.sh`
- `.github/scripts/run-reviewer-agent.sh`

Acceptance:

- Reviewer findings must carry valid `owner_agent`.
- PR delivery metadata must include `TaskBoardVersion`, `TaskID`, and `OwnerAgent` and match board ownership.

EvidenceArtifacts:

- `artifacts/policy/reviewer-agent-verdict.json`
- `artifacts/policy/agent-delivery-validation.json`
- `artifacts/policy/agent-task-board-validation.json`

### Task

TaskID: TB-004
OwnerAgent: agent1
Status: assigned
ScopePaths:

- `.github/scripts/validate-clarification-event-gating.sh`
- `.github/scripts/validate-clarification-log.sh`

Acceptance:

- Guardrail never crashes on missing `clarification-validation.json` or `ambiguity-triggers.json`.
- Missing/invalid JSON artifacts are reported as deterministic scenario errors in guardrail output.
- Guardrail still writes `artifacts/policy/clarification-event-gating-guardrail.json` on failures.

EvidenceArtifacts:

- `artifacts/policy/clarification-event-gating-guardrail.json`

## DispatchNotes

- Orchestrator and reviewer update assignments in this file only.
- Agents must reference `TaskBoardVersion` and `TaskID` in PR body metadata.
- When a task transitions to `done`, the owner agent must commit, push, and open or update the PR in the same cycle.
