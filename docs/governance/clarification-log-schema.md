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

## Event-Conditioned Trigger Activation

Trigger activation is evaluated against CI event context, not only artifact presence.

- `missing_target_scope` is active only for scoped events: `pull_request`, `push`.
- For `workflow_dispatch` and `schedule`, `missing_target_scope` is not activated.
- Other trigger types remain governed by their own detector conditions.

`artifacts/policy/clarification-validation.json` must expose event-context evidence:

- `event_name` (string): evaluated CI event.
- `target_scope_required` (boolean): whether target-scope clarification was required for the evaluated event.
- `required_clarification` (boolean): whether any clarification was required after trigger evaluation.
- `errors` (array): validation errors, empty when passing.

## Validation Semantics

CI must reject when:

- Any required field is missing.
- `ambiguities` is empty when ambiguity triggers were emitted.
- An entry lacks `user_response` or `resolved_decision`.
- Any `trigger_type` is not in the approved set.
- Clarification entries do not map to trigger IDs from `ambiguity-triggers.json`.
- `commit_id` mismatches the validated revision.

If no ambiguity trigger exists, the artifact is optional and not required to pass.

## Compatibility Note

This change is a behavioral refinement to trigger activation semantics for
`missing_target_scope`. It does not remove trigger types or required schema fields
from the clarification-log contract.

## Related Artifacts

- `artifacts/policy/ambiguity-triggers.json`: produced by CI trigger detector and treated as source of truth for whether clarification is mandatory.
- `artifacts/policy/clarification-log.json`: agent-provided clarification proof.
