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

## Runtime Performance Metrics

- `R1_RuntimeMedianMs`:
  - Median frame/step time for the active benchmark scenario set.
- `R2_RuntimeP95Ms`:
  - P95 frame/step time for the active benchmark scenario set.

Runtime metrics are enforced by LPG and are reported alongside quality metrics; promotion requires both groups to pass.

## Phase Gates

Phase gate thresholds in this file are necessary but not sufficient for
promotion. Promotion also requires governance artifact compliance under
`policy-verdict`.

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

## LPG Machine-Readable Threshold Contract

This embedded contract is the machine source for LPG threshold evaluation.
CI must resolve Lane Performance Gate thresholds from this block.
CI candidate metrics input for LPG is expected at
`artifacts/perf/lpg-metrics.json` and must preserve the existing LPG schema
contract (`phase`, `scenario_set_id`, `aggregate_metrics`, `scenario_runs`,
`environment_fingerprint`).
In CI, runtime metrics must come from direct harness execution only; fixture/bootstrap fallback is not permitted.

<!-- LPG_THRESHOLDS_BEGIN -->
```json
{
  "schema_version": "lpg-thresholds-v1",
  "scenario_sets": {
    "canonical-s1-s3": {
      "scenario_ids": [
        "S1_LightTap",
        "S2_ChiselImpact",
        "S3_HeavyDrop"
      ],
      "seeds": {
        "S1_LightTap": 101,
        "S2_ChiselImpact": 202,
        "S3_HeavyDrop": 303
      }
    }
  },
  "phases": {
    "pre-phase-0": {
      "scenario_set": "canonical-s1-s3",
      "required_metrics": {
        "D1_ReplayHashMatchRate": {
          "scope": "aggregate",
          "comparator": "eq",
          "value": 100.0
        },
        "runtime_median_ms": {
          "scope": "aggregate",
          "comparator": "lte",
          "value": 20.0
        },
        "runtime_p95_ms": {
          "scope": "aggregate",
          "comparator": "lte",
          "value": 28.0
        }
      }
    },
    "phase-1": {
      "scenario_set": "canonical-s1-s3",
      "required_metrics": {
        "D1_ReplayHashMatchRate": {
          "scope": "aggregate",
          "comparator": "eq",
          "value": 100.0
        },
        "M4_EnergyBalanceError": {
          "scope": "aggregate",
          "comparator": "lte",
          "value": 0.05
        },
        "M5_FragmentCountStability": {
          "scope": "aggregate",
          "comparator": "eq",
          "value": 0.0
        },
        "M3_CrackOrientationError": {
          "scope": "aggregate",
          "comparator": "lte",
          "value": 12.0
        },
        "runtime_median_ms": {
          "scope": "aggregate",
          "comparator": "lte",
          "value": 18.0
        },
        "runtime_p95_ms": {
          "scope": "aggregate",
          "comparator": "lte",
          "value": 25.0
        }
      }
    },
    "phase-2": {
      "scenario_set": "canonical-s1-s3",
      "required_metrics": {
        "D1_ReplayHashMatchRate": {
          "scope": "aggregate",
          "comparator": "eq",
          "value": 100.0
        },
        "V2_NormalAngularError": {
          "scope": "aggregate",
          "comparator": "lte",
          "value": 8.0
        },
        "A2_TransientOnsetErrorMs": {
          "scope": "aggregate",
          "comparator": "lte",
          "value": 8.0
        },
        "A4_BandEnergyError": {
          "scope": "aggregate",
          "comparator": "lte",
          "value": 2.5
        },
        "runtime_median_ms": {
          "scope": "aggregate",
          "comparator": "lte",
          "value": 16.0
        },
        "runtime_p95_ms": {
          "scope": "aggregate",
          "comparator": "lte",
          "value": 23.0
        }
      }
    },
    "phase-3": {
      "scenario_set": "canonical-s1-s3",
      "required_metrics": {
        "D1_ReplayHashMatchRate": {
          "scope": "aggregate",
          "comparator": "eq",
          "value": 100.0
        },
        "D2_EventStreamMatchRate": {
          "scope": "aggregate",
          "comparator": "eq",
          "value": 100.0
        },
        "runtime_median_ms": {
          "scope": "aggregate",
          "comparator": "lte",
          "value": 14.0
        },
        "runtime_p95_ms": {
          "scope": "aggregate",
          "comparator": "lte",
          "value": 20.0
        }
      }
    },
    "phase-4": {
      "scenario_set": "canonical-s1-s3",
      "required_metrics": {
        "D1_ReplayHashMatchRate": {
          "scope": "aggregate",
          "comparator": "eq",
          "value": 100.0
        },
        "D2_EventStreamMatchRate": {
          "scope": "aggregate",
          "comparator": "eq",
          "value": 100.0
        },
        "runtime_median_ms": {
          "scope": "aggregate",
          "comparator": "lte",
          "value": 12.0
        },
        "runtime_p95_ms": {
          "scope": "aggregate",
          "comparator": "lte",
          "value": 18.0
        }
      }
    }
  }
}
```
<!-- LPG_THRESHOLDS_END -->
