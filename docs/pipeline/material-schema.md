# Material State Schema (Hero Stone)

This document defines the canonical material schema for the hyperreal stone pipeline.
It is the single source of truth for simulation, rendering, and audio.

## Design Goals

- Keep one shared state model across mechanics, render, and audio.
- Encode anisotropic behavior directly in material fields.
- Concentrate resolution near fracture activity using PBSV sparsity.
- Make serialization deterministic and replay-friendly.

## Coordinate and Unit Conventions

- Length: meters (`m`)
- Mass: kilograms (`kg`)
- Time: seconds (`s`)
- Force: newtons (`N`)
- Stress: pascals (`Pa`)
- Density: `kg/m^3`
- Young's modulus: `Pa`
- Fracture toughness: `Pa*sqrt(m)`
- Sound speed: `m/s`
- Temperature: kelvin (`K`)

Axes are right-handed: `+X` right, `+Y` up, `+Z` forward.

## Core Entity Model

The state contains three layers:

1. Global metadata and versioning.
2. Sparse voxel fields for material and damage properties.
3. Narrow-band fracture structures (`SDF` and local grain graph).

## Sparse Voxel Layout (PBSV)

Each active voxel stores property channels. Inactive voxels are omitted.

Required channels:

- `rho`: density (`float32`)
- `phi`: porosity in `[0, 1]` (`float32`)
- `mineral_id`: dominant mineral class (`uint16`)
- `mineral_mix`: top-k mineral fractions (`k * float16`, sum to 1)
- `moisture`: water content in `[0, 1]` (`float16`)
- `temperature`: absolute temperature (`float16`)
- `elastic_C`: anisotropic stiffness tensor in Voigt form (`6x6 float32`)
- `damage_tensor`: directional damage tensor (`3x3 float32`)
- `microcrack_density`: scalar crack density (`float32`)
- `k_ic`: mode-I fracture toughness (`float32`)
- `k_iic`: mode-II fracture toughness (`float32`)
- `k_iiic`: mode-III fracture toughness (`float32`)
- `eta_internal`: internal damping coefficient (`float32`)
- `sound_speed`: local wave speed (`float32`)
- `acoustic_loss`: frequency-independent attenuation term (`float32`)

Optional channels (phase 2+):

- `thermal_expansion`: anisotropic thermal expansion (`3x3 float32`)
- `electrostatic_charge`: local charge density (`float32`)
- `fluid_saturation`: pore fluid saturation (`float16`)

## Narrow-Band SDF Layer

The fracture solver uses a narrow-band signed distance field around candidate crack zones.

Per SDF node:

- `sd`: signed distance (`float32`)
- `grad_sd`: distance gradient (`3x float32`)
- `fracture_resistance_dir`: directional resistance principal basis (`3x3 float32`)
- `band_level`: refinement level (`uint8`)
- `active`: narrow-band activity bit (`bool`)

## Local Grain Graph

The grain graph is only instantiated near crack fronts.

### Node Attributes

- `grain_id` (`uint32`)
- `centroid_world` (`3x float32`)
- `orientation_q` (`4x float32`)
- `grain_volume` (`float32`)
- `grain_mineral_mix` (`k * float16`)
- `grain_damage` (`float32`)

### Edge Attributes

- `src_grain_id`, `dst_grain_id` (`uint32`)
- `boundary_normal` (`3x float32`)
- `boundary_area` (`float32`)
- `cohesion` (`float32`)
- `friction_mu` (`float32`)
- `roughness` (`float32`)
- `separation` (`float32`)
- `edge_state`: one of `intact`, `softened`, `broken`

## Derived Runtime-Useful Fields

These are computed from canonical fields and saved for reuse:

- `principal_stress`: eigenvalues/eigenvectors (`3 + 3x3`)
- `principal_strain`: eigenvalues/eigenvectors (`3 + 3x3`)
- `damage_scalar`: trace-normalized damage scalar
- `acoustic_impedance`: `rho * sound_speed`
- `fragment_label`: connected-component id after break events

## Snapshot Serialization Contract

Snapshots are immutable, append-only records. File format is container + chunked binary blobs.

### Snapshot Header

- `schema_version`: semantic version (`major.minor.patch`)
- `snapshot_id`: monotonic integer
- `sim_time_s`: simulation time in seconds
- `step_index`: deterministic step counter
- `parent_snapshot_id`: previous snapshot id
- `generator_commit`: source revision hash
- `rng_seed`: fixed seed for deterministic replay

### Required Chunks

- `voxels.index`: sparse index (Morton code or block index)
- `voxels.props`: packed channel arrays
- `sdf.band`: narrow-band nodes
- `grain.nodes`: local grain graph nodes
- `grain.edges`: local grain graph edges
- `events.fracture`: fracture event stream
- `events.contact`: impact/contact events

### Determinism Rules

- Stable sort by `(block_id, local_voxel_id)` before writing.
- Store all floating-point arrays as little-endian IEEE754.
- Record solver configuration in every snapshot.
- Ban non-deterministic reductions for official benchmark runs.

## Fracture Event Schema

Each fracture event record:

- `event_id` (`uint64`)
- `time_s` (`float64`)
- `source_region_id` (`uint32`)
- `failure_mode`: `modeI`, `modeII`, `modeIII`, `mixed`
- `released_energy_j` (`float32`)
- `crack_surface_area_m2` (`float32`)
- `new_fragment_ids` (`varint[]`)
- `impulse_n_s` (`3x float32`)

## Audio Event Export

Audio consumes derived events from the same snapshot timeline:

- `impact_event`: position, impulse, contact normal, relative velocity.
- `crack_event`: mode, released energy, crack speed, centroid.
- `debris_event`: fragment mass, collision energy, rolling/sliding state.

## Versioning Policy

- `major`: binary/layout breaking change.
- `minor`: backward-compatible field additions.
- `patch`: metadata-only or documentation clarifications.

## Acceptance Criteria for D1

- One procedural or scanned hero stone represented in PBSV.
- All required channels present and unit-checked.
- Snapshot playback reproduces identical fracture initialization state.
- Mechanics, render, and audio loaders parse the same snapshot successfully.
