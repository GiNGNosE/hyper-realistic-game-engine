# Rule Read Receipt Schema

This contract defines `artifacts/policy/rule-read-receipt.json`.

## Purpose

`rule-read-receipt.json` is the agent-side declaration that active governance
rules were read and applied for the current task context. CI treats this
artifact as required but not self-authoritative: every key field is
independently cross-checked.

## Required Fields

- `schema_version` (string): schema version for this contract. Initial value: `1.0.0`.
- `task_id` (string): unique task/session identifier.
- `commit_id` (string): git commit SHA for the validated revision.
- `pr_number` (integer): pull request number when running in PR context.
- `phase` (string): governance phase identifier (for example `pre-phase-0`, `phase-1`, `phase-2`, `phase-3`, `phase-4`).
- `changed_paths` (array of string): normalized repository-relative paths included in scope.
- `rule_inventory_hash` (string): SHA-256 hash of the active `.cursor/rules/*.mdc` inventory used for validation.
- `applicable_rule_ids` (array of string): rule IDs that are active for this `phase`.
- `applied_rules` (array of object): per-rule proof entries.
- `generated_at` (string): RFC 3339 UTC timestamp.

## `applied_rules[]` Object

Each entry must include:

- `rule_id` (string)
- `evidence_note` (string)

Validation semantics:

- `rule_id` must be unique within `applied_rules`.
- `evidence_note` must be non-empty and specific:
  - minimum length 24 characters,
  - must contain at least one policy keyword (`must`, `must not`,
    `required evidence`, `reject`, `gate`, `artifact`, or `phase`),
  - generic placeholders fail (for example `read and followed`, `n/a`, `ok`, `done`).

## Cross-Validation Requirements

CI must reject the receipt when any of the following is true:

- Missing required field.
- `commit_id` mismatches the validated git revision.
- PR context exists and `pr_number` mismatches event metadata.
- `changed_paths` mismatches CI-derived changed paths.
- `rule_inventory_hash` mismatches CI-computed active-rule hash.
- `applicable_rule_ids` mismatches phase-based resolution.
- Any resolved applicable rule is missing from `applied_rules`.

## Example

```json
{
  "schema_version": "1.0.0",
  "task_id": "task-2026-02-26-001",
  "commit_id": "abc123def456",
  "pr_number": 42,
  "phase": "pre-phase-0",
  "changed_paths": [
    ".github/workflows/policy-verdict.yml",
    "docs/governance/policy-verdict.md"
  ],
  "rule_inventory_hash": "d6dc9e...f2b4",
  "applicable_rule_ids": [
    "00-core-governance-cpp",
    "15-test-discipline",
    "70-validation-matrix-enforcement"
  ],
  "applied_rules": [
    {
      "rule_id": "00-core-governance-cpp",
      "evidence_note": "Applied reject-condition checks and bound final decision to policy-verdict authority."
    }
  ],
  "generated_at": "2026-02-26T12:00:00Z"
}
```
