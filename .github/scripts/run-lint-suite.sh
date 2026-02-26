#!/usr/bin/env bash
set -euo pipefail

mkdir -p artifacts/policy

if [[ ! -f artifacts/policy/changed-paths.txt ]]; then
  git ls-files >artifacts/policy/changed-paths.txt
fi

if ! python3 .github/scripts/run-lint-suite.py; then
  if [[ -f artifacts/policy/lint-summary.json ]]; then
    echo "lint-summary.json:"
    cat artifacts/policy/lint-summary.json
  fi
  if [[ -f artifacts/policy/lint-tool-versions.json ]]; then
    echo "lint-tool-versions.json:"
    cat artifacts/policy/lint-tool-versions.json
  fi
  exit 1
fi
