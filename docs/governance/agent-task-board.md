# Agent Task Board

<!-- markdownlint-disable MD022 MD024 -->

BoardVersion: 2026-02-27.2
BoardHash: d30e4a470ed3bed3b87e6d4fd0b2f788f11cc1db617e2b165d2ff6dda7c91729
## ActiveTasks

### Task

TaskID: TB-005
OwnerAgent: agent1
Status: assigned
ScopePaths:

- `.github/scripts/validate-clarification-log.sh`
- `.github/scripts/test-validate-clarification-log-matrix.sh`
- `.github/scripts/fixtures/clarification-validator/**`
- `.github/scripts/validate-clarification-event-gating.sh`

Acceptance:

- Clarification validator and event-gating guardrail handle missing or invalid JSON artifacts without crashing.
- Matrix fixtures cover scoped (`pull_request`, `push`) and unscoped (`workflow_dispatch`, `schedule`) trigger behavior.
- Guardrail outputs deterministic error records and still emits expected policy artifacts on failures.

EvidenceArtifacts:

- `artifacts/policy/clarification-validator-matrix.json`
- `artifacts/policy/clarification-validator-matrix-summary.md`
- `artifacts/policy/clarification-event-gating-guardrail.json`

### Task

TaskID: TB-006
OwnerAgent: agent2
Status: assigned
ScopePaths:

- `docs/governance/clarification-log-schema.md`
- `docs/governance/hybrid-proof-enforcement.md`
- `docs/governance/policy-verdict.md`
- `docs/governance/branch-strategy.md`
- `docs/governance/agent-task-board.md`

Acceptance:

- Trigger/event and completion lifecycle mapping is explicitly documented for scoped and unscoped contexts.
- Soft-archive completion semantics are documented:
  agents set `Status: done`; orchestrator removes completed tasks after merge.
- Compatibility note states behavior refinement (no schema field removal) and no change to required PR metadata keys.

EvidenceArtifacts:

- `docs/governance/branch-strategy.md`
- `docs/governance/clarification-log-schema.md`
- `docs/governance/hybrid-proof-enforcement.md`
- `docs/governance/policy-verdict.md`

### Task

TaskID: TB-007
OwnerAgent: agent3
Status: assigned
ScopePaths:

- `.github/workflows/agent-delivery.yml`
- `.github/workflows/reviewer-agent.yml`
- `.github/workflows/agent-task-board.yml`
- `.github/rulesets/main-protected-trunk.json`
- `.github/scripts/validate-agent-delivery.sh`
- `.github/scripts/validate-agent-task-board.sh`
- `.github/scripts/run-reviewer-agent.sh`

Acceptance:

- Reviewer findings must carry valid `owner_agent`.
- PR delivery metadata must include `TaskBoardVersion`, `TaskID`, and `OwnerAgent`
  and match board ownership with lifecycle-aware task status validation.
- Task board validator enforces schema/hash integrity and completion lifecycle semantics
  without requiring immediate task deletion.

EvidenceArtifacts:

- `artifacts/policy/reviewer-agent-verdict.json`
- `artifacts/policy/agent-delivery-validation.json`
- `artifacts/policy/agent-task-board-validation.json`

## DispatchNotes

- Orchestrator and reviewer update assignments in this file only.
- Agents must reference `TaskBoardVersion` and `TaskID` in PR body metadata.
- When a task transitions to `done`, the owner agent must commit, push, and open or update the PR in the same cycle.
- Soft-archive lifecycle applies:
  completed tasks remain on the board with `Status: done`
  until the orchestrator removes them after merge.
