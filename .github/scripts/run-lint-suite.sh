#!/usr/bin/env bash
set -euo pipefail

mkdir -p artifacts/policy

if [[ ! -f artifacts/policy/changed-paths.txt ]]; then
  git ls-files > artifacts/policy/changed-paths.txt
fi

python3 .github/scripts/run-lint-suite.py
