# Milestone: Hero Stone Offline Vertical Slice

This milestone delivers a single benchmark-quality stone with physically grounded fracture, render truth, and audio truth.
Real-time is explicitly out of scope for this phase.

## Scope

- One hero stone asset (scanned or procedural).
- Offline anisotropic fracture simulation with localized grain refinement.
- Snapshot outputs that drive both offline rendering and offline audio generation.
- Deterministic replay for repeatable evaluation.

## Out of Scope

- Runtime frame budget constraints.
- Multi-stone interactions.
- Final gameplay integration.

## Vertical Slice Architecture

1. Build stone material state in PBSV.
2. Initialize narrow-band anisotropic SDF around high-risk fracture regions.
3. Spawn local graph-of-grains near active crack fronts only.
4. Run MLS-MPM/APIC fracture simulation with displacement discontinuity.
5. Emit synchronized state snapshots and event streams.
6. Feed snapshots to render truth and audio truth pipelines.

## Fracture Solver Configuration (Reference Preset)

- Time integration: fixed-step, implicit where stability requires.
- Base solver: MLS-MPM with APIC transfer.
- Discontinuity handling: compatible particle split at failed regions.
- Fracture criterion:
  - Energy release rate threshold (`G >= Gc_dir`).
  - Directional stress criterion using local anisotropic tensors.
  - Grain boundary weakening bias from edge cohesion and roughness.
- Adaptivity:
  - Refine SDF and grain graph only within active crack frontier band.
  - Coarsen inactive regions after configurable cooldown windows.

## Inputs

- `hero_stone.asset`:
  - external mesh (for inspection only),
  - material field seeds,
  - boundary condition tags.
- `solver_config.yaml`:
  - step sizes, convergence tolerances, adaptivity thresholds.
- `impact_scenarios.yaml`:
  - force vectors, tool contact paths, impulse duration profiles.

## Outputs

- `snapshots/*.pbsvsnap`: immutable state snapshots.
- `events/fracture_events.bin`: crack initiation and propagation records.
- `events/contact_events.bin`: impact/contact events.
- `derived/fragment_maps/*`: fragment labels and volumes.
- `derived/crack_surface/*`: crack mesh and roughness maps.

## Implementation Tasks

### T1: Hero Stone Authoring

- Import/construct one stone reference asset.
- Populate required material channels from `material-schema.md`.
- Validate units and tensor symmetry constraints.

### T2: Fracture Zone Initialization

- Create narrow-band SDF centered on precomputed stress concentrators.
- Seed local grain graph with physically plausible grain size distribution.
- Validate connectivity and edge attribute ranges.

### T3: Offline Fracture Solve

- Run baseline impact scenarios (light tap, chisel hit, heavy drop).
- Record full snapshot sequence with deterministic seed.
- Emit fracture and contact event streams.

### T4: Post-Processing

- Label connected fragments.
- Extract exposed crack surfaces and measure roughness metrics.
- Compute per-fragment inertial tensors for downstream use.

## Determinism Requirements

- Fixed RNG seed per scenario.
- Stable iteration order for sparse structures.
- Deterministic reductions for all metric calculations.
- Replay hash check every `N` steps to catch drift.

## Exit Criteria

- Crack topology is visually plausible and reproducible across reruns.
- Fragment mass histogram is stable under identical inputs.
- Crack surface area and released energy are monotonic with impact severity.
- Snapshot replay re-creates the exact final fragment graph.

## Deliverable Checklist

- [ ] One hero stone state pack.
- [ ] Three or more deterministic fracture scenarios.
- [ ] Snapshot archive and event logs.
- [ ] Post-process artifact bundle (fragment/crack outputs).
- [ ] Short technical note summarizing solver settings and observed behavior.
