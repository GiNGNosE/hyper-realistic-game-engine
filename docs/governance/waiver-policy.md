# Waiver Policy (Phase 0+)

Waivers are break-glass exceptions and not normal workflow.

## Allowed Timing

- Allowed from Phase 0 onward.
- Intended only for urgent unblock with bounded risk.

## Required Fields

- `waiver_id`
- `scope`
- `reason`
- `owner` (solo mode: `self`)
- `risk_level`
- `rollback_plan`
- `expires_at`

## Constraints

- Maximum validity should be short-lived.
- Scope must be narrow (single subsystem where possible).
- Reuse of old waivers is forbidden without re-issuance.
- Expired waivers fail `policy-verdict` automatically.

## Approval Model

- No human reviewer required.
- Waiver validity is determined by policy checks and risk gates only.
