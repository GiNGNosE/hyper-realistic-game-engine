#!/usr/bin/env bash
set -euo pipefail

python3 - <<'PY'
import hashlib
import pathlib
import re
import sys

board_path = pathlib.Path("docs/governance/agent-task-board.md")
if not board_path.exists():
    raise SystemExit("Missing docs/governance/agent-task-board.md")

content = board_path.read_text(encoding="utf-8")

if not re.search(r"(?m)^BoardVersion:\s*\S+\s*$", content):
    raise SystemExit("BoardVersion header is missing")
if not re.search(r"(?m)^BoardHash:\s*\S+\s*$", content):
    raise SystemExit("BoardHash header is missing")

normalized = re.sub(
    r"(?m)^BoardHash:\s*\S+\s*$",
    "BoardHash: __COMPUTED__",
    content,
)
computed_hash = hashlib.sha256(normalized.encode("utf-8")).hexdigest()
updated = re.sub(
    r"(?m)^BoardHash:\s*\S+\s*$",
    f"BoardHash: {computed_hash}",
    content,
)
board_path.write_text(updated, encoding="utf-8")
print(f"Updated BoardHash in {board_path}")
PY

