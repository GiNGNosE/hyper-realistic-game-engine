# Clarification Log Schema

This contract defines `artifacts/policy/clarification-log.json`.

## Purpose

`clarification-log.json` provides machine-verifiable evidence that ambiguity was surfaced to the user and resolved before implementation decisions were finalized.

This artifact is conditionally required: only when CI ambiguity triggers are detected.

## Required Fields

- `schema_version` (string): schema version for this contract. Initial value: `1.0.0`.
- `task_id` (string): unique task/session identifier.
- `commit_id` (string): git commit SHA for the validated revision.
- `ambiguities` (array of object): one entry per detected ambiguity trigger that required user clarification.

## `ambiguities[]` Object

Each item must include:

- `ambiguity_id` (string): unique ID for this ambiguity resolution.
- `trigger_type` (string): one of the approved trigger keys.
- `detected_issue` (string): short description of the ambiguous or missing requirement.
- `question_asked` (string): exact clarification question posed to the user.
- `user_response` (string): user response captured from conversation history.
- `resolved_decision` (string): implementation decision derived from user response.
- `resolved_at` (string): RFC 3339 UTC timestamp.

## Approved Trigger Types

- `missing_acceptance_criteria`
- `multiple_valid_implementations`
- `missing_target_scope`
- `governance_conflict`

## Event-Scoped Trigger Applicability

`missing_target_scope` is event-scoped and only applies when changed-path scope
is expected.

| Event | Scope expectation | `missing_target_scope` |
| --- | --- | --- |
| `pull_request` | Scoped | Evaluated |
| `push` | Scoped | Evaluated |
| `workflow_dispatch` | Unscoped | Not evaluated |
| `schedule` | Unscoped | Not evaluated |

Compatibility note: this is a behavioral refinement only. Schema contracts stay
backward compatible with no field removal in
`artifacts/policy/ambiguity-triggers.json` or
`artifacts/policy/clarification-validation.json`, and required PR metadata keys
(`TaskBoardVersion`, `TaskID`, `OwnerAgent`) are unchanged.

## Active-vs-Queued Task Lifecycle Note

Clarification evidence requirements apply only to actively executing work.

- `ActiveTasks` are executable for the current cycle.
- `QueuedTasks` are pre-assigned and become executable only after orchestrator
  promotion into `ActiveTasks`.
- This lifecycle refinement does not add or remove required fields in
  `clarification-log.json`, `ambiguity-triggers.json`, or
  `clarification-validation.json`.

## Validation Semantics

CI must reject when:

- Any required field is missing.
- `ambiguities` is empty when ambiguity triggers were emitted.
- An entry lacks `user_response` or `resolved_decision`.
- Any `trigger_type` is not in the approved set.
- Clarification entries do not map to trigger IDs from `ambiguity-triggers.json`.
- `commit_id` mismatches the validated revision.

If no ambiguity trigger exists, the artifact is optional and not required to pass.

## Related Artifacts

- `artifacts/policy/ambiguity-triggers.json`: produced by CI trigger detector and treated as source of truth for whether clarification is mandatory.
- `artifacts/policy/clarification-log.json`: agent-provided clarification proof.
