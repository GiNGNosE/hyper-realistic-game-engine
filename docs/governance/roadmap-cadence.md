# Roadmap Cadence and Program Governance

This document defines how the project is steered over a decade while preserving the technical quality gates.

## Baseline Assessment (v4 gap)

Current governance in `cpp_solo_governance_v4` is strong at merge-time
enforcement, but it does not fully specify long-horizon operating rhythm. The
gap is not technical correctness; the gap is decade-scale execution control.

## Dual-Objective Charter (Non-Negotiable)

Every planning and promotion decision must satisfy both objectives:

- scientific-grade fidelity and determinism,
- high real-time performance.

Neither objective can be traded away for short-term progress. If one objective
regresses, the cycle is not considered successful.

## Timeboxed Planning Model

Use fixed 12-week cycles:

1. Weeks 1-2: planning, hypothesis, scenario setup, benchmark lock.
2. Weeks 3-8: implementation and iterative validation.
3. Weeks 9-10: hardening, replay/perf stabilization, documentation.
4. Weeks 11-12: evidence pack, ADR updates, go/no-go review.

## Annual Thesis Contract

At the beginning of each year, publish one thesis statement that includes:

- a target capability leap,
- expected measurable improvement in both quality and runtime metrics,
- explicit dependencies and major risks.

The final cycle of each year must include a thesis validation summary.

## Phase Exit Criteria Governance

Phase progression is allowed only when all are true:

- phase gate thresholds in `docs/pipeline/validation-metrics.md` pass,
- required determinism and replay artifacts are attached,
- performance budgets for the phase are met,
- ADR entries exist for major architecture decisions made in-cycle.

## Evidence Pack Requirement

Each 12-week cycle must publish a single evidence pack that contains:

- scenario metadata and fixed seeds,
- metric outputs and pass/fail table,
- baseline delta summary,
- links to snapshots/renders/audio artifacts,
- ADR IDs touched in the cycle.

## Escalation Rule

If fidelity or performance misses target in two consecutive cycle checkpoints:

- freeze new feature work for one checkpoint,
- run focused root-cause correction,
- resume normal scope only after both objectives recover.
