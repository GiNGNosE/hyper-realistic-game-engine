#!/usr/bin/env bash
set -euo pipefail

mkdir -p artifacts/policy

python3 - <<'PY'
import json
import pathlib
import subprocess


def current_changes():
    run = subprocess.run(
        ["git", "status", "--porcelain", "-uall"],
        capture_output=True,
        text=True,
        check=True,
    )
    files = []
    for line in run.stdout.splitlines():
        if not line.strip():
            continue
        files.append(line[3:].strip())
    return files


agent_owners = {
    "agent1": [
        ".github/scripts/validate-clarification-log.sh",
        ".github/scripts/test-validate-clarification-log-matrix.sh",
        ".github/scripts/fixtures/clarification-validator/",
    ],
    "agent2": [
        "docs/governance/clarification-log-schema.md",
        "docs/governance/hybrid-proof-enforcement.md",
        "docs/governance/policy-verdict.md",
        "docs/governance/branch-strategy.md",
    ],
    "agent3": [
        ".github/scripts/run-reviewer-agent.sh",
        ".github/scripts/validate-agent-delivery.sh",
        ".github/scripts/agent-submit.sh",
        ".github/scripts/emit-agent-pr-split-plan.sh",
        ".github/scripts/run-three-agent-consolidation-dry-run.sh",
        ".github/workflows/reviewer-agent.yml",
        ".github/workflows/agent-delivery.yml",
        ".github/rulesets/main-protected-trunk.json",
    ],
}

changed = current_changes()

def belongs(path: str, owner_paths):
    for owner_path in owner_paths:
        if owner_path.endswith("/"):
            if path.startswith(owner_path):
                return True
        elif path == owner_path:
            return True
    return False


owned = {agent: [] for agent in agent_owners}
unassigned = []
for path in changed:
    mapped = False
    for agent, owner_paths in agent_owners.items():
        if belongs(path, owner_paths):
            owned[agent].append(path)
            mapped = True
            break
    if not mapped:
        unassigned.append(path)

payload = {
    "status": "ready" if not unassigned else "needs_routing",
    "owners": owned,
    "unassigned": unassigned,
}

json_path = pathlib.Path("artifacts/policy/agent-pr-split-plan.json")
md_path = pathlib.Path("artifacts/policy/agent-pr-split-plan.md")
json_path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")

lines = [
    "# Agent PR Split Plan",
    "",
    f"- Status: `{payload['status']}`",
    "",
]

for agent in ("agent1", "agent2", "agent3"):
    lines.append(f"## {agent}")
    lines.append("")
    lines.append("Files:")
    if owned[agent]:
        for path in owned[agent]:
            lines.append(f"- `{path}`")
    else:
        lines.append("- _none_")
    lines.append("")
    branch = f"gov/{agent}-scope-update"
    lines.append("Suggested commands:")
    lines.append("```bash")
    lines.append(f"git checkout -b {branch}")
    if owned[agent]:
        lines.append("git add " + " ".join(f'"{path}"' for path in owned[agent]))
        lines.append(f'git commit -m "[{agent}] scoped updates"')
    else:
        lines.append("# no files assigned")
    lines.append("```")
    lines.append("")

if unassigned:
    lines.append("## Unassigned Paths")
    lines.append("")
    for path in unassigned:
        lines.append(f"- `{path}`")
    lines.append("")
    lines.append("Route unassigned files before creating PR branches.")

md_path.write_text("\n".join(lines) + "\n", encoding="utf-8")
print(f"Wrote {json_path}")
print(f"Wrote {md_path}")
PY
