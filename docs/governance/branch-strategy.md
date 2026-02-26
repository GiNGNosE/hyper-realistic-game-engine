# Branch Strategy and Enforcement

This repository uses a protected-trunk strategy with machine-enforced policy gates.

## Branch Taxonomy

- `main`: protected integration branch, always merge-only.
- `feat/*`: feature work.
- `fix/*`: bug fixes.
- `gov/*`: governance/process/tooling changes.
- `exp/*`: bounded experiments.
- `release/*`: cycle closeout/stabilization branches (short-lived).
- `hotfix/*`: emergency fixes for `main` or an active `release/*`.

## Naming Contract

Pull request source branches must match:

- `^(feat|fix|gov|exp|release|hotfix)/[a-z0-9][a-z0-9._-]{1,62}$`

Examples:

- valid: `feat/raster-cache`, `gov/policy-verdict-branch-lane`
- invalid: `Feature/newThing`, `feat/x`, `main`

## Base Branch Matrix

- `feat/*` -> `main`
- `fix/*` -> `main`
- `gov/*` -> `main`
- `exp/*` -> `main`
- `release/*` -> `main`
- `hotfix/*` -> `main` or active `release/*`

## Enforcement Layers

1. `policy-verdict` lane `lane-branch-governance` enforces source naming and base target matrix and emits `artifacts/policy/lane-branch-governance.json`.
2. `policy-verdict` lane `lane-pr-template-governance` enforces PR template compliance and emits `artifacts/policy/pr-template-validation.json`.
3. GitHub branch protection/ruleset on `main` enforces PR-only merge flow and requires
   status checks `policy-verdict`, `reviewer-agent`, `agent-delivery`, and `agent-task-board`.

Both layers are required: CI enforces branch semantics, while platform ruleset blocks direct pushes and bypass paths.

## Main Branch Ruleset Settings

Configure on GitHub for `main`:

- Require a pull request before merging.
- Require branches to be up to date before merging.
- Require status checks `policy-verdict`, `reviewer-agent`, `agent-delivery`, and `agent-task-board`.
- Require conversation resolution before merge.
- Block force pushes.
- Block deletions.
- Restrict who can bypass protections (prefer no bypass).

Canonical desired settings are tracked in `.github/rulesets/main-protected-trunk.json`.

Apply settings through:

- `GITHUB_REPOSITORY=<owner/repo> .github/scripts/configure-main-branch-protection.sh`

## Rollout

### Phase 1: Observe

- Keep `lane-branch-governance` enabled.
- Record violations and tune naming/base matrix policy.

### Phase 2: Enforce

- Keep lane failures merge-blocking in `policy-verdict`.
- Enable/confirm required `policy-verdict`, `reviewer-agent`, `agent-delivery`, and
  `agent-task-board` status checks in `main` ruleset.

## Single Source Task Assignment Board

Task assignment source of truth is:

- `docs/governance/agent-task-board.md`

Merge-blocking checks enforce compliance:

- `agent-task-board`: validates board schema, ownership, status fields, and BoardHash integrity.
- `agent-delivery`: requires PR metadata fields `TaskBoardVersion`, `TaskID`, and
  `OwnerAgent`, and verifies they match the task board.

Agents must read and execute only tasks assigned to their `OwnerAgent` entries in the task board.

Task completion lifecycle is soft-archive:

- Owner agents set `Status: done` when implementation is complete and submit/update their PR in the same cycle.
- Completed tasks remain in `docs/governance/agent-task-board.md` until orchestrator cleanup after merge.
- Agents must not remove their own completed task blocks from the task board.
- `QueuedTasks` is reserved for pre-assigned follow-up work and is not part of the active execution wave.
- Orchestrator promotes queued tasks into `ActiveTasks` after the matching owner's active task is completed and stabilized.

## Agent Auto-Submit Contract

Agent implementation branches must use:

- `.github/scripts/agent-submit.sh --agent <agent1|agent2|agent3> --message "<summary>"`

The required `agent-delivery` check enforces:

- PR title prefix `[agent1|agent2|agent3]`.
- PR body declaration `OwnerAgent: agent1|agent2|agent3`.
- Commit subjects in the PR range prefixed with the same owner agent tag.

## Verification Matrix

- PR `feat/new-render-pass` -> `main` passes branch lane.
- PR `release/cycle-03` -> `main` passes branch lane.
- PR `Feature/new-render-pass` -> `main` fails branch lane (invalid pattern).
- PR `exp/audio-probe` -> `release/cycle-03` fails branch lane (invalid base target).
- Direct push to `main` is blocked by GitHub ruleset.

## Agent Task Ownership Lifecycle

Agents must read and execute only tasks assigned to their `OwnerAgent` entries in
the task board.

Task completion lifecycle is soft-archive:

- Owner agents set `Status: done` when implementation is complete and
  submit/update their PR in the same cycle.
- Completed tasks remain in `docs/governance/agent-task-board.md` until
  orchestrator cleanup after merge.
- Agents must not remove their own completed task blocks from the task board.
