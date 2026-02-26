# Policy Scope and Glob Coverage

This document defines canonical include and exclusion patterns for governance checks.

## Immediate Coverage

- `docs/**/*.md`
- `.cursor/rules/*.mdc`
- `assets/**/*`

## C++ and Build Coverage

- `**/*.cpp`
- `**/*.cc`
- `**/*.cxx`
- `**/*.h`
- `**/*.hpp`
- `CMakeLists.txt`
- `**/*.cmake`

## GPU and Compute Coverage

- `**/*.glsl`
- `**/*.hlsl`
- `**/*.wgsl`
- `**/*.cu`
- `**/*.cuh`
- `**/*.metal`

## Pipeline Coverage

- `sim/**/*`
- `runtime/**/*`
- `offline/**/*`
- `data/**/*`
- `src/**/*`

## Exclusions

- `third_party/**/*`
- generated artifacts and generated code outputs
- vendored shader blobs unless explicitly opted in by dedicated policy
