# Agent Task Board

<!-- markdownlint-disable MD022 MD024 -->

BoardVersion: 2026-02-27.2
BoardHash: 94f0281eb042bddf798c1db47e082c55e7fa1ded7b0a16326c51e460decdc627
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

## QueuedTasks

### Task

TaskID: TB-008
OwnerAgent: agent1
Status: assigned
ScopePaths:

- `.github/scripts/validate-clarification-log.sh`
- `.github/scripts/test-validate-clarification-log-matrix.sh`
- `.github/scripts/fixtures/clarification-validator/**`
- `.github/scripts/validate-clarification-event-gating.sh`

Acceptance:

- Validator coverage expands to edge-case payloads for missing, malformed,
  and partial clarification artifacts without nondeterministic behavior.
- Matrix harness adds queued-wave scenarios for scoped and unscoped event
  handling and reports deterministic expectation diffs.
- Guardrail output remains machine-readable and includes scenario-level error
  details for each failing fixture input.

EvidenceArtifacts:

- `artifacts/policy/clarification-validator-matrix.json`
- `artifacts/policy/clarification-validator-matrix-summary.md`
- `artifacts/policy/clarification-event-gating-guardrail.json`

### Task

TaskID: TB-009
OwnerAgent: agent2
Status: assigned
ScopePaths:

- `docs/governance/clarification-log-schema.md`
- `docs/governance/hybrid-proof-enforcement.md`
- `docs/governance/policy-verdict.md`
- `docs/governance/branch-strategy.md`
- `docs/governance/agent-task-board.md`

Acceptance:

- Governance docs include explicit active-vs-queued lifecycle mapping and
  orchestrator promotion responsibilities.
- Compatibility notes confirm queued-task addition is a behavior refinement
  and does not remove required PR metadata fields.
- Task board contract language is synchronized across governance docs with
  no contradictory assignment or lifecycle statements.

EvidenceArtifacts:

- `docs/governance/branch-strategy.md`
- `docs/governance/clarification-log-schema.md`
- `docs/governance/hybrid-proof-enforcement.md`
- `docs/governance/policy-verdict.md`

### Task

TaskID: TB-010
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

- Delivery and reviewer checks remain stable when queued tasks are present and
  task ownership mapping is validated across active and queued sections.
- Task board validator checks section-level schema for `ActiveTasks` and
  `QueuedTasks`, while preserving TaskID uniqueness across the full board.
- Automation artifacts remain deterministic and continue to fail closed on
  ownership, status, or schema mismatch.

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
- Queued tasks are pre-assigned follow-up work and are not promoted to active
  execution until the orchestrator transitions them into `ActiveTasks`.
- When an active task is completed and stabilized, orchestrator promotes the
  matching queued task for that owner agent into the active execution wave.
