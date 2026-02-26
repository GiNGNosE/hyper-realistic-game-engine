# Agent Task Board

<!-- markdownlint-disable MD022 MD024 -->

BoardVersion: 2026-02-27.1
BoardHash: c468fad2253bc95d19bb644f39a66d1bacf1fc4c1b82ee1832e5af70084713c0
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

## DispatchNotes

- Orchestrator and reviewer update assignments in this file only.
- Agents must reference `TaskBoardVersion` and `TaskID` in PR body metadata.

## Task Board Update Protocol

### Step 1: Prepare Assignment Change

- Open a dedicated branch for board updates (recommended: `gov/task-board-<date>`).
- Change task ownership/status only in `docs/governance/agent-task-board.md`.
- Increment `BoardVersion` for every assignment or scope change.
- Regenerate `BoardHash` using the repository validator before opening the PR.

### Step 2: Merge Board First

- Submit a board-only PR (no implementation files mixed in).
- Require `agent-task-board` validation and related governance checks to pass.
- Merge board PR before any agent implementation PRs start or continue.

### Step 3: Agent Sync Gate (Mandatory)

- Before implementation, every agent worktree must run:
  - `git fetch origin`
  - `git rebase origin/main`
- If rebase fails, resolve conflicts first; do not continue implementation on stale assignments.

### Step 4: Implementation Contract

- Each agent works only on tasks where `OwnerAgent` matches the agent identity.
- PR metadata must include:
  - `TaskBoardVersion`
  - `TaskID`
  - `OwnerAgent`
- PR title and commit prefixes must match the assigned owner agent policy.

### Step 5: Reassignment Rule

- If scope changes or work must move agents, update the board in a new board-only PR first.
- Do not hand off work through comments/chat alone; assignment is official only after board merge.

### Step 6: Pre-Merge Verification

- Rebase implementation branches on latest `origin/main` before final merge.
- Confirm `agent-delivery`, `reviewer-agent`, `agent-task-board`, and `policy-verdict` are green.
- If any gate fails due to assignment mismatch, update board first, then rerun checks.

### Step 7: Audit Trail

- Keep old tasks by status transition (`assigned` -> `in_progress` -> `completed`) instead of deleting immediately.
- Include a short DispatchNotes entry for why a reassignment happened.
