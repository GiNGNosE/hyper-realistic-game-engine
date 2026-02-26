# PR Template Strategy

This document defines how pull request templates are selected and validated in CI.

## Purpose

The PR template strategy ensures every pull request declares the same minimum governance evidence:

- change intent,
- risk/scope,
- dual-objective impact,
- validation evidence,
- artifact references.

## Template Catalog

Templates are stored in `.github/PULL_REQUEST_TEMPLATE/`:

- `feature.md`
- `bugfix.md`
- `governance-docs.md`
- `baseline-promotion.md`

Every template includes a marker comment used by CI to detect the selected template type.

Example:

- `<!-- pr_template: feature -->`

## Selection Rules

Choose template by dominant intent:

- capability or behavior changes -> `feature`
- defect correction -> `bugfix`
- policy/docs/process-only changes -> `governance-docs`
- baseline promotion and lineage update -> `baseline-promotion`

If a PR spans multiple intents, choose the highest-risk intent and include explicit cross-scope notes in
`Scope And Risk`.

## CI Enforcement

Validation is implemented by:

- `.github/scripts/validate-pr-template.py`
- `.github/scripts/validate-pr-template.sh`
- `.github/workflows/pr-template-enforcement.yml`
- `policy-verdict` lane `lane-pr-template-governance`

CI validates:

- marker exists and is one of supported template types,
- required sections exist and are non-empty,
- required checklist sections include explicit completion,
- placeholder content (`TODO`, `TBD`) is not left in required sections,
- baseline promotion metadata fields are present for `baseline-promotion`.

Validation artifact:

- `artifacts/policy/pr-template-validation.json`

## Failure Examples

Common merge-blocking failures:

- missing marker comment in PR body,
- missing required section such as `Dual-Objective Evidence`,
- required checklists left entirely unchecked,
- baseline promotion PR without `intent: baseline-promotion` metadata.

## Remediation

When CI fails:

1. Open PR body edit.
2. Select the correct template and confirm marker comment.
3. Fill all required sections with concrete evidence.
4. Check completed checklist items.
5. Re-run CI by pushing an empty amend or updating PR body.

## Rollout Mode

Validation supports two modes via `PR_TEMPLATE_ENFORCEMENT_MODE`:

- `advisory`: records failures but does not fail CI.
- `enforce`: failures are merge-blocking.

Recommended rollout:

1. One short iteration in `advisory` mode to identify false positives.
2. Switch to `enforce` mode and keep as required governance gate.
