# Validation Metrics and Gating

This document defines objective metrics and pass/fail gates for each development phase.
Metrics are grouped into physical plausibility, visual fidelity, audio fidelity, and determinism.

## Governance Linkage (v5)

This file is the numeric threshold source of truth for technical KPI gates.

- Automated gate authority: `docs/governance/policy-verdict.md`
- Rule activation timing by phase: `docs/governance/phase-activation-matrix.md`
- Baseline retention/promotion policy: `docs/governance/baseline-lifecycle.md`
- CI environment model for replay vs performance lanes: `docs/governance/ci-environments.md`

## Evaluation Principles

- Compare every runtime or compressed result against offline truth references.
- Prefer relative error + perceptual error together, never one metric alone.
- Use fixed benchmark scenarios and fixed camera/listener paths.
- Gate progression by thresholds, not subjective judgment only.

## Benchmark Scenario Set

Minimum scenario suite for hero stone:

- `S1_LightTap`: low impulse, local chipping expected.
- `S2_ChiselImpact`: directional strike, anisotropic crack propagation expected.
- `S3_HeavyDrop`: high impulse, multi-fragment breakup expected.

All scenarios must run with fixed seeds and fixed boundary conditions.

## Physical Metrics

- `M1_FragmentMassEMD`:
  - Earth Mover's Distance between repeated runs and baseline.
  - Goal: low distribution drift under deterministic rerun.
- `M2_CrackSurfaceAreaError`:
  - Relative error vs calibrated reference target.
- `M3_CrackOrientationError`:
  - Angular error between predicted crack normals and measured/expected anisotropy direction.
- `M4_EnergyBalanceError`:
  - `|input_work - (fracture + kinetic + damping + residual)| / input_work`.
- `M5_FragmentCountStability`:
  - Standard deviation of fragment count under identical reruns (must be near zero).

## Visual Metrics

- `V1_HDRColorDeltaE`:
  - Per-pixel color difference vs truth frame set in HDR domain.
- `V2_NormalAngularError`:
  - Mean and P95 normal map angular error on exposed fracture surfaces.
- `V3_DisplacementRMSE`:
  - Surface displacement error on crack interiors.
- `V4_SilhouetteIoU`:
  - Fragment silhouette overlap in canonical camera views.
- `V5_TemporalStability`:
  - Flicker score across sequential frames for evolving cracks.

## Audio Metrics

- `A1_STFTDistance`:
  - Spectro-temporal distance between generated and truth audio.
- `A2_TransientOnsetErrorMs`:
  - Timing error for impact/crack onsets.
- `A3_DecayTimeError`:
  - Relative error of modal decay constants.
- `A4_BandEnergyError`:
  - Error per octave band for impact + fracture + debris stems.
- `A5_SpatialCueError`:
  - Interaural and distance attenuation consistency across listener path.

## Determinism and Reproducibility Metrics

- `D1_ReplayHashMatchRate`:
  - Percent snapshot hashes exactly matching deterministic reference.
- `D2_EventStreamMatchRate`:
  - Exact match ratio for fracture/contact event ordering and counts.
- `D3_RunToRunVariance`:
  - Variance budget across repeated identical runs.

## Phase Gates

Phase gate thresholds in this file are necessary but not sufficient for promotion. Promotion also requires governance artifact compliance under `policy-verdict`.

### Phase 0 Gate (Infrastructure Ready)

- Schema validation passes for all required channels.
- Snapshot read/write roundtrip is lossless for canonical test state.
- `D1_ReplayHashMatchRate = 100%` on short deterministic replay.

Fail if any required field is missing or replay diverges.

### Phase 1 Gate (Hero Stone Truth Complete)

- `M4_EnergyBalanceError <= 0.05`
- `M5_FragmentCountStability = 0` for deterministic reruns
- `M3_CrackOrientationError <= 12 deg` mean
- Minimum 3 benchmark scenarios produce physically plausible outcomes.

Fail if crack topology is non-reproducible or energy error exceeds threshold.

### Phase 2 Gate (Surrogate Compression Qualified)

- Visual surrogate:
  - `V1_HDRColorDeltaE` within approved tolerance for 95% pixels.
  - `V2_NormalAngularError <= 8 deg` mean on fracture surfaces.
- Audio surrogate:
  - `A2_TransientOnsetErrorMs <= 8 ms`
  - `A4_BandEnergyError <= 2.5 dB` per octave band (mean).
- Fracture surrogate:
  - Fragment/major crack topology preserved in benchmark scenarios.

Fail if any surrogate breaches quality thresholds in benchmark set.

### Phase 3 Gate (Single-Stone Runtime Ready)

- Runtime outputs remain within phase-2 surrogate quality budgets.
- No catastrophic artifact under stress scenarios (`S2`, `S3`).
- Deterministic debug mode reproduces identical event streams.

Fail if runtime approximation introduces topology regressions.

### Phase 4 Gate (Multi-Stone Scale Readiness)

- Aggregate scene quality remains inside configured drift envelope.
- Prioritization/LOD does not break nearby hero-stone fidelity targets.
- Audio mixing remains stable with no transient clipping in stress scenes.

Fail if scaling strategy causes unacceptable local fidelity collapse.

## Reporting Format

Each evaluation run must emit:

- scenario metadata,
- solver and build identifiers,
- metric table with pass/fail booleans,
- artifact links to reference images/audio/snapshots,
- regression delta vs previous accepted baseline.

## Continuous Validation Policy

- Run full benchmark suite before promoting phase status.
- Run reduced smoke suite on every substantial solver/material change.
- Lock accepted baselines and version them with snapshot schema version.
- Use deterministic replay and performance lanes as separate CI environments for stable enforcement.
