# Architecture Decision Record (ADR) Index

Use ADRs to preserve decision history across long timelines.

## ADR Policy

- Create an ADR for any decision that changes interfaces, data contracts, determinism model, baseline policy, or performance architecture.
- ADRs are immutable after acceptance except for appending supersession notes.
- Each evidence pack must list ADR IDs touched in that cycle.

## ADR Status Values

- `proposed`
- `accepted`
- `superseded`
- `rejected`

## Index Table

| ADR ID | Title | Status | Date | Supersedes | Affected Areas |
|---|---|---|---|---|---|
| ADR-0001 | Dual Objective Charter | accepted | 2026-02-26 | - | governance, validation, runtime |

## Required ADR Sections

1. Context and problem statement.
2. Decision statement.
3. Alternatives considered.
4. Consequences (positive and negative).
5. Verification impact (`M*`, `V*`, `A*`, `D*`, performance budgets).
6. Migration or rollback notes if relevant.

## Naming and Storage

- Store ADR files under `docs/governance/adrs/` as `ADR-XXXX-short-title.md`.
- Keep this index sorted by ADR ID.
