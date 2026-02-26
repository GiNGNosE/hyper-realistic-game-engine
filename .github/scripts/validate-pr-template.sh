#!/usr/bin/env bash
set -euo pipefail

mkdir -p artifacts/policy
python3 .github/scripts/validate-pr-template.py
